// PURPOSE: Answer spike S5's question by measurement: how long does it take to open a stored
//          chart? The design sets a 1000 ms budget at p95 for cold-open, and the choice of how
//          the database is opened hung on whether that budget could be met at all — which is why
//          the opener was deferred to this spike rather than assumed.
// INPUTS: iterations — how many times to reopen the database. The default is modest because each
//         sample opens a real file and runs real SQL.
// OUTPUTS: A SpikeOutcome carrying the measured percentiles and a claim for each property that
//          had to hold for the numbers to mean anything.
//
//          WHAT THIS MEASURES, stated precisely: opening the SQLite file and reading the
//          document row plus its event tail, on this machine, in pure Dart. It does NOT measure
//          application start-up, Flutter engine initialisation, widget construction, the first
//          frame, or parsing the snapshot into a document. Those belong to the device bench. A
//          pass here says the STORAGE layer fits inside the budget with room to spare; it does
//          not say the app is on screen in under a second.
// KEYWORDS: spike, s5, storage, cold-open, sqlite, drift, benchmark, honest-scope
import 'dart:convert';
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:logview/logview.dart' show Summary;
import 'package:spike_harness/src/spike_s3.dart' show SpikeClaim, SpikeOutcome;
import 'package:spike_harness/src/spike_s4.dart' show buildBenchmarkSong;
import 'package:storage_drift/storage_drift.dart';

/// How many events the benchmark writes after the snapshot.
const int benchmarkTailEvents = 300;

/// How many events the benchmark writes that the snapshot already folds.
///
/// Non-zero on purpose: a log made only of tail events cannot tell a bounded read from an
/// unbounded one, so the folded events are what give the tail claim something to fail on.
const int benchmarkFoldedEvents = 400;

// PURPOSE: Produce the snapshot payload the benchmark stores.
// INPUTS: song — the chart to serialise. key — the key its chords are rendered in.
// OUTPUTS: A JSON string describing every section and bar.
//
//          This is a SPIKE-LOCAL stand-in, not the document codec. The store treats a snapshot as
//          an opaque string, so what the measurement depends on is the payload's SIZE, and this
//          function exists only to produce a payload of realistic size and shape. The real codec
//          is a separate decision, and writing it here would decide it by accident.
// KEYWORDS: snapshot-payload, spike-local, size-proxy, not-the-codec
/// Serialises [song] to a JSON payload for the benchmark to store.
String benchmarkSnapshotJson(Song song) {
  const SpellingTable table = SpellingTable();
  return jsonEncode(<String, Object?>{
    'v': 1,
    'title': song.title,
    'key': song.key.toString(),
    'tempo': song.tempo,
    'sections': <Map<String, Object?>>[
      for (final Section section in song.sections)
        <String, Object?>{
          'id': section.id,
          'label': section.label.toString(),
          'bars': <Map<String, Object?>>[
            for (final Bar bar in section.bars)
              <String, Object?>{
                'timeSignature': bar.timeSignature.toString(),
                'openingBarline': bar.openingBarline.name,
                'closingBarline': bar.closingBarline.name,
                'chords': <Map<String, Object?>>[
                  for (final ChordMark placement in bar.chords)
                    <String, Object?>{
                      'x': placement.offsetX,
                      'y': placement.place.offsetY,
                      'size': placement.size.name,
                      'symbol': placement.chord.render(song.key, table),
                    },
                ],
              },
          ],
        },
    ],
  });
}

// PURPOSE: Run spike S5 and return its measured claims.
// INPUTS: iterations — the number of reopen samples. warmUp — untimed reopens run first.
// OUTPUTS: A SpikeOutcome for spike `s5` with three claims:
//
//            1. `snapshot_round_trips` — what is read back is what was written, byte for byte.
//               Without this the timing could be measuring an empty read.
//            2. `tail_is_the_tail_only` — the tail holds exactly the events after the snapshot
//               and not the whole log. This is the property the open cost depends on; an
//               implementation that read every event would still pass a timing check on a small
//               log and fail on a real one.
//            3. `reopen_p95_within_budget` — the 95th percentile of open + read + close is at most
//               1000 ms. The observed p50 and maximum are reported alongside, as are the payload
//               sizes, so a near-miss or a suspiciously small number is visible rather than
//               hidden behind one figure.
//
//          The temporary database is removed afterwards whether the measurement succeeded or not.
// KEYWORDS: cold-open, reopen, percentile, p95, budget, snapshot-plus-tail, cleanup
/// Runs spike S5 and returns its measured claims.
Future<SpikeOutcome> runSpikeS5({int iterations = 30, int warmUp = 5}) async {
  const double budgetMilliseconds = 1000;
  final Directory scratch = Directory.systemTemp.createTempSync('chartapp_s5');
  final String path = '${scratch.path}${Platform.pathSeparator}bench.sqlite';

  try {
    final Song song = buildBenchmarkSong();
    final String snapshot = benchmarkSnapshotJson(song);

    final ChartStore writer = ChartStore.openFile(path);
    await writer.putDocument(
      id: 'bench',
      title: song.title,
      songKey: song.key.toString(),
      bpm: song.tempo,
      snapshotJson: snapshot,
      snapshotSeq: 1000,
      updatedAt: '2026-10-10T10:00:00Z',
    );
    // Events the snapshot ALREADY folds, written first so that the tail claim can fail.
    //
    // Without them the log would contain nothing but tail events, and "the tail holds every event
    // in the log" and "the tail holds only the events after the snapshot" would be the same
    // statement — so a claim named `tail_is_the_tail_only` would pass while testing nothing. The
    // first version of this spike had exactly that flaw, which is why the numbers below are
    // reported alongside the log's total size.
    await writer.appendEvents('bench', <DocumentEventInput>[
      for (int i = 1; i <= benchmarkFoldedEvents; i++)
        DocumentEventInput(
          seq: i,
          type: 'chord.insert',
          json: '{"folded":true,"n":$i}',
          ts: '2026-10-10T09:00:00Z',
          deviceId: 'bench-device',
        ),
    ]);
    await writer.appendEvents('bench', <DocumentEventInput>[
      for (int i = 1; i <= benchmarkTailEvents; i++)
        DocumentEventInput(
          seq: 1000 + i,
          type: 'chord.insert',
          json:
              '{"root":"C","quality":"m7","alt":[],"slash":null,'
              '"anchor":{"sectionId":"sec-0","bar":$i,"beat":1.0}}',
          ts: '2026-10-10T10:00:00Z',
          deviceId: 'bench-device',
        ),
    ]);
    final int logLength = await writer.eventCount('bench');
    await writer.close();

    for (int i = 0; i < warmUp; i++) {
      final ChartStore store = ChartStore.openFile(path);
      await store.loadForOpen('bench');
      await store.close();
    }

    final List<double> samples = <double>[];
    String? readBack;
    int tailLength = 0;
    for (int i = 0; i < iterations; i++) {
      final Stopwatch stopwatch = Stopwatch()..start();
      final ChartStore store = ChartStore.openFile(path);
      final OpenDocument? opened = await store.loadForOpen('bench');
      await store.close();
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds / 1000);
      readBack = opened?.snapshotJson;
      tailLength = opened?.tail.length ?? -1;
    }

    final Summary summary = Summary.of(samples, ranks: const <double>[50, 95]);
    final double p50 = summary.percentile(50) ?? 0;
    final double p95 = summary.percentile(95) ?? 0;

    return SpikeOutcome(
      id: 's5',
      question: 'Storage: is cold-open under 1000 ms at p95?',
      claims: <SpikeClaim>[
        SpikeClaim(
          name: 'snapshot_round_trips',
          passed: readBack == snapshot,
          detail:
              'wrote ${snapshot.length} chars, read back ${readBack?.length ?? -1}',
        ),
        SpikeClaim(
          name: 'tail_is_the_tail_only',
          passed:
              tailLength == benchmarkTailEvents &&
              logLength == benchmarkFoldedEvents + benchmarkTailEvents,
          detail:
              'the log holds $logLength events; opening returned $tailLength, so the '
              '$benchmarkFoldedEvents already folded into the snapshot were excluded',
        ),
        SpikeClaim(
          name: 'reopen_p95_within_budget',
          passed: p95 <= budgetMilliseconds,
          detail:
              '$iterations samples after $warmUp warm-up; '
              'p50 ${p50.toStringAsFixed(2)} ms, '
              'p95 ${p95.toStringAsFixed(2)} ms, '
              'max ${(summary.max ?? 0).toStringAsFixed(2)} ms, '
              'budget $budgetMilliseconds ms; '
              'snapshot ${snapshot.length} chars, $benchmarkTailEvents tail events',
        ),
      ],
    );
  } finally {
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  }
}
