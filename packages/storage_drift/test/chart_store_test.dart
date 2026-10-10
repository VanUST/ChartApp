// PURPOSE: Pin the two rules this package exists to enforce — that the event log is append-only,
//          and that opening a document reads its snapshot plus the tail after it and nothing else
//          — plus the ordinary round-trips a caller depends on. These are the behaviours the
//          cold-open budget is spent on, so a regression here changes a measured number.
// INPUTS: None. Each test uses an in-memory database, except the persistence test, which uses a
//         temporary file.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, repository, append-only, snapshot, tail, persistence, in-memory
import 'dart:io';

import 'package:storage_drift/storage_drift.dart';
import 'package:test/test.dart';

/// Builds an event at [seq] carrying [body] as its payload.
DocumentEventInput event(int seq, String body) => DocumentEventInput(
  seq: seq,
  type: 'chord.insert',
  json: body,
  ts: '2026-10-10T00:00:0${seq % 10}Z',
  deviceId: 'device-a',
);

void main() {
  late ChartStore store;

  setUp(() {
    store = ChartStore.inMemory();
  });

  tearDown(() async {
    await store.close();
  });

  group('a document round-trips', () {
    test('metadata and snapshot come back exactly as written', () async {
      await store.putDocument(
        id: 'doc-1',
        title: 'Paper Kite',
        songKey: 'Eb major',
        bpm: 138,
        snapshotJson: '{"sections":[]}',
        snapshotSeq: 7,
        updatedAt: '2026-10-10T10:00:00Z',
      );

      final OpenDocument? opened = await store.loadForOpen('doc-1');
      expect(opened, isNotNull);
      expect(opened!.title, 'Paper Kite');
      expect(opened.songKey, 'Eb major');
      expect(opened.bpm, 138);
      expect(opened.snapshotJson, '{"sections":[]}');
      expect(opened.snapshotSeq, 7);
      expect(opened.updatedAt, '2026-10-10T10:00:00Z');
    });

    test('an unknown document answers null rather than throwing', () async {
      // Whether a missing document is an error depends on the caller: an open request for a
      // deleted chart is ordinary, an import that lost a row is not.
      expect(await store.loadForOpen('nope'), isNull);
    });

    test('a document with no snapshot and no events is valid', () async {
      await store.putDocument(
        id: 'doc-empty',
        title: '',
        songKey: 'C major',
        bpm: 0,
        snapshotJson: null,
        snapshotSeq: 0,
        updatedAt: '2026-10-10T10:00:00Z',
      );

      final OpenDocument opened = (await store.loadForOpen('doc-empty'))!;
      expect(opened.snapshotJson, isNull);
      expect(opened.snapshotSeq, 0);
      expect(opened.tail, isEmpty);
    });
  });

  group('the tail is the tail, not the whole log', () {
    test(
      'only events after the snapshot are returned, in sequence order',
      () async {
        await store.putDocument(
          id: 'doc-1',
          title: 'T',
          songKey: 'C major',
          bpm: 0,
          snapshotJson: '{}',
          snapshotSeq: 5,
          updatedAt: '2026-10-10T10:00:00Z',
        );
        // Appended out of order on purpose, so that an implementation which returned insertion
        // order instead of sequence order would be caught.
        await store.appendEvents('doc-1', <DocumentEventInput>[
          event(9, 'nine'),
          event(3, 'three'),
          event(6, 'six'),
          event(5, 'five'),
          event(7, 'seven'),
        ]);

        final OpenDocument opened = (await store.loadForOpen('doc-1'))!;
        // Sequence 5 is already folded into the snapshot, and 3 is older still.
        expect(opened.tail.map((DocumentEventInput e) => e.seq).toList(), <int>[
          6,
          7,
          9,
        ]);
        expect(opened.tail.first.json, 'six');
      },
    );

    test('the count reports the whole log, not just the tail', () async {
      await store.putDocument(
        id: 'doc-1',
        title: 'T',
        songKey: 'C major',
        bpm: 0,
        snapshotJson: '{}',
        snapshotSeq: 2,
        updatedAt: '2026-10-10T10:00:00Z',
      );
      await store.appendEvents('doc-1', <DocumentEventInput>[
        event(1, 'a'),
        event(2, 'b'),
        event(3, 'c'),
      ]);

      expect(await store.eventCount('doc-1'), 3);
      expect((await store.loadForOpen('doc-1'))!.tail.length, 1);
    });
  });

  group('the log is append-only', () {
    test(
      'appending a sequence that already exists does not overwrite it',
      () async {
        await store.putDocument(
          id: 'doc-1',
          title: 'T',
          songKey: 'C major',
          bpm: 0,
          snapshotJson: null,
          snapshotSeq: 0,
          updatedAt: '2026-10-10T10:00:00Z',
        );
        await store.appendEvents('doc-1', <DocumentEventInput>[
          event(1, 'original'),
        ]);
        await store.appendEvents('doc-1', <DocumentEventInput>[
          event(1, 'replacement'),
        ]);

        final OpenDocument opened = (await store.loadForOpen('doc-1'))!;
        expect(opened.tail.length, 1);
        // The event that happened is the one that stays. This is what makes re-importing a share
        // file idempotent instead of destructive.
        expect(opened.tail.single.json, 'original');
      },
    );

    test('re-appending a whole batch is idempotent', () async {
      // The property an import of the same .chart file twice depends on.
      await store.putDocument(
        id: 'doc-1',
        title: 'T',
        songKey: 'C major',
        bpm: 0,
        snapshotJson: null,
        snapshotSeq: 0,
        updatedAt: '2026-10-10T10:00:00Z',
      );
      final List<DocumentEventInput> batch = <DocumentEventInput>[
        event(1, 'a'),
        event(2, 'b'),
        event(3, 'c'),
      ];
      await store.appendEvents('doc-1', batch);
      await store.appendEvents('doc-1', batch);

      expect(await store.eventCount('doc-1'), 3);
    });

    test('events of two documents do not mix', () async {
      for (final String id in <String>['doc-a', 'doc-b']) {
        await store.putDocument(
          id: id,
          title: id,
          songKey: 'C major',
          bpm: 0,
          snapshotJson: null,
          snapshotSeq: 0,
          updatedAt: '2026-10-10T10:00:00Z',
        );
        // The same sequence number in both logs: identities are per document, not global.
        await store.appendEvents(id, <DocumentEventInput>[event(1, id)]);
      }

      expect((await store.loadForOpen('doc-a'))!.tail.single.json, 'doc-a');
      expect((await store.loadForOpen('doc-b'))!.tail.single.json, 'doc-b');
    });
  });

  group('replacing a snapshot is not an append', () {
    test('a new snapshot leaves the events it folds untouched', () async {
      await store.putDocument(
        id: 'doc-1',
        title: 'T',
        songKey: 'C major',
        bpm: 0,
        snapshotJson: '{"v":1}',
        snapshotSeq: 3,
        updatedAt: '2026-10-10T10:00:00Z',
      );
      await store.appendEvents('doc-1', <DocumentEventInput>[
        event(1, 'a'),
        event(2, 'b'),
        event(3, 'c'),
        event(4, 'd'),
      ]);

      await store.putDocument(
        id: 'doc-1',
        title: 'T',
        songKey: 'C major',
        bpm: 0,
        snapshotJson: '{"v":2}',
        snapshotSeq: 4,
        updatedAt: '2026-10-10T11:00:00Z',
      );

      // The snapshot is a derived cache of the log, so replacing it is what taking a snapshot
      // means. The log itself must be exactly as it was.
      expect(await store.eventCount('doc-1'), 4);
      final OpenDocument opened = (await store.loadForOpen('doc-1'))!;
      expect(opened.snapshotSeq, 4);
      expect(opened.snapshotJson, '{"v":2}');
      expect(opened.tail, isEmpty);
    });
  });

  group('meta', () {
    test('round-trips and updates', () async {
      expect(await store.getMeta('schema'), isNull);
      await store.setMeta('schema', '1');
      expect(await store.getMeta('schema'), '1');
      await store.setMeta('schema', '2');
      expect(await store.getMeta('schema'), '2');
    });
  });

  group('a file-backed store', () {
    test('persists across close and reopen', () async {
      final Directory scratch = Directory.systemTemp.createTempSync(
        'chart_store_test',
      );
      final String path =
          '${scratch.path}${Platform.pathSeparator}chartapp.sqlite';
      try {
        final ChartStore first = ChartStore.openFile(path);
        await first.putDocument(
          id: 'doc-1',
          title: 'Persisted',
          songKey: 'F# minor',
          bpm: 96,
          snapshotJson: '{"kept":true}',
          snapshotSeq: 2,
          updatedAt: '2026-10-10T10:00:00Z',
        );
        await first.appendEvents('doc-1', <DocumentEventInput>[
          event(3, 'tail'),
        ]);
        await first.close();

        final ChartStore second = ChartStore.openFile(path);
        final OpenDocument opened = (await second.loadForOpen('doc-1'))!;
        expect(opened.title, 'Persisted');
        expect(opened.songKey, 'F# minor');
        expect(opened.snapshotJson, '{"kept":true}');
        expect(opened.tail.single.json, 'tail');
        await second.close();
      } finally {
        if (scratch.existsSync()) {
          scratch.deleteSync(recursive: true);
        }
      }
    });
  });
}
