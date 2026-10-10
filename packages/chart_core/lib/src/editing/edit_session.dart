// PURPOSE: Be the one place a chart document changes while a musician edits it. Every mutation
//          goes into the operation log and then through `DocumentReducer`; undo and redo are
//          appends of the inverses the catalogue already carries. Nothing here writes to a `Song`
//          or to a `DocumentState` field: if a change cannot be expressed as an event, it cannot
//          be made, which is the whole reason the log is the only writer.
// INPUTS: A starting [DocumentState] and, for a document read back from a file, the events that
//         were already in its tail. A document id taken from the state's song, or the caller's
//         override, because every event must name the document it belongs to.
// OUTPUTS: A session that reports the current [document], the [log] of everything applied since it
//          started, its [seq] counter, and whether [canUndo] or [canRedo]. Applying an event and
//          then undoing it returns a document EQUAL to the one before it — not approximately: the
//          comparison is `DocumentState ==`, which compares the song, the strokes, the annotations
//          and the text cues in order.
// KEYWORDS: edit-session, op-log, reducer, undo, redo, inverse, append-only, single-writer
//
// WHY UNDO IS AN APPEND AND NOT A POP.
//
// The catalogue gives every event an `inverse` that is again an event, and the document state was
// designed around that: an undo is the inverse appended to the same log, so the record of what
// happened keeps both the edit and its reversal. A session that popped instead would erase the
// history, and the `.chart` file it saves would then hold a document whose log does not explain it.
// This class therefore never removes an event from [log]; it grows on every undo and redo.
//
// WHY UNDO AND REDO STACKS HOLD EVENTS RATHER THAN SNAPSHOTS.
//
// An [UndoOp] is either an event a musician just applied or a generated redo event, and in both
// cases the session holds what is needed to reverse it. Nothing is snapshotted, so a session costs
// one small value per edit instead of a copy of the whole chart per edit, and there is exactly one
// rule: whatever is at the top of a stack is what the next operation does.
//
// WHY THE LOG IS NOT THE SAME THING AS A `.chart` FILE'S TAIL.
//
// The container stores a snapshot plus the operations AFTER that snapshot. This session's log
// starts at the state it was given, so it is exactly that tail — which is why `chartFileFor` can
// hand [log] to the container untouched. `storage_drift` already keeps the same shape
// (`DocumentSnapshot` plus the events after it), so a session restored from the store carries a
// log whose sequence numbers continue from the snapshot's.

part of '../oplog/oplog.dart';

/// One undoable edit: the event to apply on redo, and the event to apply on undo.
class UndoOp {
  /// Creates an undoable edit whose redo event is [forward] and whose undo event is [undoEvent].
  ///
  /// Both are retained rather than one being derived from the other, because an event's inverse
  /// describes the reversal and not the position: re-topping the 62nd event of a log as a redo and
  /// re-topping the original as an undo are two different operations, not one and its inverse.
  const UndoOp({required this.forward, required this.undoEvent});

  /// The event that applies this edit, as appended when it was first made.
  final ChartEvent forward;

  /// The event that reverses this edit.
  final ChartEvent undoEvent;
}

/// A chart document being edited, and the log that explains it.
///
/// The sequence counter is private because a session must issue the next number itself:
/// `(docId, seq)` addresses a log row, so a caller able to set it could produce two events
/// claiming one position.
class EditSession {
  /// Opens a session on the document named by [document], continuing a log that ended at [seq].
  ///
  /// [docId] defaults to the song's own id and falls back to [untitledDocumentId] when the song has
  /// none, because an event must name a document and a chart typed from scratch has no identity
  /// until the store assigns one. [restored] is the operations a `.chart` file carried, which this
  /// session continues from rather than reissues.
  EditSession({
    required DocumentState document,
    String? docId,
    this._seq = 0,
    List<ChartEvent> restored = const <ChartEvent>[],
  }) : _document = document,
       _docId = docId ?? _defaultDocId(document.song.id),
       _restored = List<ChartEvent>.of(restored);

  DocumentState _document;
  final String _docId;
  int _seq;
  final List<ChartEvent> _restored;
  final List<UndoOp> _undo = <UndoOp>[];
  final List<UndoOp> _redo = <UndoOp>[];
  final List<ChartEvent> _appliedEvents = <ChartEvent>[];

  /// The document id every event this session writes carries.
  String get docId => _docId;

  /// The document as it stands, with every applied event folded in.
  DocumentState get document => _document;

  /// The song as it stands, which is what a reader shows and an editor edits.
  Song get song => _document.song;

  /// The sequence number the next appended event will carry.
  ///
  /// One past the highest number this session has written, and never reused: a log is addressed by
  /// `(docId, seq)`, so two events sharing a number would be one row in the store.
  int get seq => _seq;

  /// The operations applied since this session opened, in order, including every undo and redo.
  ///
  /// This is the tail a `.chart` file stores beside its snapshot, which is why it is the events as
  /// they were written and not the stack of edits that is still undoable.
  List<ChartEvent> get log => <ChartEvent>[..._restored, ..._appliedEvents];

  /// Whether there is an edit to undo.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is an undone edit to redo.
  bool get canRedo => _redo.isNotEmpty;

  /// Number of edits that can still be undone.
  int get undoDepth => _undo.length;

  /// Number of undone edits that can still be redone.
  int get redoDepth => _redo.length;

  /// The document id used when a song carries none of its own.
  static const String untitledDocumentId = 'chartapp-untitled';

  /// Returns [id] when it is not empty, and the untitled document id otherwise.
  static String _defaultDocId(String id) =>
      id.isEmpty ? untitledDocumentId : id;

  // PURPOSE: Apply an event and remember how to take it back, which is the single entrance every
  //          edit funnels through: a chord the palette inserts, a measure a later feature inserts
  //          and a redo of either all arrive here.
  // INPUTS: event — the event to apply, carrying this session's document id and a sequence number.
  // OUTPUTS: Nothing. The document is the reduction, the event is appended to the log and the
  //          inverse is pushed as the next undo. Throws [DocumentReducerException] when the event
  //          cannot be applied, leaving this session untouched; throws [ArgumentError] when the
  //          event names another document, because applying it here would write a log row that the
  //          container refuses on save. A new edit after an undo drops the redo stack: the branch
  //          that was undone is no longer the branch being edited, and offering to redo onto it
  //          would apply an event built for a document that no longer exists.
  // KEYWORDS: apply, append, undo-stack, redo-invalidation, fail-loud, single-writer
  /// Applies [event] to this session's document and records its inverse.
  void apply(ChartEvent event) {
    if (event.docId != _docId) {
      throw ArgumentError.value(
        event.docId,
        'event.docId',
        'belongs to another document; this session edits "$_docId"',
      );
    }
    final DocumentState next = DocumentReducer.apply(_document, event);
    final int seq = _seq + 1;
    final ChartEvent numbered = event.withSeq(seq) as ChartEvent;
    _document = next;
    _seq = seq;
    _appliedEvents.add(numbered);
    _undo.add(UndoOp(forward: numbered, undoEvent: numbered.inverse()));
    _redo.clear();
  }

  // PURPOSE: Take back the most recent edit the musician still has, by applying the inverse the
  //          catalogue carries for it.
  // INPUTS: None.
  // OUTPUTS: True when an edit was undone, false when there was none. The undo appends the inverse
  //          to the log rather than deleting the original, and pushes the original as the next
  //          redo. The document afterwards is EQUAL to the document before the original edit: the
  //          inverse restores the field the event carried, and because the event carried the whole
  //          previous value — a `BeatChord` in full, not an address — nothing is reconstructed from
  //          what the document happens to hold now.
  // KEYWORDS: undo, inverse-event, append-only, exact-restore, no-op-when-empty
  /// Reverses the most recent edit, reporting whether there was one.
  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    final UndoOp op = _undo.removeLast();
    final DocumentState next = DocumentReducer.apply(_document, op.undoEvent);
    final int seq = _seq + 1;
    final ChartEvent numbered = op.undoEvent.withSeq(seq) as ChartEvent;
    _document = next;
    _seq = seq;
    _appliedEvents.add(numbered);
    _redo.add(UndoOp(forward: op.forward, undoEvent: numbered));
    return true;
  }

  // PURPOSE: Put back the edit the musician just took back, exactly as it was made.
  // INPUTS: None.
  // OUTPUTS: True when an edit was redone, false when there was none. Because [apply] renumbers an
  //          event before storing it, the redo of the original edit is the original edit's inverse
  //          re-applied through the same door — the event at the top of the redo stack holds both
  //          halves, so the log stays a record of applications rather than of intentions.
  // KEYWORDS: redo, re-apply, append-only, exact-forward, no-op-when-empty
  /// Re-applies the most recently undone edit, reporting whether there was one.
  bool redo() {
    if (_redo.isEmpty) {
      return false;
    }
    final UndoOp op = _redo.removeLast();
    final DocumentState next = DocumentReducer.apply(_document, op.forward);
    final int seq = _seq + 1;
    final ChartEvent numbered = op.forward.withSeq(seq) as ChartEvent;
    _document = next;
    _seq = seq;
    _appliedEvents.add(numbered);
    _undo.add(UndoOp(forward: numbered, undoEvent: op.undoEvent));
    return true;
  }

  // PURPOSE: Put a chosen chord into a cell, which is the edit the palette exists to make. It
  //          decides between the catalogue's two chord events from what the document holds, so the
  //          caller never has to know whether the cell was empty.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. beat — the cell index
  //         inside that bar. chord — the chosen chord. size — the engraved size to keep, normally
  //         the size of the placement being replaced and [ChordSize.normal] for an empty cell.
  // OUTPUTS: True when the edit was applied, false when the address names no bar at all. A cell
  //          that already holds a `step 0` placement is REPLACED, which keeps its engraved size and
  //          holds the addresses of every other chord in the bar still; an empty cell gets an
  //          INSERTION at `step 0`. An insertion into a cell that already holds chords cannot
  //          happen here, so no other chord's step is disturbed, and a chart written with two
  //          chords packed on one beat keeps them where the composer put them.
  //
  //          A [beat] beyond the bar's meter is NOT rejected here. The number of cells a bar has is
  //          the layout engine's rule and it lives in one place there — the meter's count widened
  //          by any chord written past it — and a second copy of that arithmetic in this class
  //          would be a copy that drifts. A beat the bar genuinely cannot hold is refused by
  //          [DocumentReducerException] from the reducer, which is the same answer every other
  //          caller gets.
  // KEYWORDS: chord-edit, update-or-insert, address-stability, size-preservation, guard
  /// Puts [chord] into the cell at ([sectionId], [barIndex], [beat]).
  bool applyChordToCell({
    required String sectionId,
    required int barIndex,
    required int beat,
    required Chord chord,
    ChordSize size = ChordSize.normal,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return false;
    }
    final BeatChord? existing = existingChordAt(
      sectionId: sectionId,
      barIndex: barIndex,
      beat: beat,
    );
    if (existing == null) {
      apply(
        ChordInsertEvent(
          docId: _docId,
          seq: _seq,
          sectionId: sectionId,
          barIndex: barIndex,
          chord: BeatChord(chord: chord, beat: beat, size: size),
        ),
      );
      return true;
    }
    apply(
      ChordUpdateEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        from: existing,
        to: BeatChord(
          chord: chord,
          beat: existing.beat,
          step: existing.step,
          size: existing.size,
        ),
      ),
    );
    return true;
  }

  // PURPOSE: Remove the chord a cell holds, which is the palette's other action and the one the
  //          catalogue's `chord.delete` exists for.
  // INPUTS: sectionId, barIndex and beat as in [applyChordToCell].
  // OUTPUTS: True when a chord was removed, false when the cell held none or the address names no
  //          bar. Removal closes the gap in its beat, which is the reducer's documented rule; in
  //          the ordinary one-chord-per-cell case there is no gap and the result is the same bar
  //          without that chord.
  // KEYWORDS: chord-delete, palette-action, guard, gap-closing
  /// Removes the chord at ([sectionId], [barIndex], [beat]), reporting whether one was there.
  bool removeChordAt({
    required String sectionId,
    required int barIndex,
    required int beat,
  }) {
    final BeatChord? existing = existingChordAt(
      sectionId: sectionId,
      barIndex: barIndex,
      beat: beat,
    );
    if (existing == null) {
      return false;
    }
    apply(
      ChordDeleteEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        removed: existing,
      ),
    );
    return true;
  }

  // PURPOSE: Answer what a cell currently holds, so the palette can open showing the chord the
  //          musician is about to change rather than an unrelated default.
  // INPUTS: sectionId, barIndex and beat as above.
  // OUTPUTS: The placement at that cell with the lowest step, or null when the cell is empty or the
  //          address names no bar. The lowest step is the one the cell's own column is labelled
  //          with: a packed pair `E7b5 A7` occupies one beat as two steps, and the palette edits
  //          the first of them. A cell carrying a second chord is therefore reachable only by
  //          removing the first, which is a gap this class reports rather than hides.
  // KEYWORDS: cell-query, lowest-step, packed-beat, null-when-empty
  /// Returns the chord the cell at ([sectionId], [barIndex], [beat]) holds, or null.
  BeatChord? existingChordAt({
    required String sectionId,
    required int barIndex,
    required int beat,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return null;
    }
    BeatChord? found;
    for (final BeatChord placed in bar.chords) {
      if (placed.beat != beat) {
        continue;
      }
      if (found == null || placed.step < found.step) {
        found = placed;
      }
    }
    return found;
  }
}
