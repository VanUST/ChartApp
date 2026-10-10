// PURPOSE: Prove, without a device, that the bench log's writes are serialised and that the count
//          the writer reports equals the number of valid records in the file. The owner's real run
//          reported 9138 logged samples while its artifact held 671 lines, 31 of them torn — a
//          quoted number whose evidence did not exist. This test pushes far more records than a run
//          would, with flushes deliberately overlapping, and then reads the file back.
// INPUTS: None; a temporary directory is created and removed by the test itself.
// OUTPUTS: Pass/fail. The counts compared are printed in the failure message of the equality
//          assertions, so a failure says which side disagreed and by how much.
// KEYWORDS: bench-log, large-write, serialisation, jsonl, torn-line, integrity, regression
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chartapp/ink_bench/bench_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_native/ink_native.dart';

/// The number of records pushed through the writer; far above a real run's thousands.
const int recordCount = 20000;

/// A minimal but complete sample, so every record carries the metric logview requires.
InkLatencySample sampleAt(int index) => InkLatencySample(
  strokeId: index ~/ 100,
  sampleIndex: index % 100,
  pointerKind: InkPointerKind.sPen,
  presentationSource: InkPresentationSource.vsyncPlusDelay,
  touchToPresentMs: 20 + (index % 17),
  eventTimeNanos: 1000000 + index,
  presentTimeNanos: 2000000 + index,
  pressure: 0.5,
  tiltRadians: 0.1,
  orientationRadians: 0.2,
  touchMajorPx: 0,
  isHistorical: index.isEven,
  eventAction: 'move',
  sourceIsStylus: true,
  rawToolType: 2,
  rawSource: 0x5002,
  x: index.toDouble(),
  y: index.toDouble(),
);

/// The surface description every record carries.
const InkSurfaceInfo surfaceInfo = InkSurfaceInfo(
  platformViewMode: 'hybridComposition',
  presentationSource: InkPresentationSource.vsyncPlusDelay,
  apiLevel: 32,
  refreshRateHz: 120,
  clockOffsetMs: 0,
  clockOffsetDriftMs: 0,
  deviceModel: 'samsung SM-X806B',
  androidRelease: '12',
  eventTimePrecision: 'millisecond',
  usedTimelinePoster: false,
  displayDensity: 2.125,
  palmWidthThreshold: 40,
  palmStylusProximityWindowMs: 1000,
  stylusHoverEventCount: 0,
);

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ink_bench_log_test_');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  test('20000 records, overlapping flushes: the file count equals the reported count', () async {
    final StringBuffer stdoutCopy = StringBuffer();
    final BenchLogWriter writer = BenchLogWriter(
      runId: 'test-large-write',
      out: stdoutCopy,
      directory: directory.path,
    );
    await writer.open();
    expect(
      writer.writesFile,
      isTrue,
      reason: 'the temp directory must be writable',
    );

    for (int index = 0; index < recordCount; index++) {
      writer.writeSample(
        sampleAt(index),
        info: surfaceInfo,
        device: 'test device',
      );
      // The writer chains a flush every 25 records on its own; these add many more calls that
      // overlap it, which is the shape that tore the owner's file.
      if (index % 7 == 0) {
        unawaited(writer.flush());
      }
    }

    await writer.close();
    final String? logPath = writer.logPath;
    expect(logPath, isNotNull);

    // 1. The writer must say what it counted, and that count must be what was offered.
    final LogIntegrity? integrity = writer.integrity;
    expect(integrity, isNotNull);
    expect(integrity!.reportedRecordCount, recordCount);
    expect(integrity.writtenRecordCount, recordCount);
    expect(integrity.flushFailureCount, 0);
    expect(integrity.recordsLostCount, 0);
    expect(
      integrity.fileLineCount,
      recordCount,
      reason: 'file lines must equal reported records',
    );
    expect(
      integrity.validJsonRecordCount,
      recordCount,
      reason: 'valid records must equal reported records',
    );
    expect(
      integrity.tornLineCount,
      0,
      reason: 'no line may be a torn fragment',
    );
    expect(
      integrity.ok,
      isTrue,
      reason: 'the reported count must match the artifact',
    );

    // 2. And the file itself must hold exactly that many parseable records.
    final List<String> lines = const LineSplitter().convert(
      File(logPath!).readAsStringSync().trimRight(),
    );
    expect(lines.length, recordCount);
    int parsed = 0;
    for (final String line in lines) {
      final Object? decoded = jsonDecode(line);
      expect(decoded, isA<Map<String, Object?>>());
      final Map<String, Object?> record = decoded! as Map<String, Object?>;
      expect(record['touchToPresentMs'], isA<num>());
      expect(record['pointerType'], 'sPen');
      parsed++;
    }
    expect(parsed, recordCount);

    // 3. The stdout copy still carries every record, so the file's fix did not cost the console.
    expect(
      const LineSplitter().convert(stdoutCopy.toString()).length,
      recordCount,
    );
  });

  test('the record counter separates valid records from torn fragments', () {
    // The shape of the owner's `bench-20261010T143629.jsonl`: complete records interleaved with
    // tails left by two writers racing on one append. Verified against that file's real damage,
    // which was 640 valid records and 31 fragments.
    const String content =
        '{"v":1,"name":"a"}\n'
        '}}\n'
        '{"v":1,"name":"b"}\n'
        '6B","androidRelease":"12"}}\n'
        '\n'
        '{"v":1,"name":"c"}\n';
    final JsonlRecordCounts counts = countJsonlRecords(content);
    expect(counts.totalLines, 5, reason: 'the blank line is not a record');
    expect(counts.validJsonRecords, 3);
    expect(counts.tornLines, 2);
  });

  test(
    'a document whose valid records do not match the reported count is not ok',
    () {
      const String content = '{"v":1}\n{"v":1}\n}}\n';
      final JsonlRecordCounts counts = countJsonlRecords(content);
      final LogIntegrity integrity = LogIntegrity(
        reportedRecordCount: 3,
        writtenRecordCount: 3,
        fileLineCount: counts.totalLines,
        validJsonRecordCount: counts.validJsonRecords,
        tornLineCount: counts.tornLines,
        flushFailureCount: 0,
        recordsLostCount: 0,
      );
      expect(counts.validJsonRecords, 2);
      expect(
        integrity.ok,
        isFalse,
        reason: '2 valid records cannot satisfy a reported 3',
      );
      expect(integrity.toJson()['ok'], isFalse);
    },
  );

  test(
    'a run with no writable directory writes no file and does not throw',
    () async {
      // A regular file where a directory was expected: `File.create(recursive: true)` must fail.
      final File blocker = File('${directory.path}/not-a-directory')
        ..writeAsStringSync('x');
      final BenchLogWriter writer = BenchLogWriter(
        runId: 'test-no-directory',
        out: StringBuffer(),
        directory: blocker.path,
      );
      await writer.open();
      writer.writeSample(sampleAt(0), info: surfaceInfo, device: 'test device');
      await writer.close();

      expect(writer.writesFile, isFalse);
      expect(writer.logPath, isNull);
      expect(
        writer.lineCount,
        1,
        reason: 'the count still records what was offered',
      );
      expect(writer.writtenRecordCount, 0);
      expect(writer.integrity, isNull, reason: 'there is nothing to verify');
    },
  );
}
