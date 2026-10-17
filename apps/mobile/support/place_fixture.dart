// PURPOSE: Give a TEST OR A PROBE a terse way to write a mark at a chosen place in a bar, without
//          the library carrying a helper that only fixtures need. The model's place is an
//          [AnchoredPlace]; a fixture that wants "the third mark of this bar" would otherwise spell
//          out an anchor and two doubles every time, and a test whose subject is the ENGRAVING
//          should not be buried in the construction of its input.
// INPUTS: A slot index, plus an optional sub-slot for a second mark at the same slot, or the bar's
//         own address when the fixture knows it.
// OUTPUTS: An [AnchoredPlace] at a fixed pitch of 18 logical pixels per slot and 1.125 per sub-slot,
//          measured from 8 — the numbers the tree used while the grid existed, kept HERE so that a
//          fixture that used to place two marks two slots apart still places them two slots apart.
// KEYWORDS: test-fixture, anchors, places, no-grid, support, not-shipped
//
// WHY THIS IS A FIXTURE AND NOT THE MODEL'S GRID COMING BACK.
//
// The owner removed the grid as a class: a mark's position is a coordinate the musician chose, and
// nothing in `chart_core` divides a bar by its metre, computes a column, or recovers an index from an
// x. There is no inverse direction here and there is no exported name from the library: this file
// lives OUTSIDE `lib/`, it is imported only by `test/` and `tool/`, and it offers one direction
// only — slot to x. A fixture needs SOME numbers to place its marks at, and 18 is a perfectly good
// spacing for the purpose; what made the deleted shim a defect was that production code read
// positions back through it, not that a test picked a comfortable distance.
//
// A test that wants to assert the model's semantics should use real coordinates it chose itself
// (`placeAt(44)`), and a test that pinned a cell width or a beat index has to be rewritten rather
// than migrated: those assertions belong to the grid that was removed.
import 'package:chart_core/chart_core.dart';

/// The distance between two fixture slots, in bar-local logical pixels.
///
/// Eighteen is the width the tree used for a beat's column while the grid existed. It is a FIXTURE's
/// spacing: nothing in the library reads it, and no page is engraved from it.
const double fixtureSlotPitch = 18;

/// The distance between two marks written in ONE fixture slot, in bar-local logical pixels.
///
/// An exact binary fraction, so a fixture that puts two marks in one slot produces two distinct
/// doubles that compare exactly and survive a round trip through a file.
const double fixtureSubSlotPitch = 1.125;

/// The x of the first fixture slot, in bar-local logical pixels.
const double fixtureSlotOrigin = 8;

/// Returns the x of [slot] (and [sub]) in a fixture's own spacing.
double fixtureX(int slot, [int sub = 0]) =>
    fixtureSlotOrigin + slot * fixtureSlotPitch + sub * fixtureSubSlotPitch;

/// The placeholder bar a fixture uses when its marks belong to a bar that is not in a document yet.
///
/// An EMPTY section id, which no section can carry: a section id is either given by the importer or
/// minted by the edit session, and both are never empty, so a fixture's placeholder is recognisably
/// not an address. A bar that reaches the document through an event is re-anchored by the reducer,
/// which is why the placeholder never survives into a stored document.
const EventAnchor fixtureBar = EventAnchor(sectionId: '', bar: 0);

/// A place at fixture slot [slot] (and [sub]) of a bar whose address the fixture does not know.
AnchoredPlace placeAt(int slot, [int sub = 0]) =>
    AnchoredPlace(anchor: fixtureBar, offsetX: fixtureX(slot, sub), offsetY: 0);

/// A place at fixture slot [slot] (and [sub]) of bar [bar] of [sectionId].
AnchoredPlace placeIn(String sectionId, int bar, int slot, [int sub = 0]) =>
    AnchoredPlace(
      anchor: EventAnchor(sectionId: sectionId, bar: bar),
      offsetX: fixtureX(slot, sub),
      offsetY: 0,
    );

// ---------------------------------------------------------------------------
// SESSION CALLS AT A FIXTURE SLOT.
//
// A test that writes a chord "at slot 2" is building an input, and the number 2 is the fixture's own
// index — it is not a beat, a cell or a column, and the model has none of those. These forwarders
// exist so that a migrated call site keeps saying the same thing it said before without any of them
// reaching into the library: the slot is translated to an x HERE, with the fixture's own pitch, and
// the session is asked for a chord at that PLACE with a tolerance of 0, which means "the mark written
// exactly here" — the semantics a beat-addressed call had.
//
// A tolerance of zero is deliberate and not a tightening for its own sake: the session's own default
// reach is the distance a finger has, and a fixture that inserted at one place while a mark stood 18
// pixels away would replace that mark instead of adding one.
ChordEntry fixtureChord(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
  required Chord chord,
  ChordSize size = ChordSize.normal,
}) => session.applyChordAt(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  chord: chord,
  size: size,
  tolerance: 0,
);

ChordSymbolParse fixtureChordSymbol(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
  required String symbol,
  ChordSize size = ChordSize.normal,
}) => session.applyChordSymbolAt(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  symbol: symbol,
  size: size,
);

ChordMark? fixtureChordAt(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
}) => session.existingChordNear(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  tolerance: 0,
);

bool fixtureRemoveChord(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
}) => session.removeChordNear(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  tolerance: 0,
);

bool fixtureInsertNote(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
  required PitchedNote pitch,
  required NoteValue value,
  bool tiedToNext = false,
}) => session.insertNote(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  pitch: pitch,
  value: value,
  tiedToNext: tiedToNext,
);

bool fixtureUpdateNote(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
  PitchedNote? pitch,
  NoteValue? value,
  bool? tiedToNext,
}) => session.updateNote(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  tolerance: 0,
  pitch: pitch,
  value: value,
  tiedToNext: tiedToNext,
);

bool fixtureTieNote(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
  required bool tied,
}) => session.setNoteTie(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  tolerance: 0,
  tied: tied,
);

bool fixtureDeleteNote(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
}) => session.deleteNoteNear(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  tolerance: 0,
);

NoteMark? fixtureNoteAt(
  EditSession session, {
  required String sectionId,
  required int barIndex,
  required int slot,
  int sub = 0,
}) => session.existingNoteNear(
  sectionId: sectionId,
  barIndex: barIndex,
  offsetX: fixtureX(slot, sub),
  tolerance: 0,
);
