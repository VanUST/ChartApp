// PURPOSE: Turn a [MelodyNoteReading] into the STRUCTURE the model stores — a list of [NoteMark]
//          values written into the bar's melody through the operation log, so that a recognised
//          note is an ordinary note: undoable, addressable, transposable and drawn by the same
//          engraver as one the palette placed. This is the file that answers "what does a
//          recognised note BECOME", and the answer is deliberately the smallest one the model
//          already has rather than a new kind of object.
//
//          WHAT A RECOGNISED NOTE IS: a [NoteMark] carrying a beat (which column of the bar it
//          stands in), a `step` (its position INSIDE that beat, counting from the left, which A75
//          established as TIME rather than pitch), and a pitch (the letter and octave its staff
//          step names).
//
//          WHAT IT IS NOT, AND THIS IS THE HALF THAT MUST NOT BE GLOSSED. Its DURATION IS NOT READ.
//          Beams, flags and augmentation dots were not implemented and not scored by the
//          measurement this reader is ported from, so no recognised note has a measured rhythm.
//          Rather than invent one, every recognised note is given [recognisedNoteValue] — the value
//          the note palette writes when the musician has not chosen another — and that constant
//          carries the whole of the reasoning. A writer that guessed a quarter for an eighth would
//          put a rhythm on the chart that the musician did not write, which is the failure this
//          project's own rule about silent conversion exists to prevent.
//
//          ITS ACCIDENTAL IS NOT READ EITHER: `MelodyNoteHead.pitch` is always natural, because a
//          sharp or a flat is a separate glyph beside the head and this reader does not read it.
//
//          WHY IT ADDS AND NEVER REPLACES OR DELETES. A reading is written as the notes the bar's
//          melody does not already hold at those addresses; nothing that is already there is
//          removed or rewritten. Three properties follow, and each is why the direction was chosen:
//
//            1. RECOGNISING THE SAME INK TWICE CHANGES NOTHING. The addresses are occupied after
//               the first run, so a second run writes no events. A replace-everything reading would
//               have to delete and re-insert on every commit, which is two log rows per note and a
//               window in which the bar holds the wrong music.
//            2. A CORRECTION THE MUSICIAN MADE SURVIVES THE NEXT RECOGNITION. If he taps a
//               misread note and fixes its pitch (D37 makes that a one-or-two-action edit), the
//               address is occupied, so the ink cannot put the wrong pitch back. That is the
//               property that makes recognition usable on handwriting that is not perfect, and a
//               replace-everything reading would destroy it on the next stroke.
//            3. NOTHING HE PLACED BY HAND IS LOST. A palette note in the same bar is not deleted by
//               ink arriving beside it. The reading covers only the addresses it names.
//
//          WHAT IT COSTS, NAMED RATHER THAN HIDDEN. One operational event per added note, so a
//          four-note bar costs four undo steps and not one. The alternative — a single "replace the
//          melody of this bar" event — is the identity this file would need to give one gesture one
//          undo step (A71's rule), and it is a NEW EVENT TYPE in the file format: a new `type`
//          token, a reducer branch, an inverse, a codec branch and a version question for every
//          reader of `.chart`. That is a format decision and not an implementation detail, so it is
//          named here and left to the owner rather than taken silently.
//
//          AND WHY THE ADDRESS IS EXPLICIT RATHER THAN APPENDED. `EditSession.insertNote` appends
//          to the end of a cell when no `step` is given, because that is what a musician typing
//          left to right wants (A75). A reading already knows where each note stands, so it writes
//          with an explicit step and needs no discovery of the end. Both go through the same
//          `note.insert` event, so the log, the undo history and a re-read `.chart` are the same in
//          both cases.
// INPUTS: A [MelodyNoteReading] and an [EditSession] whose document holds the bar it names.
// OUTPUTS: A [MelodyNoteWrite] naming the notes actually written, the notes whose addresses were
//          already occupied, and the value every recognised note is given. Nothing is returned when
//          the bar does not exist: the caller gets an empty result rather than an exception, because
//          a reading is produced from a page and the document may have changed under it.
// KEYWORDS: note-writing, op-log, undoable, beat-note, sub-beat-step, duration-not-read,
//           idempotent, non-destructive, d37, d28, a75
import 'package:chart_core/src/ink/melody_note_reader.dart';
import 'package:chart_core/src/oplog/oplog.dart';
import 'package:chart_core/src/song/bar.dart';
import 'package:chart_core/src/song/note.dart';
import 'package:chart_core/src/song/note_value.dart';

/// The written value every recognised note is given, and the reason it is this one.
///
/// A RECOGNISED NOTE'S RHYTHM IS NOT KNOWN. The method this reader is ported from reads a notehead's
/// POSITION and nothing else: beams, flags and augmentation dots were not implemented and were not
/// scored, so there is no measured rhythm to report. What is stored has to be a value the model can
/// hold, so it is the one the editor already uses by convention for "a note of no stated length" —
/// the value the note palette starts from, `NoteBase.quarter` (see
/// `apps/mobile/lib/note_palette_sheet.dart`, whose `_lastBase` is initialised to it).
///
/// WHY A QUARTER AND NOT A WHOLE OR A SIXTEENTH. A quarter is the value the palette writes when the
/// musician has not chosen otherwise, so a recognised note looks exactly like a note he placed and
/// did not choose a value for; and it is the value at which the engraver draws no beam, no flag and
/// no dot, so the page does not ASSERT a grouping the reading never established. Storing a whole
/// note would make a recognised fourth-beat note a bar-long sound; storing an eighth would make the
/// engraver draw a flag and, in A74's terms, tell the reader a rhythm nobody measured.
///
/// IT IS STILL AN INVENTED VALUE, AND IT IS NAMED AS ONE. A caller that knows better — a future
/// reader that measures beams — passes its own [MelodyNoteReader]-independent value through
/// [writeRecognisedNotes]'s `value` argument rather than changing this constant, so that the
/// default stays the honest placeholder it is.
const NoteValue recognisedNoteValue = NoteValue.plain(NoteBase.quarter);

/// What writing a [MelodyNoteReading] into a session actually did.
class MelodyNoteWrite {
  /// Creates a write result with the notes it added, the ones it skipped and the value it used.
  const MelodyNoteWrite({
    required this.written,
    required this.alreadyPresent,
    required this.value,
  });

  /// A write that changed nothing, which is what recognising the same ink twice produces.
  const MelodyNoteWrite.none(this.value)
    : written = const <NoteMark>[],
      alreadyPresent = const <NoteMark>[];

  /// The notes this write added, in the bar's address order.
  final List<NoteMark> written;

  /// The notes the reading named that the bar already held at those addresses, so they were left
  /// exactly as they were.
  final List<NoteMark> alreadyPresent;

  /// The written value every added note carries; see [recognisedNoteValue].
  final NoteValue value;

  /// Whether this write added nothing, either because the bar was up to date or because the reading
  /// named no note at all.
  bool get isEmpty => written.isEmpty;

  @override
  String toString() =>
      'MelodyNoteWrite(${written.length} written, '
      '${alreadyPresent.length} already present, value $value)';
}

// PURPOSE: Put every note a reading found into the bar's melody, as ordinary `note.insert`
//          operations, skipping the addresses the bar already has — and report what it did rather
//          than only how many.
// INPUTS: session — the open document, whose operation log every added note is written through.
//         reading — the notes one bar's ink yielded, from [MelodyNoteReader.read] or
//         [readMelodyNotesOfBar]. value — the written duration to give each added note, defaulting
//         to [recognisedNoteValue]; a caller with a measured rhythm passes its own.
// OUTPUTS: The [MelodyNoteWrite] naming the added notes and the skipped ones. When the reading
//          names a bar the session's document does not hold — the document changed under a reading
//          taken from an older page — the result is empty and no event is written; that is a
//          refusal rather than a failure because a reading is advice, and advice about a bar that
//          no longer exists must not throw inside a write path.
//
//          THE EVENT IS `note.insert` AND NOTHING ELSE. Every added note is one row of the log, so
//          it is undoable by the ordinary undo, it replays identically from a saved `.chart`, and it
//          produces the same NoteMark as the palette's own insertion would. A note at an address the
//          bar already holds is SKIPPED rather than rewritten: see the file header for the three
//          properties that buys and the one undo step it costs.
//
//          THE STEP IS THE HEAD'S ORDINAL INSIDE ITS BEAT, so the notes of one cell land left to
//          right in the order the musician drew them (A75). An insertion before notes that are
//          already there pushes them up, which is the reducer's own documented rule: an ordinary
//          cell is filled left to right and no push happens, and a hand-edited cell keeps its notes
//          rather than losing them.
// KEYWORDS: recognised-note, write, insert, op-log, idempotent, non-destructive, explicit-step,
//           value-placeholder, refusal-not-throw
/// Writes every note [reading] found into its bar, as one `note.insert` operation each.
///
/// A note whose address the bar already holds is left exactly as it is, so recognising the same ink
/// twice writes nothing and a correction the musician made survives the next run. The written
/// duration is [value], which defaults to [recognisedNoteValue] because a recognised note's rhythm
/// is not known — see that constant for why a quarter and what it would take to read a real one.
MelodyNoteWrite writeRecognisedNotes({
  required EditSession session,
  required MelodyNoteReading reading,
  NoteValue value = recognisedNoteValue,
}) {
  final Bar? bar = session.song.barAt(reading.sectionId, reading.barIndex);
  if (bar == null) {
    return const MelodyNoteWrite.none(recognisedNoteValue);
  }
  final List<NoteMark> written = <NoteMark>[];
  final List<NoteMark> present = <NoteMark>[];
  for (final MelodyNoteHead head in reading.heads) {
    final NoteMark? existing = _noteAt(bar, head.beat, head.orderInBeat);
    if (existing != null) {
      present.add(existing);
      continue;
    }
    final NoteMark note = NoteMark(
      // The reader measures a head's column and its order within that column, which is the cell the
      // musician drew in; the place says where that is on the page.
      place: cellPlace(
        reading.sectionId,
        reading.barIndex,
        head.beat,
        head.orderInBeat,
      ),
      pitch: head.pitch,
      value: value,
    );
    session.apply(
      NoteInsertEvent(docId: session.docId, seq: session.seq, note: note),
    );
    written.add(note);
  }
  return MelodyNoteWrite(
    written: written,
    alreadyPresent: present,
    value: value,
  );
}

// PURPOSE: Find the note a bar already holds at one address, which is the only question the write
//          above asks of the model: "is this position spoken for".
// INPUTS: bar — the bar; beat — the cell; step — the ordinal inside the cell.
// OUTPUTS: The note at that address, or null when the address is free. A bar with no melody
//          answers null for every address, which is the ordinary first-recognition case.
// KEYWORDS: address-lookup, beat-step, occupied, dense-sequence
NoteMark? _noteAt(Bar bar, int beat, int step) {
  for (final NoteMark note in bar.melody) {
    if (note.pseudoBeat == beat && note.pseudoStep == step) {
      return note;
    }
  }
  return null;
}
