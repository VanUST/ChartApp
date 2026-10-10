// PURPOSE: Compute the order statistics the ink thresholds are written in, so the bench screen can
//          show a p95 the moment a stroke ends, and show the SAME p95 that `tools/logview` will
//          print from the log afterwards. Two different definitions of p95 in one project would
//          make the threshold undecidable, so the definition here is a deliberate copy of
//          `tools/logview/lib/src/statistics.dart`: linear interpolation between the two nearest
//          ranks, which is numpy's `percentile(..., method='linear')`.
// INPUTS: A list of finite latency measurements in milliseconds, in any order, duplicates allowed,
//         possibly empty.
// OUTPUTS: A [BenchStats] whose nullable fields are null exactly when there were no samples, so
//          "nothing was measured" stays distinguishable from "the measurement was zero
//          milliseconds". No entry point throws for an empty or single-element sample.
// KEYWORDS: statistics, percentile, p95, latency, bench, logview-parity
library;

// PURPOSE: Hold one group's summary in the form the screen prints and the thresholds are compared
//          against.
// INPUTS: Built by [BenchStats.of]; the constructor is public so a caller can wrap pre-computed
//         numbers.
// OUTPUTS: Immutable counts and millisecond values; every statistic is null for an empty sample.
// KEYWORDS: summary, count, mean, percentile, latency
/// Immutable order statistics for one group of latency measurements.
class BenchStats {
  /// Creates a summary from already-computed values.
  const BenchStats({
    required this.count,
    required this.minMs,
    required this.meanMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
  });

  /// Summarises [samples], which must all be finite.
  ///
  /// The list is copied before sorting, so the caller's list is never reordered.
  factory BenchStats.of(List<double> samples) {
    if (samples.isEmpty) {
      return const BenchStats(
        count: 0,
        minMs: null,
        meanMs: null,
        p50Ms: null,
        p95Ms: null,
        maxMs: null,
      );
    }
    final List<double> sorted = List<double>.of(samples)..sort();
    double total = 0;
    for (final double value in sorted) {
      total += value;
    }
    return BenchStats(
      count: sorted.length,
      minMs: sorted.first,
      meanMs: total / sorted.length,
      p50Ms: percentileOfSorted(sorted, 50),
      p95Ms: percentileOfSorted(sorted, 95),
      maxMs: sorted.last,
    );
  }

  /// Number of measurements in the sample; zero for an empty sample.
  final int count;

  /// Smallest measurement in milliseconds, or null for an empty sample.
  final double? minMs;

  /// Arithmetic mean in milliseconds, or null for an empty sample.
  final double? meanMs;

  /// Median in milliseconds, or null for an empty sample.
  final double? p50Ms;

  /// 95th percentile in milliseconds, or null for an empty sample.
  final double? p95Ms;

  /// Largest measurement in milliseconds, or null for an empty sample.
  final double? maxMs;
}

// PURPOSE: Answer "what value does percentile p sit at" with the one definition this project uses,
//          so a number shown on the tablet and the same number printed by logview cannot disagree.
// INPUTS: ascending — a finite, non-empty, already-ascending list; rank — a percentile in [0, 100].
// OUTPUTS: The interpolated value at [rank]: position = rank/100 * (n - 1); an integral position
//          returns that element, otherwise the result is linearly interpolated between neighbours.
//          A single-element list returns that element for every rank.
//          Throws [ArgumentError] for an empty list or a rank outside [0, 100].
// KEYWORDS: percentile, linear-interpolation, numpy-compatible, logview-parity
/// Returns the value at percentile [rank] of an ascending sample.
double percentileOfSorted(List<double> ascending, double rank) {
  if (ascending.isEmpty) {
    throw ArgumentError.value(ascending, 'ascending', 'must not be empty');
  }
  if (rank.isNaN || rank < 0 || rank > 100) {
    throw ArgumentError.value(rank, 'rank', 'must lie in [0, 100]');
  }
  if (ascending.length == 1) {
    return ascending.first;
  }
  final double position = rank / 100 * (ascending.length - 1);
  final int lower = position.floor();
  final int upper = position.ceil();
  if (lower == upper) {
    return ascending[lower];
  }
  final double fraction = position - lower;
  return ascending[lower] + (ascending[upper] - ascending[lower]) * fraction;
}
