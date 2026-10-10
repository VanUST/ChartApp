// PURPOSE: Turn latency samples into the JSON Lines records `tools/logview` aggregates, and put
//          them where a person can retrieve them, without inventing a second percentile definition
//          or a record that lacks the metric. It also owes the run an answer to "did every record
//          the bench counted actually reach the file", because a count whose artifact is missing
//          93% of its lines is worse than no count at all: the number gets quoted and the evidence
//          does not exist.
// INPUTS: A directory to write into (or null when the platform has none), a run identifier, a sink
//         for the stdout copy, and one sample plus its run context per record.
// OUTPUTS: One JSON object per line containing, at minimum, a finite `touchToPresentMs` and a
//          `pointerType`, so logview never reports `skippedMissingMetric`, which the acceptance
//          protocol treats as invalidating a whole run. Run metadata and palm observations are
//          deliberately NOT written as records in this file: they carry no latency, so they would
//          be exactly the metric-less lines that rule forbids. They go to a sibling
//          `-info.json` file, which logview does not read because it only expands `*.jsonl`.
//          Write failures are counted rather than swallowed, and [BenchLogWriter.close] reads the
//          file back and compares its record count with the counter, so a lossy run says so.
// KEYWORDS: jsonl, logview-parity, bench-log, stdout, no-missing-metric, artifact,
//           serialised-writes, single-sink, integrity-check
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ink_native/ink_native.dart';

/// How many buffered records are written to disk at once.
///
/// A record is held in memory until it is handed to the sink, so a device killed mid-run loses at
/// most this many samples. Twenty-five out of the thousands a thirty-second run produces is not
/// enough to move a p95. The batching is about how much is at risk between flushes, not about how
/// often the file is opened: the sink is opened once per run (see [BenchLogWriter.open]).
const int benchLogFlushEvery = 25;

// PURPOSE: Count the records in a JSONL document and separate the ones that parse from the torn
//          fragments a partially flushed or concurrently written file leaves behind, so the same
//          arithmetic can be used by the writer's own check and by a test.
// INPUTS: content — the whole file as text, possibly empty, possibly ending without a newline.
// OUTPUTS: A [JsonlRecordCounts]. Blank lines (including the one a trailing newline produces) are
//          not records and are not counted in any field. Never throws.
// KEYWORDS: jsonl, line-count, torn-record, integrity, parse
/// Counts the records in [content] and how many of them parse as a JSON object.
JsonlRecordCounts countJsonlRecords(String content) {
  int totalLines = 0;
  int validJsonRecords = 0;
  int tornLines = 0;
  for (final String rawLine in const LineSplitter().convert(content)) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    totalLines++;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      tornLines++;
      continue;
    }
    if (decoded is Map<Object?, Object?>) {
      validJsonRecords++;
    } else {
      // Parses, but is not a record: a bare number or a stray array is a fragment that happens to
      // be valid JSON, and counting it as a record would let a torn file look complete.
      tornLines++;
    }
  }
  return JsonlRecordCounts(
    totalLines: totalLines,
    validJsonRecords: validJsonRecords,
    tornLines: tornLines,
  );
}

// PURPOSE: Hold the three counts the integrity check produces, so a caller cannot read one of them
//          without the other two being available next to it.
// INPUTS: Built by [countJsonlRecords].
// OUTPUTS: Immutable non-negative counts; `totalLines` is always `validJsonRecords + tornLines`.
// KEYWORDS: record-count, valid, torn, integrity
/// How many lines a JSONL document has, and how many of them are usable records.
class JsonlRecordCounts {
  /// Creates a count from already-computed values.
  const JsonlRecordCounts({
    required this.totalLines,
    required this.validJsonRecords,
    required this.tornLines,
  });

  /// Non-blank lines in the document.
  final int totalLines;

  /// Lines that parse as a JSON object and are therefore usable records.
  final int validJsonRecords;

  /// Non-blank lines that do not parse as a JSON object.
  final int tornLines;
}

// PURPOSE: State, for one run, whether the record count the bench reported equals the number of
//          valid records in the artifact, so the claim and the evidence are compared in the
//          artifact itself instead of in someone's head.
// INPUTS: The reported count, the counts read back from the file, and the writer's own failure
//         counters.
// OUTPUTS: An immutable record with an [ok] flag. `ok` is true only when the file read back
//          cleanly, has exactly as many lines as were reported, all of them are valid records and
//          none is torn.
// KEYWORDS: integrity, assertion, record-count, torn-record, artifact
/// The result of reading a run's JSONL file back and comparing it with the logged count.
class LogIntegrity {
  /// Creates an integrity record from already-computed values.
  const LogIntegrity({
    required this.reportedRecordCount,
    required this.writtenRecordCount,
    required this.fileLineCount,
    required this.validJsonRecordCount,
    required this.tornLineCount,
    required this.flushFailureCount,
    required this.recordsLostCount,
    this.readError,
  });

  /// Records the bench counted as logged.
  final int reportedRecordCount;

  /// Records the writer handed to the sink and whose flush completed.
  final int writtenRecordCount;

  /// Non-blank lines found in the file.
  final int fileLineCount;

  /// Lines found in the file that parse as JSON objects.
  final int validJsonRecordCount;

  /// Lines found in the file that do not parse as JSON objects.
  final int tornLineCount;

  /// Flushes that threw.
  final int flushFailureCount;

  /// Records known to have been dropped because a flush failed or the sink was already broken.
  final int recordsLostCount;

  /// Why the file could not be read back, or null when it was read.
  final String? readError;

  /// Whether the reported count and the artifact agree.
  bool get ok =>
      readError == null &&
      fileLineCount == reportedRecordCount &&
      validJsonRecordCount == reportedRecordCount &&
      tornLineCount == 0;

  /// A flat map for the `-info.json` sidecar.
  Map<String, Object?> toJson() => <String, Object?>{
    'reportedRecordCount': reportedRecordCount,
    'writtenRecordCount': writtenRecordCount,
    'fileLineCount': fileLineCount,
    'validJsonRecordCount': validJsonRecordCount,
    'tornLineCount': tornLineCount,
    'flushFailureCount': flushFailureCount,
    'recordsLostCount': recordsLostCount,
    'readError': readError,
    'ok': ok,
  };
}

/// Assembles and persists one bench run's records so the artifact a device produces can be read by
/// the project's existing analyser without a translation step.
///
/// Writes are serialised. Every flush is appended to a single future chain, and the file is opened
/// once per run as one [IOSink] rather than reopened for every batch: a concurrent `append` open
/// gives two file descriptors racing at the same offset, which is what tore 31 lines out of the
/// owner's `bench-20261010T143629.jsonl` while the bench reported 9138 records for 640 usable
/// ones. A failure is counted, surfaced and re-checked against the file — never swallowed.
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
  int _writtenRecordCount = 0;
  int _flushFailureCount = 0;
  int _recordsLost = 0;
  String? _lastWriteError;
  LogIntegrity? _integrity;

  /// The run's sink, open from [open] until [close]; null when there is no file or it has failed.
  // This field IS closed — by [_closeSink], which [open] and [close] both call. The analyzer cannot
  // follow a close across two methods and asks for one in the creating function, which is exactly
  // what must NOT happen here: holding one descriptor for the whole run is the fix for the torn
  // file, so the lint is suppressed at this one field rather than the structure bent around it.
  // ignore: close_sinks
  IOSink? _sink;

  /// Set when the sink has failed and must not be written to again.
  bool _sinkBroken = false;

  /// The tail of the single chain every flush is appended to, so no two flushes overlap.
  Future<void> _chain = Future<void>.value();

  /// Records written so far but not yet handed to the sink.
  final StringBuffer _pending = StringBuffer();

  /// How many records have been accepted for logging; the count the screen shows as evidence of a
  /// live log. It is NOT yet evidence that the file holds them — [integrity] is.
  int get lineCount => _lineCount;

  /// How many records were handed to the sink and flushed successfully.
  int get writtenRecordCount => _writtenRecordCount;

  /// How many flushes threw. Non-zero means the file lost records.
  int get flushFailureCount => _flushFailureCount;

  /// How many records are known not to be in the file because a write failed.
  int get recordsLostToWriteFailures => _recordsLost;

  /// The most recent write error, or null when no write has failed.
  String? get lastWriteError => _lastWriteError;

  /// The last [verifyIntegrity] result, or null before one has run.
  LogIntegrity? get integrity => _integrity;

  /// True when records were lost, so the screen can say so without re-deriving the condition.
  bool get lossy => _recordsLost > 0 || _flushFailureCount > 0;

  /// The path of the `.jsonl` file, or null when there is no writable directory.
  String? get logPath => _logPath;

  /// The path of the run's info file, or null before [writeInfo] has run.
  String? get infoPath => _infoPath;

  /// True when records are being mirrored into a file as well as to [out].
  bool get writesFile => _logFile != null;

  /// Creates the log file and opens the one sink the whole run writes through.
  ///
  /// ONE SINK, NOT ONE OPEN PER FLUSH. `file.writeAsString(..., mode: append)` opens, writes and
  /// closes per call; two of them in flight on one path race at the same end offset and interleave
  /// their bytes, which is the torn-line failure this method exists to remove. A single [IOSink]
  /// holds one descriptor for the run, so appends are ordered by the chain in [flush] and a short
  /// write cannot land on top of another.
  ///
  /// A failure to create the file is not fatal: the stdout copy still exists, and a bench that
  /// refuses to start because a path was unwritable would waste the device time it was set up for.
  /// It is, however, visible: [writesFile] stays false and [logPath] stays null.
  Future<void> open() async {
    // Drain and retire anything left from a previous run before touching the new state, so a
    // chained flush from the previous run cannot write into the new file.
    await _chain;
    await _closeSink(markBroken: false);

    _lineCount = 0;
    _writtenRecordCount = 0;
    _flushFailureCount = 0;
    _recordsLost = 0;
    _lastWriteError = null;
    _integrity = null;
    _infoPath = null;
    _sinkBroken = false;
    _pending.clear();
    _logFile = null;
    _logPath = null;

    final String? directory = this.directory;
    if (directory == null) {
      return;
    }
    try {
      final File file = File('$directory/bench-$runId.jsonl');
      await file.create(recursive: true);
      _logFile = file;
      _logPath = file.path;
      _sink = file.openWrite(mode: FileMode.write);
    } on FileSystemException catch (error) {
      _logFile = null;
      _logPath = null;
      _sink = null;
      _sinkBroken = true;
      _lastWriteError = error.toString();
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
      unawaited(flush());
    }
  }

  /// Hands everything buffered so far to the sink and returns a future for that write.
  ///
  /// The buffer is taken synchronously, before the chain is extended, so a record written while a
  /// flush is queued lands in the NEXT chunk and cannot appear in two chunks or be dropped by one.
  /// Every returned future resolves when that chunk and every chunk before it has been written.
  Future<void> flush() {
    final String chunk = _pending.toString();
    _pending.clear();
    if (chunk.isEmpty) {
      return _chain;
    }
    _chain = _chain.then((_) => _writeChunk(chunk));
    return _chain;
  }

  /// Writes everything that is not a latency sample next to the log.
  ///
  /// This is where the surface limits, the budgets, the palm observations and the log's own
  /// integrity check go, because they carry no latency and a record without the metric would
  /// invalidate the run for logview. The file is named `-info.json`, not `.jsonl`, so logview's
  /// directory expansion never picks it up.
  ///
  /// It must be called after [close] when the integrity result is wanted, because [close] is what
  /// reads the file back.
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

  /// Flushes whatever is buffered, closes the run's sink and verifies the artifact.
  ///
  /// Safe to call at any time, including when no file is open; a second call is a no-op apart from
  /// re-running the read-back check. The sink is closed only after every chained write has settled,
  /// so a close can never truncate a write that was still in flight.
  Future<void> close() async {
    await flush();
    await _chain;
    await _closeSink(markBroken: false);
    _integrity = await verifyIntegrity();
  }

  /// Reads the log back and compares what is in it with the count the bench reported.
  ///
  /// This is the check that makes the reported count falsifiable: it is not a promise that the
  /// writes worked, it is a measurement of whether they did. It is deliberately a returned record
  /// and not a thrown error, because the run that discovers a loss is the one whose `-info.json`
  /// must say so; aborting the write would destroy the evidence that the loss happened.
  ///
  /// Returns null when there is no file. A file that cannot be read yields a record whose
  /// `readError` is set and whose [LogIntegrity.ok] is false.
  Future<LogIntegrity?> verifyIntegrity() async {
    final File? file = _logFile;
    if (file == null) {
      return null;
    }
    String content;
    try {
      content = await file.readAsString();
    } on FileSystemException catch (error) {
      return LogIntegrity(
        reportedRecordCount: _lineCount,
        writtenRecordCount: _writtenRecordCount,
        fileLineCount: 0,
        validJsonRecordCount: 0,
        tornLineCount: 0,
        flushFailureCount: _flushFailureCount,
        recordsLostCount: _recordsLost,
        readError: error.toString(),
      );
    }
    final JsonlRecordCounts counts = countJsonlRecords(content);
    return LogIntegrity(
      reportedRecordCount: _lineCount,
      writtenRecordCount: _writtenRecordCount,
      fileLineCount: counts.totalLines,
      validJsonRecordCount: counts.validJsonRecords,
      tornLineCount: counts.tornLines,
      flushFailureCount: _flushFailureCount,
      recordsLostCount: _recordsLost,
    );
  }

  /// Writes one chunk to the run's sink, counting the records it carries.
  ///
  /// Never throws, so one failed write cannot poison the chain and silently stop every later one.
  /// A failure is counted, the sink is retired, and any record handed to a retired sink is counted
  /// as lost rather than assumed delivered.
  Future<void> _writeChunk(String chunk) async {
    final int records = const LineSplitter().convert(chunk).length;
    final IOSink? sink = _sink;
    if (sink == null || _sinkBroken) {
      if (_logFile != null) {
        _recordsLost += records;
      }
      return;
    }
    try {
      sink.write(chunk);
      await sink.flush();
      _writtenRecordCount += records;
    } on Object catch (error) {
      _flushFailureCount++;
      _recordsLost += records;
      _lastWriteError = error.toString();
      await _closeSink(markBroken: true);
    }
  }

  /// Closes the run's sink, optionally marking it unusable.
  ///
  /// [markBroken] is true when the sink failed: a failure can leave an IOSink in a state where a
  /// later write neither throws nor reaches the disk, so it is retired and every later record is
  /// counted as lost instead of being written into the void.
  Future<void> _closeSink({required bool markBroken}) async {
    final IOSink? sink = _sink;
    _sink = null;
    if (markBroken) {
      _sinkBroken = true;
    }
    if (sink == null) {
      return;
    }
    try {
      await sink.close();
    } on Object catch (error) {
      _flushFailureCount++;
      _lastWriteError = error.toString();
    }
  }
}
