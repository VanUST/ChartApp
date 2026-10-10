// PURPOSE: Turn command line arguments and log files into a printed bench report, returning a
//          process exit code. It is separated from `bin/logview.dart` so that the tool's real
//          behaviour — which report it prints, on which streams, with which exit code — can be
//          driven by a test without spawning a process.
// INPUTS: arguments — the raw argv tail. out and err — the sinks for the report and for
//         diagnostics. In production these are stdout and stderr; in a test they are buffers.
// OUTPUTS: An exit code. 0 when a report was produced; 2 for a usage error (unknown option,
//          missing --metric, unknown aggregate name, or no input found); 1 when no input could
//          be read or when no record carried a numeric value at the metric path. The report
//          alone goes to `out`: every diagnostic goes to `err`, so `--json` output stays
//          machine-parseable even when the log contained malformed lines.
// KEYWORDS: cli, exit-code, logview, runner, testable-seam, diagnostics
import 'dart:io';

import 'package:args/args.dart';

import 'bench_analysis.dart';
import 'jsonl.dart';

const String _usage = '''
Usage: logview <file-or-directory>... --metric <path> [options]

Reads JSON Lines bench logs and reports per-group statistics for one numeric field.

Options:
  -m, --metric <path>    Dotted path to the measurement, e.g. touchToPresentMs
                         or payload.durationMs. Required.
  -g, --group-by <path>  Dotted path to group by, e.g. stage or pointer.type.
                         Omit to summarise the whole log as one group.
  -a, --agg <list>       Comma-separated aggregates. Names: count, min, max,
                         mean, and percentiles written p<rank> (p50, p95, p99.9).
                         Default: count,min,mean,p50,p95,max
      --json             Emit the report as JSON instead of an aligned table.
  -h, --help             Print this help.

Directories are searched for files ending in .jsonl.

Exit codes:
  0  a report was produced
  1  input could not be read, or no record had a numeric value at --metric
  2  usage error
''';

/// Runs the logview command and returns the process exit code.
int runLogview(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) {
  final ArgParser parser = ArgParser()
    ..addOption(
      'metric',
      abbr: 'm',
      help: 'Dotted path to the numeric measurement.',
    )
    ..addOption('group-by', abbr: 'g', help: 'Dotted path to group records by.')
    ..addOption(
      'agg',
      abbr: 'a',
      defaultsTo: 'count,min,mean,p50,p95,max',
      help: 'Comma-separated aggregate names.',
    )
    ..addFlag('json', negatable: false, help: 'Emit JSON instead of a table.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage.');

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    err.writeln('logview: ${error.message}');
    err.writeln(_usage);
    return 2;
  }

  if (results.flag('help')) {
    out.writeln(_usage);
    return 0;
  }

  final String metric = results.option('metric') ?? '';
  if (metric.isEmpty) {
    err.writeln('logview: --metric is required');
    err.writeln(_usage);
    return 2;
  }

  final String? groupBy = switch (results.option('group-by')) {
    final String value when value.isNotEmpty => value,
    _ => null,
  };

  final List<String> aggregates = (results.option('agg') ?? '')
      .split(',')
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList();
  if (aggregates.isEmpty) {
    err.writeln('logview: --agg listed no aggregate names');
    return 2;
  }
  for (final String aggregate in aggregates) {
    if (!isKnownAggregate(aggregate)) {
      err.writeln('logview: unknown aggregate "$aggregate"');
      return 2;
    }
  }

  if (results.rest.isEmpty) {
    err.writeln('logview: no input given');
    err.writeln(_usage);
    return 2;
  }

  final List<String> inputs;
  try {
    inputs = _resolveInputs(results.rest);
  } on _InputError catch (error) {
    err.writeln('logview: ${error.message}');
    return 1;
  }
  if (inputs.isEmpty) {
    err.writeln('logview: no .jsonl input found');
    return 2;
  }

  final List<JsonlRecord> records = <JsonlRecord>[];
  final List<JsonlIssue> issues = <JsonlIssue>[];
  for (final String path in inputs) {
    final String contents;
    try {
      contents = File(path).readAsStringSync();
    } on FileSystemException catch (error) {
      err.writeln(
        'logview: cannot read $path (${error.osError?.message ?? error.message})',
      );
      return 1;
    }
    final JsonlReadResult parsed = parseJsonl(contents);
    records.addAll(parsed.records);
    issues.addAll(<JsonlIssue>[
      for (final JsonlIssue issue in parsed.issues)
        JsonlIssue(line: issue.line, message: '$path: ${issue.message}'),
    ]);
  }

  final BenchAnalysis analysis = BenchAnalysis.of(
    source: inputs.join(', '),
    metric: metric,
    groupBy: groupBy,
    aggregates: aggregates,
    records: records,
    issues: issues,
  );

  for (final JsonlIssue issue in issues) {
    err.writeln('logview: skipped $issue');
  }
  if (analysis.skippedMissingMetric > 0) {
    err.writeln(
      'logview: ${analysis.skippedMissingMetric} record(s) had no numeric value '
      'at "$metric" and were excluded',
    );
  }

  if (analysis.groups.isEmpty) {
    err.writeln(
      'logview: no numeric value found at "$metric" in ${records.length} record(s)',
    );
    return 1;
  }

  if (results.flag('json')) {
    analysis.writeJson(out);
  } else {
    analysis.writeTable(out);
  }
  return 0;
}

/// Raised when a command line path cannot be used as log input.
class _InputError implements Exception {
  _InputError(this.message);

  final String message;
}

// PURPOSE: Turn the command line's paths into a concrete list of log files, expanding a
//          directory to the .jsonl files inside it. PowerShell does not expand a wildcard for
//          a native executable, so accepting a directory keeps the documented
//          `logview bench-out/` invocation working on Windows as well as on a POSIX shell.
// INPUTS: paths — the positional arguments, each a file or a directory.
// OUTPUTS: A sorted list of file paths. Throws [_InputError] when a path is neither an
//          existing file nor an existing directory, so the caller can report it and exit 1.
// KEYWORDS: input-resolution, directory-expansion, cross-platform, glob
List<String> _resolveInputs(List<String> paths) {
  final List<String> files = <String>[];
  for (final String path in paths) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      final List<String> found =
          Directory(path)
              .listSync()
              .whereType<File>()
              .map((File entity) => entity.path)
              .where(
                (String candidate) =>
                    candidate.toLowerCase().endsWith('.jsonl'),
              )
              .toList()
            ..sort();
      files.addAll(found);
    } else if (type == FileSystemEntityType.file) {
      files.add(path);
    } else {
      throw _InputError('cannot read "$path" as a log file or directory');
    }
  }
  return files;
}
