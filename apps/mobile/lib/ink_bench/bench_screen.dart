// PURPOSE: Show the ink bench on the device that can produce the number, and make what the number
//          does and does not include impossible to miss while standing at the tablet. It owns the
//          screen, the two windows of a run, and the path of the artifact; it owns no measurement
//          logic, which lives in the recorder and behind the platform channel.
// INPUTS: The ink platform implementation installed at startup, and taps on its buttons.
// OUTPUTS: A drawing area hosting the native surface, a live per-pointer-kind verdict against the
//          45 ms stylus and 60 ms finger budgets, the palm and contact observations, a list of the
//          measurement's own limits, and the path of the JSONL log being written.
// KEYWORDS: bench-screen, hud, verdict, budget, limits, warm-up, protocol
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ink_native/ink_native.dart';

import 'bench_log.dart';
import 'bench_stats.dart';
import 'ink_surface_host.dart';
import 'latency_recorder.dart';

/// The bench screen: the native ink surface plus everything needed to run and read a measurement.
class BenchScreen extends StatefulWidget {
  /// Creates the bench screen.
  const BenchScreen({super.key});

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  late final BenchLogWriter _writer;
  late final LatencyRecorder _recorder;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  bool _ready = false;
  String _status = 'Warming up the platform…';
  int _committedStrokeCount = 0;

  @override
  void initState() {
    super.initState();
    _writer = BenchLogWriter(runId: _newRunId(), out: stdout);
    _recorder = LatencyRecorder(writer: _writer)..addListener(_onRecorderTick);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _recorder
      ..removeListener(_onRecorderTick)
      ..dispose();
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_writer.close());
    super.dispose();
  }

  void _onRecorderTick() {
    if (mounted) {
      setState(() {});
    }
  }

  // PURPOSE: Ask the platform what it can measure before offering to measure anything, so a run
  //          that cannot produce a number says why instead of showing zeroes. It also subscribes to
  //          the three measurement streams and learns where a log may be written.
  // INPUTS: None.
  // OUTPUTS: Nothing. Sets the status line and [ready]; on a platform with no native surface it
  //          leaves the screen in a state that explains the absence rather than hiding the surface.
  // KEYWORDS: bootstrap, capability-probe, subscriptions, log-directory
  Future<void> _bootstrap() async {
    final InkNativePlatform ink = InkNativePlatform.instance;
    if (!ink.supportsInk) {
      setState(() {
        _status =
            'No native ink surface is registered on this platform. '
            'This bench needs an Android device with the ink_native_android '
            'implementation wired in.';
      });
      return;
    }
    try {
      await ink.initialize();
      final InkSurfaceInfo info = await ink.describeSurface();
      _writer.directory = await ink.benchLogDirectory();
      _recorder.noteSurfaceInfo(
        info,
        timelineDelivered:
            info.presentationSource == InkPresentationSource.frameTimeline,
      );
      _subscriptions.add(ink.onLatencySample.listen(_recorder.acceptSample));
      _subscriptions.add(
        ink.onPalmObservation.listen(_recorder.acceptPalmObservation),
      );
      _subscriptions.add(ink.onStrokeCommitted.listen(_onCommittedStroke));
    } on Object catch (error) {
      setState(() {
        _status = 'The ink platform refused to initialize: $error';
      });
      return;
    }
    setState(() {
      _ready = true;
      _status = 'Ready. Warm up first: the protocol discards the first window.';
    });
  }

  void _onCommittedStroke(CommittedStroke stroke) {
    _committedStrokeCount++;
    _recorder.acceptCommittedStroke(stroke);
  }

  Future<void> _startRun({
    required Duration warmup,
    required Duration measure,
  }) async {
    // Re-read before the first record is written, so every logged sample carries the real refresh
    // rate and the clock that actually answered rather than whatever was known at startup. Bounded
    // to a few attempts so a device that reports no rate cannot delay the start of a run.
    await _refreshSurfaceInfo(attempts: 3);
    await _recorder.start(warmup: warmup, measure: measure);
    if (mounted) {
      setState(() {
        _status = warmup == Duration.zero
            ? 'Measuring. Draw with the S Pen.'
            : 'Warming up — these samples are shown but NOT logged.';
      });
    }
  }

  // PURPOSE: End the running window and re-read the surface description, because the clock the
  //          surface ended up using is only known after it has delivered frames.
  // INPUTS: None.
  // OUTPUTS: Nothing. The log is flushed and the run's info file written by the recorder.
  // KEYWORDS: stop-run, final-description, flush
  Future<void> _stopRun() async {
    _recorder.stop();
    try {
      final InkSurfaceInfo info = await InkNativePlatform.instance
          .describeSurface();
      _recorder.noteSurfaceInfo(
        info,
        timelineDelivered:
            info.presentationSource == InkPresentationSource.frameTimeline,
      );
    } on Object {
      // A description read at stop time is a nicety; failing to read it must not lose the log.
    }
    if (mounted) {
      setState(() {
        _status = 'Run finished. The log is complete.';
      });
    }
  }

  Future<void> _reset() async {
    await _recorder.reset();
    await InkNativePlatform.instance.loadStrokes(const <InkStrokeBlob>[]);
    if (mounted) {
      setState(() {
        _committedStrokeCount = 0;
        _status = 'Reset. Start a new run when ready.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ink latency bench'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text('run ${_writer.runId}', style: _small)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The surface keeps a flexible share of the screen rather than a fixed height, so the
            // bench still works with the Book Cover keyboard attached, which makes the app window
            // shorter than the panel.
            Expanded(flex: 3, child: _surface()),
            const Divider(height: 1),
            Expanded(flex: 2, child: _hud()),
          ],
        ),
      ),
    );
  }

  Widget _surface() {
    if (!_ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_status, textAlign: TextAlign.center),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueGrey.shade200),
        color: Colors.white,
      ),
      child: InkSurfaceHost(onCreated: () => unawaited(_refreshSurfaceInfo())),
    );
  }

  // PURPOSE: Read the surface description once the native view exists, retrying briefly, because the
  //          description before that point truthfully says there is no surface and would make the
  //          bench report the no-op fallback on a device where the view is fine.
  // INPUTS: None.
  // OUTPUTS: Nothing. Updates the recorder with the real description, or stops after the bounded
  //          number of attempts and leaves the one it has, so a genuinely absent surface is still
  //          reported as absent rather than retried forever.
  // KEYWORDS: view-created, bounded-retry, honest-description
  Future<void> _refreshSurfaceInfo({int attempts = 15}) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      final bool lastAttempt = attempt == attempts - 1;
      try {
        final InkSurfaceInfo info = await InkNativePlatform.instance
            .describeSurface();
        // The refresh rate is only known once the view has been measured and attached, which can be
        // a frame or two after it is created. Waiting for it is what keeps the stored records from
        // claiming a 0 Hz display, which would make the 45 ms budget look unmeasurable rather than
        // merely unmet. On the final attempt a missing rate is accepted, so a device that genuinely
        // reports none is described as it is instead of retried forever.
        final bool described =
            info.platformViewMode != 'none' &&
            (info.refreshRateHz > 0 || lastAttempt);
        if (described) {
          _recorder.noteSurfaceInfo(
            info,
            timelineDelivered:
                info.presentationSource == InkPresentationSource.frameTimeline,
          );
          return;
        }
      } on Object {
        // Treated as "not ready yet"; the loop is bounded so this cannot spin.
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Widget _hud() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: <Widget>[
        _controls(),
        const SizedBox(height: 8),
        _facts(),
        const SizedBox(height: 8),
        _verdicts(),
        const SizedBox(height: 8),
        _palm(),
        const SizedBox(height: 8),
        _limits(),
      ],
    );
  }

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The status lives here rather than in the app bar because it is a sentence, and an app bar
        // clips it on a narrow window such as the one a Book Cover keyboard leaves.
        Text(_status, style: _small),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton(
              onPressed: _ready
                  ? () => unawaited(
                      _startRun(
                        warmup: const Duration(seconds: 30),
                        measure: const Duration(seconds: 30),
                      ),
                    )
                  : null,
              child: const Text('Protocol: 30 s warm-up + 30 s measure'),
            ),
            OutlinedButton(
              onPressed: _ready
                  ? () => unawaited(
                      _startRun(
                        warmup: const Duration(seconds: 5),
                        measure: const Duration(seconds: 10),
                      ),
                    )
                  : null,
              child: const Text('Quick: 5 s + 10 s'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(_stopRun()),
              child: const Text('Stop'),
            ),
            TextButton(
              onPressed: () => unawaited(_reset()),
              child: const Text('Reset'),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '${_recorder.phase.name}  |  '
                '${_recorder.phaseRemaining.inSeconds}s left  |  '
                'logged ${_recorder.loggedSampleCount}  |  '
                'strokes $_committedStrokeCount',
                style: _small,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _facts() {
    final InkSurfaceInfo? info = _recorder.surfaceInfo;
    final String display =
        'apiLevel: ${info?.apiLevel ?? 0}   '
        'refreshHz: ${(info?.refreshRateHz ?? 0).toStringAsFixed(1)}   '
        'platformViewMode: ${info?.platformViewMode ?? 'unknown'}';
    final String clocks =
        'presentSource: ${info?.presentationSource.wireName ?? 'unknown'}   '
        'timelinePoster: ${_recorder.usedTimelinePoster}   '
        'timelineDelivered: ${_recorder.timelineDelivered}';
    final String precision =
        'eventTimePrecision: ${_recorder.eventTimePrecision}   '
        'clockOffsetMs: ${(info?.clockOffsetMs ?? 0).toStringAsFixed(3)}   '
        'clockDriftMs: ${(info?.clockOffsetDriftMs ?? 0).toStringAsFixed(3)}';
    return _card('What is measuring', <String>[
      'device: ${_recorder.deviceLabel}',
      display,
      clocks,
      precision,
      'log dir: ${_recorder.logDirectory ?? '(none offered by the platform)'}',
      'log file: ${_recorder.logPath ?? '(created when a run starts)'}',
      'info file: ${_recorder.infoPath ?? '(written when a run ends)'}',
    ]);
  }

  Widget _verdicts() {
    final List<InkPointerKind> kinds = <InkPointerKind>[
      InkPointerKind.sPen,
      InkPointerKind.finger,
      for (final InkPointerKind kind in _recorder.measuredKinds)
        if (kind != InkPointerKind.sPen && kind != InkPointerKind.finger) kind,
    ];
    return _card(
      'Read this: p95 per pointer type  (measured window only)',
      <String>[
        for (final InkPointerKind kind in kinds) _verdictLine(kind),
        'last sample: ${_lastSampleLine()}',
      ],
    );
  }

  String _verdictLine(InkPointerKind kind) {
    final BenchStats stats = _recorder.measuredStats(kind);
    final double? budget = LatencyRecorder.budgetFor(kind);
    final bool? passes = _recorder.passesBudget(kind);
    final String verdict = passes == null
        ? (budget == null ? 'no budget defined' : 'no data yet')
        : passes
        ? 'PASS'
        : 'FAIL';
    final String p50 = stats.p50Ms == null
        ? '-'
        : stats.p50Ms!.toStringAsFixed(2);
    final String p95 = stats.p95Ms == null
        ? '-'
        : stats.p95Ms!.toStringAsFixed(2);
    return '${kind.wireName.padRight(11)} n=${stats.count.toString().padLeft(5)}  '
        'p50=${p50.padLeft(6)}  p95=${p95.padLeft(6)}  '
        'budget=${budget == null ? '-' : budget.toStringAsFixed(0).padLeft(3)}  '
        '$verdict';
  }

  String _lastSampleLine() {
    final InkLatencySample? sample = _recorder.lastSample;
    if (sample == null) {
      return 'none yet';
    }
    return '${sample.pointerKind.wireName} '
        '${sample.touchToPresentMs.toStringAsFixed(2)} ms  '
        'pressure=${sample.pressure.toStringAsFixed(3)}  '
        'tilt=${(sample.tiltRadians * 180 / 3.141592653589793).toStringAsFixed(1)}deg  '
        'major=${sample.touchMajorPx.toStringAsFixed(1)} px  '
        'historical=${sample.isHistorical}  '
        'toolType=${sample.rawToolType}  '
        'source=0x${sample.rawSource.toRadixString(16)}';
  }

  Widget _palm() {
    final String howToRead =
        'How to read it: rest a palm on the glass while drawing with the pen. '
        'If both numbers stay 0, the palm never reached the app — the '
        'digitizer removed it upstream and this app cannot see it. If the '
        'count rises, a palm DID arrive and was ignored; a large width is '
        'the signature of an unfiltered palm the platform called a finger.';
    final String suppressed =
        'platform-classified palm contacts suppressed: '
        '${_recorder.suppressedPalmContacts}';
    final String concurrent =
        'contacts from a non-owning pointer during a stroke: '
        '${_recorder.concurrentContactSamples}';
    final String largest =
        'largest such contact: '
        '${_recorder.concurrentMaxTouchMajorPx.toStringAsFixed(1)} px';
    final List<String> lines = <String>[suppressed];
    lines
      ..add(concurrent)
      ..add(largest)
      ..add(howToRead);
    return _card(
      'Palm and contact observation (what arrived, not what was assumed)',
      lines,
    );
  }

  Widget _limits() {
    final InkSurfaceInfo? info = _recorder.surfaceInfo;
    final InkPresentationSource source =
        info?.presentationSource ?? InkPresentationSource.vsyncPlusDelay;
    final double refreshHz = (info?.refreshRateHz ?? 60).clamp(1, 240);
    final String measured =
        'MEASURED: touchToPresentMs = (expected presentation time of the frame '
        'that first drew the sample) - (the sample event timestamp).';
    final String included =
        'INCLUDED: digitizer-to-app delivery, this view\'s own drawing of every '
        'coalesced sample, the rest of the app\'s work in that frame, and '
        'compositor scheduling.';
    final String excluded =
        'EXCLUDED, so this UNDER-states true input-to-photon latency: the '
        'digitizer and kernel work before the event is stamped, and the '
        'display panel\'s own latency after the compositor presents.';
    final String presentation = source == InkPresentationSource.vsyncPlusDelay
        ? 'ON THIS DEVICE the presentation time is a LOWER BOUND: it is '
              'frameTimeNanos + one refresh period '
              '(${(1e9 / refreshHz).toStringAsFixed(2)} ms), which assumes the '
              'frame met its deadline. A missed frame slips a full interval '
              'that this cannot see at this API level.'
        : 'ON THIS DEVICE the presentation time is the display pipeline\'s own '
              'frame timeline, so a missed deadline is reported as late.';
    final String precision = _recorder.eventTimePrecision == 'millisecond'
        ? 'Input timestamps are quantised to 1 ms (getEventTimeNanos is public '
              'only from API 34), so every sample carries up to 0.5 ms of '
              'quantisation.'
        : 'Input timestamps carry nanosecond precision.';
    final String texture =
        'Hybrid composition: the surface is a real view in the Android '
        'hierarchy, so there is no PlatformView texture copy in this path; had '
        'the texture path been used, one copy and possibly one extra frame '
        'would sit between the native frame and the presented one.';
    final String injected =
        'An injected touch (adb shell input) has no stylus source, pressure or '
        'tilt, so it cannot produce the stylus figure. Only a person drawing '
        'with the S Pen can.';
    return _card('Limits of this number', <String>[
      measured,
      included,
      excluded,
      presentation,
      precision,
      texture,
      injected,
    ]);
  }

  Widget _card(String title, List<String> lines) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: _cardTitle),
            const SizedBox(height: 6),
            for (final String line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(line, style: _small),
              ),
          ],
        ),
      ),
    );
  }

  static String _newRunId() {
    final DateTime now = DateTime.now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        'T${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static const TextStyle _small = TextStyle(fontSize: 12, height: 1.3);

  static const TextStyle _cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
  );
}
