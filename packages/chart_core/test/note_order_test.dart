// PURPOSE: Pin the ONE ordering question the melodic staff has: the notes of a bar are a sequence IN
//          TIME, that sequence IS their x, and the list a surface reads back is in reading order —
//          left to right on the page. That is the fact a run played left to right depends on, and it
//          is the fact this project once had backwards: `insertNote` used to default to `step: 0`,
//          which put every new note in FRONT of the ones already written, so a run typed C-D-E-F was
//          stored F-E-D-C and engraved as a different melody.
//
//          WHY THIS IS STILL A STATEMENT ABOUT MUSIC AND NOT ABOUT THE WRITER. The engraver draws a
//          note at `bar.left + place.offsetX`, so x order IS left-to-right order on the page, and a
//          bar whose notes are read back in any other order is a bar whose melody reads backwards.
//          The grid's `step` is gone — the model has no sub-beat index at all now — but the ordering
//          requirement it used to carry did not go with it: it moved into the coordinate, and into
//          `EditSession.notesInBar`, which sorts by x so that "the third note" is a thing an edit can
//          name.
//
//          IT ALSO PINS THE OTHER DIRECTION. A test that asserts only "the notes come back in the
//          order they were written" cannot tell reading order from insertion order, because the
//          fixture writes them in reading order; so the second case writes a note to the LEFT of one
//          already there and checks that the note already written did not move. An explicit place is
//          honoured and nothing is pushed aside — there is nothing left to renumber.
// INPUTS: None. The chart is built here and every note is written through `EditSession`, which is
//         the operation log's only writer.
// OUTPUTS: Pass/fail per claim, plus `note.order.*` lines on stdout naming the places as the model
//          holds them, so a failure shows the run rather than only a boolean.
// KEYWORDS: test, melody, note-order, reading-order, coordinate, left-to-right, edit-session,
//           no-step, place-not-cell
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

/// The run the chart's first bar holds, as the model holds it: `x:pitch` per note, in reading order.
String _run(EditSession session) => <String>[
  for (final NoteMark note in session.notesInBar(sectionId: 'A', barIndex: 0))
    '${note.offsetX.toStringAsFixed(1)}:${note.pitch}',
].join(' ');

void main() {
  test('a run written left to right is stored left to right', () {
    // THE RUN AS A MUSICIAN WRITES IT: four notes, one after another, each a little further along
    // the bar than the last — the places a finger or a pen produces on the staff, and not a
    // fixture's opinion about beats.
    final EditSession session = EditSession(
      document: DocumentState(song: _chart()),
    );
    const List<NoteLetter> typed = <NoteLetter>[
      NoteLetter.c,
      NoteLetter.d,
      NoteLetter.e,
      NoteLetter.f,
    ];
    for (int slot = 0; slot < typed.length; slot++) {
      expect(
        fixtureInsertNote(
          session,
          sectionId: 'A',
          barIndex: 0,
          slot: slot,
          pitch: _pitch(typed[slot]),
          value: _sixteenth,
        ),
        isTrue,
        reason: 'the writer must accept a note anywhere in the bar that is not left of it',
      );
    }
    final String observed = _run(session);
    stdout.writeln('note.order.run places=$observed');
    // THE OLD ASSERTION, QUOTED: expect(observed, '0:C4 1:D4 2:E4 3:F4', reason: 'C then D then E
    // then F, typed into one beat, is C D E F and not F E D C: the engraver draws step order left to
    // right, so a reversed cell is engraved as the wrong melody'); — where the printed field was the
    // note's STEP in its beat. There is no step: the field is the note's x, and the claim the old
    // number was making — the run reads left to right, in the order it was written — is made by the x
    // values themselves. The four fixture slots are 8, 26, 44 and 62.
    expect(
      observed,
      '8.0:C4 26.0:D4 44.0:E4 62.0:F4',
      reason:
          'C then D then E then F, written left to right along the bar, is engraved left to right: '
          'a bar whose notes came back in any other order would read as a different melody',
    );
    // AND EVERY NOTE HAS ITS OWN PLACE, which is what makes "the third note" a thing an edit can
    // name. The old assertion here was `<int>[0, 1, 2, 3]` — a DENSE sequence of steps from zero.
    // There is no step: the four notes are four x values, one fixture slot apart, and the list is in
    // reading order because `notesInBar` sorts by x.
    expect(
      session
          .notesInBar(sectionId: 'A', barIndex: 0)
          .map((NoteMark note) => note.offsetX),
      <double>[fixtureX(0), fixtureX(1), fixtureX(2), fixtureX(3)],
      reason: 'four notes written left to right stand left to right, each at its own place',
    );
  });

  test('an explicit place is honoured, and the neighbours are not moved', () {
    // REWRITTEN TWICE OVER, and both old texts are worth keeping because they name the two things
    // the grid used to do. It was first "naming step 0 still writes IN FRONT of the cell, and pushes
    // the rest up", asserting
    //   expect(observed, '0:G4 1:E4',
    //       reason: 'an explicit step 0 puts the note in front and moves the note that was there up
    //                one place — the reducer keeps the cell dense and the caller asked for the
    //                front');
    // and it was then, still in the grid's units,
    //   expect(observed, '0:E4 2:G4 3:A4',
    //       reason: 'the named step is where the note goes, and the next appended note is given the
    //                step after the highest one in the cell — nothing is renumbered').
    //
    // THE RENUMBERING IS GONE, AND SO IS THE APPEND. A note is written where it is written, so the
    // claim is now the whole of what a musician asked for in both versions: the place he names is the
    // place the note takes, and no note already in the bar moves because of it. Two notes at one
    // place are legal and are two marks; the session does not create one by itself, because a caller
    // with no place to name gets the palette's own.
    final EditSession session = EditSession(
      document: DocumentState(song: _chart()),
    );
    fixtureInsertNote(
      session,
      sectionId: 'A',
      barIndex: 0,
      slot: 1,
      pitch: _pitch(NoteLetter.e),
      value: _sixteenth,
    );
    // A place LEFT of the note already written. Under the grid this would have been "step 0", the
    // push-it-in-front case; now it is simply an x, and what has to be true is that it is honoured.
    fixtureInsertNote(
      session,
      sectionId: 'A',
      barIndex: 0,
      slot: 0,
      pitch: _pitch(NoteLetter.g),
      value: _sixteenth,
    );
    fixtureInsertNote(
      session,
      sectionId: 'A',
      barIndex: 0,
      slot: 2,
      pitch: _pitch(NoteLetter.a),
      value: _sixteenth,
    );
    final String observed = _run(session);
    stdout.writeln('note.order.explicit places=$observed');
    expect(
      observed,
      '8.0:G4 26.0:E4 44.0:A4',
      reason:
          'the place the caller named is the place the note takes, and the note that was already '
          'written at 26 is still at 26: nothing is renumbered and nothing is pushed aside',
    );
  });

  test('two notes of one PITCH are two marks, each at its own place', () {
    // THE QUESTION THIS ANSWERS: a repeated note — a run of sixteenths on one pitch — is the
    // commonest thing a jazz chart carries, so the bar has to be able to hold the same pitch twice
    // and read each one back separately, or an edit cannot tell them apart.
    //
    // THE OLD ASSERTION, QUOTED: expect(observed, '0:B4 1:B4', reason: 'the same pitch twice in
    // one beat is two notes'); and `existingNoteAt(beat: 0, step: 1)` for the second one. Two notes
    // at one BEAT differed by their step; two notes now differ by their x, which is the same fact
    // in the unit the model uses.
    final EditSession session = EditSession(
      document: DocumentState(song: _chart()),
    );
    for (int slot = 0; slot < 2; slot++) {
      fixtureInsertNote(
        session,
        sectionId: 'A',
        barIndex: 0,
        slot: slot,
        pitch: _pitch(NoteLetter.b),
        value: _sixteenth,
      );
    }
    final String observed = _run(session);
    stdout.writeln('note.order.same-pitch places=$observed');
    expect(
      observed,
      '8.0:B4 26.0:B4',
      reason: 'the same pitch twice in a bar is two marks, not one',
    );
    expect(
      fixtureNoteAt(
        session,
        sectionId: 'A',
        barIndex: 0,
        slot: 1,
      )?.pitch.toString(),
      'B4',
      reason: 'the second note is reachable at its own place, so an edit can tell them apart',
    );
  });
}
