// PURPOSE: Answer spike S4's question by measurement: how long does it take to engrave a page?
//          The design sets a 16 ms budget, which is one frame at 60 Hz, so the answer decides
//          whether the layout pipeline can run inside a frame or has to be cached and deferred.
// INPUTS: iterations — how many samples to take. The default is enough to place a p95.
// OUTPUTS: A SpikeOutcome carrying the measured percentiles and a claim for each property that
//          had to hold for the measurement to mean anything.
//
//          WHAT THIS MEASURES, stated precisely: the LAYOUT COMPUTATION in pure Dart, on this
//          machine. It does not measure rasterisation, text shaping through a real font, the
//          cost of transferring a picture to the GPU, or anything a specific device does. Those
//          require the device and are the L3 bench's job. A number here that passes the budget
//          therefore says the algorithm fits in a frame's CPU budget, not that the app renders a
//          page in 16 ms.
// KEYWORDS: spike, s4, layout, benchmark, percentile, frame-budget, honest-scope, measurement
import 'dart:convert';

import 'package:chart_core/chart_core.dart';
import 'package:logview/logview.dart' show Summary;

import 'spike_s3.dart' show SpikeClaim, SpikeOutcome;

/// The page the benchmark engraves, roughly a large phone in logical pixels.
const double benchPageWidth = 390;

/// The page height the benchmark engraves.
const double benchPageHeight = 844;

// PURPOSE: Build the chart the benchmark measures: four sections of eight bars, a chord on each
//          beat one, changing root. It is sized so that it lands on exactly one page at the
//          benchmark's page size, because the budget is stated per page and a multi-page result
//          would compare a different quantity against it.
// INPUTS: None.
// OUTPUTS: A Song whose layout is one page. The claim in [runSpikeS4] fails if that stops being
//          true, so the measurement cannot silently start describing two pages while still being
//          compared against a one-page budget.
// KEYWORDS: benchmark-fixture, realistic-chart, one-page, comparability
/// Builds the chart the benchmark measures: four sections of eight bars on one page.
Song buildBenchmarkSong() {
  final List<Section> sections = <Section>[];
  for (int section = 0; section < 4; section++) {
    final List<Bar> bars = <Bar>[];
    for (int index = 0; index < 8; index++) {
      bars.add(
        Bar(
          chords: <ChordMark>[
            ChordMark(
              place: AnchoredPlace(
                anchor: const EventAnchor(sectionId: '', bar: 0),
                offsetX: 8 + (index % 4) * 18,
              ),
              chord: Chord(
                root: ChordRoot((index + section * 3) % 12),
                quality: index.isEven
                    ? ChordQuality.minorSeventh
                    : ChordQuality.dominantSeventh,
                bass: index % 4 == 0 ? ChordRoot((index + 7) % 12) : null,
              ),
            ),
          ],
        ),
      );
    }
    sections.add(
      Section(
        id: 'sec-$section',
        label: SectionLabel.letter(String.fromCharCode(65 + section)),
        bars: bars,
      ),
    );
  }
  return Song(
    id: 'bench',
    title: 'Benchmark',
    style: 'Medium Swing',
    key: Key.cMajor,
    tempo: 140,
    sections: sections,
  );
}

// PURPOSE: Run spike S4 and return its measured claims.
// INPUTS: iterations — the number of timed layouts; warmUp — the number of untimed layouts run
//         first so that the reported numbers describe the engine rather than the just-in-time
//         compiler.
// OUTPUTS: A SpikeOutcome for spike `s4` with three claims:
//
//            1. `one_page_fixture` — the benchmark chart engraves to exactly one page. Without
//               this the budget comparison is meaningless, so it is asserted rather than assumed.
//            2. `no_bar_lost` — the number of placed bars equals the chart's written bar count.
//               This is what separates a fast layout from a fast early return: an engine that
//               dropped most of the music would otherwise report an excellent time.
//            3. `layout_p95_within_budget` — the 95th percentile of a whole-page engraving is at
//               most 16 ms, the design's budget. p50 and the maximum are reported alongside so
//               that a near-miss is visible rather than hidden behind one number.
//
//          The percentiles come from logview's [Summary], the same implementation the device
//          bench logs are reduced with, so that "p95" means one thing across this project.
// KEYWORDS: benchmark, warm-up, percentile, p95, frame-budget, no-bar-lost, spike-verdict
/// Runs spike S4 and returns its measured claims.
SpikeOutcome runSpikeS4({int iterations = 300, int warmUp = 50}) {
  const LayoutEngine engine = LayoutEngine();
  const double budgetMilliseconds = 16;
  final Song song = buildBenchmarkSong();

  final List<PageLayout> probe = engine.layout(
    song,
    pageWidth: benchPageWidth,
    pageHeight: benchPageHeight,
  );
  final int placedBars = probe.fold<int>(
    0,
    (int total, PageLayout page) => total + page.bars.length,
  );

  // Warm up. The first layouts pay for class loading and for the just-in-time compiler, and
  // including them would describe the harness rather than the engine.
  for (int i = 0; i < warmUp; i++) {
    engine.layout(song, pageWidth: benchPageWidth, pageHeight: benchPageHeight);
  }

  final List<double> samples = <double>[];
  for (int i = 0; i < iterations; i++) {
    final Stopwatch stopwatch = Stopwatch()..start();
    engine.layout(song, pageWidth: benchPageWidth, pageHeight: benchPageHeight);
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds / 1000);
  }

  final Summary summary = Summary.of(samples, ranks: const <double>[50, 95]);
  final double p50 = summary.percentile(50) ?? 0;
  final double p95 = summary.percentile(95) ?? 0;

  return SpikeOutcome(
    id: 's4',
    question: 'Layout: is a page laid out in under 16 ms?',
    claims: <SpikeClaim>[
      SpikeClaim(
        name: 'one_page_fixture',
        passed: probe.length == 1,
        detail: 'the benchmark chart engraves to ${probe.length} page(s)',
      ),
      SpikeClaim(
        name: 'no_bar_lost',
        passed: placedBars == song.writtenBarCount,
        detail: 'placed $placedBars of ${song.writtenBarCount} written bars',
      ),
      SpikeClaim(
        name: 'layout_p95_within_budget',
        passed: p95 <= budgetMilliseconds,
        detail:
            '$iterations samples after $warmUp warm-up; '
            'p50 ${p50.toStringAsFixed(3)} ms, '
            'p95 ${p95.toStringAsFixed(3)} ms, '
            'max ${(summary.max ?? 0).toStringAsFixed(3)} ms, '
            'budget $budgetMilliseconds ms',
      ),
    ],
  );
}

/// The measurement as a JSON object, for a caller that wants the numbers without parsing text.
///
/// Kept separate from [SpikeOutcome.report] because the outcome carries claims for any spike
/// while this carries the numbers only S4 produces.
Map<String, Object?> spikeS4Measurement({int iterations = 300}) {
  final SpikeOutcome outcome = runSpikeS4(iterations: iterations);
  return <String, Object?>{
    'spike': outcome.id,
    'passed': outcome.passed,
    'claims': <Map<String, Object?>>[
      for (final SpikeClaim claim in outcome.claims)
        <String, Object?>{
          'name': claim.name,
          'passed': claim.passed,
          'detail': claim.detail,
        },
    ],
    'note': 'layout computation only; rasterisation is measured on a device, not here',
  };
}

/// Renders the measurement as a single JSON line.
String spikeS4JsonLine({int iterations = 300}) =>
    jsonEncode(spikeS4Measurement(iterations: iterations));
