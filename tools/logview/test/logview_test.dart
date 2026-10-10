// PURPOSE: Exercise the logview command as a user experiences it — given a log file, what
//          report comes out, on which stream, and with which exit code. These are the
//          behaviours a CI gate or a human after a bench run depends on; assertions are on the
//          produced report and exit code, not on internal helpers.
// INPUTS: None. Each test writes its own temporary JSONL log.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, end-to-end, cli, exit-code, jsonl, grouping, diagnostics
import 'dart:convert';
import 'dart:io';

import 'package:logview/logview.dart';
import 'package:test/test.dart';

// Hand-written log. Line 5 is not JSON and line 6 is JSON but carries no `ms` field, so a
// correct run reports exactly one parse issue and exactly one record excluded.
const String _log = '''
{"stage":"ink.pen","ms":10}
{"stage":"ink.pen","ms":20}
{"stage":"ink.pen","ms":30}
{"stage":"eraser","ms":50}
this line is not json
{"stage":"eraser","other":1}
''';

/// The outcome of one CLI invocation: exit code plus both captured streams.
class CliRun {
  /// Creates a captured run result.
  const CliRun({required this.code, required this.out, required this.err});

  /// Process exit code the tool returned.
  final int code;

  /// Everything written to the report stream.
  final String out;

  /// Everything written to the diagnostics stream.
  final String err;
}

void main() {
  late Directory scratch;
  late String logPath;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('logview_test');
    logPath = '${scratch.path}${Platform.pathSeparator}bench.jsonl';
    File(logPath).writeAsStringSync(_log);
  });

  tearDown(() {
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  /// Runs the tool against a fixed log and returns its exit code with both output streams.
  CliRun run(List<String> arguments) {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    final int code = runLogview(arguments, out: out, err: err);
    return CliRun(code: code, out: out.toString(), err: err.toString());
  }

  /// Decodes the JSON report from a run's stdout.
  Map<String, Object?> reportOf(CliRun cliRun) =>
      jsonDecode(cliRun.out) as Map<String, Object?>;

  /// The `groups` array of a JSON report.
  List<Map<String, Object?>> groupsOf(Map<String, Object?> report) =>
      (report['groups']! as List<Object?>).cast<Map<String, Object?>>();

  test('groups by a field and reports hand-checked statistics as JSON', () {
    final CliRun cliRun = run(<String>[
      logPath,
      '--metric',
      'ms',
      '--group-by',
      'stage',
      '--agg',
      'count,min,mean,p50,p95,max',
      '--json',
    ]);

    expect(cliRun.code, 0);
    final List<Map<String, Object?>> groups = groupsOf(reportOf(cliRun));

    // Groups are ordered by label, so 'eraser' precedes 'ink.pen'.
    expect(groups.map((Map<String, Object?> g) => g['group']), <String>[
      'eraser',
      'ink.pen',
    ]);

    final Map<String, Object?> eraser = groups[0];
    // One sample of 50 ms: every statistic is that sample.
    expect(eraser['count'], 1);
    expect(eraser['min'], 50.0);
    expect(eraser['mean'], 50.0);
    expect(eraser['p50'], 50.0);
    expect(eraser['p95'], 50.0);
    expect(eraser['max'], 50.0);

    final Map<String, Object?> inkPen = groups[1];
    // [10, 20, 30]: mean 20; p50 position = 0.5*2 = 1 -> 20; p95 position = 0.95*2 = 1.9
    // -> 20 + (30-20)*0.9 = 29.
    expect(inkPen['count'], 3);
    expect(inkPen['min'], 10.0);
    expect(inkPen['mean'], 20.0);
    expect(inkPen['p50'], 20.0);
    expect(inkPen['p95'], closeTo(29.0, 1e-9));
    expect(inkPen['max'], 30.0);
  });

  test(
    'discloses malformed lines and excluded records on stderr, not in stdout',
    () {
      final CliRun cliRun = run(<String>[logPath, '--metric', 'ms', '--json']);

      expect(cliRun.code, 0);
      // stdout stays valid JSON: a diagnostic must never corrupt machine-readable output.
      expect(() => jsonDecode(cliRun.out), returnsNormally);
      expect(cliRun.err, contains('line 5'));
      expect(cliRun.err, contains('no numeric value'));

      final Map<String, Object?> report = reportOf(cliRun);
      expect(report['skippedMissingMetric'], 1);
      expect((report['issues']! as List<Object?>).length, 1);
    },
  );

  test('prints an aligned table when --json is absent', () {
    final CliRun cliRun = run(<String>[
      logPath,
      '--metric',
      'ms',
      '--group-by',
      'stage',
    ]);

    expect(cliRun.code, 0);
    expect(cliRun.out, contains('ink.pen'));
    expect(cliRun.out, contains('eraser'));
    // 20.00 is the p50 of [10,20,30]; the table prints two decimals.
    expect(cliRun.out, contains('20.00'));
    expect(cliRun.out, contains('metric: ms'));
  });

  test('exits 1 when no record carries the requested metric', () {
    final CliRun cliRun = run(<String>[
      logPath,
      '--metric',
      'notAPresentField',
    ]);

    expect(cliRun.code, 1);
    expect(cliRun.out, isEmpty);
    expect(cliRun.err, contains('notAPresentField'));
  });

  test(
    'exits 2 on an unknown aggregate rather than printing a column of dashes',
    () {
      // 'median' is not an aggregate name at all. 'p77' would be a WRONG probe here: any
      // 'p<rank>' with rank in [0, 100] is a legal request, because the tool accepts any
      // percentile rather than a fixed set of them.
      final CliRun cliRun = run(<String>[
        logPath,
        '--metric',
        'ms',
        '--agg',
        'count,median',
      ]);

      expect(cliRun.code, 2);
      expect(cliRun.err, contains('unknown aggregate'));
    },
  );

  test('exits 2 on a percentile rank outside 0..100', () {
    final CliRun cliRun = run(<String>[
      logPath,
      '--metric',
      'ms',
      '--agg',
      'count,p101',
    ]);

    expect(cliRun.code, 2);
    expect(cliRun.err, contains('unknown aggregate'));
  });

  test('exits 2 when --metric is missing', () {
    final CliRun cliRun = run(<String>[logPath]);

    expect(cliRun.code, 2);
    expect(cliRun.err, contains('--metric is required'));
  });

  test('exits 1 for a path that is neither a file nor a directory', () {
    final CliRun cliRun = run(<String>[
      '${scratch.path}/missing.jsonl',
      '--metric',
      'ms',
    ]);

    expect(cliRun.code, 1);
    expect(cliRun.err, contains('cannot read'));
  });

  test('accepts a directory and reads the .jsonl files inside it', () {
    // PowerShell does not expand a wildcard for a native executable, so the documented
    // `logview <dir>` form has to work without shell help.
    final CliRun cliRun = run(<String>[
      scratch.path,
      '--metric',
      'ms',
      '--agg',
      'count',
      '--json',
    ]);

    expect(cliRun.code, 0);
    final List<Map<String, Object?>> groups = groupsOf(reportOf(cliRun));
    expect(groups.single['group'], 'all');
    expect(groups.single['count'], 4);
  });

  test('a nested metric path is resolved through the object graph', () {
    final String nested =
        '${scratch.path}${Platform.pathSeparator}nested.jsonl';
    File(nested).writeAsStringSync(
      '{"payload":{"durationMs":12}}\n{"payload":{"durationMs":16}}\n',
    );
    final CliRun cliRun = run(<String>[
      nested,
      '--metric',
      'payload.durationMs',
      '--agg',
      'count,mean',
      '--json',
    ]);

    expect(cliRun.code, 0);
    final Map<String, Object?> group = groupsOf(reportOf(cliRun)).single;
    expect(group['count'], 2);
    expect(group['mean'], 14.0);
  });
}
