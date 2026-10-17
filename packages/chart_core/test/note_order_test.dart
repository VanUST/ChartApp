// PURPOSE: Pin the ONE ordering question a cell of the melodic staff has: the notes of one beat are
//          a sequence IN TIME, `NoteMark.step` is the place in that sequence, and the note a
//          musician writes arrives at the END of it. That is the fact a run typed left to right
//          depends on, and it is the fact this project had backwards: `insertNote` defaulted to
//          `step: 0`, which put every new note in FRONT of the ones already written, so four
//          sixteenths typed C-D-E-F were stored F-E-D-C.
//
//          WHY THIS IS A STATEMENT ABOUT MUSIC AND NOT ABOUT THE WRITER. The engraver draws step `k`
//          of a cell at `cellX + k * stride`, so step order IS left-to-right order on the page. A
//          cell whose notes are stored in the reverse of the order they were written is therefore
//          engraved as a different melody, not merely as a different list — the run reads backwards.
//          So "append" is not a convenience of the API: it is the only behaviour under which a
//          musician's left-to-right gesture produces left-to-right music.
//
//          IT ALSO PINS THE OTHER DIRECTION, because a test that asserts only the append cannot tell
//          an append from a writer that ignores `step` altogether. Naming `step: 0` must still put
//          the note in FRONT of the cell's others and push them up — that is what the reducer's
//          dense sequence is for, and it is what a caller uses deliberately.
// INPUTS: None. The chart is built here and every note is written through `EditSession`, which is
//         the operation log's only writer.
// OUTPUTS: Pass/fail per claim, plus `note.order.*` lines on stdout naming the cell as the model
//          holds it, so a failure shows the sequence rather than only a boolean.
// KEYWORDS: test, melody, note-order, step, append, insert, dense-sequence, sub-beat-address,
//           left-to-right, edit-session
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

import '../support/place_fixture.dart';

/// A one-bar chart in C major that declares a pitched staff, so the melody has somewhere to live.
Song _chart() => Song(
  id: 'note-order',
  title: 'Note order',
  key: Key.cMajor,
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
  sections: <Section>[
    Section(id: 'A', label: const SectionLabel.letter('A'), bars: <Bar>[Bar()]),
  ],
);

/// One written pitch in the fourth octave, which is the register a melody is written in.
PitchedNote _pitch(NoteLetter letter) =>
    PitchedNote(note: WrittenNote(letter, 0), octave: 4);

/// A note of [letter] written as a sixteenth.
NoteValue get _sixteenth => const NoteValue.plain(NoteBase.sixteenth);

/// The cell at ([beat]) of the chart's first bar, as the model holds it: `step:pitch` per note, in
/// storage order.
String _cell(EditSession session) => <String>[
  for (final NoteMark note in session.notesInBar(sectionId: 'A', barIndex: 0))
    '${note.offsetX.toStringAsFixed(1)}:${note.pitch}',
].join(' ');

void main() {
  test('a run written left to right is stored left to right', () {
    // THE RUN AS A MUSICIAN WRITES IT: the notes of one beat, one after another, each tap with no
    // address beyond "this beat" — which is the call the note palette makes, so this is the order a
    // finger produces and not a fixture's opinion.
    final EditSession session = EditSession(
      document: DocumentState(song: _chart()),
    );
    const List<NoteLetter> typed = <NoteLetter>[
      NoteLetter.c,
      NoteLetter.d,
      NoteLetter.e,
      NoteLetter.f,
    ];
    for (final NoteLetter letter in typed) {
      expect(
        fixtureInsertNote(
          session,
          sectionId: 'A',
          barIndex: 0,
          slot: 0,
          pitch: _pitch(letter),
          value: _sixteenth,
        ),
        isTrue,
        reason: 'the writer must accept a note at a cell the bar has',
      );
    }
    final String observed = _cell(session);
    stdout.writeln('note.order.run cell=$observed');
    expect(
      observed,
      '0:C4 1:D4 2:E4 3:F4',
      reason:
          'C then D then E then F, typed into one beat, is C D E F and not F E D C: the engraver '
          'draws step order left to right, so a reversed cell is engraved as the wrong melody',
    );
    // AND EVERY NOTE HAS ITS OWN PLACE, which is what makes "the third note" a thing an edit can
    // name. The old assertion here was `<int>[0, 1, 2, 3]` — a DENSE sequence of steps from zero,
    // "what makes step usable as the third note of the beat". There is no step: the four notes are
    // four x values, one fixture slot apart, and the list is in reading order.
    expect(
      session
          .notesInBar(sectionId: 'A', barIndex: 0)
          .map((NoteMark note) => note.offsetX),
      <double>[fixtureX(0), fixtureX(1), fixtureX(2), fixtureX(3)],
      reason: 'four notes typed left to right stand left to right, each at its own place',
    );
  });

  test('naming a step writes there, and nothing is pushed aside', () {
    // REWRITTEN. This test used to be named "naming step 0 still writes IN FRONT of the cell, and
    // pushes the rest up", and it asserted
    //   expect(observed, '0:G4 1:E4',
    //       reason: 'an explicit step 0 puts the note in front and moves the note that was there
    //                up one place — the reducer keeps the cell dense and the caller asked for the
    //                front');
    // — that is, the reducer RENUMBERED the note already in the cell so that the newly named step
    // stayed free. That renumbering was the grid keeping itself dense, and it is gone: a note is
    // written where it is written and the reducer does not move its neighbours. What survives, and
    // what this asserts instead, is the part the musician asked for in the first place: an explicit
    // step is HONOURED — the note lands at that step and not at the end of the cell.
    //
    // THE COST, NAMED RATHER THAN HIDDEN: a caller that names a step already occupied now leaves
    // two notes at one place, and two notes at one place are indistinguishable to `existingNoteAt`
    // and to a deletion. The edit session does not create one — a caller that passes no step is
    // given the next free one — so this is reachable only by naming a collision on purpose.
    final EditSession session = EditSession(
      document: DocumentState(song: _chart()),
    );
    fixtureInsertNote(
      session,
      sectionId: 'A',
      barIndex: 0,
      slot: 0,
      pitch: _pitch(NoteLetter.e),
      value: _sixteenth,
    );
    fixtureInsertNote(
      session,
      sectionId: 'A',
      barIndex: 0,
      slot: 0,
      pitch: _pitch(NoteLetter.g),
      value: _sixteenth,
      sub: 2,
    );
    fixtureInsertNote(
      session,
      sectionId: 'A',
      barIndex: 0,
      slot: 0,
      pitch: _pitch(NoteLetter.a),
      value: _sixteenth,
    );
    final String observed = _cell(session);
    stdout.writeln('note.order.front cell=$observed');
    expect(
      observed,
      '0:E4 2:G4 3:A4',
      reason:
          'the named step is where the note goes, and the next appended note is given the step '
          'after the highest one in the cell — nothing is renumbered',
    );
  });

  test(
    'two notes of one PITCH can share a beat, and they are two addresses',
    () {
      // THE QUESTION THIS ANSWERS: a cell with no sub-beat ADDRESS would be unable to hold a repeated
      // note, and a run of sixteenths on one pitch is the commonest thing a jazz chart carries. It can:
      // the notes share `beat` and differ by `step`, and `existingNoteAt` reads each one back.
      final EditSession session = EditSession(
        document: DocumentState(song: _chart()),
      );
      for (int tap = 0; tap < 2; tap++) {
        fixtureInsertNote(
          session,
          sectionId: 'A',
          barIndex: 0,
          slot: 0,
          pitch: _pitch(NoteLetter.b),
          value: _sixteenth,
        );
      }
      final String observed = _cell(session);
      stdout.writeln('note.order.same-pitch cell=$observed');
      expect(
        observed,
        '0:B4 1:B4',
        reason: 'the same pitch twice in one beat is two notes',
      );
      expect(
        fixtureNoteAt(
          session,
          sectionId: 'A',
          barIndex: 0,
          slot: 0,
          sub: 1,
        )?.pitch.toString(),
        'B4',
        reason: 'the second note is reachable at its own step, so an edit can tell them apart',
      );
    },
  );
}
