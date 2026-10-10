// PURPOSE: Turn a sample of latency or frame-time measurements into the order statistics that
//          ChartApp's acceptance thresholds are written in — "ink PencilKit p95 <= 30 ms",
//          "layout < 16 ms per page" — so that a threshold decision rests on recorded bench
//          data rather than on watching a demo and judging it fast enough.
// INPUTS: Summary.of(samples, ranks) takes an iterable of finite doubles, one per
//         measurement, in any order, duplicates allowed, possibly empty. ranks is an iterable
//         of percentile ranks, each in [0, 100].
//         percentileOf(ascending, rank) takes a non-empty list sorted ascending and one rank.
// OUTPUTS: A Summary. For an empty sample: count 0, min/max/mean null, and an EMPTY
//         percentiles map — so "no measurements were recorded" stays distinguishable from
//         "the measurement was zero milliseconds", and a caller cannot accidentally print a
//         percentile that was never computed. For a single-element sample every rank returns
//         that element. Both entry points throw ArgumentError on a non-finite sample, on an
//         empty list, or on a rank outside [0, 100]; a non-finite latency is a harness bug
//         and must not be averaged into a threshold decision.
// KEYWORDS: statistics, percentile, p50, p95, latency, bench, summary, acceptance-threshold
//
// This file is pure: no I/O, no clock, no globals. Its behaviour is fully determined by its
// arguments, which is what makes the thresholds above testable without a device.

/// Immutable order statistics for one sample of measurements.
class Summary {
  /// Wraps already-computed statistics. Callers normally use [Summary.of] instead.
  ///
  /// [percentiles] is defensively copied, so mutating the caller's map afterwards cannot
  /// change this summary.
  Summary({
    required this.count,
    required this.min,
    required this.max,
    required this.mean,
    required Map<double, double> percentiles,
  }) : percentiles = Map<double, double>.unmodifiable(percentiles);

  /// Computes the statistics of [samples] at each rank in [ranks].
  ///
  /// The sample is copied before sorting, so the caller's iterable is never reordered.
  /// Ranks that are not requested are not present in [percentiles]; duplicate ranks
  /// collapse into a single entry.
  ///
  /// Throws [ArgumentError] if a sample is NaN or infinite, or if a rank is NaN or lies
  /// outside `[0, 100]`.
  factory Summary.of(
    Iterable<double> samples, {
    Iterable<double> ranks = const <double>[50, 95],
  }) {
    final List<double> values = List<double>.of(samples);
    for (final double value in values) {
      if (!value.isFinite) {
        throw ArgumentError.value(
          value,
          'samples',
          'every sample must be finite',
        );
      }
    }
    final List<double> requested = List<double>.of(ranks);
    for (final double rank in requested) {
      if (rank.isNaN || rank < 0 || rank > 100) {
        throw ArgumentError.value(
          rank,
          'ranks',
          'every rank must lie in [0, 100]',
        );
      }
    }

    if (values.isEmpty) {
      return Summary(
        count: 0,
        min: null,
        max: null,
        mean: null,
        percentiles: const <double, double>{},
      );
    }

    values.sort();
    final double total = values.fold<double>(
      0,
      (double sum, double v) => sum + v,
    );
    final Map<double, double> computed = <double, double>{
      for (final double rank in requested) rank: percentileOf(values, rank),
    };
    return Summary(
      count: values.length,
      min: values.first,
      max: values.last,
      mean: total / values.length,
      percentiles: computed,
    );
  }

  /// Number of measurements in the sample; zero for an empty sample.
  final int count;

  /// Smallest measurement, or null when the sample is empty.
  final double? min;

  /// Largest measurement, or null when the sample is empty.
  final double? max;

  /// Arithmetic mean of the sample, or null when the sample is empty.
  final double? mean;

  /// Requested percentile rank to its computed value. Empty for an empty sample.
  final Map<double, double> percentiles;

  /// The value at percentile [rank], or null when that rank was not requested.
  double? percentile(double rank) => percentiles[rank];
}

// PURPOSE: Answer "what value does percentile p sit at" for an already-ordered sample, with a
//          single documented definition so that a reported p95 means the same thing in
//          logview, in a CI gate and in the usability protocol.
// INPUTS: ascending — a finite, non-empty, already-ascending list. rank — a percentile in
//         [0, 100]. Passing an unsorted list is a caller bug and is not detected here.
// OUTPUTS: The interpolated value at [rank]. Exactly: position = rank/100 * (n - 1); if
//          position is integral the value at that index is returned; otherwise the result is
//          linearly interpolated between the two neighbouring values. This is the definition
//          numpy's `percentile(..., method='linear')` uses, so published numbers stay
//          comparable. A single-element list returns that element for every rank.
//          Throws [ArgumentError] if [ascending] is empty or [rank] is NaN or outside
//          [0, 100].
// KEYWORDS: percentile, interpolation, linear, numpy-compatible, order-statistics
/// Returns the value at percentile [rank] of an ascending sample.
double percentileOf(List<double> ascending, double rank) {
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
