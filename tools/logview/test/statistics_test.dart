// PURPOSE: Pin the exact meaning of the percentile and summary statistics that every latency
//          acceptance threshold in this project is expressed in. If this file's expectations
//          are wrong, a green bench gate means nothing, so every expected number below was
//          derived by hand from the documented definition rather than copied from a run.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, percentile, statistics, hand-derived, numpy-linear, acceptance-threshold
import 'package:logview/logview.dart';
import 'package:test/test.dart';

void main() {
  group('percentileOf uses linear interpolation between closest ranks', () {
    // position = rank/100 * (n - 1); interpolate between the neighbours of position.
    test('p50 of [1,2,3,4] is 2.5', () {
      // position = 0.50 * 3 = 1.5  ->  2 + (3 - 2) * 0.5
      expect(percentileOf(<double>[1, 2, 3, 4], 50), closeTo(2.5, 1e-12));
    });

    test('p95 of [10,20,30,40] is 38.5', () {
      // position = 0.95 * 3 = 2.85  ->  30 + (40 - 30) * 0.85
      expect(percentileOf(<double>[10, 20, 30, 40], 95), closeTo(38.5, 1e-12));
    });

    test('p25 of [1,2,3,4] is 1.75', () {
      // position = 0.25 * 3 = 0.75  ->  1 + (2 - 1) * 0.75
      expect(percentileOf(<double>[1, 2, 3, 4], 25), closeTo(1.75, 1e-12));
    });

    test('integral positions return the sample itself', () {
      // position = 0.50 * 2 = 1  ->  index 1
      expect(percentileOf(<double>[1, 2, 3], 50), closeTo(2, 1e-12));
    });

    test('the extremes are min and max', () {
      expect(percentileOf(<double>[4, 8, 15, 16], 0), closeTo(4, 1e-12));
      expect(percentileOf(<double>[4, 8, 15, 16], 100), closeTo(16, 1e-12));
    });

    test('a single sample returns itself at every rank', () {
      expect(percentileOf(<double>[7], 0), closeTo(7, 1e-12));
      expect(percentileOf(<double>[7], 95), closeTo(7, 1e-12));
      expect(percentileOf(<double>[7], 100), closeTo(7, 1e-12));
    });

    test('an empty sample is rejected rather than reported as zero', () {
      expect(() => percentileOf(<double>[], 50), throwsArgumentError);
    });

    test('a rank outside [0,100] is rejected', () {
      expect(() => percentileOf(<double>[1, 2], 101), throwsArgumentError);
      expect(() => percentileOf(<double>[1, 2], -1), throwsArgumentError);
    });
  });

  group('Summary.of', () {
    test('reports count, mean, min and max of an unordered sample', () {
      // [3,1,2] -> sorted [1,2,3]; mean = 6/3 = 2; p50 position = 0.5*2 = 1 -> 2
      final Summary summary = Summary.of(
        <double>[3, 1, 2],
        ranks: const <double>[50],
      );
      expect(summary.count, 3);
      expect(summary.min, closeTo(1, 1e-12));
      expect(summary.max, closeTo(3, 1e-12));
      expect(summary.mean, closeTo(2, 1e-12));
      expect(summary.percentile(50), closeTo(2, 1e-12));
    });

    test('does not reorder the caller\'s list', () {
      final List<double> input = <double>[3, 1, 2];
      Summary.of(input);
      expect(input, <double>[3, 1, 2]);
    });

    test('an empty sample yields no statistics and no percentiles', () {
      // The distinction this protects: "no measurements" must not look like "0 ms", which
      // would satisfy every upper-bound threshold trivially.
      final Summary summary = Summary.of(
        <double>[],
        ranks: const <double>[50, 95],
      );
      expect(summary.count, 0);
      expect(summary.min, isNull);
      expect(summary.max, isNull);
      expect(summary.mean, isNull);
      expect(summary.percentiles, isEmpty);
      expect(summary.percentile(95), isNull);
    });

    test('only the requested ranks are present', () {
      final Summary summary = Summary.of(
        <double>[1, 2, 3, 4],
        ranks: const <double>[50],
      );
      expect(summary.percentiles.keys, <double>[50]);
      expect(summary.percentile(95), isNull);
    });

    test('a non-finite sample is rejected', () {
      expect(() => Summary.of(<double>[1, double.nan]), throwsArgumentError);
      expect(
        () => Summary.of(<double>[1, double.infinity]),
        throwsArgumentError,
      );
    });
  });
}
