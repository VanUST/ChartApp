// PURPOSE: Reduce a set of bench log records to per-group latency statistics and render them,
//          so that a recorded run answers "was the p95 under the threshold" without a human
//          reading raw lines. Grouping is by an arbitrary log field rather than by a fixed
//          concept such as 'stage', because which dimension matters (tool, pointer type,
//          page) is a question the bench harness answers, not this analyser.
// INPUTS: BenchAnalysis.of() takes the already-parsed records and issues, the metric path to
//         extract, an optional group-by path, and the list of aggregate names. Aggregate
//         names are 'count', 'min', 'max', 'mean', or 'p<rank>' with rank in [0, 100].
// OUTPUTS: An analysis holding one Summary per group label, plus a count of records that had
//         no numeric value at the metric path. Records missing the metric are counted, never
//         treated as zero, so a partially-instrumented run cannot drag an average down.
//         A record whose group field is absent falls into the '(missing)' group rather than
//         being dropped. Groups are ordered by label so output is stable across runs.
//         writeTable/writeJson write to the supplied sink and return nothing.
// KEYWORDS: bench-report, aggregation, percentile, grouping, rendering, latency-threshold
import 'dart:convert';

import 'json_path.dart';
import 'jsonl.dart';
import 'statistics.dart';

/// Aggregate names that are not percentiles.
const Set<String> scalarAggregates = <String>{'count', 'min', 'max', 'mean'};

/// Group label used for records whose group-by path is absent.
const String missingGroupLabel = '(missing)';

// PURPOSE: Decode an aggregate name such as "p95" into the percentile rank it denotes, so the
//          CLI can accept percentiles as user input while the statistics layer keeps working
//          in plain ranks.
// INPUTS: aggregate — a candidate name.
// OUTPUTS: The rank (95.0 for "p95", 99.9 for "p99.9"), or null when the name is not a
//          percentile form or its rank lies outside [0, 100]. Never throws.
// KEYWORDS: aggregate, percentile, parsing, cli-input
/// Returns the percentile rank encoded by [aggregate], or null when it is not a percentile.
double? percentileRankOf(String aggregate) {
  if (aggregate.length < 2 || !aggregate.startsWith('p')) {
    return null;
  }
  final double? rank = double.tryParse(aggregate.substring(1));
  if (rank == null || rank.isNaN || rank < 0 || rank > 100) {
    return null;
  }
  return rank;
}

// PURPOSE: Decide whether an aggregate name is one logview can compute, so an unknown name is
//          rejected at argument parsing time rather than silently producing a column of
//          dashes that a reader would mistake for missing data.
// INPUTS: aggregate — a candidate name.
// OUTPUTS: True for 'count'/'min'/'max'/'mean' and for well-formed 'p<rank>' names.
// KEYWORDS: aggregate, validation, cli-input
/// True when [aggregate] is an aggregate name logview can compute.
bool isKnownAggregate(String aggregate) =>
    scalarAggregates.contains(aggregate) || percentileRankOf(aggregate) != null;

/// Per-group statistics for one bench log, plus the records that could not contribute.
class BenchAnalysis {
  /// Wraps pre-computed [groups] and the record bookkeeping around them.
  BenchAnalysis({
    required this.source,
    required this.metric,
    required this.groupBy,
    required this.aggregates,
    required this.groups,
    required this.skippedMissingMetric,
    required this.issues,
  });

  /// Splits [records] into groups and summarises each one.
  ///
  /// Records whose metric path does not resolve to a number are counted in
  /// [skippedMissingMetric]. The group label of a record whose group-by path is absent or
  /// null is [missingGroupLabel].
  factory BenchAnalysis.of({
    required String source,
    required String metric,
    required String? groupBy,
    required List<String> aggregates,
    required List<JsonlRecord> records,
    required List<JsonlIssue> issues,
  }) {
    final List<double> ranks = <double>[
      for (final String aggregate in aggregates)
        if (percentileRankOf(aggregate) case final double rank) rank,
    ];

    final Map<String, List<double>> samplesByGroup = <String, List<double>>{};
    int skipped = 0;
    for (final JsonlRecord record in records) {
      final Object? raw = selectPath(record.data, metric);
      if (raw is! num) {
        skipped++;
        continue;
      }
      final String label = groupBy == null
          ? 'all'
          : _labelOf(selectPath(record.data, groupBy));
      samplesByGroup.putIfAbsent(label, () => <double>[]).add(raw.toDouble());
    }

    final List<String> orderedLabels = samplesByGroup.keys.toList()..sort();
    final Map<String, Summary> groups = <String, Summary>{
      for (final String label in orderedLabels)
        label: Summary.of(samplesByGroup[label]!, ranks: ranks),
    };

    return BenchAnalysis(
      source: source,
      metric: metric,
      groupBy: groupBy,
      aggregates: List<String>.unmodifiable(aggregates),
      groups: Map<String, Summary>.unmodifiable(groups),
      skippedMissingMetric: skipped,
      issues: List<JsonlIssue>.unmodifiable(issues),
    );
  }

  /// Human-readable identification of the input, used as a heading and in JSON output.
  final String source;

  /// Dotted path the numeric measurement was read from.
  final String metric;

  /// Dotted path the records were grouped by, or null for a single 'all' group.
  final String? groupBy;

  /// Aggregate names to report, in the order they should appear.
  final List<String> aggregates;

  /// Group label to its summary, ordered by label.
  final Map<String, Summary> groups;

  /// Number of records that carried no numeric value at [metric].
  final int skippedMissingMetric;

  /// Lines that could not be parsed, retained so the report can disclose them.
  final List<JsonlIssue> issues;

  // PURPOSE: Render the analysis as a fixed-width table for a human reading a terminal after
  //          a device bench run.
  // INPUTS: out — the sink to write to.
  // OUTPUTS: Nothing. Writes a heading, a column header and one row per group; statistics
  //          absent because the group is empty render as '-', never as 0 or NaN.
  // KEYWORDS: rendering, table, terminal, report
  /// Writes the analysis as an aligned text table.
  void writeTable(StringSink out) {
    out.writeln('source: $source');
    out.writeln(
      'metric: $metric'
      '${groupBy == null ? '' : '   groupBy: $groupBy'}'
      '   aggregates: ${aggregates.join(',')}',
    );
    out.writeln('');

    final List<String> headers = <String>[groupBy ?? 'group', ...aggregates];
    final List<List<String>> rows = <List<String>>[
      for (final MapEntry<String, Summary> entry in groups.entries)
        <String>[
          entry.key,
          for (final String aggregate in aggregates)
            _formatAggregate(entry.value, aggregate),
        ],
    ];

    final List<int> widths = <int>[
      for (int column = 0; column < headers.length; column++)
        <int>[
          headers[column].length,
          for (final List<String> row in rows) row[column].length,
        ].reduce((int a, int b) => a > b ? a : b),
    ];

    out.writeln(_renderRow(headers, widths));
    for (final List<String> row in rows) {
      out.writeln(_renderRow(row, widths));
    }
  }

  // PURPOSE: Render the same analysis as JSON so a CI job or a script can compare a bench run
  //          against a threshold without parsing a text table.
  // INPUTS: out — the sink to write to.
  // OUTPUTS: Nothing. Writes one pretty-printed JSON object; null statistics stay JSON null.
  // KEYWORDS: rendering, json, machine-readable, ci-gate
  /// Writes the analysis as a single pretty-printed JSON object.
  void writeJson(StringSink out) {
    final Map<String, Object?> document = <String, Object?>{
      'source': source,
      'metric': metric,
      'groupBy': groupBy,
      'aggregates': aggregates,
      'skippedMissingMetric': skippedMissingMetric,
      'groups': <Map<String, Object?>>[
        for (final MapEntry<String, Summary> entry in groups.entries)
          <String, Object?>{
            'group': entry.key,
            'count': entry.value.count,
            for (final String aggregate in aggregates)
              if (aggregate != 'count')
                aggregate: _aggregateValue(entry.value, aggregate),
          },
      ],
      'issues': <Map<String, Object?>>[
        for (final JsonlIssue issue in issues)
          <String, Object?>{'line': issue.line, 'message': issue.message},
      ],
    };
    out.writeln(const JsonEncoder.withIndent('  ').convert(document));
  }

  static String _labelOf(Object? value) {
    if (value == null) {
      return missingGroupLabel;
    }
    return value is String ? value : value.toString();
  }

  static double? _aggregateValue(Summary summary, String aggregate) {
    switch (aggregate) {
      case 'min':
        return summary.min;
      case 'max':
        return summary.max;
      case 'mean':
        return summary.mean;
      default:
        final double? rank = percentileRankOf(aggregate);
        return rank == null ? null : summary.percentile(rank);
    }
  }

  static String _formatAggregate(Summary summary, String aggregate) {
    if (aggregate == 'count') {
      return summary.count.toString();
    }
    final double? value = _aggregateValue(summary, aggregate);
    return value == null ? '-' : value.toStringAsFixed(2);
  }

  static String _renderRow(List<String> cells, List<int> widths) {
    final StringBuffer buffer = StringBuffer();
    for (int column = 0; column < cells.length; column++) {
      if (column > 0) {
        buffer.write('  ');
      }
      buffer.write(cells[column].padLeft(widths[column]));
    }
    return buffer.toString();
  }
}
