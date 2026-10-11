// PURPOSE: Produce the evidence the melodic writer and the melody half of transposition have to
//          stand on, as printed numbers and printed note strings rather than as a single "ok". Three
//          claims are at stake and none of them can be read off the source: (1) every note operation
//          goes through the operation log, and undoing it returns a document EQUAL to the one before
//          it — including the stacked-notes case, where the reducer renumbers the notes of a beat
//          and only a whole-value inverse can put them back; (2) a no-op is refused rather than
//          appended; (3) transposing a chart moves the melody with the chords, so the two agree,
//          while the document that was transposed is not changed by having been shown in another key.
// INPUTS: None. Every fixture is built here; nothing is read from the network, a file or a device.
// OUTPUTS: One `[ok]`/FAIL line per claim with the values it compared, then `CHECKS=n FAILURES=n` and
//          an exit code: 0 when every claim held, 1 when one did not. A claim that fails prints both
//          the expected and the observed value, so a wrong root, a wrong octave or a lost tie is
//          readable rather than merely red.
// KEYWORDS: probe, melody, note-writer, edit-session, inverse, undo, transposition, round-trip,
//           evidence, not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

int _checks = 0;
int _failures = 0;

/// A one-bar song in C major with an A7 chord on beat 0, which is what the transposition half needs:
/// a chord and a melody in the same bar that have to agree after a move.
Song _songWithChords({List<BeatNote> melody = const <BeatNote>[]}) => Song(
  id: 'probe-song',
  title: 'Probe',
  key: const Key(tonic: WrittenNote(NoteLetter.c, 0), mode: Mode.major),
  sections: <Section>[
    Section(
      id: 's1',
      label: SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          chords: <BeatChord>[
            const BeatChord(
              chord: Chord(
                root: ChordRoot(9),
                quality: ChordQuality.dominantSeventh,
              ),
              beat: 0,
            ),
          ],
          melody: melody,
        ),
      ],
    ),
  ],
);

/// A note of [base] at ([beat], [step]) with the given written pitch.
BeatNote _note(
  NoteLetter letter,
  int alter,
  int octave,
  int beat, {
  int step = 0,
  NoteBase base = NoteBase.quarter,
  bool tied = false,
}) => BeatNote(
  pitch: PitchedNote(note: WrittenNote(letter, alter), octave: octave),
  value: NoteValue.plain(base),
  beat: beat,
  step: step,
  tiedToNext: tied,
);

/// One note as the probe prints it: its address, its written pitch, its written value and its tie.
String _render(BeatNote note) =>
    '${note.beat}.${note.step}:${note.pitch} ${note.value}'
    '${note.tiedToNext ? '~' : ''}';

/// Every note of [document]'s first bar, as a readable string, in the model's own order.
List<String> _notes(DocumentState document) => <String>[
  for (final BeatNote note in document.song.barsInReadingOrder.first.melody)
    _render(note),
];

/// Every note of [song]'s first bar, as a readable string, in the model's own order.
List<String> _songNotes(Song song) => <String>[
  for (final BeatNote note in song.barsInReadingOrder.first.melody)
    _render(note),
];

/// Every chord root pitch class of [song]'s first bar, so a note can be checked against it.
List<int> _chordClasses(Song song) => <int>[
  for (final BeatChord placed in song.barsInReadingOrder.first.chords)
    placed.chord.root.pitchClass,
];

/// Every melody pitch class of [song]'s first bar, in order.
List<int> _noteClasses(Song song) => <int>[
  for (final BeatNote note in song.barsInReadingOrder.first.melody)
    note.pitch.note.pitchClass,
];

void main() {
  _writerBasics();
  _stackedNotesAndInverse();
  _noOpRefusals();
  _roundTripThroughTheContainer();
  _transposition();
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

// ---------------------------------------------------------------------------------------------
// The writer
// ---------------------------------------------------------------------------------------------

void _writerBasics() {
  _section(
    'a note is written through the log, and undo restores the whole document',
  );
  final EditSession session = EditSession(
    document: DocumentState(song: _songWithChords()),
  );
  final DocumentState before = session.document;
  final bool inserted = session.insertNote(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
    value: const NoteValue.plain(NoteBase.quarter),
  );
  _same('insert returns true', true, inserted);
  _same('one event in the log', 1, session.log.length);
  _same('the event is note.insert', 'note.insert', session.log.single.type);
  _same('the note is at 0.0:E4 quarter', <String>[
    '0.0:E4 quarter',
  ], _notes(session.document));

  final bool undone = session.undo();
  _same('undo returns true', true, undone);
  _same(
    'the document after undo IS the document before',
    before,
    session.document,
  );
  _same('no notes are left', const <String>[], _notes(session.document));
  _same('the log grew rather than shrank', 2, session.log.length);
  _same(
    'the second log row is the inverse',
    'note.delete',
    session.log[1].type,
  );

  final bool redone = session.redo();
  _same('redo returns true', true, redone);
  _same('the note is back', <String>[
    '0.0:E4 quarter',
  ], _notes(session.document));
  stdout.writeln(
    'log types=${session.log.map((ChartEvent e) => e.type).toList()}',
  );
}

void _stackedNotesAndInverse() {
  _section(
    'two notes on one beat, their dense order, and the inverse of a deletion',
  );
  final EditSession session = EditSession(
    document: DocumentState(song: _songWithChords()),
  );
  session.insertNote(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
    value: const NoteValue.plain(NoteBase.quarter),
  );
  final DocumentState oneNote = session.document;
  session.insertNote(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.g, 0), octave: 4),
    value: const NoteValue.plain(NoteBase.half),
  );
  final DocumentState bothNotes = session.document;
  // THE SECOND INSERTION TAKES STEP 0 AND PUSHES THE FIRST NOTE UP. An insertion at a step pushes
  // the notes already AT OR AFTER that step one place up and then the cell is sorted by
  // `(beat, step)`, so the note just written is the one at the front. This is read off the run
  // rather than argued: it is the opposite of what a first reading of `_withNoteInserted` suggests,
  // and the probe prints the case so the two orders can never be confused again.
  _same(
    'the note just written is at step 0, and the one before it moved up',
    <String>['0.0:G4 half', '0.1:E4 quarter'],
    _notes(session.document),
  );
  _same(
    'the cell reports both, by step',
    <String>['0.0:G4 half', '0.1:E4 quarter'],
    <String>[
      for (final BeatNote note in session.existingNotesAt(
        sectionId: 's1',
        barIndex: 0,
        beat: 0,
      ))
        _render(note),
    ],
  );
  // `oneNote` is read here rather than left for the undo check below, so the intermediate state is
  // asserted to be an INTERMEDIATE state: one note before the second insertion, two after it.
  _same(
    'one note before the second insertion',
    1,
    oneNote.song.barsInReadingOrder.first.melody.length,
  );
  _same(
    'two notes after it',
    2,
    session.song.barsInReadingOrder.first.melody.length,
  );
  _same('the two notes are dense: steps 0 and 1', <String>[
    '0.0:G4 half',
    '0.1:E4 quarter',
  ], _notes(session.document));

  // Delete the note at step 0. The gap closes, so the surviving note moves DOWN to step 0; the  // inverse has to push it back up, which is exactly the case a delta-based inverse gets wrong.
  final bool deleted = session.deleteNoteAt(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    step: 0,
  );
  _same('delete returns true', true, deleted);
  _same('the surviving note closed the gap and is now at step 0', <String>[
    '0.0:E4 quarter',
  ], _notes(session.document));
  final bool undone = session.undo();
  _same('undo returns true', true, undone);
  _same(
    'the document after undo IS the document before the deletion, whole value',
    bothNotes,
    session.document,
  );
  _same(
    'the deleted note is back at step 0 and its neighbour back at step 1',
    <String>['0.0:G4 half', '0.1:E4 quarter'],
    _notes(session.document),
  );

  _section('an update keeps the address and carries the previous value whole');
  final BeatNote? atStepOne = session.existingNoteAt(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    step: 1,
  );
  _same(
    'the note at 0.1 is E4 quarter',
    '0.1:E4 quarter',
    _renderNote(atStepOne),
  );
  final bool updated = session.updateNote(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    step: 1,
    value: const NoteValue.plain(NoteBase.eighth),
  );
  _same('update returns true', true, updated);
  _same('only the value changed', <String>[
    '0.0:G4 half',
    '0.1:E4 eighth',
  ], _notes(session.document));
  _same('the event is note.update', 'note.update', session.log.last.type);
  session.undo();
  _same(
    'undo of the value change IS the document before it, whole value',
    bothNotes,
    session.document,
  );

  _section('a tie is one field of one note, and it is undoable');
  final bool tied = session.setNoteTie(
    sectionId: 's1',
    barIndex: 0,
    beat: 0,
    step: 1,
    tied: true,
  );
  _same('the tie was set', true, tied);
  _same('the tie is on the note, not beside it', <String>[
    '0.0:G4 half',
    '0.1:E4 quarter~',
  ], _notes(session.document));
  _same(
    'setting it again is refused',
    false,
    session.setNoteTie(
      sectionId: 's1',
      barIndex: 0,
      beat: 0,
      step: 1,
      tied: true,
    ),
  );
  session.undo();
  _same(
    'undo of the tie IS the document before it, whole value',
    bothNotes,
    session.document,
  );
}

void _noOpRefusals() {
  _section('a no-op is refused rather than appended');
  final EditSession session = EditSession(
    document: DocumentState(song: _songWithChords()),
  );
  session.insertNote(
    sectionId: 's1',
    barIndex: 0,
    beat: 1,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.f, 0), octave: 4),
    value: const NoteValue.plain(NoteBase.quarter),
  );
  final int eventsBefore = session.log.length;

  _same(
    'updating a note that is not there is refused',
    false,
    session.updateNote(
      sectionId: 's1',
      barIndex: 0,
      beat: 3,
      step: 0,
      value: const NoteValue.plain(NoteBase.half),
    ),
  );
  _same(
    'deleting a note that is not there is refused',
    false,
    session.deleteNoteAt(sectionId: 's1', barIndex: 0, beat: 3, step: 0),
  );
  _same(
    'updating a note to the value it already has is refused',
    false,
    session.updateNote(
      sectionId: 's1',
      barIndex: 0,
      beat: 1,
      step: 0,
      value: const NoteValue.plain(NoteBase.quarter),
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.f, 0), octave: 4),
    ),
  );
  _same(
    'tying a note that is not tied is not a no-op, but untie is',
    false,
    session.setNoteTie(
      sectionId: 's1',
      barIndex: 0,
      beat: 1,
      step: 0,
      tied: false,
    ),
  );
  _same(
    'a beat past the last cell is refused',
    false,
    session.insertNote(
      sectionId: 's1',
      barIndex: 0,
      beat: 4,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
      value: const NoteValue.plain(NoteBase.quarter),
    ),
  );
  _same(
    'a negative beat is refused',
    false,
    session.insertNote(
      sectionId: 's1',
      barIndex: 0,
      beat: -1,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
      value: const NoteValue.plain(NoteBase.quarter),
    ),
  );
  _same(
    'a beat read from a bar that is not there is refused',
    false,
    session.insertNote(
      sectionId: 'nope',
      barIndex: 0,
      beat: 0,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
      value: const NoteValue.plain(NoteBase.quarter),
    ),
  );
  _same(
    'a note longer than the bar is refused',
    false,
    session.insertNote(
      sectionId: 's1',
      barIndex: 0,
      beat: 0,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
      value: const NoteValue(base: NoteBase.whole, dots: 1),
    ),
  );
  _same('no refusal appended anything', eventsBefore, session.log.length);
}

void _roundTripThroughTheContainer() {
  _section('write notes, save a .chart, reopen it, and compare');
  final EditSession session = EditSession(
    document: DocumentState(song: _songWithChords()),
  );
  const List<NoteBase> bases = <NoteBase>[
    NoteBase.whole,
    NoteBase.half,
    NoteBase.quarter,
    NoteBase.eighth,
    NoteBase.sixteenth,
  ];
  // Five notes on five beats, each a different written value, plus a tie and a stacked pair.
  for (int beat = 0; beat < bases.length; beat++) {
    session.insertNote(
      sectionId: 's1',
      barIndex: 0,
      beat: beat,
      pitch: PitchedNote(
        note: WrittenNote(NoteLetter.values[beat], beat.isEven ? 1 : -1),
        octave: 4,
      ),
      value: NoteValue.plain(bases[beat]),
      tiedToNext: beat == 1,
    );
  }
  // A second bar, so the second note of one beat can be written there too and the bar's own meter
  // is the ordinary 4/4 rather than the widened one the first bar just grew.
  session.duplicateBar(sectionId: 's1', barIndex: 0);
  session.insertNote(
    sectionId: 's1',
    barIndex: 1,
    beat: 0,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.b, -1), octave: 3),
    value: const NoteValue.plain(NoteBase.quarter),
  );
  session.insertNote(
    sectionId: 's1',
    barIndex: 1,
    beat: 0,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 5),
    value: const NoteValue.plain(NoteBase.sixteenth),
  );

  final List<String> before = _allNotes(session.document);
  final ChartFile file = ChartFile(
    metadata: ChartMetadata(docId: session.docId),
    snapshot: session.baseDocument,
    events: session.log,
  );
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(
    ChartFileCodec.encode(file).bytes,
  );
  final List<String> after = _allNotes(decoded.file.reducedDocument);
  stdout.writeln('before=$before');
  stdout.writeln('after =$after');
  _same(
    'the notes that came back are the notes that were written',
    before,
    after,
  );
  _same(
    'the reopened document IS the saved document',
    session.document,
    decoded.file.reducedDocument,
  );
  _same('the reopened log is the saved log', session.log, decoded.file.events);
}

// ---------------------------------------------------------------------------------------------
// Transposition
// ---------------------------------------------------------------------------------------------

void _transposition() {
  _section(
    'the melody moves with the chords, and the written chart is not touched',
  );
  final Song written = _songWithChords(
    melody: <BeatNote>[
      _note(NoteLetter.e, 0, 4, 0),
      _note(NoteLetter.g, 0, 4, 0, step: 1),
      _note(NoteLetter.f, 0, 4, 1, base: NoteBase.half, tied: true),
      _note(NoteLetter.d, 0, 4, 2),
      _note(NoteLetter.b, 0, 3, 3),
    ],
  );
  const Key cMajor = Key(tonic: WrittenNote(NoteLetter.c, 0), mode: Mode.major);
  final Key dMajor = const TranspositionGrid()
      .targets(cMajor)
      .firstWhere((TranspositionTarget t) => t.semitones == 2)
      .key;
  _same('the target key is D major', 'D major', dMajor.toString());

  final Song shown = transposeSong(written, 2, toKey: dMajor);

  stdout.writeln(
    'chord written=${_chordClasses(written)} shown=${_chordClasses(shown)}',
  );
  stdout.writeln('notes written=${_songNotes(written)}');
  stdout.writeln('notes shown  =${_songNotes(shown)}');

  _same('the chord root moved by two semitones', <int>[
    11,
  ], _chordClasses(shown));
  _same('the notes moved by two semitones, as pitch classes', <int>[
    6,
    9,
    7,
    4,
    1,
  ], _noteClasses(shown));
  _same(
    'the notes are spelled in the key the chords are in, and every pitch class is inside it',
    true,
    _everyPitchClassInsideKey(shown, dMajor),
  );
  _same(
    'the note and the chord under it agree about the key',
    true,
    _chordClasses(shown).first == 11 && _noteClasses(shown).first == 6,
  );
  _same('addresses, written values and the tie survived the move', <String>[
    '0.0:F#4 quarter',
    '0.1:A4 quarter',
    '1.0:G4 half~',
    '2.0:E4 quarter',
    '3.0:C#4 quarter',
  ], _songNotes(shown));
  _same('the chart that was transposed is not changed by being shown', <String>[
    '0.0:E4 quarter',
    '0.1:G4 quarter',
    '1.0:F4 half~',
    '2.0:D4 quarter',
    '3.0:B3 quarter',
  ], _songNotes(written));
  _same('the written key is still C major', 'C major', written.key.toString());

  _section('the same interval in the other direction, and the round trip');
  final Song back = transposeSong(shown, -2, toKey: cMajor);
  stdout.writeln('notes back   =${_songNotes(back)}');
  _same(
    'down two semitones returns the chart it started from, note for note',
    _songNotes(written),
    _songNotes(back),
  );
  _same('and an equal song', written, back);

  _section('transposing by zero is the song itself');
  _same(
    'zero semitones returns an equal chart',
    written,
    transposeSong(written, 0, toKey: cMajor),
  );
}

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

/// [note] as the probe prints it, with a readable placeholder when it is absent.
String _renderNote(BeatNote? note) => note == null
    ? 'none'
    : '${note.beat}.${note.step}:${note.pitch} ${note.value}';

/// Every note of every bar of [document], in reading order.
List<String> _allNotes(DocumentState document) => <String>[
  for (final Section section in document.song.sections)
    for (int barIndex = 0; barIndex < section.bars.length; barIndex++)
      for (final BeatNote note in section.bars[barIndex].melody)
        '${section.id}[$barIndex] ${_render(note)}',
];

/// Whether every melody pitch class of [song] is one of [key]'s own scale degrees, which is the
/// musical statement "the melody is written in this key" rather than a spelling comparison.
bool _everyPitchClassInsideKey(Song song, Key key) {
  const SpellingTable table = SpellingTable();
  final Set<int> degrees = <int>{
    for (final WrittenNote degree in table.scaleOf(key)) degree.pitchClass,
  };
  for (final int pitchClass in _noteClasses(song)) {
    if (!degrees.contains(pitchClass)) {
      return false;
    }
  }
  return true;
}

/// Prints a section heading.
void _section(String title) => stdout.writeln('--- $title');

/// Counts one check and prints PASS or FAIL with the two values compared.
///
/// A [List] is compared ELEMENT BY ELEMENT rather than with `==`, because Dart's `List` does not
/// override equality: `[1] == [1]` is false, and a probe that compared lists directly would report
/// every list claim as a failure while printing two identical lines beside it. That defect was in
/// the first version of this file and it is why this helper exists rather than `_same(x, y)` being
/// spelled out at each call.
void _same(String what, Object? expected, Object? observed) {
  _checks++;
  final bool ok = _deepEquals(expected, observed);
  if (!ok) {
    _failures++;
  }
  stdout.writeln(
    '${ok ? '[ok]' : 'FAIL'} $what'
    '${ok ? '' : '\n     expected: $expected\n     observed: $observed'}',
  );
}

/// Whether two probe values are equal, treating lists element by element.
bool _deepEquals(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index++) {
      if (!_deepEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}
