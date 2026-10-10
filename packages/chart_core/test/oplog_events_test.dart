// PURPOSE: Pin the three properties the document event catalogue is built on: every event
//          survives a JSON round trip unchanged, applying an event and then its inverse returns
//          the document it started from, and the encoded field names and order are what the
//          reader expects — so a swapped pair of fields cannot pass the round trip unnoticed.
// INPUTS: None. The fixtures are hand-built documents whose values are all distinct, so that a
//         field mapped to the wrong place produces a different value rather than a coincidence.
// OUTPUTS: Pass/fail per expectation. The inverse property is asserted by applying the event,
//          checking the document actually CHANGED, applying the inverse and comparing with the
//          original value — a test that would pass with a no-op reducer is not evidence.
// KEYWORDS: test, op-log, event, json-round-trip, inverse, field-mapping, strict-decode, undo
import 'dart:convert';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------------------------
// The document the events are applied to. Every value that a field could be confused with is
// deliberately different from every other value in the same event.
// ---------------------------------------------------------------------------------------------

const WrittenNote _d = WrittenNote(NoteLetter.d, 0);
const WrittenNote _eFlat = WrittenNote(NoteLetter.e, -1);
const WrittenNote _a = WrittenNote(NoteLetter.a, 0);

const Chord _cMajor = Chord(root: ChordRoot(0));
const Chord _gSeventh = Chord(
  root: ChordRoot(7),
  quality: ChordQuality.dominantSeventh,
);
const Chord _dMinorSeventh = Chord(
  root: ChordRoot(2),
  quality: ChordQuality.minorSeventh,
);
const Chord _eMinorSeventh = Chord(
  root: ChordRoot(4),
  quality: ChordQuality.minorSeventh,
);

const BeatChord _cOnBeat0 = BeatChord(chord: _cMajor, beat: 0);
const BeatChord _gOnBeat2 = BeatChord(chord: _gSeventh, beat: 2);

const BeatNote _dQuarter = BeatNote(
  pitch: PitchedNote(note: _d, octave: 4),
  value: NoteValue.plain(NoteBase.quarter),
  beat: 0,
);
const BeatNote _eFlatHalf = BeatNote(
  pitch: PitchedNote(note: _eFlat, octave: 5),
  value: NoteValue.plain(NoteBase.half),
  beat: 2,
);

const Bar _barA = Bar(
  chords: <BeatChord>[_cOnBeat0, _gOnBeat2],
  melody: <BeatNote>[_dQuarter],
);
const Bar _barB = Bar(
  openingBarline: Barline.repeatStart,
  closingBarline: Barline.repeatEnd,
  volta: Volta(1),
);
const Bar _barC = Bar(
  noChord: true,
  marks: <BarMark>{BarMark.coda},
  staffText: <String>['To Coda'],
);
const Bar _barD = Bar(closingBarline: Barline.finalBar);

const Section _sectionA = Section(
  id: 's1',
  label: SectionLabel.letter('A'),
  bars: <Bar>[_barA, _barB, _barC],
);
const Section _sectionB = Section(
  id: 's2',
  label: SectionLabel.letter('B'),
  bars: <Bar>[_barD, Bar()],
);

final Song _song = Song(
  id: 'doc-1',
  title: 'Paper Kite',
  composer: 'A. Nonymous',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 132,
  sections: const <Section>[_sectionA, _sectionB],
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
);

const EventAnchor _atA0Beat0 = EventAnchor(sectionId: 's1', bar: 0, beat: 0);
const EventAnchor _atA0Beat2 = EventAnchor(sectionId: 's1', bar: 0, beat: 2);
const EventAnchor _atA0Bar = EventAnchor(sectionId: 's1', bar: 0);
const EventAnchor _atB1Bar = EventAnchor(sectionId: 's2', bar: 1);

const InkStroke _strokePen = InkStroke(
  id: 'ink-1',
  tool: StrokeTool.pen,
  color: '#112233',
  size: 2.5,
  anchor: _atA0Beat0,
  points: <InkPoint>[
    InkPoint(x: 0.0, y: 0.0, w: 0.5, t: 0.0),
    InkPoint(x: 3.5, y: 1.25, w: 0.75, t: 16.0),
  ],
);
const InkStroke _strokeHighlighter = InkStroke(
  id: 'ink-2',
  tool: StrokeTool.highlighter,
  color: '#ffcc00aa',
  size: 8.0,
  anchor: _atA0Beat2,
  points: <InkPoint>[InkPoint(x: 9.5, y: -4.25, w: 1.0, t: 33.0)],
);
const InkStroke _strokeNew = InkStroke(
  id: 'ink-3',
  tool: StrokeTool.pen,
  color: '#445566',
  size: 1.25,
  anchor: _atB1Bar,
  points: <InkPoint>[
    InkPoint(x: 1.0, y: 2.0, w: 0.25, t: 0.0),
    InkPoint(x: 5.0, y: 6.0, w: 0.5, t: 8.0),
    InkPoint(x: 7.0, y: 8.0, w: 0.75, t: 24.0),
  ],
);

const Annotation _annotationStamp = Annotation(
  id: 'ann-1',
  kind: AnnotationKind.stamp,
  place: AnchoredPlace(anchor: _atA0Beat0, offsetX: 1.5, offsetY: -2.0),
  payload: 'segno',
);
const Annotation _annotationInk = Annotation(
  id: 'ann-2',
  kind: AnnotationKind.ink,
  place: AnchoredPlace(anchor: _atA0Bar, offsetX: 0.0, offsetY: 4.0),
  payload: 'ink-1',
);
const Annotation _annotationCopy = Annotation(
  id: 'ann-3',
  kind: AnnotationKind.cue,
  place: AnchoredPlace(anchor: _atB1Bar),
  payload: 'copy of ann-1',
);

const TextCue _cueSoft = TextCue(
  id: 'cue-1',
  place: AnchoredPlace(anchor: _atA0Beat0),
  text: 'soft',
);
const TextCue _cueBuild = TextCue(
  id: 'cue-2',
  place: AnchoredPlace(anchor: _atA0Beat2, offsetX: -3.5, offsetY: 2.25),
  text: 'build',
);
const TextCue _cueInserted = TextCue(
  id: 'cue-3',
  place: AnchoredPlace(anchor: _atB1Bar, offsetX: 1.0, offsetY: 1.0),
  text: '',
);

/// The document every chart event below is applied to.
DocumentState _document() => DocumentState(
  song: _song,
  strokes: const <InkStroke>[_strokePen, _strokeHighlighter],
  annotations: const <Annotation>[_annotationStamp, _annotationInk],
  textCues: const <TextCue>[_cueSoft, _cueBuild],
);

final Setlist _setlist = Setlist(
  id: 'set-1',
  title: 'First set',
  items: <SetlistItem>[
    const SetlistItem(documentId: 'doc-1', transposeSem: 0, notes: 'count off'),
    const SetlistItem(documentId: 'doc-2', transposeSem: -2),
    const SetlistItem(documentId: 'doc-3', transposeSem: 3, notes: 'ballad'),
  ],
);

/// Every chart event, applied to the document above.
List<ChartEvent> _chartEvents() => <ChartEvent>[
  const ChordInsertEvent(
    docId: 'doc-1',
    seq: 1,
    sectionId: 's1',
    barIndex: 0,
    chord: BeatChord(chord: _dMinorSeventh, beat: 1, step: 0),
  ),
  ChordUpdateEvent(
    docId: 'doc-1',
    seq: 2,
    sectionId: 's1',
    barIndex: 0,
    from: _gOnBeat2,
    to: BeatChord(
      chord: _eMinorSeventh,
      beat: 2,
      step: 0,
      size: ChordSize.small,
    ),
  ),
  const ChordDeleteEvent(
    docId: 'doc-1',
    seq: 3,
    sectionId: 's1',
    barIndex: 0,
    removed: _gOnBeat2,
  ),
  const NoteInsertEvent(
    docId: 'doc-1',
    seq: 4,
    sectionId: 's1',
    barIndex: 0,
    note: _eFlatHalf,
  ),
  NoteUpdateEvent(
    docId: 'doc-1',
    seq: 5,
    sectionId: 's1',
    barIndex: 0,
    from: _dQuarter,
    to: BeatNote(
      pitch: PitchedNote(note: _a, octave: 3),
      value: NoteValue.plain(NoteBase.eighth),
      beat: 0,
      tiedToNext: true,
    ),
  ),
  const NoteDeleteEvent(
    docId: 'doc-1',
    seq: 6,
    sectionId: 's1',
    barIndex: 0,
    removed: _dQuarter,
  ),
  const MeasureInsertEvent(
    docId: 'doc-1',
    seq: 7,
    sectionId: 's1',
    index: 1,
    bar: Bar(
      timeSignature: TimeSignature.threeFour,
      chords: <BeatChord>[_cOnBeat0],
    ),
  ),
  const MeasureDeleteEvent(
    docId: 'doc-1',
    seq: 8,
    sectionId: 's1',
    index: 1,
    removed: _barB,
  ),
  const MeasureDuplicateEvent(
    docId: 'doc-1',
    seq: 9,
    sectionId: 's1',
    index: 0,
    duplicate: _barA,
  ),
  const SectionInsertEvent(
    docId: 'doc-1',
    seq: 10,
    index: 1,
    section: Section(id: 's-intro', label: SectionLabel.intro()),
  ),
  const SectionDeleteEvent(
    docId: 'doc-1',
    seq: 11,
    index: 1,
    removed: _sectionB,
  ),
  const SectionUpdateEvent(
    docId: 'doc-1',
    seq: 12,
    sectionId: 's2',
    from: SectionLabel.letter('B'),
    to: SectionLabel.custom('Chorus'),
  ),
  const SectionDuplicateEvent(
    docId: 'doc-1',
    seq: 13,
    sourceId: 's1',
    index: 0,
    duplicate: Section(id: 's1-copy', label: SectionLabel.letter('A')),
  ),
  const SectionReorderEvent(
    docId: 'doc-1',
    seq: 14,
    sectionId: 's2',
    fromIndex: 1,
    toIndex: 0,
  ),
  const RepeatSetEvent(
    docId: 'doc-1',
    seq: 15,
    sectionId: 's1',
    barIndex: 1,
    from: RepeatSigns(
      openingBarline: Barline.repeatStart,
      closingBarline: Barline.repeatEnd,
    ),
    to: RepeatSigns(slashRepeat: true),
  ),
  const VoltaSetEvent(
    docId: 'doc-1',
    seq: 16,
    sectionId: 's1',
    barIndex: 1,
    from: Volta(1),
    to: Volta(2),
  ),
  const KeyTransposeEvent(
    docId: 'doc-1',
    seq: 17,
    semitones: 2,
    fromKey: Key.cMajor,
    toKey: Key(tonic: _d, mode: Mode.major),
  ),
  const InkStrokeAddEvent(
    docId: 'doc-1',
    seq: 18,
    index: 1,
    stroke: _strokeNew,
  ),
  const InkStrokeDeleteEvent(
    docId: 'doc-1',
    seq: 19,
    index: 0,
    stroke: _strokePen,
  ),
  const AnnotationInsertEvent(
    docId: 'doc-1',
    seq: 20,
    index: 0,
    annotation: _annotationCopy,
  ),
  const AnnotationDeleteEvent(
    docId: 'doc-1',
    seq: 21,
    index: 0,
    removed: _annotationStamp,
  ),
  const AnnotationMoveEvent(
    docId: 'doc-1',
    seq: 22,
    id: 'ann-2',
    from: AnchoredPlace(anchor: _atA0Bar, offsetX: 0.0, offsetY: 4.0),
    to: AnchoredPlace(anchor: _atB1Bar, offsetX: -1.0, offsetY: 1.0),
  ),
  const AnnotationDuplicateEvent(
    docId: 'doc-1',
    seq: 23,
    sourceId: 'ann-1',
    index: 1,
    duplicate: _annotationCopy,
  ),
  const TextCueInsertEvent(
    docId: 'doc-1',
    seq: 24,
    index: 0,
    cue: _cueInserted,
  ),
  const TextCueDeleteEvent(
    docId: 'doc-1',
    seq: 25,
    index: 0,
    removed: _cueSoft,
  ),
  const TextCueEditEvent(
    docId: 'doc-1',
    seq: 26,
    id: 'cue-1',
    from: 'soft',
    to: 'gently, then build',
  ),
  const TextCueMoveEvent(
    docId: 'doc-1',
    seq: 27,
    id: 'cue-2',
    from: AnchoredPlace(anchor: _atA0Beat2, offsetX: -3.5, offsetY: 2.25),
    to: AnchoredPlace(anchor: _atB1Bar, offsetX: 0.5, offsetY: 0.5),
  ),
  // Every one of the four metadata fields differs from the song's own, so a field mapped to the
  // wrong slot — a style written into the composer, a tempo read as the title — changes the value
  // instead of coinciding with it.
  const SongUpdateEvent(
    docId: 'doc-1',
    seq: 28,
    from: SongMetadata(
      title: 'Paper Kite',
      composer: 'A. Nonymous',
      style: 'Medium Swing',
      tempo: 132,
    ),
    to: SongMetadata(
      title: 'Paper Kite (live)',
      composer: 'Anonymous',
      style: 'Ballad',
      tempo: 64,
    ),
  ),
  // A bar that carried NO sign gains two at once, which is the case a single-mark event could not
  // express: the `to` side is a set of two and the `from` side is the EMPTY set — the state a bar
  // reaches when its last sign is taken off, and one an inverse must be able to name. The bar is
  // the first of section s1, which carries no mark at all, so this changes the document.
  const BarMarkSetEvent(
    docId: 'doc-1',
    seq: 29,
    sectionId: 's1',
    barIndex: 0,
    from: <BarMark>{},
    to: <BarMark>{BarMark.segno, BarMark.coda},
  ),
];

/// Every setlist event, applied to the setlist above.
List<SetlistEvent> _setlistEvents() => <SetlistEvent>[
  const SetlistRenameEvent(
    docId: 'set-1',
    seq: 40,
    fromTitle: 'First set',
    toTitle: 'Encore',
  ),
  const SetlistItemInsertEvent(
    docId: 'set-1',
    seq: 41,
    index: 1,
    item: SetlistItem(documentId: 'doc-9', transposeSem: 1),
  ),
  const SetlistItemDeleteEvent(
    docId: 'set-1',
    seq: 42,
    index: 1,
    removed: SetlistItem(documentId: 'doc-2', transposeSem: -2),
  ),
  const SetlistItemMoveEvent(docId: 'set-1', seq: 43, fromIndex: 0, toIndex: 2),
  const SetlistItemUpdateEvent(
    docId: 'set-1',
    seq: 44,
    index: 0,
    from: SetlistItem(documentId: 'doc-1', transposeSem: 0, notes: 'count off'),
    to: SetlistItem(
      documentId: 'doc-1',
      transposeSem: -1,
      notes: 'count off, quieter',
    ),
  ),
];

/// Parses [line] as a JSON object, failing the test when it is not one.
Map<String, Object?> _json(String line) {
  final Object? decoded = jsonDecode(line);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  fail('not a JSON object: $line');
}

void main() {
  group('json round trip', () {
    test('every chart event encodes and decodes to the same value', () {
      for (final ChartEvent event in _chartEvents()) {
        final DocumentEvent decoded = EventCodec.decode(
          EventCodec.encode(event),
        );
        expect(decoded, event, reason: event.type);
      }
    });

    test('every setlist event encodes and decodes to the same value', () {
      for (final SetlistEvent event in _setlistEvents()) {
        expect(EventCodec.decode(EventCodec.encode(event)), event);
      }
    });

    test('an event survives a line of events.jsonl', () {
      for (final DocumentEvent event in <DocumentEvent>[
        ..._chartEvents(),
        ..._setlistEvents(),
      ]) {
        expect(EventCodec.decodeLine(EventCodec.encodeLine(event)), event);
      }
    });

    test('the sequence number can be reassigned without changing the rest', () {
      for (final DocumentEvent event in <DocumentEvent>[
        ..._chartEvents(),
        ..._setlistEvents(),
      ]) {
        final DocumentEvent renumbered = event.withSeq(9001);
        expect(renumbered.seq, 9001);
        expect(renumbered, isNot(event));
        expect(renumbered.withSeq(event.seq), event);
      }
    });
  });

  group('encoded field names are pinned, per family', () {
    // Each case decodes a literal line and compares it with the event it must produce, then
    // re-encodes the event and compares that with the same literal object. A field mapped to the
    // wrong key, or two fields swapped, fails one of the two comparisons — which the value-only
    // round trip above cannot catch, because a swapped pair swaps back.
    final Map<String, (String, DocumentEvent)>
    cases = <String, (String, DocumentEvent)>{
      'chord.insert': (
        '{"v":1,"docId":"doc-1","seq":1,"anchor":{"sectionId":"s1","bar":0,'
            '"beat":1,"step":0},'
            '"type":"chord.insert","payload":{"sectionId":"s1","bar":0,'
            '"chord":{"chord":{"root":{"semitones":2,"preference":"automatic"},'
            '"quality":"m7","bass":null,"alternate":null},'
            '"beat":1,"step":0,"size":"normal"}}}',
        ChordInsertEvent(
          docId: 'doc-1',
          seq: 1,
          sectionId: 's1',
          barIndex: 0,
          chord: BeatChord(chord: _dMinorSeventh, beat: 1),
        ),
      ),
      'note.insert': (
        '{"v":1,"docId":"doc-1","seq":4,"anchor":{"sectionId":"s1","bar":0,'
            '"beat":2,"step":0},'
            '"type":"note.insert","payload":{"sectionId":"s1","bar":0,'
            '"note":{"pitch":{"note":{"letter":"e","alter":-1},"octave":5},'
            '"value":{"base":"half","dots":0,"tuplet":null},'
            '"beat":2,"step":0,"tiedToNext":false}}}',
        NoteInsertEvent(
          docId: 'doc-1',
          seq: 4,
          sectionId: 's1',
          barIndex: 0,
          note: _eFlatHalf,
        ),
      ),
      'measure.insert': (
        '{"v":1,"docId":"doc-1","seq":7,"anchor":{"sectionId":"s1","bar":1,'
            '"beat":null,"step":0},'
            '"type":"measure.insert","payload":{"sectionId":"s1","index":1,'
            '"bar":{"timeSignature":{"numerator":3,"denominator":4},'
            '"chords":[{"chord":{"root":{"semitones":0,"preference":"automatic"},'
            '"quality":"","bass":null,"alternate":null},"beat":0,"step":0,'
            '"size":"normal"}],'
            '"melody":[],"percussion":[],'
            '"openingBarline":"single","closingBarline":"single",'
            '"volta":null,"repeatPrevious":"none","slashRepeat":false,'
            '"noChord":false,"marks":[],"staffText":[]}}}',
        const MeasureInsertEvent(
          docId: 'doc-1',
          seq: 7,
          sectionId: 's1',
          index: 1,
          bar: Bar(timeSignature: TimeSignature.threeFour, chords: [_cOnBeat0]),
        ),
      ),
      'section.update': (
        '{"v":1,"docId":"doc-1","seq":12,'
            '"type":"section.update","payload":{"sectionId":"s2",'
            '"from":{"kind":"letter","text":"B"},'
            '"to":{"kind":"custom","text":"Chorus"}}}',
        SectionUpdateEvent(
          docId: 'doc-1',
          seq: 12,
          sectionId: 's2',
          from: SectionLabel.letter('B'),
          to: SectionLabel.custom('Chorus'),
        ),
      ),
      'section.reorder': (
        '{"v":1,"docId":"doc-1","seq":14,'
            '"type":"section.reorder","payload":{"sectionId":"s2",'
            '"fromIndex":1,"toIndex":0}}',
        const SectionReorderEvent(
          docId: 'doc-1',
          seq: 14,
          sectionId: 's2',
          fromIndex: 1,
          toIndex: 0,
        ),
      ),
      'repeat.set': (
        '{"v":1,"docId":"doc-1","seq":15,"anchor":{"sectionId":"s1","bar":1,'
            '"beat":null,"step":0},'
            '"type":"repeat.set","payload":{"sectionId":"s1","bar":1,'
            '"from":{"opening":"repeatStart","closing":"repeatEnd",'
            '"previous":"none","slash":false},'
            '"to":{"opening":"single","closing":"single",'
            '"previous":"none","slash":true}}}',
        const RepeatSetEvent(
          docId: 'doc-1',
          seq: 15,
          sectionId: 's1',
          barIndex: 1,
          from: RepeatSigns(
            openingBarline: Barline.repeatStart,
            closingBarline: Barline.repeatEnd,
          ),
          to: RepeatSigns(slashRepeat: true),
        ),
      ),
      'volta.set': (
        '{"v":1,"docId":"doc-1","seq":16,"anchor":{"sectionId":"s1","bar":1,'
            '"beat":null,"step":0},'
            '"type":"volta.set","payload":{"sectionId":"s1","bar":1,'
            '"from":1,"to":2}}',
        const VoltaSetEvent(
          docId: 'doc-1',
          seq: 16,
          sectionId: 's1',
          barIndex: 1,
          from: Volta(1),
          to: Volta(2),
        ),
      ),
      'key.transpose': (
        '{"v":1,"docId":"doc-1","seq":17,"type":"key.transpose",'
            '"payload":{"semitones":2,'
            '"fromKey":{"tonic":{"letter":"c","alter":0},"mode":"major"},'
            '"toKey":{"tonic":{"letter":"d","alter":0},"mode":"major"}}}',
        const KeyTransposeEvent(
          docId: 'doc-1',
          seq: 17,
          semitones: 2,
          fromKey: Key.cMajor,
          toKey: Key(tonic: _d, mode: Mode.major),
        ),
      ),
      'song.update': (
        '{"v":1,"docId":"doc-1","seq":28,"type":"song.update",'
            '"payload":{"from":{"title":"Paper Kite","composer":"A. Nonymous",'
            '"style":"Medium Swing","tempo":132},'
            '"to":{"title":"Paper Kite (live)","composer":"Anonymous",'
            '"style":"Ballad","tempo":64}}}',
        const SongUpdateEvent(
          docId: 'doc-1',
          seq: 28,
          from: SongMetadata(
            title: 'Paper Kite',
            composer: 'A. Nonymous',
            style: 'Medium Swing',
            tempo: 132,
          ),
          to: SongMetadata(
            title: 'Paper Kite (live)',
            composer: 'Anonymous',
            style: 'Ballad',
            tempo: 64,
          ),
        ),
      ),
      'mark.set': (
        '{"v":1,"docId":"doc-1","seq":29,"anchor":{"sectionId":"s1","bar":0,'
            '"beat":null,"step":0},'
            '"type":"mark.set","payload":{"sectionId":"s1","bar":0,'
            '"from":[],"to":["segno","coda"]}}',
        const BarMarkSetEvent(
          docId: 'doc-1',
          seq: 29,
          sectionId: 's1',
          barIndex: 0,
          from: <BarMark>{},
          to: <BarMark>{BarMark.segno, BarMark.coda},
        ),
      ),
      'ink.stroke.add': (
        '{"v":1,"docId":"doc-1","seq":18,"anchor":{"sectionId":"doc-a",'
            '"bar":7,"beat":3,"step":1},'
            '"type":"ink.stroke.add","payload":{"index":1,'
            '"stroke":{"id":"ink-9","tool":"highlighter",'
            '"color":"#ffcc00aa","size":8.0,'
            '"anchor":{"sectionId":"doc-a","bar":7,"beat":3,"step":1},'
            '"points":[[1.0,2.0,0.5,0.0],[3.0,4.5,0.25,16.0]]}}}',
        const InkStrokeAddEvent(
          docId: 'doc-1',
          seq: 18,
          index: 1,
          stroke: InkStroke(
            id: 'ink-9',
            tool: StrokeTool.highlighter,
            color: '#ffcc00aa',
            size: 8.0,
            anchor: EventAnchor(sectionId: 'doc-a', bar: 7, beat: 3, step: 1),
            points: <InkPoint>[
              InkPoint(x: 1.0, y: 2.0, w: 0.5, t: 0.0),
              InkPoint(x: 3.0, y: 4.5, w: 0.25, t: 16.0),
            ],
          ),
        ),
      ),
      'annotation.insert': (
        '{"v":1,"docId":"doc-1","seq":20,"anchor":{"sectionId":"s2",'
            '"bar":1,"beat":null,"step":0},'
            '"type":"annotation.insert","payload":{"index":0,'
            '"annotation":{"id":"ann-3","kind":"cue",'
            '"place":{"anchor":{"sectionId":"s2","bar":1,"beat":null,'
            '"step":0},"offsetX":0.0,"offsetY":0.0},'
            '"payload":"copy of ann-1"}}}',
        const AnnotationInsertEvent(
          docId: 'doc-1',
          seq: 20,
          index: 0,
          annotation: _annotationCopy,
        ),
      ),
      'annotation.move': (
        '{"v":1,"docId":"doc-1","seq":22,"anchor":{"sectionId":"s2",'
            '"bar":1,"beat":null,"step":0},'
            '"type":"annotation.move","payload":{"id":"ann-2",'
            '"from":{"anchor":{"sectionId":"s1","bar":0,"beat":null,'
            '"step":0},"offsetX":0.0,"offsetY":4.0},'
            '"to":{"anchor":{"sectionId":"s2","bar":1,"beat":null,'
            '"step":0},"offsetX":-1.0,"offsetY":1.0}}}',
        const AnnotationMoveEvent(
          docId: 'doc-1',
          seq: 22,
          id: 'ann-2',
          from: AnchoredPlace(anchor: _atA0Bar, offsetX: 0.0, offsetY: 4.0),
          to: AnchoredPlace(anchor: _atB1Bar, offsetX: -1.0, offsetY: 1.0),
        ),
      ),
      'textcue.edit': (
        '{"v":1,"docId":"doc-1","seq":26,"type":"textcue.edit",'
            '"payload":{"id":"cue-1","from":"soft",'
            '"to":"gently, then build"}}',
        const TextCueEditEvent(
          docId: 'doc-1',
          seq: 26,
          id: 'cue-1',
          from: 'soft',
          to: 'gently, then build',
        ),
      ),
      'textcue.move': (
        '{"v":1,"docId":"doc-1","seq":27,"anchor":{"sectionId":"s2",'
            '"bar":1,"beat":null,"step":0},'
            '"type":"textcue.move","payload":{"id":"cue-2",'
            '"from":{"anchor":{"sectionId":"s1","bar":0,"beat":2,'
            '"step":0},"offsetX":-3.5,"offsetY":2.25},'
            '"to":{"anchor":{"sectionId":"s2","bar":1,"beat":null,'
            '"step":0},"offsetX":0.5,"offsetY":0.5}}}',
        const TextCueMoveEvent(
          docId: 'doc-1',
          seq: 27,
          id: 'cue-2',
          from: AnchoredPlace(anchor: _atA0Beat2, offsetX: -3.5, offsetY: 2.25),
          to: AnchoredPlace(anchor: _atB1Bar, offsetX: 0.5, offsetY: 0.5),
        ),
      ),
      'setlist.item.move': (
        '{"v":1,"docId":"set-1","seq":43,"type":"setlist.item.move",'
            '"payload":{"fromIndex":0,"toIndex":2}}',
        const SetlistItemMoveEvent(
          docId: 'set-1',
          seq: 43,
          fromIndex: 0,
          toIndex: 2,
        ),
      ),
    };

    for (final MapEntry<String, (String, DocumentEvent)> entry
        in cases.entries) {
      test(entry.key, () {
        final Map<String, Object?> literal = _json(entry.value.$1);
        final DocumentEvent expected = entry.value.$2;
        expect(expected.type, entry.key);
        expect(EventCodec.decode(literal), expected);
        expect(EventCodec.encode(expected), literal);
      });
    }
  });

  group('applying an event and then its inverse', () {
    for (final ChartEvent event in _chartEvents()) {
      test('restores the document after ${event.type}', () {
        final DocumentState before = _document();
        final DocumentState after = DocumentReducer.apply(before, event);
        expect(
          after,
          isNot(before),
          reason: '${event.type} must actually change the document',
        );
        expect(
          DocumentReducer.apply(after, event.inverse()),
          before,
          reason: 'the inverse of ${event.type} must restore the document',
        );
      });
    }

    for (final SetlistEvent event in _setlistEvents()) {
      test('restores the setlist after ${event.type}', () {
        final Setlist after = DocumentReducer.applySetlist(_setlist, event);
        expect(
          after,
          isNot(_setlist),
          reason: '${event.type} must actually change the setlist',
        );
        expect(
          DocumentReducer.applySetlist(after, event.inverse()),
          _setlist,
          reason: 'the inverse of ${event.type} must restore the setlist',
        );
      });
    }
  });

  group('a note packed onto a shared beat is still addressable', () {
    test('inserting at a step pushes the later steps up and the inverse pushes '
        'them back', () {
      // Two chords on one beat is what a comma packs into a cell, and the case where a naive
      // "append to the list" would leave two chords claiming the same address.
      const DocumentState before = DocumentState(
        song: Song(
          id: 'doc-step',
          title: 'packed',
          sections: <Section>[
            Section(
              id: 's1',
              label: SectionLabel.letter('A'),
              bars: <Bar>[
                Bar(
                  chords: <BeatChord>[
                    BeatChord(chord: _cMajor, beat: 0),
                    BeatChord(chord: _gSeventh, beat: 0, step: 1),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      const ChordInsertEvent event = ChordInsertEvent(
        docId: 'doc-step',
        seq: 1,
        sectionId: 's1',
        barIndex: 0,
        chord: BeatChord(chord: _dMinorSeventh, beat: 0),
      );
      final DocumentState after = DocumentReducer.apply(before, event);
      expect(after.song.barAt('s1', 0)!.chords, <BeatChord>[
        BeatChord(chord: _dMinorSeventh, beat: 0),
        BeatChord(chord: _cMajor, beat: 0, step: 1),
        BeatChord(chord: _gSeventh, beat: 0, step: 2),
      ]);
      expect(DocumentReducer.apply(after, event.inverse()), before);
    });
  });

  group('strict decoding', () {
    test('an unknown type is reported rather than skipped', () {
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":1,'
        '"type":"chord.upsert","payload":{"sectionId":"s1","bar":0}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('chord.upsert'),
          ),
        ),
      );
    });

    test('a missing required field is reported', () {
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":1,"type":"textcue.edit",'
        '"payload":{"id":"cue-1","from":"soft"}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(isA<EventFormatException>()),
      );
    });

    test('a song.update that names only the field being changed is reported '
        'rather than defaulted', () {
      // The event is whole-value on both sides, because its inverse is the same four fields
      // swapped: a payload carrying only the changed field would leave the inverse unable to name
      // the values it must restore, and a default would make a truncated event look like an edit
      // that cleared a title. Absent is therefore a typed failure.
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":28,"type":"song.update",'
        '"payload":{"from":{"title":"a","composer":"b","style":"c","tempo":120},'
        '"to":{"tempo":90}}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('title'),
          ),
        ),
      );
    });

    test('a mark.set missing a side is reported rather than defaulted', () {
      // The event carries the WHOLE set of signs on both sides, because its inverse is the two
      // sets swapped: a payload naming only the side that changed would leave the inverse unable
      // to say what the bar carried before, and a default would make a truncated event look like
      // an edit that cleared every sign. Absent is therefore a typed failure.
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":29,"type":"mark.set",'
        '"payload":{"sectionId":"s1","bar":0,"to":["segno"]}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('from'),
          ),
        ),
      );
    });

    test('a mark.set naming a sign this build does not have is reported, not '
        'dropped', () {
      // A dropped sign is a sign the musician put on the bar and the page no longer shows, which
      // is the outcome an event log exists to make impossible.
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":29,"type":"mark.set",'
        '"payload":{"sectionId":"s1","bar":0,"from":[],'
        '"to":["segno","dalSegno"]}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('dalSegno'),
          ),
        ),
      );
    });

    test('a field of the wrong type is reported, not coerced', () {
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":1,"type":"chord.insert",'
        '"payload":{"sectionId":"s1","bar":"zero","chord":{}}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('bar'),
          ),
        ),
      );
    });

    test('an unknown enum token is reported', () {
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":1,"type":"volta.set",'
        '"payload":{"sectionId":"s1","bar":0,"from":1,"to":2}}',
      );
      expect(EventCodec.decode(json), isA<VoltaSetEvent>());
      final Map<String, Object?> badVersion = <String, Object?>{
        ...json,
        'v': 99,
      };
      expect(
        () => EventCodec.decode(badVersion),
        throwsA(isA<EventFormatException>()),
      );
    });

    test('a jsonl tail skips blank lines and reports a bad line with its '
        'number', () {
      const ChordDeleteEvent event = ChordDeleteEvent(
        docId: 'doc-1',
        seq: 3,
        sectionId: 's1',
        barIndex: 0,
        removed: _gOnBeat2,
      );
      final String line = EventCodec.encodeLine(event);
      expect(EventCodec.decodeLines(<String>[line, '', '   ', line]).length, 2);
      expect(
        () => EventCodec.decodeLines(<String>[line, 'not json at all']),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('line 2'),
          ),
        ),
      );
    });
  });

  group('the reducer reports an edit it cannot place', () {
    test('a missing section is a failure, not a silent no-op', () {
      const ChordInsertEvent event = ChordInsertEvent(
        docId: 'doc-1',
        seq: 1,
        sectionId: 'nope',
        barIndex: 0,
        chord: _cOnBeat0,
      );
      expect(
        () => DocumentReducer.apply(_document(), event),
        throwsA(isA<DocumentReducerException>()),
      );
    });

    test('a bar index past the end of a section is a failure', () {
      const MeasureDeleteEvent event = MeasureDeleteEvent(
        docId: 'doc-1',
        seq: 1,
        sectionId: 's1',
        index: 99,
        removed: _barA,
      );
      expect(
        () => DocumentReducer.apply(_document(), event),
        throwsA(isA<DocumentReducerException>()),
      );
    });
  });
}
