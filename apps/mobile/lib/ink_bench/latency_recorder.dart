// PURPOSE: Hold a bench run's state — which phase it is in, what has been measured so far, and what
//          the surface observed — and decide which samples count. It is the one place that knows
//          the difference between a warm-up sample, which is shown but never logged, and a measured
//          sample, which is logged and against which the thresholds are applied.
// INPUTS: Samples, palm observations and committed strokes pushed from the ink platform streams;
//         a [BenchLogWriter] to hand measured samples to; a clock for the phase countdown.
// OUTPUTS: Per-pointer-kind [BenchStats] for the measured window and for the warm-up window, the
//          phase and its remaining time, and a `notifyListeners()` at most every 100 ms rather
//          than once per sample, so refreshing the screen never becomes part of what is measured.
// KEYWORDS: bench-state, warm-up-window, measurement-window, phase-machine, percentiles
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ink_native/ink_native.dart';

import 'bench_log.dart';
import 'bench_stats.dart';

/// The phase a bench run is in.
enum BenchPhase {
  /// Nothing is running; samples are neither counted nor logged.
  idle,

  /// The protocol's discard window: samples update the screen but never reach the log.
  warmup,

  /// The measured window: every sample is logged as it arrives.
  measuring,

  /// The measured window ended; the log is complete.
  finished,
}

// PURPOSE: Be the single authority on what a bench run has measured, so the screen, the log and the
//          verdict all read the same numbers and a warm-up sample can never leak into a percentile.
// INPUTS: Injected [BenchLogWriter] and device label; durations for the two windows.
// OUTPUTS: Read-only statistics per pointer kind, the phase, and the log path. Throws nothing for
//          an out-of-order call: starting while running restarts, and stopping while idle is a
//          no-op, because a bench is driven by a person tapping a tablet.
// KEYWORDS: recorder, phase-machine, thresholds, warm-up-exclusion, change-notifier
/// The single authority on what a bench run has measured.
class LatencyRecorder extends ChangeNotifier {
  /// Creates an idle recorder writing through [writer].
  LatencyRecorder({required this.writer});

  /// The log the measured window's samples are handed to.
  ///
  /// Public because the run's artifact is part of the recorder's contract, not an implementation
  /// detail: callers read its path and its record count.
  final BenchLogWriter writer;

  /// The 45 ms p95 Android stylus budget from `docs/sdd.md` section 6.
  static const double sPenBudgetMs = 45;

  /// The 60 ms p95 finger budget from `docs/sdd.md` section 6.
  static const double fingerBudgetMs = 60;

  final Map<InkPointerKind, List<double>> _warmupByKind =
      <InkPointerKind, List<double>>{};
  final Map<InkPointerKind, List<double>> _measuredByKind =
      <InkPointerKind, List<double>>{};

  final List<InkPalmObservation> _palmObservations = <InkPalmObservation>[];

  BenchPhase _phase = BenchPhase.idle;
  Duration _phaseDuration = Duration.zero;
  final Stopwatch _phaseClock = Stopwatch();
  Timer? _ticker;

  InkLatencySample? _lastSample;
  int _committedStrokes = 0;
  int _suppressedPalmContacts = 0;
  int _concurrentContactSamples = 0;
  double _concurrentMaxTouchMajorPx = 0;
  InkSurfaceInfo? _surfaceInfo;
  String _deviceLabel = 'unknown';
  bool _timelineDelivered = false;
  bool _usedTimelinePoster = false;
  String _eventTimePrecision = 'unknown';

  /// The phase the run is in.
  BenchPhase get phase => _phase;

  /// How long the current phase lasts.
  Duration get phaseDuration => _phaseDuration;

  /// How much of the current phase is left, floored at zero.
  Duration get phaseRemaining {
    final Duration left = _phaseDuration - _phaseClock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Every sample that has been logged; the count a person checks against the on-screen tally.
  int get loggedSampleCount => writer.lineCount;

  /// Path of the JSONL file being written, or null when there is no writable directory.
  String? get logPath => writer.logPath;

  /// The directory a run's files go in, or null when the platform offered none.
  ///
  /// Distinct from [logPath]: the file does not exist until a run starts, so a screen that only
  /// showed [logPath] would report "no writable directory" for the whole time before the first run,
  /// which is a different and much more alarming statement.
  String? get logDirectory => writer.directory;

  /// Path of the run's info file, or null until it has been written.
  String? get infoPath => writer.infoPath;

  /// The most recent sample of any kind, for the live readout.
  InkLatencySample? get lastSample => _lastSample;

  /// How many strokes the native surface has committed since the run started.
  int get committedStrokes => _committedStrokes;

  /// How many contacts the surface refused to draw because the platform called them palms.
  int get suppressedPalmContacts => _suppressedPalmContacts;

  /// How many contacts from non-owning pointers were observed while a stroke was drawing.
  int get concurrentContactSamples => _concurrentContactSamples;

  /// Largest contact width seen among those non-owning contacts, in surface pixels.
  double get concurrentMaxTouchMajorPx => _concurrentMaxTouchMajorPx;

  /// The surface description read at the start of the run, or null before it was read.
  InkSurfaceInfo? get surfaceInfo => _surfaceInfo;

  /// The device label written into every record.
  String get deviceLabel => _deviceLabel;

  /// Whether the display pipeline's own frame timeline ever answered.
  bool get timelineDelivered => _timelineDelivered;

  /// Whether a frame-timeline poster was in use at all.
  bool get usedTimelinePoster => _usedTimelinePoster;

  /// The precision of the input timestamps, as the surface reported it.
  String get eventTimePrecision => _eventTimePrecision;

  /// The observations of palm and concurrent contacts, newest last.
  List<InkPalmObservation> get palmObservations =>
      List<InkPalmObservation>.unmodifiable(_palmObservations);

  /// The budget in milliseconds for [kind], or null when no budget is defined for it.
  ///
  /// Null is returned rather than a default: an unknown pointer kind has no acceptance criterion,
  /// and comparing it against the finger budget would invent one.
  static double? budgetFor(InkPointerKind kind) => switch (kind) {
    InkPointerKind.sPen || InkPointerKind.sPenEraser => sPenBudgetMs,
    InkPointerKind.finger => fingerBudgetMs,
    InkPointerKind.palm ||
    InkPointerKind.mouse ||
    InkPointerKind.unknown => null,
  };

  /// Records the surface description read before the run.
  void noteSurfaceInfo(InkSurfaceInfo info, {required bool timelineDelivered}) {
    _surfaceInfo = info;
    _timelineDelivered = timelineDelivered;
    _usedTimelinePoster = info.usedTimelinePoster;
    _eventTimePrecision = info.eventTimePrecision;
    _deviceLabel = info.deviceModel.isEmpty
        ? 'android${info.androidRelease} api${info.apiLevel}'
        : '${info.deviceModel} android${info.androidRelease} api${info.apiLevel}';
    notifyListeners();
  }

  // PURPOSE: Begin a run with the protocol's order enforced: a discard window, then the measured
  //          window. Doing them in one action is what keeps the order from being forgotten, because
  //          a measured window that followed no warm-up is not comparable to one that did.
  // INPUTS: warmup and measure — the two window durations.
  // OUTPUTS: Nothing. Any previous run is reset, the file is opened, and the phase becomes
  //          [BenchPhase.warmup].
  // KEYWORDS: start-run, warm-up-first, reset, protocol-order
  /// Begins a run: opens the log, then runs a discard window before the measured window.
  Future<void> start({
    required Duration warmup,
    required Duration measure,
  }) async {
    stop();
    await reset();
    await writer.open();
    _measureDuration = measure;
    _phase = BenchPhase.warmup;
    _phaseDuration = warmup;
    _startTick();
    notifyListeners();
  }

  /// Ends whichever window is running and leaves the recorder in [BenchPhase.finished].
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _phaseClock.stop();
    if (_phase == BenchPhase.warmup || _phase == BenchPhase.measuring) {
      _phase = BenchPhase.finished;
      unawaited(_finish());
    }
    notifyListeners();
  }

  /// Clears every measurement and returns to [BenchPhase.idle].
  Future<void> reset() async {
    _ticker?.cancel();
    _ticker = null;
    _phaseClock
      ..stop()
      ..reset();
    _warmupByKind.clear();
    _measuredByKind.clear();
    _palmObservations.clear();
    _lastSample = null;
    _committedStrokes = 0;
    _suppressedPalmContacts = 0;
    _concurrentContactSamples = 0;
    _concurrentMaxTouchMajorPx = 0;
    _phase = BenchPhase.idle;
    _phaseDuration = Duration.zero;
    notifyListeners();
  }

  // PURPOSE: Accept one sample and decide whether it counts, so the logging decision lives with the
  //          window definition instead of with the widget that paints the screen.
  // INPUTS: sample — one measured sample from the platform.
  // OUTPUTS: Nothing. In [BenchPhase.measuring] the sample is logged immediately, before any
  //          statistics are updated, so a crash mid-run leaves the file with everything measured so
  //          far. In [BenchPhase.warmup] it is counted for display only. In the other phases it is
  //          ignored, which is what makes the warm-up exclusion structural rather than a filter
  //          somebody has to remember to apply.
  // KEYWORDS: warm-up-exclusion, log-first, ignore-when-idle
  /// Accepts one sample and decides whether it counts.
  void acceptSample(InkLatencySample sample) {
    if (!sample.touchToPresentMs.isFinite) {
      return;
    }
    if (_phase == BenchPhase.warmup) {
      _lastSample = sample;
      _warmupByKind
          .putIfAbsent(sample.pointerKind, () => <double>[])
          .add(sample.touchToPresentMs);
      return;
    }
    if (_phase == BenchPhase.measuring) {
      _lastSample = sample;
      _measuredByKind
          .putIfAbsent(sample.pointerKind, () => <double>[])
          .add(sample.touchToPresentMs);
      // Written before the statistics are recomputed: a device killed mid-run leaves a file with
      // every measured sample, which is the whole reason this format appends.
      writer.writeSample(
        sample,
        info: _surfaceInfo ?? _unsupportedInfo(),
        device: _deviceLabel,
      );
    }
  }

  /// Accepts one contact observation, keeping only the most recent [maxObservations].
  ///
  /// The surface-level palm counters are summed here rather than read from the surface description,
  /// because a description read at the start of a run cannot know what happened during it. Every
  /// number below is derived from observations the surface actually sent, so a zero means the
  /// surface never reported a palm contact — which is the finding, not an absence of data.
  void acceptPalmObservation(
    InkPalmObservation observation, {
    int maxObservations = 200,
  }) {
    _palmObservations.add(observation);
    if (_palmObservations.length > maxObservations) {
      _palmObservations.removeAt(0);
    }
    if (!observation.drawAdmitted) {
      _suppressedPalmContacts++;
    }
    _concurrentContactSamples += observation.concurrentPointerSamples;
    if (observation.concurrentMaxTouchMajorPx > _concurrentMaxTouchMajorPx) {
      _concurrentMaxTouchMajorPx = observation.concurrentMaxTouchMajorPx;
    }
  }

  /// Counts a stroke the native surface committed.
  void acceptCommittedStroke(CommittedStroke stroke) {
    _committedStrokes++;
  }

  /// The statistics of [kind] over the measured window.
  BenchStats measuredStats(InkPointerKind kind) =>
      BenchStats.of(_measuredByKind[kind] ?? const <double>[]);

  /// The statistics of [kind] over the warm-up window.
  BenchStats warmupStats(InkPointerKind kind) =>
      BenchStats.of(_warmupByKind[kind] ?? const <double>[]);

  /// The pointer kinds that produced at least one measured sample, in a stable order.
  List<InkPointerKind> get measuredKinds {
    // Ordered by the enum's own declaration so the screen does not reshuffle between runs.
    return <InkPointerKind>[
      for (final InkPointerKind kind in InkPointerKind.values)
        if ((_measuredByKind[kind] ?? const <double>[]).isNotEmpty) kind,
    ];
  }

  /// Whether the p95 of [kind] is within its budget; null when there is no sample or no budget.
  bool? passesBudget(InkPointerKind kind) {
    final double? budget = budgetFor(kind);
    final double? p95 = measuredStats(kind).p95Ms;
    if (budget == null || p95 == null) {
      return null;
    }
    return p95 <= budget;
  }

  /// Writes the run's non-latency facts next to the log.
  Future<void> writeRunInfo({required Map<String, Object?> extra}) async {
    final Map<String, Object?> info = <String, Object?>{
      'run': writer.runId,
      'device': _deviceLabel,
      'phase': _phase.name,
      'loggedSampleCount': writer.lineCount,
      'committedStrokes': _committedStrokes,
      'suppressedPalmContacts': _suppressedPalmContacts,
      'concurrentContactSamples': _concurrentContactSamples,
      'concurrentMaxTouchMajorPx': _concurrentMaxTouchMajorPx,
      'timelineDelivered': _timelineDelivered,
      'usedTimelinePoster': _usedTimelinePoster,
      'eventTimePrecision': _eventTimePrecision,
      'budgetsMs': <String, Object?>{
        'sPen': sPenBudgetMs,
        'finger': fingerBudgetMs,
      },
      'measuredStats': <String, Object?>{
        for (final InkPointerKind kind in measuredKinds)
          kind.wireName: <String, Object?>{
            'count': measuredStats(kind).count,
            'p50': measuredStats(kind).p50Ms,
            'p95': measuredStats(kind).p95Ms,
            'max': measuredStats(kind).maxMs,
            'budget': budgetFor(kind),
            'passes': passesBudget(kind),
          },
      },
      'palmObservations': <Map<String, Object?>>[
        for (final InkPalmObservation observation in _palmObservations)
          <String, Object?>{
            'strokeId': observation.strokeId,
            'pointerType': observation.pointerKind.wireName,
            'eventCount': observation.eventCount,
            'maxTouchMajorPx': observation.maxTouchMajorPx,
            'meanTouchMajorPx': observation.meanTouchMajorPx,
            'rawToolType': observation.rawToolType,
            'drawAdmitted': observation.drawAdmitted,
            'concurrentPointerSamples': observation.concurrentPointerSamples,
            'concurrentMaxTouchMajorPx': observation.concurrentMaxTouchMajorPx,
          },
      ],
      'extra': extra,
    };
    await writer.writeInfo(info);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  void _startTick() {
    _ticker?.cancel();
    _phaseClock
      ..reset()
      ..start();
    // 100 ms is fast enough that a person sees the countdown and the tally move, and slow enough
    // that refreshing the screen is not itself work on the drawing path.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      if (_phaseClock.elapsed >= _phaseDuration) {
        _advancePhase();
      }
      notifyListeners();
    });
  }

  void _advancePhase() {
    if (_phase == BenchPhase.warmup) {
      // The warm-up window is discarded here, by moving to a phase that starts its own lists. Any
      // warm-up sample that arrives after this boundary is counted as measured, which is the
      // honest behaviour: the phone does not tell us which window a sample belonged to.
      _phase = BenchPhase.measuring;
      _phaseDuration = _measureDuration;
      _phaseClock
        ..reset()
        ..start();
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    _phaseClock.stop();
    _phase = BenchPhase.finished;
    unawaited(_finish());
  }

  Duration _measureDuration = Duration.zero;

  Future<void> _finish() async {
    await writeRunInfo(
      extra: <String, Object?>{
        'note':
            'Records in the .jsonl file are per drawn sample and all carry '
            'touchToPresentMs and pointerType, so logview reports no missing metric.',
      },
    );
    await writer.close();
  }

  InkSurfaceInfo _unsupportedInfo() => const InkSurfaceInfo(
    platformViewMode: 'none',
    presentationSource: InkPresentationSource.vsyncPlusDelay,
    apiLevel: 0,
    refreshRateHz: 0,
    clockOffsetMs: 0,
    clockOffsetDriftMs: 0,
    deviceModel: '',
    androidRelease: '',
    eventTimePrecision: 'unknown',
    usedTimelinePoster: false,
  );
}
