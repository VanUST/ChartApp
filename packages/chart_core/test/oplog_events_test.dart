// PURPOSE: Pin the three properties the document event catalogue is built on: every event
//          survives a JSON round trip unchanged, applying an event and then its inverse returns
//          the document it started from, and a payload the reader does not understand is refused
//          by name rather than partly applied. The catalogue is what a `.chart` file's operation
//          tail is made of and what undo appends to, so a field swapped between two places in a
//          payload would lose a musician's handwriting on the next save.
// INPUTS: None. The fixtures are hand-built documents whose values are ALL DISTINCT, so that a
//         field mapped to the wrong place produces a different value rather than a coincidence —
//         which is what makes the round trip a test of the field mapping and not only of JSON.
// OUTPUTS: Pass/fail per expectation. The inverse property is asserted by applying the event,
//          checking the document actually CHANGED, applying the inverse and comparing with the
//          original value — a test that would pass with a no-op reducer is not evidence.
// KEYWORDS: test, op-log, event, json-round-trip, inverse, strict-decode, undo, ink, text-cue
//
// The families that survive are the ones the application can still produce: the pen
// (`ink.stroke.*`), a remark on a bar (`textcue.*`), the room a bar is given (`size.set`), the
// chart's own metadata (`song.update`) and a programme's entries (`setlist.*`). The note, chord,
// measure, section, repeat, meter, staff, transposition, division, annotation and selection
// families were deleted with the musical editing they served, and their tests went with them.
import 'dart:convert';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

const EventAnchor _atA0 = EventAnchor(sectionId: 's1', bar: 0);
const EventAnchor _atA1 = EventAnchor(sectionId: 's1', bar: 1);

const InkStroke _strokeOne = InkStroke(
  id: 'ink-1',
  tool: StrokeTool.pen,
  color: '#112233',
  size: 2.5,
  anchor: _atA0,
  points: <InkPoint>[
    InkPoint(x: 0.0, y: 0.0, w: 0.5, t: 0.0),
    InkPoint(x: 3.5, y: 1.25, w: 0.75, t: 16.0),
    InkPoint(x: 7.0, y: 8.0, w: 0.25, t: 33.0),
  ],
);

const InkStroke _strokeTwo = InkStroke(
  id: 'ink-2',
  tool: StrokeTool.highlighter,
  color: '#445566',
  size: 9.75,
  anchor: _atA1,
  points: <InkPoint>[
    InkPoint(x: 1.0, y: 2.0, w: 0.125, t: 4.0),
    InkPoint(x: 5.0, y: 6.0, w: 1.0, t: 20.0),
  ],
);

const TextCue _cueOne = TextCue(
  id: 'cue-1',
  place: AnchoredPlace(anchor: _atA0, offsetX: 11.5, offsetY: 2.25),
  text: 'To Coda',
);

const TextCue _cueTwo = TextCue(
  id: 'cue-2',
  place: AnchoredPlace(anchor: _atA1, offsetX: 60.0, offsetY: 0.0),
  text: 'Vamp',
);

const SongMetadata _metaOne = SongMetadata(
  title: 'Paper Kite',
  composer: 'A. Nonymous',
  style: 'Medium Swing',
  tempo: 132,
);

const SongMetadata _metaTwo = SongMetadata(
  title: 'Paper Kite, arr.',
  composer: 'B. Other',
  style: 'Ballad',
  tempo: 96,
);

const SetlistItem _itemOne = SetlistItem(
  documentId: 'doc-1',
  chartIdentity: 'identity-one',
  transposeSem: 2,
  notes: 'count off',
);

const SetlistItem _itemTwo = SetlistItem(
  documentId: 'doc-2',
  chartIdentity: 'identity-two',
  transposeSem: -3,
  notes: '',
);

Song _song() => Song(
  id: 'doc-1',
  title: _metaOne.title,
  composer: _metaOne.composer,
  style: _metaOne.style,
  key: Key.cMajor,
  tempo: _metaOne.tempo,
  sections: <Section>[
    const Section(
      id: 's1',
      label: SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(),
        Bar(closingBarline: Barline.finalBar),
      ],
    ),
  ],
);

DocumentState _document() => DocumentState(
  song: _song(),
  strokes: <InkStroke>[_strokeOne],
  textCues: <TextCue>[_cueOne],
);

/// The document an event is applicable TO, which differs per family: an insert needs its value
/// absent and a delete needs it present, and an inverse test that applied an insert of something
/// already there would be testing the reducer's refusal rather than the round trip.
DocumentState _beforeFor(ChartEvent event) {
  final DocumentState base = _document();
  return switch (event) {
    InkStrokeAddEvent() => DocumentState(
      song: base.song,
      strokes: base.strokes
          .where((InkStroke s) => s.id != event.stroke.id)
          .toList(),
      textCues: base.textCues,
    ),
    InkStrokeDeleteEvent() => DocumentState(
      song: base.song,
      strokes: <InkStroke>[
        event.stroke,
        ...base.strokes.where((InkStroke s) => s.id != event.stroke.id),
      ],
      textCues: base.textCues,
    ),
    TextCueInsertEvent() => DocumentState(
      song: base.song,
      strokes: base.strokes,
      textCues: base.textCues
          .where((TextCue c) => c.id != event.cue.id)
          .toList(),
    ),
    TextCueDeleteEvent() => DocumentState(
      song: base.song,
      strokes: base.strokes,
      textCues: <TextCue>[
        event.removed,
        ...base.textCues.where((TextCue c) => c.id != event.removed.id),
      ],
    ),
    _ => base,
  };
}

/// Every surviving chart event, with all-distinct payload values.
final List<ChartEvent> _chartEvents = <ChartEvent>[
  const InkStrokeAddEvent(docId: 'doc-1', seq: 1, index: 0, stroke: _strokeOne),
  const InkStrokeAddEvent(docId: 'doc-1', seq: 2, index: 1, stroke: _strokeTwo),
  const InkStrokeDeleteEvent(
    docId: 'doc-1',
    seq: 3,
    index: 0,
    stroke: _strokeOne,
  ),
  const TextCueInsertEvent(docId: 'doc-1', seq: 4, index: 0, cue: _cueOne),
  const TextCueInsertEvent(docId: 'doc-1', seq: 5, index: 1, cue: _cueTwo),
  const TextCueDeleteEvent(docId: 'doc-1', seq: 6, index: 0, removed: _cueOne),
  const TextCueEditEvent(
    docId: 'doc-1',
    seq: 7,
    id: 'cue-1',
    from: 'To Coda',
    to: 'To Coda, then D.C.',
  ),
  const TextCueMoveEvent(
    docId: 'doc-1',
    seq: 8,
    id: 'cue-1',
    from: AnchoredPlace(anchor: _atA0, offsetX: 11.5, offsetY: 2.25),
    to: AnchoredPlace(anchor: _atA1, offsetX: 4.0, offsetY: 1.0),
  ),
  const BarSizeSetEvent(
    docId: 'doc-1',
    seq: 9,
    sectionId: 's1',
    barIndex: 1,
    from: BarSize.natural,
    to: BarSize(2.5),
  ),
  const SongUpdateEvent(docId: 'doc-1', seq: 10, from: _metaOne, to: _metaTwo),
];

final List<SetlistEvent> _setlistEvents = <SetlistEvent>[
  const SetlistRenameEvent(
    docId: 'set-1',
    seq: 1,
    fromTitle: 'Set A',
    toTitle: 'Set B',
  ),
  const SetlistItemInsertEvent(
    docId: 'set-1',
    seq: 2,
    index: 0,
    item: _itemOne,
  ),
  const SetlistItemInsertEvent(
    docId: 'set-1',
    seq: 3,
    index: 1,
    item: _itemTwo,
  ),
  const SetlistItemDeleteEvent(
    docId: 'set-1',
    seq: 4,
    index: 0,
    removed: _itemOne,
  ),
  const SetlistItemMoveEvent(docId: 'set-1', seq: 5, fromIndex: 0, toIndex: 1),
  const SetlistItemUpdateEvent(
    docId: 'set-1',
    seq: 6,
    index: 0,
    from: _itemOne,
    to: _itemTwo,
  ),
];

void main() {
  group('json round trip', () {
    for (final ChartEvent event in _chartEvents) {
      test('${event.type} survives the codec', () {
        final Map<String, Object?> json = EventCodec.encode(event);
        final DocumentEvent read = EventCodec.decode(json);
        expect(read, equals(event));
        expect(read.type, event.type);
        expect(read.payloadJson(), equals(event.payloadJson()));
      });
    }
    for (final SetlistEvent event in _setlistEvents) {
      test('${event.type} survives the codec', () {
        final DocumentEvent read = EventCodec.decode(EventCodec.encode(event));
        expect(read, equals(event));
        expect(read.payloadJson(), equals(event.payloadJson()));
      });
    }
  });

  group('applying an event and then its inverse', () {
    for (final ChartEvent event in _chartEvents) {
      test('returns the document ${event.type} started from', () {
        final DocumentState before = _beforeFor(event);
        final DocumentState after = DocumentReducer.apply(before, event);
        expect(
          after,
          isNot(equals(before)),
          reason: 'a reducer that did nothing would pass every inverse test',
        );
        final DocumentState restored = DocumentReducer.apply(
          after,
          event.inverse(),
        );
        expect(restored.strokes, equals(before.strokes));
        expect(restored.textCues, equals(before.textCues));
        expect(restored.song, equals(before.song));
      });
    }
  });

  group('the reducer reports an edit it cannot place', () {
    test('a stroke the document does not hold is refused by name', () {
      expect(
        () => DocumentReducer.apply(
          _document(),
          const InkStrokeDeleteEvent(
            docId: 'doc-1',
            seq: 1,
            index: 0,
            stroke: _strokeTwo,
          ),
        ),
        throwsA(isA<DocumentReducerException>()),
      );
    });

    test('a cue the document does not hold is refused by name', () {
      expect(
        () => DocumentReducer.apply(
          _document(),
          const TextCueDeleteEvent(
            docId: 'doc-1',
            seq: 1,
            index: 0,
            removed: _cueTwo,
          ),
        ),
        throwsA(isA<DocumentReducerException>()),
      );
    });

    test('a bar the song does not have is refused by name', () {
      expect(
        () => DocumentReducer.apply(
          _document(),
          const BarSizeSetEvent(
            docId: 'doc-1',
            seq: 1,
            sectionId: 's1',
            barIndex: 99,
            from: BarSize.natural,
            to: BarSize(2),
          ),
        ),
        throwsA(isA<DocumentReducerException>()),
      );
    });
  });

  group('strict decoding', () {
    test('an event type this build does not know is refused, not guessed', () {
      final Map<String, Object?> json = EventCodec.encode(_chartEvents.first);
      json['type'] = 'note.insert';
      expect(
        () => EventCodec.decode(json),
        throwsA(isA<UnknownEventTypeException>()),
      );
    });

    test('a payload missing one of its fields is refused', () {
      final Map<String, Object?> json = EventCodec.encode(_chartEvents.first);
      final Map<String, Object?> payload = Map<String, Object?>.of(
        json['payload']! as Map<String, Object?>,
      )..remove('stroke');
      json['payload'] = payload;
      expect(
        () => EventCodec.decode(json),
        throwsA(isA<EventFormatException>()),
      );
    });

    test('a document from a newer format is refused by version', () {
      final Map<String, Object?> json = EventCodec.encode(_chartEvents.first);
      json['v'] = 99;
      expect(
        () => EventCodec.decode(json),
        throwsA(isA<UnsupportedEventVersionException>()),
      );
    });

    test('a line is one event and decodes as one', () {
      final String line = EventCodec.encodeLine(_chartEvents.last);
      expect(jsonDecode(line), isA<Map<String, Object?>>());
      expect(EventCodec.decodeLine(line), equals(_chartEvents.last));
    });
  });
}
