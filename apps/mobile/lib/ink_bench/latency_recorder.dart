// PURPOSE: Hold a bench run's state — which phase it is in, what has been measured so far, and what
//          the surface observed — and decide which samples count. It is the one place that knows
//          the difference between a warm-up sample, which is shown but never logged, and a measured
//          sample, which is logged and against which the thresholds are applied. It also owns the
//          two cross-checks a run's report is worthless without: whether the log's record count
//          matches the artifact, and whether the surface's contact-admission decisions match the
//          documented palm rule.
// INPUTS: Samples, palm observations and committed strokes pushed from the ink platform streams;
//         a [BenchLogWriter] to hand measured samples to; a clock for the phase countdown.
// OUTPUTS: Per-pointer-kind [BenchStats] for the measured window and for the warm-up window, the
//          phase and its remaining time, the log's count and integrity record, the palm counters
//          and every admission decision the surface reported, and a `notifyListeners()` at most
//          every 100 ms rather than once per sample, so refreshing the screen never becomes part of
//          what is measured.
// KEYWORDS: bench-state, warm-up-window, measurement-window, phase-machine, percentiles,
//           palm-rule-audit, log-integrity
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
  int _rejectedByPlatformToolType = 0;
  int _rejectedByPalmLikeWidth = 0;
  int _admittedPalmLikeWidthWithStylus = 0;
  int _admittedPalmLikeWidthWithoutStylus = 0;
  int _admittedThenExceededThreshold = 0;
  int _palmRuleDisagreements = 0;
  final List<int> _admittedPalmLikeWidthWithStylusStrokeIds = <int>[];
  final List<int> _admittedPalmLikeWidthWithoutStylusStrokeIds = <int>[];
  final List<int> _admittedThenExceededStrokeIds = <int>[];
  final List<int> _palmRuleDisagreementStrokeIds = <int>[];
  int _concurrentContactSamples = 0;
  double _concurrentMaxTouchMajorPx = 0;
  InkSurfaceInfo? _surfaceInfo;
  String _deviceLabel = 'unknown';
  bool _timelineDelivered = false;
  bool _usedTimelinePoster = false;
  String _eventTimePrecision = 'unknown';

  /// The end-of-run work, while it is running, so a restart can wait for it instead of racing it.
  Future<void>? _finishFuture;

  /// True while [_finishFuture] has not settled; guards against two end-of-run writes.
  bool _finishing = false;

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

  /// How many contacts the surface refused to draw.
  int get suppressedPalmContacts => _suppressedPalmContacts;

  /// How many of those rejections the platform decided by classifying the contact itself as a palm.
  int get rejectedByPlatformToolType => _rejectedByPlatformToolType;

  /// How many of those rejections the palm-width rule decided.
  int get rejectedByPalmLikeWidth => _rejectedByPalmLikeWidth;

  /// How many admitted contacts were palm-like by width AND had the pen in play.
  ///
  /// Expected to be zero: with the gate in place the rule refuses exactly this combination, so a
  /// non-zero value means a palm-like contact was drawn as ink while a stylus was in play. The run's
  /// info file states it at the top level instead of leaving it to be found in a list.
  int get admittedPalmLikeWidthWithStylus => _admittedPalmLikeWidthWithStylus;

  /// How many admitted contacts were palm-like by width but had NO pen in play.
  ///
  /// This is the touch-parity case working as intended: a wide finger draws when no stylus is in
  /// play. Counted separately from the line above so a legitimate wide finger can never be mistaken
  /// for the defect, and the same wide contact can be told apart by the pen's presence.
  int get admittedPalmLikeWidthWithoutStylus =>
      _admittedPalmLikeWidthWithoutStylus;

  /// How many admitted strokes were narrow at down and grew past the threshold during the stroke.
  ///
  /// Admission is decided once, on the down sample, so this can be non-zero; it is counted
  /// separately because "admitted while it looked like a finger" is a different finding from
  /// "admitted while it already looked like a palm".
  int get admittedThenExceededThreshold => _admittedThenExceededThreshold;

  /// How many strokes where the native decision disagreed with the documented rule.
  ///
  /// The documented rule is the Dart predicate and the native decision is the Kotlin mirror; this
  /// count is what keeps the two implementations from drifting silently.
  int get palmRuleDisagreements => _palmRuleDisagreements;

  /// Stroke identifiers of the admitted contacts that were palm-like with the pen in play.
  List<int> get admittedPalmLikeWidthWithStylusStrokeIds =>
      List<int>.unmodifiable(_admittedPalmLikeWidthWithStylusStrokeIds);

  /// Stroke identifiers of the admitted contacts that were palm-like with no pen in play.
  List<int> get admittedPalmLikeWidthWithoutStylusStrokeIds =>
      List<int>.unmodifiable(_admittedPalmLikeWidthWithoutStylusStrokeIds);

  /// Stroke identifiers of the admitted strokes that grew past the threshold.
  List<int> get admittedThenExceededStrokeIds =>
      List<int>.unmodifiable(_admittedThenExceededStrokeIds);

  /// Stroke identifiers where the native decision and the documented rule disagreed.
  List<int> get palmRuleDisagreementStrokeIds =>
      List<int>.unmodifiable(_palmRuleDisagreementStrokeIds);

  /// How many contacts from non-owning pointers were observed while a stroke was drawing.
  int get concurrentContactSamples => _concurrentContactSamples;

  /// Largest contact value seen among those non-owning contacts, in axis units.
  double get concurrentMaxTouchMajorPx => _concurrentMaxTouchMajorPx;

  /// Whether the writer lost records to failed writes.
  bool get logLossy => writer.lossy;

  /// The last read-back comparison of the reported count against the artifact.
  LogIntegrity? get logIntegrity => writer.integrity;

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
    // The previous run's close and read-back must settle before a new file is opened: its close
    // would otherwise land on the sink the new run just opened and truncate it.
    final Future<void>? previousFinish = _finishFuture;
    if (previousFinish != null) {
      try {
        await previousFinish;
      } on Object {
        // A failed end-of-run report must not stop the next run from starting; the failure is
        // already visible in the previous run's writer counters.
      }
    }
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
      _scheduleFinish();
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
    _rejectedByPlatformToolType = 0;
    _rejectedByPalmLikeWidth = 0;
    _admittedPalmLikeWidthWithStylus = 0;
    _admittedPalmLikeWidthWithoutStylus = 0;
    _admittedThenExceededThreshold = 0;
    _palmRuleDisagreements = 0;
    _admittedPalmLikeWidthWithStylusStrokeIds.clear();
    _admittedPalmLikeWidthWithoutStylusStrokeIds.clear();
    _admittedThenExceededStrokeIds.clear();
    _palmRuleDisagreementStrokeIds.clear();
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
  /// The surface-level counters are summed here rather than read from the surface description,
  /// because a description read at the start of a run cannot know what happened during it. Every
  /// number below is derived from observations the surface actually sent, so a zero means the
  /// surface never reported a contact of that kind — which is the finding, not an absence of data.
  ///
  /// The documented rule is re-run here on the numbers the surface reported. Three things come out
  /// of it: an explicit count of palm-like contacts that were admitted WITH the pen in play (the
  /// defect — expected zero), an explicit count of those admitted WITHOUT it (touch parity working
  /// as intended), and a disagreement count that catches the Dart predicate and the native mirror
  /// drifting apart. All three are written into the info file, so none has to be found by reading a
  /// list by hand.
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
      if (observation.admissionReason == PalmWidthRule.reasonPalmLikeWidth) {
        _rejectedByPalmLikeWidth++;
      } else if (observation.admissionReason ==
          PalmWidthRule.reasonPlatformPalm) {
        _rejectedByPlatformToolType++;
      }
    }

    final PalmContactDecision recomputed = PalmWidthRule.decide(
      kind: observation.pointerKind,
      touchMajor: observation.decidingTouchMajor,
      thresholdTouchMajor: observation.palmWidthThreshold,
      stylusInPlay: observation.stylusInPlay,
    );
    if (recomputed.admitted != observation.drawAdmitted ||
        recomputed.palmLikeWidth != observation.palmLikeWidth) {
      _palmRuleDisagreements++;
      _palmRuleDisagreementStrokeIds.add(observation.strokeId);
    }

    if (observation.drawAdmitted && observation.palmLikeWidth) {
      if (observation.stylusInPlay) {
        // The gate should have refused this. Getting here means a palm-like contact was drawn while
        // the pen was in play, which is the defect the rule exists to prevent.
        _admittedPalmLikeWidthWithStylus++;
        _admittedPalmLikeWidthWithStylusStrokeIds.add(observation.strokeId);
      } else {
        // Touch parity: a wide finger with no pen in play draws, by design.
        _admittedPalmLikeWidthWithoutStylus++;
        _admittedPalmLikeWidthWithoutStylusStrokeIds.add(observation.strokeId);
      }
    }
    if (observation.drawAdmitted &&
        !observation.palmLikeWidth &&
        observation.palmWidthThreshold > 0 &&
        PalmWidthRule.isPalmLikeWidth(
          touchMajor: observation.maxTouchMajorPx,
          thresholdTouchMajor: observation.palmWidthThreshold,
        )) {
      _admittedThenExceededThreshold++;
      _admittedThenExceededStrokeIds.add(observation.strokeId);
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
  ///
  /// Call it after the writer has closed, so the log's integrity record is available: the reported
  /// record count and the count read back from the artifact are the two numbers a reader compares,
  /// and this is the file that states both next to each other.
  Future<void> writeRunInfo({required Map<String, Object?> extra}) async {
    final LogIntegrity? integrity = writer.integrity;
    final Map<String, Object?> info = <String, Object?>{
      'run': writer.runId,
      'device': _deviceLabel,
      'phase': _phase.name,
      // The count the bench reports as logged, and the artifact's own count. They are equal when
      // `logIntegrityOk` is true, and the run is lossy when it is not.
      'loggedSampleCount': writer.lineCount,
      'writtenSampleCount': writer.writtenRecordCount,
      'logFile': writer.logPath,
      'logFileWritten': writer.writesFile,
      'logLossy': writer.lossy,
      'logWriteFailures': writer.flushFailureCount,
      'recordsLostToWriteFailures': writer.recordsLostToWriteFailures,
      'lastLogWriteError': writer.lastWriteError,
      'logIntegrityOk': integrity?.ok,
      'logIntegrity': integrity?.toJson(),
      'logWriteMode': 'single open IOSink per run, flushes chained on one future, failures counted',
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
      // The rule itself, so a run in which no contact was ever palm-like still records the
      // threshold it was judged by. A threshold nobody can see is a threshold nobody can check.
      'palmWidthRule': _palmRuleJson(),
      // The defect, stated explicitly: a palm-like contact drawn while the pen was in play. The
      // gate should make this zero.
      'admittedPalmLikeWidthWithStylus': <String, Object?>{
        'count': _admittedPalmLikeWidthWithStylus,
        'strokeIds': _admittedPalmLikeWidthWithStylusStrokeIds,
        'note':
            'A non-zero count means a contact whose compared value was at or above the palm '
            'threshold was admitted and drawn as ink WHILE a stylus was in play. It is stated here '
            'rather than left to be found among the per-stroke observations below.',
      },
      // Touch parity, stated explicitly: a palm-like width drawn because no pen was in play.
      'admittedPalmLikeWidthWithoutStylus': <String, Object?>{
        'count': _admittedPalmLikeWidthWithoutStylus,
        'strokeIds': _admittedPalmLikeWidthWithoutStylusStrokeIds,
        'note':
            'A wide contact admitted because no stylus had been seen within the proximity window. '
            'This is the touch-parity case working as intended, not a defect: with no pen in play a '
            'finger draws however wide it is.',
      },
      'admittedThenExceededPalmThreshold': <String, Object?>{
        'count': _admittedThenExceededThreshold,
        'strokeIds': _admittedThenExceededStrokeIds,
        'note':
            'Admission is decided once, on the pointer-down sample. These strokes were narrower '
            'than the threshold then and their maximum value later crossed it, so the rule could '
            'not have rejected them at down.',
      },
      'rejectedByPlatformToolType': _rejectedByPlatformToolType,
      'rejectedByPalmLikeWidth': _rejectedByPalmLikeWidth,
      'palmRuleDisagreements': _palmRuleDisagreements,
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
            'admissionReason': observation.admissionReason,
            'palmLikeWidth': observation.palmLikeWidth,
            'decidingTouchMajor': observation.decidingTouchMajor,
            'palmWidthThreshold': observation.palmWidthThreshold,
            'stylusInPlay': observation.stylusInPlay,
            'concurrentPointerSamples': observation.concurrentPointerSamples,
            'concurrentMaxTouchMajorPx': observation.concurrentMaxTouchMajorPx,
          },
      ],
      'extra': extra,
    };
    await writer.writeInfo(info);
    notifyListeners();
  }

  // PURPOSE: Publish the palm rule next to the run's numbers, so the artifact states the threshold,
  //          the unit it is in and the stylus gate even when no contact ever crossed it.
  // INPUTS: None; the rule constants, the surface's own values and the audit counters.
  // OUTPUTS: A flat map for the info file. The Dart constants and the surface's reported values sit
  //          side by side so a drift between the two implementations is visible rather than
  //          inferred; `constantsAgree` is that comparison.
  // KEYWORDS: palm-rule, threshold, unit, provenance, stylus-gate, audit, inspectable
  Map<String, Object?> _palmRuleJson() {
    final double surfaceThreshold = _surfaceInfo?.palmWidthThreshold ?? 0;
    final int surfaceWindow = _surfaceInfo?.palmStylusProximityWindowMs ?? 0;
    return <String, Object?>{
      'version': PalmWidthRule.version,
      'thresholdTouchMajor': PalmWidthRule.thresholdTouchMajor,
      'thresholdUnit': PalmWidthRule.thresholdUnit,
      'thresholdUnitEvidence': PalmWidthRule.thresholdUnitEvidence,
      'thresholdIsPhysicalLength': false,
      'densityScalingApplied': false,
      'comparison': 'palmLikeWidth = decidingTouchMajor >= thresholdTouchMajor (inclusive)',
      'stylusGate':
          'palmLikeWidth is REJECTED only while a stylus was seen within '
          'stylusProximityWindowMs; with no pen in play a finger draws however wide it is '
          '(touch parity)',
      'stylusProximityWindowMs': PalmWidthRule.stylusProximityWindowMs,
      'appliesTo':
          'every contact the platform did not classify as a stylus, eraser or mouse; a contact the '
          'platform classified as a palm is rejected whatever its width',
      'provenance': PalmWidthRule.provenance,
      'surfaceValues': <String, Object?>{
        'thresholdTouchMajor': surfaceThreshold,
        'stylusProximityWindowMs': surfaceWindow,
        'displayDensity': _surfaceInfo?.displayDensity ?? 0,
        'displayDensityUsedForThreshold': false,
        'stylusHoverEvents': _surfaceInfo?.stylusHoverEventCount ?? 0,
        'stylusHoverNote':
            'Hover is how the gate learns a pen is near the glass without it touching. Zero on a '
            'run made with a pen in hand means the proximity signal never reached the view, and '
            'the gate opened only during and just after pen strokes.',
      },
      'constantsAgree':
          surfaceThreshold == PalmWidthRule.thresholdTouchMajor &&
          surfaceWindow == PalmWidthRule.stylusProximityWindowMs,
      'disagreementsWithSurface': _palmRuleDisagreements,
      'disagreementStrokeIds': _palmRuleDisagreementStrokeIds,
    };
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
    _scheduleFinish();
  }

  Duration _measureDuration = Duration.zero;

  /// Starts the end-of-run work at most once, so a stop racing a phase change cannot write two
  /// info files or close the sink twice.
  void _scheduleFinish() {
    if (_finishing) {
      return;
    }
    _finishing = true;
    _finishFuture = _finish().whenComplete(() {
      _finishing = false;
    });
  }

  // PURPOSE: Close the log, check it against its own artifact, and write the run's info file, in
  //          that order, because the check needs the file closed and the report needs the check.
  // INPUTS: None; the recorder's counters and the writer's integrity record.
  // OUTPUTS: Nothing. Writes the info file, which is the only place the integrity result reaches a
  //          reader, and completes when it has. Does not throw for a failed write: a run that
  //          discovers a loss is exactly the run whose report must survive.
  // KEYWORDS: finish-run, close-log, integrity, info-file, ordering
  Future<void> _finish() async {
    await writer.close();
    final LogIntegrity? integrity = writer.integrity;
    await writeRunInfo(
      extra: <String, Object?>{
        'note':
            'Records in the .jsonl file are per drawn sample and all carry '
            'touchToPresentMs and pointerType, so logview reports no missing metric.',
        'logIntegrityCheck': integrity == null
            ? 'No log file was written, so there is no artifact to compare the count against.'
            : integrity.ok
            ? 'loggedSampleCount equals the number of valid records in the .jsonl file '
                  '(${integrity.validJsonRecordCount}), with ${integrity.tornLineCount} torn lines.'
            : 'THE ARTIFACT DISAGREES WITH THE REPORTED COUNT. Reported '
                  '${integrity.reportedRecordCount}, file lines ${integrity.fileLineCount}, '
                  'valid records ${integrity.validJsonRecordCount}, torn lines '
                  '${integrity.tornLineCount}, failed flushes ${integrity.flushFailureCount}, '
                  'records lost ${integrity.recordsLostCount}. The p95 above is not reproducible '
                  'from this file.',
        'palmRuleNote':
            'Every stroke carries an admission reason and the value, threshold and stylus-in-play '
            'fact that decided it, and the documented rule was re-run on those numbers; see '
            'palmWidthRule, admittedPalmLikeWidthWithStylus (the defect, expected 0) and '
            'admittedPalmLikeWidthWithoutStylus (touch parity).',
      },
    );
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
    displayDensity: 0,
    palmWidthThreshold: 0,
    palmStylusProximityWindowMs: 0,
    stylusHoverEventCount: 0,
  );
}
