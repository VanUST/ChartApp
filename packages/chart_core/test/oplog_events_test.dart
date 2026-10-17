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

// THE FIXTURE MARKS CARRY THEIR REAL ADDRESS. A mark's place names its bar, and the reducer keeps
// that address truthful on every edit (see `DocumentReducer._anchoredBars`), so a fixture built with
// a placeholder address would be rewritten the first time any event landed in its section and would
// then differ from the very value an assertion compares it to. `cellPlace(section, bar, beat)` is the
// shim's write direction and is what keeps these fixtures saying the same thing the document says.
final ChordMark _cOnBeat0 = ChordMark(
  place: cellPlace('s1', 0, 0),
  chord: _cMajor,
);
final ChordMark _gOnBeat2 = ChordMark(
  place: cellPlace('s1', 0, 2),
  chord: _gSeventh,
);

final NoteMark _dQuarter = NoteMark(
  place: cellPlace('s1', 0, 0),
  pitch: PitchedNote(note: _d, octave: 4),
  value: NoteValue.plain(NoteBase.quarter),
);
final NoteMark _eFlatHalf = NoteMark(
  place: cellPlace('s1', 0, 2),
  pitch: PitchedNote(note: _eFlat, octave: 5),
  value: NoteValue.plain(NoteBase.half),
);

final Bar _barA = Bar(
  chords: <ChordMark>[_cOnBeat0, _gOnBeat2],
  melody: <NoteMark>[_dQuarter],
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

final Section _sectionA = Section(
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
  sections: <Section>[_sectionA, _sectionB],
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
);

const EventAnchor _atA0Bar = EventAnchor(sectionId: 's1', bar: 0);
const EventAnchor _atB1Bar = EventAnchor(sectionId: 's2', bar: 1);

const InkStroke _strokePen = InkStroke(
  id: 'ink-1',
  tool: StrokeTool.pen,
  color: '#112233',
  size: 2.5,
  anchor: _atA0Bar,
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
  anchor: _atA0Bar,
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
  place: AnchoredPlace(anchor: _atA0Bar, offsetX: 1.5, offsetY: -2.0),
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
  place: AnchoredPlace(anchor: _atA0Bar),
  text: 'soft',
);
const TextCue _cueBuild = TextCue(
  id: 'cue-2',
  place: AnchoredPlace(anchor: _atA0Bar, offsetX: -3.5, offsetY: 2.25),
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
  ChordInsertEvent(
    docId: 'doc-1',
    seq: 1,
    chord: ChordMark(place: cellPlace('s1', 0, 1, 0), chord: _dMinorSeventh),
  ),
  ChordUpdateEvent(
    docId: 'doc-1',
    seq: 2,
    from: _gOnBeat2,
    to: ChordMark(
      place: cellPlace('s1', 0, 2, 0),
      chord: _eMinorSeventh,
      size: ChordSize.small,
    ),
  ),
  ChordDeleteEvent(docId: 'doc-1', seq: 3, removed: _gOnBeat2),
  NoteInsertEvent(docId: 'doc-1', seq: 4, note: _eFlatHalf),
  NoteUpdateEvent(
    docId: 'doc-1',
    seq: 5,
    from: _dQuarter,
    to: NoteMark(
      place: cellPlace('s1', 0, 0),
      pitch: PitchedNote(note: _a, octave: 3),
      value: NoteValue.plain(NoteBase.eighth),
      tiedToNext: true,
    ),
  ),
  NoteDeleteEvent(docId: 'doc-1', seq: 6, removed: _dQuarter),
  MeasureInsertEvent(
    docId: 'doc-1',
    seq: 7,
    sectionId: 's1',
    index: 1,
    bar: Bar(
      timeSignature: TimeSignature.threeFour,
      chords: <ChordMark>[_cOnBeat0],
    ),
  ),
  MeasureDeleteEvent(
    docId: 'doc-1',
    seq: 8,
    sectionId: 's1',
    index: 1,
    removed: _barB,
  ),
  MeasureDuplicateEvent(
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
    from: AnchoredPlace(anchor: _atA0Bar, offsetX: -3.5, offsetY: 2.25),
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
  // A bar in 4/4 taken into 3/4, which is a real meter change on a real bar: the two figures
  // travel together and both sides carry the whole meter, because the model has no value meaning
  // "leave the meter alone" — 4/4 is a meter a musician may have chosen, not the absence of one.
  const MeterSetEvent(
    docId: 'doc-1',
    seq: 30,
    sectionId: 's1',
    barIndex: 0,
    from: TimeSignature.fourFour,
    to: TimeSignature.threeFour,
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
        // UPDATED BY THE CHANGE THAT MADE A CHORD'S ADDRESS A PLACE, and here is what it said
        // before, so a reader can see what moved: the envelope's anchor carried `"beat":1,"step":0`,
        // the payload carried `"sectionId":"s1","bar":0` as well, and the mark itself was
        // `"beat":1,"step":0`. All three are gone: the mark's place names the bar AND the position
        // in it, so this payload has one address, and `26.0` is where beat 1 of a bar is written
        // (the shim's `cellPlace('s1', 0, 1)`), not a new number the reader has to trust.
        '{"v":1,"docId":"doc-1","seq":1,"type":"chord.insert",'
            '"anchor":{"sectionId":"s1","bar":0},'
            '"payload":{"chord":{"place":{"anchor":{"sectionId":"s1","bar":0},'
            '"offsetX":26.0,"offsetY":0.0},'
            '"chord":{"root":{"semitones":2,"preference":"automatic"},'
            '"quality":"m7","bass":null,"alternate":null},'
            '"size":"normal"}}}',
        ChordInsertEvent(
          docId: 'doc-1',
          seq: 1,
          chord: ChordMark(place: cellPlace('s1', 0, 1), chord: _dMinorSeventh),
        ),
      ),
      'note.insert': (
        // UPDATED WITH THE SAME CHANGE, for the same reason: the note's address is its place.
        // Before this, the literal read `"note":{...,"beat":2,"step":0,"tiedToNext":false}` and the
        // payload also carried `"sectionId":"s1","bar":0`.
        '{"v":1,"docId":"doc-1","seq":4,"type":"note.insert",'
            '"anchor":{"sectionId":"s1","bar":0},'
            '"payload":{"note":{"pitch":{"note":{"letter":"e","alter":-1},'
            '"octave":5},'
            '"value":{"base":"half","dots":0,"tuplet":null},'
            '"place":{"anchor":{"sectionId":"s1","bar":0},'
            '"offsetX":44.0,"offsetY":0.0},"tiedToNext":false}}}',
        NoteInsertEvent(docId: 'doc-1', seq: 4, note: _eFlatHalf),
      ),
      'measure.insert': (
        // THIS LITERAL WAS UPDATED BY THE CHANGE THAT ADDED `Bar.size`, AND HERE IS WHAT IT SAID
        // BEFORE, so a reader can see what moved rather than trusting that nothing did. The bar
        // object used to begin:
        //   '"bar":{"timeSignature":{"numerator":3,"denominator":4},'
        //   '"chords":[{"chord":{...
        // and it now carries the size between the two, because a `measure.*` event carries a WHOLE
        // bar for its inverse's sake and a bar restored without the width the musician set would be
        // a silently different bar. `1.0` is the natural size: the bar in this case was never
        // resized, and a factor of 1 is the one every bar had before the property existed.
        // THE ANCHOR AND THE BAR'S CHORD ADDRESS CHANGED IN THE SAME BREAK AS `chord.insert`, and
        // what this literal said before is: `"anchor":{"sectionId":"s1","bar":1}`
        // and, inside the bar, `"beat":0,"step":0` for its one chord. The anchor is now
        // `{"sectionId":"s1","bar":1}` — a bar-level event has no cell to name — and the chord carries
        // its own place, whose `8.0` is the first column of a bar.
        '{"v":1,"docId":"doc-1","seq":7,"type":"measure.insert",'
            '"anchor":{"sectionId":"s1","bar":1},'
            '"payload":{"sectionId":"s1","index":1,'
            '"bar":{"timeSignature":{"numerator":3,"denominator":4},'
            '"size":1.0,'
            '"chords":[{"place":{"anchor":{"sectionId":"s1","bar":0},'
            '"offsetX":8.0,"offsetY":0.0},'
            '"chord":{"root":{"semitones":0,"preference":"automatic"},'
            '"quality":"","bass":null,"alternate":null},"size":"normal"}],'
            '"melody":[],"percussion":[],'
            '"openingBarline":"single","closingBarline":"single",'
            '"volta":null,"repeatPrevious":"none","slashRepeat":false,'
            '"noChord":false,"marks":[],"staffText":[]}}}',
        MeasureInsertEvent(
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
        '{"v":1,"docId":"doc-1","seq":15,"anchor":{"sectionId":"s1","bar":1'
            '},'
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
        '{"v":1,"docId":"doc-1","seq":16,"anchor":{"sectionId":"s1","bar":1'
            '},'
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
        '{"v":1,"docId":"doc-1","seq":29,"anchor":{"sectionId":"s1","bar":0'
            '},'
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
      'meter.set': (
        '{"v":1,"docId":"doc-1","seq":30,"anchor":{"sectionId":"s1","bar":0},'
            '"type":"meter.set","payload":{"sectionId":"s1","bar":0,'
            '"from":{"numerator":4,"denominator":4},'
            '"to":{"numerator":3,"denominator":4}}}',
        const MeterSetEvent(
          docId: 'doc-1',
          seq: 30,
          sectionId: 's1',
          barIndex: 0,
          from: TimeSignature.fourFour,
          to: TimeSignature.threeFour,
        ),
      ),
      'ink.stroke.add': (
        '{"v":1,"docId":"doc-1","seq":18,"anchor":{"sectionId":"doc-a",'
            '"bar":7},'
            '"type":"ink.stroke.add","payload":{"index":1,'
            '"stroke":{"id":"ink-9","tool":"highlighter",'
            '"color":"#ffcc00aa","size":8.0,'
            '"anchor":{"sectionId":"doc-a","bar":7},'
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
            anchor: EventAnchor(sectionId: 'doc-a', bar: 7),
            points: <InkPoint>[
              InkPoint(x: 1.0, y: 2.0, w: 0.5, t: 0.0),
              InkPoint(x: 3.0, y: 4.5, w: 0.25, t: 16.0),
            ],
          ),
        ),
      ),
      'annotation.insert': (
        '{"v":1,"docId":"doc-1","seq":20,"anchor":{"sectionId":"s2",'
            '"bar":1},'
            '"type":"annotation.insert","payload":{"index":0,'
            '"annotation":{"id":"ann-3","kind":"cue",'
            '"place":{"anchor":{"sectionId":"s2","bar":1},'
            '"offsetX":0.0,"offsetY":0.0},'
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
            '"bar":1},'
            '"type":"annotation.move","payload":{"id":"ann-2",'
            '"from":{"anchor":{"sectionId":"s1","bar":0},'
            '"offsetX":0.0,"offsetY":4.0},'
            '"to":{"anchor":{"sectionId":"s2","bar":1},'
            '"offsetX":-1.0,"offsetY":1.0}}}',
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
            '"bar":1},'
            '"type":"textcue.move","payload":{"id":"cue-2",'
            '"from":{"anchor":{"sectionId":"s1","bar":0},'
            '"offsetX":-3.5,"offsetY":2.25},'
            '"to":{"anchor":{"sectionId":"s2","bar":1},'
            '"offsetX":0.5,"offsetY":0.5}}}',
        const TextCueMoveEvent(
          docId: 'doc-1',
          seq: 27,
          id: 'cue-2',
          from: AnchoredPlace(anchor: _atA0Bar, offsetX: -3.5, offsetY: 2.25),
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
        // ignore: avoid_print
        print(
          'ENCODED ${entry.key} => ${jsonEncode(EventCodec.encode(expected))}',
        );
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
    test('a chord written where another already stands does not push it '
        'aside, and the inverse still restores the bar', () {
      // REWRITTEN, because the old test pinned the rule this change removes. Its name was
      // "inserting at a step pushes the later steps up and the inverse pushes them back", and its
      // assertion was that writing a chord at step 0 of an occupied cell produced
      //   ChordMark(place: 0, chord: _dMinorSeventh),
      //   ChordMark(place: (0, 1), chord: _cMajor),
      //   ChordMark(place: (0, 2), chord: _gSeventh)
      // — the bar's chords RENUMBERED so that the cell stayed a dense sequence of steps. That rule
      // was the grid: a step existed only so that two marks could not claim one address. There are no
      // steps now, so writing a chord where another stands leaves both where they were written, and
      // what has to be true instead is that the bar keeps both and that undo still restores the
      // document — which the last line checks, and which is stronger than the old line because it
      // compares the whole state rather than three addresses.
      final DocumentState before = DocumentState(
        song: Song(
          id: 'doc-step',
          title: 'packed',
          sections: <Section>[
            Section(
              id: 's1',
              label: SectionLabel.letter('A'),
              bars: <Bar>[
                Bar(
                  chords: <ChordMark>[
                    ChordMark(place: cellPlace('s1', 0, 0), chord: _cMajor),
                    ChordMark(
                      place: cellPlace('s1', 0, 0, 1),
                      chord: _gSeventh,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final ChordInsertEvent event = ChordInsertEvent(
        docId: 'doc-step',
        seq: 1,
        chord: ChordMark(place: cellPlace('s1', 0, 0), chord: _dMinorSeventh),
      );
      final DocumentState after = DocumentReducer.apply(before, event);
      final List<ChordMark> chords = after.song.barAt('s1', 0)!.chords;
      // THREE MARKS, NOT THREE ADDRESSES, and the two at the same x are not ordered against each
      // other: nothing tells them apart, so the assertion says the bar holds all three rather than
      // insisting on an order the model does not have.
      expect(chords.length, 3);
      expect(
        chords,
        contains(
          ChordMark(place: cellPlace('s1', 0, 0), chord: _dMinorSeventh),
        ),
      );
      expect(
        chords,
        contains(ChordMark(place: cellPlace('s1', 0, 0), chord: _cMajor)),
      );
      expect(
        chords,
        contains(ChordMark(place: cellPlace('s1', 0, 0, 1), chord: _gSeventh)),
      );
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

    test('a meter.set missing a side is reported rather than defaulted', () {
      // Both sides carry the whole meter, because the inverse is the two meters swapped. A payload
      // naming only the side that changed would leave the inverse unable to say what the bar was
      // in, and a default would make a truncated event look like an edit that put the bar into 4/4.
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":30,"type":"meter.set",'
        '"payload":{"sectionId":"s1","bar":0,'
        '"to":{"numerator":3,"denominator":4}}}',
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

    test('a meter.set naming a meter of no beats is reported, not stored', () {
      // `0/0` is not a meter. Storing it would put the document into a state no surface can repair,
      // because the form that could set a meter would have to read the zero it would have to
      // replace, and `parseMeterFigures` refuses to produce one.
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":30,"type":"meter.set",'
        '"payload":{"sectionId":"s1","bar":0,'
        '"from":{"numerator":4,"denominator":4},'
        '"to":{"numerator":0,"denominator":0}}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            allOf(contains('to'), contains('0/0')),
          ),
        ),
      );
    });

    test('a field of the wrong type is reported, not coerced', () {
      // REWRITTEN. The payload used to carry its own `"bar":"zero"` and the assertion named that
      // field: `contains('bar')`. A `chord.insert` payload has no bar of its own any more — the bar
      // is inside the mark's place — so the malformed field this checks is the place, and the
      // message has to name it. The property being protected is unchanged: a value of the wrong type
      // is REPORTED with the field it is wrong in, never coerced into a number or a default.
      final Map<String, Object?> json = _json(
        '{"v":1,"docId":"doc-1","seq":1,"type":"chord.insert",'
        '"payload":{"chord":{"place":"nowhere","chord":{},"size":"normal"}}}',
      );
      expect(
        () => EventCodec.decode(json),
        throwsA(
          isA<EventFormatException>().having(
            (EventFormatException e) => e.message,
            'message',
            contains('place'),
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
      final ChordDeleteEvent event = ChordDeleteEvent(
        docId: 'doc-1',
        seq: 3,
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
      // The bad address is in the MARK's place now, because that is where a chord's one address
      // lives: an event no longer carries a section of its own to be wrong about.
      final ChordInsertEvent event = ChordInsertEvent(
        docId: 'doc-1',
        seq: 1,
        chord: ChordMark(place: cellPlace('nope', 0, 0), chord: _cMajor),
      );
      expect(
        () => DocumentReducer.apply(_document(), event),
        throwsA(isA<DocumentReducerException>()),
      );
    });

    test('a bar index past the end of a section is a failure', () {
      final MeasureDeleteEvent event = MeasureDeleteEvent(
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
