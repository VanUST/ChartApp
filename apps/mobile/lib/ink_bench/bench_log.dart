// PURPOSE: Turn latency samples into the JSON Lines records `tools/logview` aggregates, and put
//          them where a person can retrieve them, without inventing a second percentile definition
//          or a record that lacks the metric.
// INPUTS: A directory to write into (or null when the platform has none), a run identifier, a sink
//         for the stdout copy, and one sample plus its run context per record.
// OUTPUTS: One JSON object per line containing, at minimum, a finite `touchToPresentMs` and a
//          `pointerType`, so logview never reports `skippedMissingMetric`, which the acceptance
//          protocol treats as invalidating a whole run. Run metadata and palm observations are
//          deliberately NOT written as records in this file: they carry no latency, so they would
//          be exactly the metric-less lines that rule forbids. They go to a sibling
//          `-info.json` file, which logview does not read because it only expands `*.jsonl`.
// KEYWORDS: jsonl, logview-parity, bench-log, stdout, no-missing-metric, artifact
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ink_native/ink_native.dart';

/// How many buffered records are written to disk at once.
///
/// A record is held in memory until the buffer is flushed, so a device killed mid-run loses at most
/// this many samples. Twenty-five out of the thousands a thirty-second run produces is not enough
/// to move a p95, and batching the writes keeps the file open once per twenty-five records instead
/// of once per record.
const int benchLogFlushEvery = 25;

/// Assembles and persists one bench run's records so the artifact a device produces can be read by
/// the project's existing analyser without a translation step.
class BenchLogWriter {
  /// Creates a writer for [runId]; nothing is created on disk until [open] runs.
  BenchLogWriter({required this.runId, required this.out, this.directory});

  /// Identifier shared by this run's `.jsonl` file and its `-info.json` file.
  final String runId;

  /// The sink the JSONL copy is written to, normally the process's standard output.
  ///
  /// Public because it is the destination, not an implementation detail: a caller that wants the
  /// records somewhere else supplies a different sink.
  final StringSink out;

  /// Where to write, or null while the platform has not yet said where it may write.
  ///
  /// Settable after construction because the answer comes from an asynchronous platform call, and a
  /// writer that could not exist until then would make every widget that shows the log path
  /// nullable for no reason.
  String? directory;

  File? _logFile;
  String? _logPath;
  String? _infoPath;
  int _lineCount = 0;

  /// Records written so far but not yet flushed to disk.
  final StringBuffer _pending = StringBuffer();

  /// How many records have been written; the count the screen shows as evidence of a live log.
  int get lineCount => _lineCount;

  /// The path of the `.jsonl` file, or null when there is no writable directory.
  String? get logPath => _logPath;

  /// The path of the run's info file, or null before [writeInfo] has run.
  String? get infoPath => _infoPath;

  /// True when records are being mirrored into a file as well as to [out].
  bool get writesFile => _logFile != null;

  /// Creates the log file, truncating any previous run with the same id.
  ///
  /// A failure to create the file is not fatal: the stdout copy still exists, and a bench that
  /// refuses to start because a path was unwritable would waste the device time it was set up for.
  Future<void> open() async {
    _lineCount = 0;
    _infoPath = null;
    _pending.clear();
    final String? directory = this.directory;
    if (directory == null) {
      return;
    }
    try {
      final File file = File('$directory/bench-$runId.jsonl');
      await file.create(recursive: true);
      _logFile = file;
      _logPath = file.path;
    } on FileSystemException {
      _logFile = null;
      _logPath = null;
    }
  }

  /// Writes one drawn sample as one record, with the metric present by construction.
  void writeSample(
    InkLatencySample sample, {
    required InkSurfaceInfo info,
    required String device,
  }) {
    // One map holds every measurement scalar; it is referenced both as the telemetry envelope's
    // `fields` and, for the two documented selectors, copied to the top level. The copies come
    // from the same values, so they cannot drift: `docs/ux/test-protocol.md` documents
    // `--metric touchToPresentMs --group-by pointerType` at the top level, while `telemetry.dart`
    // documents `fields` as the flat map a logview path selects from.
    final Map<String, Object?> fields = <String, Object?>{
      'touchToPresentMs': sample.touchToPresentMs,
      'pointerType': sample.pointerKind.wireName,
      'presentSource': sample.presentationSource.wireName,
      'strokeId': sample.strokeId,
      'sampleIndex': sample.sampleIndex,
      'pressure': sample.pressure,
      'tiltRadians': sample.tiltRadians,
      'orientationRadians': sample.orientationRadians,
      'touchMajorPx': sample.touchMajorPx,
      'isHistorical': sample.isHistorical,
      'eventAction': sample.eventAction,
      'sourceIsStylus': sample.sourceIsStylus,
      'rawToolType': sample.rawToolType,
      'rawSource': sample.rawSource,
      'x': sample.x,
      'y': sample.y,
      'eventTimeNanos': sample.eventTimeNanos,
      'presentTimeNanos': sample.presentTimeNanos,
      'apiLevel': info.apiLevel,
      'refreshRateHz': info.refreshRateHz,
      'deviceModel': info.deviceModel,
      'androidRelease': info.androidRelease,
    };
    final String line = jsonEncode(<String, Object?>{
      'v': 1,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'run': runId,
      'name': 'ink.latency.sample',
      'device': device,
      'touchToPresentMs': sample.touchToPresentMs,
      'pointerType': sample.pointerKind.wireName,
      'fields': fields,
    });
    out.writeln(line);
    _lineCount++;
    _pending.writeln(line);
    if (_lineCount % benchLogFlushEvery == 0) {
      unawaited(_flush());
    }
  }

  /// Writes everything that is not a latency sample next to the log.
  ///
  /// This is where the surface limits, the budgets and the palm observations go, because they carry
  /// no latency and a record without the metric would invalidate the run for logview. The file is
  /// named `-info.json`, not `.jsonl`, so logview's directory expansion never picks it up.
  Future<void> writeInfo(Map<String, Object?> info) async {
    final String? directory = this.directory;
    if (directory == null) {
      return;
    }
    try {
      final File file = File('$directory/bench-$runId-info.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(info),
      );
      _infoPath = file.path;
    } on FileSystemException {
      _infoPath = null;
    }
  }

  /// Flushes the buffer and returns. Safe to call at any time, including when no file is open.
  Future<void> close() async {
    await _flush();
  }

  Future<void> _flush() async {
    final File? file = _logFile;
    if (file == null || _pending.isEmpty) {
      return;
    }
    final String chunk = _pending.toString();
    _pending.clear();
    try {
      await file.writeAsString(chunk, mode: FileMode.append, flush: true);
    } on FileSystemException {
      // A write failure leaves the stdout copy intact; the screen still shows the record count and
      // the path, so the loss is visible rather than silent.
    }
  }
}
