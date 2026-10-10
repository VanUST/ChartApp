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
  ///
  /// [document] IS THE STATE BEFORE [restored], AND THIS CONSTRUCTOR APPLIES THEM. That is the
  /// container's own contract — a file is a snapshot plus the operations AFTER it, and the document
  /// is what the two say together — and it is the only shape in which the log can be written again
  /// without being applied twice. A caller that has already folded the tail into its snapshot and
  /// hands the tail over as well is asking for every operation to happen twice, which is how a form
  /// of four sections and sixteen bars comes back as six and twenty-four.
  ///
  /// [seq] IS THE CALLER'S DUTY AND THIS CLASS DOES NOT SECOND-GUESS IT: it must be at least the
  /// highest sequence number [restored] carries, or the next appended event reuses a position the
  /// log already holds and `(docId, seq)` stops addressing one row. A caller restoring a tail takes
  /// it from the tail's last event, which is what a file's own order guarantees. It is documented
  /// rather than clamped because a session that quietly renumbered itself would hide a caller that
  /// is counting from the wrong place.
  EditSession({
    required DocumentState document,
    String? docId,
    this._seq = 0,
    List<ChartEvent> restored = const <ChartEvent>[],
  }) : _base = document,
       _docId = docId ?? _defaultDocId(document.song.id),
       _restored = List<ChartEvent>.of(restored),
       _document = _reduceTail(document, restored);

  DocumentState _document;

  /// The state this session was opened on: the document BEFORE [log].
  ///
  /// It is what a save writes as the container's snapshot, so that `snapshot + tail` is the chart
  /// the musician is looking at. The alternative — writing the CURRENT document as the snapshot and
  /// the tail beside it — stores every operation twice: the reader's contract is that the document
  /// is the snapshot PLUS the operations, so a snapshot that already contains them is applied again
  /// on the way back in. Inserts then double, deletes take a neighbouring bar, and a re-applied
  /// stroke throws because a stroke with that id is already present.
  final DocumentState _base;

  final String _docId;
  int _seq;
  final List<ChartEvent> _restored;
  final List<UndoOp> _undo = <UndoOp>[];
  final List<UndoOp> _redo = <UndoOp>[];
  final List<ChartEvent> _appliedEvents = <ChartEvent>[];

  // PURPOSE: Fold the operations a file carried into the state that file stored, so a session
  //          opened on a `.chart` document holds the chart the writer saw rather than its snapshot
  //          alone.
  // INPUTS: document — the snapshot, which is the state before the tail. restored — the operations
  //         after it, in log order.
  // OUTPUTS: The reduced document. An empty tail returns [document] itself, which is the ordinary
  //          case of a session that was not opened from a file. An event the reducer cannot apply
  //          throws [DocumentReducerException] here rather than being skipped, because a tail that
  //          does not fit its snapshot is a document nobody can reconstruct.
  // KEYWORDS: reduce-tail, snapshot-plus-log, restore, fail-loud
  static DocumentState _reduceTail(
    DocumentState document,
    List<ChartEvent> restored,
  ) {
    DocumentState state = document;
    for (final ChartEvent event in restored) {
      state = DocumentReducer.apply(state, event);
    }
    return state;
  }

  /// The document id every event this session writes carries.
  String get docId => _docId;

  /// The state this session started from: what a save writes as the container's snapshot.
  ///
  /// Not the same value as [document] once anything has been edited — the difference between the
  /// two is exactly [log] — which is why a file holds this one and the tail and reopens into
  /// [document].
  DocumentState get baseDocument => _base;

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

  // --- Bars and sections: the form of the tune ------------------------------------------------
  //
  // The catalogue already carries every one of these operations (`measure.insert`,
  // `measure.delete`, `measure.duplicate`, `section.insert`, `section.delete`, `section.update`,
  // `section.duplicate`, `section.reorder`). What is here is the decision of WHAT to put in each
  // event, which is the part a caller must not restate: a bar put into a 3/4 tune has to be 3/4,
  // and a duplicated section has to carry an identity no other section has.

  // PURPOSE: Insert one blank bar before the bar the musician is working on, which is how a form of
  //          a chosen length gets built: a bar is added where it is needed and then written into.
  // INPUTS: sectionId and barIndex — the bar the musician selected, in the model's own address.
  // OUTPUTS: True when the bar was inserted, false when [sectionId] names no section or [barIndex]
  //          is past the section's bars. The new bar takes [barIndex], so the selected bar and
  //          every bar after it move one place later; a caller that wants to stay on the bar it was
  //          on has to follow it. The blank bar carries the METER of the bar it was built beside
  //          and nothing else: a meter is per bar here, so a new 4/4 bar in a 3/4 tune would be a
  //          musical change nobody asked for, while repeat signs and alternative endings are signs
  //          of a passage and copying one into an arbitrary position invents a repeat.
  // KEYWORDS: bar-insert, measure-insert, meter-inheritance, form-building, undoable
  /// Inserts a blank bar before the bar at ([sectionId], [barIndex]).
  bool insertBarBefore({required String sectionId, required int barIndex}) {
    final Bar? reference = _document.song.barAt(sectionId, barIndex);
    if (reference == null) {
      return false;
    }
    apply(
      MeasureInsertEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        index: barIndex,
        bar: _blankBarLike(reference),
      ),
    );
    return true;
  }

  // PURPOSE: Insert one blank bar after the bar the musician is working on, which is the same
  //          operation as [insertBarBefore] with the new bar landing one place later.
  // INPUTS: sectionId and barIndex — the selected bar, as in [insertBarBefore].
  // OUTPUTS: True when the bar was inserted, false when the address names no bar. The new bar takes
  //          `barIndex + 1`, so the selected bar does not move. The meter is inherited for the same
  //          reason as above.
  // KEYWORDS: bar-insert, measure-insert, append-after, meter-inheritance, undoable
  /// Inserts a blank bar after the bar at ([sectionId], [barIndex]).
  bool insertBarAfter({required String sectionId, required int barIndex}) {
    final Bar? reference = _document.song.barAt(sectionId, barIndex);
    if (reference == null) {
      return false;
    }
    apply(
      MeasureInsertEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        index: barIndex + 1,
        bar: _blankBarLike(reference),
      ),
    );
    return true;
  }

  // PURPOSE: Copy the bar the musician is working on into the place after it, which is how a chart
  //          of a repeated bar — eight bars of one groove, two bars of a turnaround — is written
  //          once and repeated.
  // INPUTS: sectionId and barIndex — the bar to copy.
  // OUTPUTS: True when the copy was made, false when the address names no bar. The copy is a new
  //          immutable value carrying every field of its source, including chords, signs and meter,
  //          and it lands at `barIndex + 1`. A copied bar is equal to its source, which is the
  //          point: a musician who wanted a different bar will edit it after it is there.
  // KEYWORDS: bar-duplicate, measure-duplicate, whole-value-copy, deterministic-replay, undoable
  /// Copies the bar at ([sectionId], [barIndex]) into the position after it.
  bool duplicateBar({required String sectionId, required int barIndex}) {
    final Bar? source = _document.song.barAt(sectionId, barIndex);
    if (source == null) {
      return false;
    }
    apply(
      MeasureDuplicateEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        index: barIndex,
        duplicate: source.copyWith(),
      ),
    );
    return true;
  }

  // PURPOSE: Remove the bar the musician is working on, which is how a form that came out one bar
  //          too long is fixed.
  // INPUTS: sectionId and barIndex — the bar to remove.
  // OUTPUTS: True when the bar was removed, false when the address names no bar, and false when
  //          this is the section's LAST bar. That second refusal is deliberate and is the one rule
  //          this method adds to the catalogue's: the page draws a section through the bars it
  //          contains, so a section with no bars cannot be seen, cannot be tapped and therefore
  //          cannot be selected again — a state a musician could reach in one tap and not leave.
  //          Removing the last section is refused for the same reason by [deleteSection].
  // KEYWORDS: bar-delete, measure-delete, last-bar-refusal, addressability, undoable
  /// Removes the bar at ([sectionId], [barIndex]).
  bool deleteBar({required String sectionId, required int barIndex}) {
    final Section? section = _document.song.sectionById(sectionId);
    if (section == null ||
        barIndex < 0 ||
        barIndex >= section.bars.length ||
        section.bars.length <= 1) {
      return false;
    }
    apply(
      MeasureDeleteEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        index: barIndex,
        removed: section.bars[barIndex],
      ),
    );
    return true;
  }

  // PURPOSE: Insert a new section before the one the musician is working in, which is how an intro
  //          is put in front of a form that was written without one.
  // INPUTS: sectionId — a section of the song, whose own meter and position decide the new one's.
  // OUTPUTS: The new section's id, or null when [sectionId] names no section. The new section
  //          carries one blank bar in the meter of the reference section's last bar, and a fresh
  //          identity and label: a section with no bars would be invisible and unreachable (see
  //          [deleteBar]), so "new section" means "new section with its first bar in it".
  // KEYWORDS: section-insert, rehearsal-letter, fresh-identity, one-bar, meter-inheritance, undoable
  /// Inserts a new one-bar section before the section named [sectionId].
  String? insertSectionBefore(String sectionId) =>
      _insertSectionBeside(sectionId, after: false);

  // PURPOSE: Insert a new section after the one the musician is working in, which is how a B part
  //          is added after the A part.
  // INPUTS: sectionId — the section to insert after.
  // OUTPUTS: The new section's id, or null when [sectionId] names no section. Built exactly as in
  //          [insertSectionBefore].
  // KEYWORDS: section-insert, form-building, fresh-identity, one-bar, undoable
  /// Inserts a new one-bar section after the section named [sectionId].
  String? insertSectionAfter(String sectionId) =>
      _insertSectionBeside(sectionId, after: true);

  // PURPOSE: Copy a whole section, which is how a form that plays A twice is written once — the
  //          copy is a starting point the musician then edits.
  // INPUTS: sectionId — the section to copy.
  // OUTPUTS: The copy's id, or null when [sectionId] names no section. The copy lands directly
  //          after its source and carries a FRESH identity: two sections sharing an id would make
  //          every annotation anchor naming that id ambiguous, and an anchor is resolved by id. Its
  //          label is deliberately NOT changed — a chart may hold two sections called A, and
  //          relabelling silently would be the app deciding what the musician's form is called.
  // KEYWORDS: section-duplicate, fresh-identity, anchor-safety, label-preserved, undoable
  /// Copies the section named [sectionId] into the position after it, under a new identity.
  String? duplicateSection(String sectionId) {
    final int index = _sectionIndex(sectionId);
    if (index < 0) {
      return null;
    }
    final Section source = _document.song.sections[index];
    final Section duplicate = source.copyWith(id: _freshSectionId());
    apply(
      SectionDuplicateEvent(
        docId: _docId,
        seq: _seq,
        sourceId: sectionId,
        index: index,
        duplicate: duplicate,
      ),
    );
    return duplicate.id;
  }

  // PURPOSE: Remove a whole section, which is how a part that turned out not to belong is taken out
  //          of the form.
  // INPUTS: sectionId — the section to remove.
  // OUTPUTS: True when the section was removed, false when [sectionId] names no section and false
  //          when it is the song's ONLY section. The second refusal is the same rule [deleteBar]
  //          applies one level down: a song with no sections has no bars, the page shows nothing to
  //          tap, and there would be no way back to a chart from inside the app. Every bar the
  //          section held goes with it. An annotation anchored in the removed section is NOT removed
  //          with it: the catalogue has no cascade, so such a mark is left naming a section that no
  //          longer exists and is simply not drawn, which is the same state a mark in a section
  //          another device removed is in. Undo restores the section, and the mark with it, because
  //          the deletion event carries the whole section.
  // KEYWORDS: section-delete, last-section-refusal, dangling-anchor, undoable, form-building
  /// Removes the section named [sectionId], unless it is the song's only section.
  bool deleteSection(String sectionId) {
    final int index = _sectionIndex(sectionId);
    if (index < 0 || _document.song.sections.length <= 1) {
      return false;
    }
    apply(
      SectionDeleteEvent(
        docId: _docId,
        seq: _seq,
        index: index,
        removed: _document.song.sections[index],
      ),
    );
    return true;
  }

  // PURPOSE: Give a section a different label, which is how a section that came out of an import
  //          as the wrong rehearsal letter — or as no letter at all — is fixed.
  // INPUTS: sectionId — the section to relabel. label — the label it should carry.
  // OUTPUTS: True when the label changed, false when [sectionId] names no section and false when
  //          the label is already that one, because an event that changes nothing is still an entry
  //          in the log and an offer to undo it. The event carries both labels, so undo restores
  //          the exact label that was written before — not a re-derived one.
  // KEYWORDS: section-rename, section-update, reversible, no-op-refusal, undoable
  /// Relabels the section named [sectionId] with [label].
  bool renameSection(String sectionId, SectionLabel label) {
    final Section? section = _document.song.sectionById(sectionId);
    if (section == null || section.label == label) {
      return false;
    }
    apply(
      SectionUpdateEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        from: section.label,
        to: label,
      ),
    );
    return true;
  }

  // PURPOSE: Move a section earlier or later in the written order, which is how a form that came
  //          out in the wrong order is repaired without retyping it.
  // INPUTS: sectionId — the section to move. places — how many positions to move it by; negative
  //         moves it earlier, positive later.
  // OUTPUTS: True when the section moved, false when [sectionId] names no section, when [places] is
  //          zero (an event that changes nothing) and when the target position would fall outside
  //          the song. The section's identity travels with it, so every annotation anchored in it
  //          stays anchored: an address is (section id, bar index), and a reorder changes neither.
  // KEYWORDS: section-reorder, move, stable-identity, anchor-survival, bounds-check, undoable
  /// Moves the section named [sectionId] by [places] positions in the written order.
  bool moveSection(String sectionId, int places) {
    final int index = _sectionIndex(sectionId);
    if (index < 0 || places == 0) {
      return false;
    }
    final int target = index + places;
    if (target < 0 || target >= _document.song.sections.length) {
      return false;
    }
    apply(
      SectionReorderEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        fromIndex: index,
        toIndex: target,
      ),
    );
    return true;
  }

  // --- Repeats and alternative endings ---------------------------------------------------------
  //
  // The catalogue has carried `repeat.set` and `volta.set` since it was written, and until these
  // methods existed nothing wrote either: the scene bar counted the repeats a chart already had and
  // a musician had no way to give it one. Both events carry the WHOLE state of the sign on both
  // sides — `repeat.set` carries all four fields of `RepeatSigns` and `volta.set` a nullable
  // bracket — and that is what decides the shape of everything below.
  //
  // WHY THE BAR IS READ HERE AND NOT BY THE CALLER. A caller that built the `to` half itself would
  // be restating the model's own shape, and a caller that read the bar to build the `from` half
  // could read it after some other edit had already moved it. Deciding both halves next to the one
  // writer is the same rule the form operations follow.
  //
  // WHAT CLEARING MEANS, AND WHY IT IS NOT ONE RULE. A repeat barline is cleared by setting it
  // back to `Barline.single`, because a barline has a neutral value and the model has no way to
  // write "no barline at all". A volta is cleared by REMOVING it — `to: null` — because
  // `Bar.volta == null` and `Volta(0)` are two different things in this model: null is "no
  // bracket", and 0 is an UNNUMBERED bracket the musician asked for and the page draws. Setting a
  // volta to zero would not clear it, it would draw a bracket.
  //
  // WHAT IS ALLOWED, AND WHY THE DERIVATION DECIDES IT. A repeat start with no repeat end, and a
  // bracket on a bar inside no repeat, are both LEGAL here. `derivePlayOrder` already answers what
  // each one means — the unmatched start plays once and is reported as
  // `repeatStartWithoutEnd`; the stray bracket selects no pass and is reported as
  // `voltaOutsideRepeat` — and a UI that refused them would be a second answer to a question the
  // derivation has already answered, written at the edit instead of at the reading. The two things
  // REFUSED here are the ones nothing downstream can read: a negative bracket figure, which no pass
  // can ever select, and a change whose two halves are equal, which would be a log row and an offer
  // to undo an edit that did not happen.

  // PURPOSE: Mark or unmark the selected bar as the start of a repeated passage, which is one half
  //          of the gesture that makes a chart repeat — the other half is [setRepeatEnd] on the bar
  //          the passage comes back to.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. starts — true to put a
  //         repeat-start barline on it, false to take one off.
  // OUTPUTS: True when the sign changed, false when the address names no bar or the bar already
  //          carries exactly that opening barline. Turning the sign OFF is a real edit with a real
  //          inverse, so it appends rather than doing nothing. A start with no matching end is
  //          allowed and not rejected: the derivation reads it as a passage played once and reports
  //          [PlayOrderIssueKind.repeatStartWithoutEnd].
  // KEYWORDS: repeat-start, barline, toggle, repeat-set, undoable, unmatched-start-allowed
  /// Sets or clears the repeat-start barline of the bar at ([sectionId], [barIndex]).
  bool setRepeatStart({
    required String sectionId,
    required int barIndex,
    required bool starts,
  }) => _setRepeatSigns(
    sectionId,
    barIndex,
    opening: starts ? Barline.repeatStart : Barline.single,
  );

  // PURPOSE: Mark or unmark the selected bar as the end of a repeated passage, which is the bar the
  //          repeat barline is drawn on and the bar the passage jumps from.
  // INPUTS: sectionId and barIndex — the bar. ends — true to put a repeat-end barline on it, false
  //         to take one off.
  // OUTPUTS: True when the sign changed, false when the address names no bar or the bar already
  //          carries exactly that closing barline. An end with no matching start is allowed and not
  //          rejected: the derivation plays the barline as an ordinary one and reports
  //          [PlayOrderIssueKind.repeatEndWithoutStart].
  // KEYWORDS: repeat-end, barline, toggle, repeat-set, undoable, unmatched-end-allowed
  /// Sets or clears the repeat-end barline of the bar at ([sectionId], [barIndex]).
  bool setRepeatEnd({
    required String sectionId,
    required int barIndex,
    required bool ends,
  }) => _setRepeatSigns(
    sectionId,
    barIndex,
    closing: ends ? Barline.repeatEnd : Barline.single,
  );

  // PURPOSE: Change what the selected bar says about repeating the music before it — nothing, the
  //          previous bar, or the previous two — which is the `%` symbol a chart uses to avoid
  //          writing a bar twice.
  // INPUTS: sectionId and barIndex — the bar. previous — the symbol it should carry.
  // OUTPUTS: True when the symbol changed, false when the address names no bar or the bar already
  //          carries that symbol. A `%` as the first bar of the song is allowed: the derivation
  //          keeps the position, names the bar itself as what sounds, and reports
  //          [PlayOrderIssueKind.percentWithoutPreviousBar].
  // KEYWORDS: repeat-previous, percent-bar, repeat-set, toggle, undoable, first-bar-allowed
  /// Sets the repeat-previous symbol of the bar at ([sectionId], [barIndex]).
  bool setRepeatPrevious({
    required String sectionId,
    required int barIndex,
    required RepeatPrevious previous,
  }) => _setRepeatSigns(sectionId, barIndex, previous: previous);

  // PURPOSE: Put an alternative-ending bracket on the selected bar, change which ending it is, or
  //          take the bracket off — the sign a musician reads as "first time" and "second time".
  // INPUTS: sectionId and barIndex — the bar. volta — the bracket it should carry: `Volta(0)` for
  //         an unnumbered bracket, `Volta(n)` for the n-th ending, or null to remove the bracket.
  // OUTPUTS: True when the bracket changed, false when the address names no bar, when the bar
  //          already carries that bracket, and when the figure is negative. The negative refusal is
  //          the one rule this method adds to the catalogue's: no pass the derivation can take
  //          equals a negative number, so a bar carrying one would select no pass — a bracket that
  //          silences the bar it is drawn on. Setting a bracket on a bar inside no repeat is
  //          ALLOWED: [PlayOrderIssueKind.voltaOutsideRepeat] is the derivation's answer, and it is
  //          reported there rather than refused here.
  // KEYWORDS: volta, ending, bracket, clear-by-null, negative-refusal, undoable, stray-allowed
  /// Sets or removes the alternative-ending bracket of the bar at ([sectionId], [barIndex]).
  bool setVolta({
    required String sectionId,
    required int barIndex,
    required Volta? volta,
  }) {
    if (volta != null && volta.number < 0) {
      return false;
    }
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null || bar.volta == volta) {
      return false;
    }
    apply(
      VoltaSetEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        from: bar.volta,
        to: volta,
      ),
    );
    return true;
  }

  // PURPOSE: Apply one change to the repeat signs of a bar, so the four calls above share one place
  //          where the bar is read, the change is merged into the signs already there, and a change
  //          that alters nothing is refused.
  // INPUTS: sectionId and barIndex — the bar. opening, closing and previous — the fields to change;
  //         a null argument leaves that field as the bar already carries it, and a caller that
  //         wants a field cleared passes the value that means cleared (`Barline.single`), never
  //         null.
  // OUTPUTS: True when an event was appended, false when the address names no bar or when the
  //          merged signs equal the ones already on the bar. The event carries the complete signs on
  //          both sides, read from the bar here, so its inverse restores the bar exactly and no
  //          field the caller did not name is lost.
  // KEYWORDS: repeat-set, read-modify-append, whole-value, no-op-refusal, one-home
  bool _setRepeatSigns(
    String sectionId,
    int barIndex, {
    Barline? opening,
    Barline? closing,
    RepeatPrevious? previous,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return false;
    }
    final RepeatSigns from = RepeatSigns.of(bar);
    final RepeatSigns to = RepeatSigns(
      openingBarline: opening ?? from.openingBarline,
      closingBarline: closing ?? from.closingBarline,
      repeatPrevious: previous ?? from.repeatPrevious,
      slashRepeat: from.slashRepeat,
    );
    if (to == from) {
      return false;
    }
    apply(
      RepeatSetEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        from: from,
        to: to,
      ),
    );
    return true;
  }

  // --- The signs drawn on a bar ----------------------------------------------------------------
  //
  // `BarMark` — the segno, the coda, the fermata and the player's stop — has been drawn by
  // `chart_painter.dart` since the painter was written, and the owner's own setlist carries 31 of
  // them, but until this method existed NOTHING wrote one: they were the one mark on a bar with no
  // control (A48). The catalogue had no event for them either, so `mark.set` was added beside
  // `repeat.set` and `volta.set` for the same reason `song.update` was added beside the form
  // operations (A38): an operation a musician needs had no event to carry it.
  //
  // WHY THE WHOLE SET IS CARRIED AND NOT A SINGLE MARK. A bar may carry several marks at once and
  // the painter joins them into one line of glyphs, so "add the coda" and "remove the fermata" are
  // deltas against a set that a later edit, an undo or another device can change in between. The
  // event therefore records the set on both sides, read from the bar here, and its inverse is a
  // swap rather than a reconstruction.
  //
  // WHY CLEARING REMOVES A MEMBER RATHER THAN WRITING A NEUTRAL VALUE. A repeat barline has a
  // neutral value (`Barline.single`) because a barline is always there; a mark has none, because a
  // bar either carries the sign or it does not. `BarMark` is an enum with no "none" member, so
  // taking the last mark off a bar produces an EMPTY set — a real value the model holds, and one
  // the event can therefore carry as its `to` side (see `BarMarkSetEvent`).

  // PURPOSE: Put one of the four signs the painter draws on a bar onto the selected bar, or take it
  //          off — the operation that makes the 31 segnos, codas, fermatas and player stops in the
  //          owner's own setlist reachable from the application.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. mark — which of the four
  //         signs to change. present — true to put the sign on the bar, false to take it off.
  // OUTPUTS: True when the signs changed, false when the address names no bar, and false when the
  //          bar already carries exactly the state asked for. The second refusal is the rule every
  //          other edit here follows (see [setVolta], [updateSong]): an event whose two sides are
  //          equal is a log row that changed nothing and an offer to undo an edit that did not
  //          happen. The event carries the COMPLETE set of signs on both sides, read from the bar
  //          here, so its inverse restores the bar exactly — including the other marks the caller
  //          did not name, and the order they were drawn in.
  // KEYWORDS: bar-mark, segno, coda, fermata, player-ending, toggle, whole-value, no-op-refusal,
  //           order-preserving, undoable
  /// Sets or clears [mark] on the bar at ([sectionId], [barIndex]), reporting whether it changed.
  bool setBarMark({
    required String sectionId,
    required int barIndex,
    required BarMark mark,
    required bool present,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return false;
    }
    final Set<BarMark> from = bar.marks;
    if (from.contains(mark) == present) {
      return false;
    }
    // A COPY, because the bar's own set may be unmodifiable (the iReal parser wraps its marks in
    // `Set.unmodifiable`) and because the `from` half must keep naming the state before the edit
    // rather than the state a later mutation produced. The copy preserves the order of the marks
    // already on the bar; a mark that is being added lands at the end, which is the order the
    // painter draws it in.
    final Set<BarMark> to = Set<BarMark>.of(from);
    if (present) {
      to.add(mark);
    } else {
      to.remove(mark);
    }
    apply(
      BarMarkSetEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        from: from,
        to: to,
      ),
    );
    return true;
  }

  // --- Text cues: the words a musician writes on the chart -------------------------------------
  //
  // `textcue.insert`, `textcue.edit`, `textcue.move` and `textcue.delete` have been in the
  // catalogue since it was written and until these four methods existed nothing appended one: a
  // musician could write `To Coda` with a pen and not in words. They are here, next to the one
  // writer, for the same reason the form and repeat operations are (A35, A38, A41).
  //
  // WHY A CUE REUSES THE ANCHOR RATHER THAN A PAGE COORDINATE. `TextCue.place` is an
  // [AnchoredPlace] — an [EventAnchor] plus an anchor-local offset — which is the SAME value an
  // [Annotation] carries and the same address scheme an ink stroke is captured against
  // (`resolveEventAnchor`). One mechanism for "where on the music is this thing" is what makes a
  // cue survive a FITTED page, a transposition and a round trip for exactly the reasons a stroke
  // does: the address is re-resolved against the layout on screen and the stored offset is not a
  // page coordinate at all. A second scheme — a page pixel, a bar-relative fraction — would have
  // been a second thing to keep true.
  //
  // WHAT IS REFUSED HERE, AND WHY IT IS REFUSED AT THE EDIT RATHER THAN AT THE DRAWING. An anchor
  // naming a bar the song does not have, and a negative beat, are both refused by returning null
  // or false. Neither is caught by the reducer: `_withCueInserted` stores the cue whatever its
  // place says, and a cue whose anchor resolves nowhere is simply never drawn — an edit the
  // musician made and cannot see, which is the one outcome an event log exists to make
  // impossible. A bar an older version of the song had, restored by an undo, is not this case:
  // the address exists or it does not, and this is the only place that can answer.
  //
  // AN EMPTY CUE IS ALLOWED, AND THAT IS THE MODEL'S OWN ANSWER. `TextCue.text` documents empty as
  // "inserted and not yet typed into", which is an ordinary editing state: the cue has to exist
  // before there is a cursor to type into. So the insert may carry empty words and `editTextCue`
  // may write them back — the log then shows an insert followed by an edit to empty, in that
  // order, and each half is separately undoable. What the DOCUMENT may not do is keep one: a cue
  // with no words draws nothing, so nothing on the page can be tapped to select it, and only the
  // log could ever reach it again. That end is the app's to enforce (it deletes one it leaves
  // empty, through `textcue.delete`), and this class deliberately does not enforce it, because
  // "empty" is reachable as an intermediate state here and the model says so.
  //
  // TWO CUES AT ONE PLACE ARE BOTH KEPT. The reducer appends to an ordered list and nothing here
  // refuses an address another cue already occupies, so two remarks on one bar are two cues and
  // the later one in document order is drawn over the earlier one. Refusing the second would make
  // the app arbitrate which remark a musician "really" wanted, and nudging it aside would be the
  // app rewriting a place the musician chose — and rewriting it differently after every reflow.
  // Separating them is an edit, and it is exactly what `moveTextCue` is for.

  // PURPOSE: Put a piece of text a musician wants to read on the chart — `To Coda`, `D.C. al
  //          Fine`, `Solo`, `Vamp`, `4×` — at an address in the music, through the operation log.
  // INPUTS: sectionId and barIndex — the bar to hang it on, in the model's own address. beat — the
  //         cell inside that bar to hang it on, or null for the bar as a whole, which is what a
  //         remark about the whole bar (a navigation word at the top of it) wants. offsetX and
  //         offsetY — where the words sit from the anchor's own top-left corner, in anchor-local
  //         logical pixels; the defaults place a bar-level cue in the bar's sign band. text — the
  //         words, empty to insert and then type into (see the section note).
  // OUTPUTS: The new cue's identity, or null when the address names no bar or [beat] is negative —
  //          in both cases nothing is appended and the document is untouched. The cue is appended
  //          at the END of the cue list, which is the end of the render order: a cue put on a bar
  //          now is drawn over cues that were already there, so the musician sees what they just
  //          wrote rather than the remark it landed on top of.
  // KEYWORDS: text-cue, insert, anchored, bar-level, cell-level, offset, render-order, undoable
  /// Inserts a text cue at ([sectionId], [barIndex], [beat]) and returns its id, or null.
  String? insertTextCue({
    required String sectionId,
    required int barIndex,
    int? beat,
    double offsetX = 0,
    double offsetY = 0,
    String text = '',
  }) {
    if (beat != null && beat < 0) {
      return null;
    }
    if (_document.song.barAt(sectionId, barIndex) == null) {
      return null;
    }
    final TextCue cue = TextCue(
      id: _freshCueId(),
      place: AnchoredPlace(
        anchor: EventAnchor(sectionId: sectionId, bar: barIndex, beat: beat),
        offsetX: offsetX,
        offsetY: offsetY,
      ),
      text: text,
    );
    apply(
      TextCueInsertEvent(
        docId: _docId,
        seq: _seq,
        index: _document.textCues.length,
        cue: cue,
      ),
    );
    return cue.id;
  }

  // PURPOSE: Change the words of a cue the musician already wrote, which is the edit separate from
  //          moving it — the catalogue keeps them apart, and so does this (see `textcue_events`).
  // INPUTS: id — the cue to edit. text — what it should say; empty clears it.
  // OUTPUTS: True when an edit was appended, false when no cue carries [id] and false when the cue
  //          already says exactly that. The second refusal is the rule every other edit here
  //          follows (see [setVolta], [updateSong]): an event whose two sides are equal is a log
  //          row that changed nothing and an offer to undo an edit that did not happen. The event
  //          carries the words on BOTH sides, read from the cue here, so its inverse is a swap and
  //          restores the previous words exactly.
  // KEYWORDS: text-cue, edit-words, before-after, no-op-refusal, undoable
  /// Replaces the words of the cue [id] with [text], reporting whether anything changed.
  bool editTextCue(String id, String text) {
    final int index = _cueIndex(id);
    if (index < 0) {
      return false;
    }
    final String from = _document.textCues[index].text;
    if (from == text) {
      return false;
    }
    apply(
      TextCueEditEvent(docId: _docId, seq: _seq, id: id, from: from, to: text),
    );
    return true;
  }

  // PURPOSE: Move a cue to another place in the music — another bar, another cell of the same bar,
  //          or another offset within the cell it already sits on — which is how a musician
  //          separates two remarks that landed on top of each other and how a cue written on the
  //          wrong bar is put right without retyping its words.
  // INPUTS: id — the cue to move. sectionId and barIndex — the bar to move it to. beat — the cell
  //         inside that bar, or null for the bar as a whole. offsetX and offsetY — the new
  //         anchor-local offset.
  // OUTPUTS: True when a move was appended, false when no cue carries [id], when the TARGET names
  //          no bar, when [beat] is negative, and when the target place equals the one the cue
  //          already occupies. The target is deliberately not restricted to the cue's own bar or
  //          section: `textcue.move` carries a whole [AnchoredPlace] on each side and the reducer
  //          accepts any address, so a cue can be moved anywhere the song has a bar, and a rule
  //          confining it here would be a second, weaker copy of the model's own address rule. A
  //          call that moves a cue one bar has the same effect as a drag, which is why the app can
  //          offer the operation as buttons without a second event type.
  // KEYWORDS: text-cue, move, re-anchor, offset, any-bar, no-op-refusal, undoable
  /// Moves the cue [id] to ([sectionId], [barIndex], [beat]) with the given offset.
  bool moveTextCue(
    String id, {
    required String sectionId,
    required int barIndex,
    int? beat,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final int index = _cueIndex(id);
    if (index < 0 || (beat != null && beat < 0)) {
      return false;
    }
    if (_document.song.barAt(sectionId, barIndex) == null) {
      return false;
    }
    final AnchoredPlace from = _document.textCues[index].place;
    final AnchoredPlace to = AnchoredPlace(
      anchor: EventAnchor(sectionId: sectionId, bar: barIndex, beat: beat),
      offsetX: offsetX,
      offsetY: offsetY,
    );
    if (to == from) {
      return false;
    }
    apply(
      TextCueMoveEvent(docId: _docId, seq: _seq, id: id, from: from, to: to),
    );
    return true;
  }

  // PURPOSE: Take a cue off the chart, which is the half `textcue.insert`'s inverse needs and the
  //          gesture that removes a remark the band no longer reads.
  // INPUTS: id — the cue to remove.
  // OUTPUTS: True when a deletion was appended, false when no cue carries [id]. The event carries
  //          the cue IN FULL and the position it occupied, so undoing the deletion restores the
  //          words, the cell and the offset exactly, and restores the cue's place in the render
  //          order rather than appending it to the end.
  // KEYWORDS: text-cue, delete, whole-value, render-order, undoable
  /// Removes the cue [id] from the document, reporting whether one was there.
  bool deleteTextCue(String id) {
    final int index = _cueIndex(id);
    if (index < 0) {
      return false;
    }
    apply(
      TextCueDeleteEvent(
        docId: _docId,
        seq: _seq,
        index: index,
        removed: _document.textCues[index],
      ),
    );
    return true;
  }

  // PURPOSE: Answer what a cue currently says and where it sits, so a sheet that holds an identity
  //          across several edits can read the value it is editing rather than a copy it took when
  //          it opened.
  // INPUTS: id — the identity to look for.
  // OUTPUTS: The cue, or null when the document has none with that id. Null is a real answer: a
  //          deletion, or an undo of an insertion, is exactly how an identity stops naming
  //          anything, and a sheet that has to keep working after either needs to be told.
  // KEYWORDS: text-cue, lookup, identity, null-when-absent, total-function
  /// Returns the cue with [id], or null when the document has none.
  TextCue? textCueById(String id) {
    final int index = _cueIndex(id);
    return index < 0 ? null : _document.textCues[index];
  }

  // PURPOSE: Find where a cue sits in the document's cue list, so every cue operation turns an
  //          identity into the position the events need — and, for a deletion, the position its
  //          inverse must restore the cue to.
  // INPUTS: id — the identity to look for.
  // OUTPUTS: The cue's index, or -1 when no cue carries that id. Negative rather than null so
  //          every caller's guard is the same single comparison, as [_sectionIndex] is.
  // KEYWORDS: lookup, cue-index, identity-to-position, sentinel
  int _cueIndex(String id) =>
      _document.textCues.indexWhere((TextCue cue) => cue.id == id);

  // PURPOSE: Mint an identity for a cue that is being inserted, which no operation may leave to a
  //          caller: two cues sharing an id would make `textcue.edit` and `textcue.move`
  //          ambiguous — they address a cue by id alone — and the reducer refuses a second cue
  //          with an id already present, so a collision would be a failed insert rather than a
  //          renamed cue.
  // INPUTS: None; reads the document's cues and this session's sequence counter.
  // OUTPUTS: An id of the form `cue-N` that no cue currently carries. The counter starts at the
  //          next sequence number, and the loop closes the remaining case: a cue restored from a
  //          file that happens to be named `cue-N` already.
  // KEYWORDS: identity, fresh-id, collision-avoidance, monotone, cue-creation
  String _freshCueId() {
    final Set<String> used = <String>{
      for (final TextCue cue in _document.textCues) cue.id,
    };
    int counter = _seq + 1;
    String candidate = 'cue-$counter';
    while (used.contains(candidate)) {
      counter++;
      candidate = 'cue-$counter';
    }
    return candidate;
  }

  // --- Ink: the strokes a musician wrote on the chart -------------------------------------------
  //
  // The catalogue has carried `ink.stroke.add` and `ink.stroke.delete` since it was written, and
  // the eraser is the operation the second one exists for. The ADD is written by the capture layer,
  // which owns the live samples and the identity it mints for them; the DELETE is written here,
  // next to the one writer, because it needs the stroke's POSITION in the document's list and only
  // the document can answer that. The position matters: it is what the deletion's inverse restores
  // the stroke to, so a stroke removed from the middle of the render order comes back in the middle
  // and not on top of the ink it used to lie beneath.
  //
  // WHY THE STROKE IS REMOVED BY IDENTITY AND NOT BY POSITION. A position is a photograph of a
  // list that an undo, a redo or another device's edit can change between the touch and the append.
  // The id is the identity the capture layer minted and the identity the delete event carries, so
  // the reducer can apply the removal even if earlier edits shifted the list — and the position is
  // carried alongside it for the inverse alone, which is exactly how `InkStrokeDeleteEvent` is
  // documented.

  // PURPOSE: Remove one stroke from the document, which is the whole of what the eraser does: the
  //          model removes WHOLE STROKES rather than nibbling pixels, so there is no partial erase
  //          here and no stroke to store for one. See `oplog/ink.dart` for that decision.
  // INPUTS: id — the identity of the stroke to remove, as the document currently holds it and as
  //         the capture layer's hit test reported it.
  // OUTPUTS: True when a deletion was appended, false when no stroke carries [id]. The event
  //          carries the stroke IN FULL and the position it occupied, so an undo restores the exact
  //          geometry — same id, same points, same anchor — at the exact place in the render order
  //          rather than re-derived from anything. An id naming no stroke is refused rather than
  //          appended as a no-op: a log row that changes nothing is still an offer to undo an edit
  //          that did not happen.
  // KEYWORDS: ink-erase, stroke-delete, whole-value, render-order, identity-not-position, undoable
  /// Removes the stroke with [id], reporting whether the document held one.
  bool eraseStroke(String id) {
    final int index = _document.strokes.indexWhere(
      (InkStroke stroke) => stroke.id == id,
    );
    if (index < 0) {
      return false;
    }
    apply(
      InkStrokeDeleteEvent(
        docId: _docId,
        seq: _seq,
        index: index,
        stroke: _document.strokes[index],
      ),
    );
    return true;
  }

  // --- The song's own metadata ------------------------------------------------------------------
  //
  // One event family covers all four fields, because they are one thing a musician edits: what the
  // tune is. Keeping them together is also what lets the event carry both whole values, which is
  // what makes its inverse exact.

  // PURPOSE: Change what the tune says about itself — its name, who wrote it, what it is played as
  //          and how fast — which is the edit the scene bar's tempo and style were waiting for.
  // INPUTS: The fields to replace. A null argument leaves that field alone; an empty string and a
  //         zero tempo are VALUES the model represents rather than absences, so a title can be
  //         cleared and a tempo unset.
  // OUTPUTS: True when the update was appended, false in two cases. Nothing to change: an event
  //          whose two sides are equal is still a log row and still an offer to undo, so it is not
  //          written. A negative tempo: a tempo below zero is not a tempo, and the model already
  //          documents 0 as the value for "this chart sets none", so a negative one would be a
  //          third state nothing else in the system knows how to read. The event carries all four
  //          fields on both sides, so undo restores the previous values exactly rather than
  //          reconstructing them from the change.
  // KEYWORDS: song-update, metadata, title, composer, style, tempo, no-op-refusal, undoable
  /// Replaces the named fields of the song's metadata, reporting whether anything changed.
  bool updateSong({
    String? title,
    String? composer,
    String? style,
    int? tempo,
  }) {
    if (tempo != null && tempo < 0) {
      return false;
    }
    final SongMetadata from = SongMetadata.of(_document.song);
    final SongMetadata to = SongMetadata(
      title: title ?? from.title,
      composer: composer ?? from.composer,
      style: style ?? from.style,
      tempo: tempo ?? from.tempo,
    );
    if (to == from) {
      return false;
    }
    apply(SongUpdateEvent(docId: _docId, seq: _seq, from: from, to: to));
    return true;
  }

  // PURPOSE: Find where a section sits, so every section operation can turn the identity a caller
  //          holds into the position an event needs.
  // INPUTS: sectionId — the identity to look for.
  // OUTPUTS: The section's index in the song, or -1 when no section carries that id. Negative
  //          rather than null so every caller's guard is the same single comparison.
  // KEYWORDS: lookup, section-index, identity-to-position, sentinel
  int _sectionIndex(String sectionId) => _document.song.sections.indexWhere(
    (Section section) => section.id == sectionId,
  );

  // PURPOSE: Build the blank bar a form edit needs, so the meter rule has one home.
  // INPUTS: reference — the bar the musician was working from.
  // OUTPUTS: A bar carrying [reference]'s meter and no content: no chords (which means the previous
  //          chord sustains), no notes, no signs and single barlines.
  // KEYWORDS: blank-bar, meter-inheritance, new-measure, single-rule
  Bar _blankBarLike(Bar reference) =>
      Bar(timeSignature: reference.timeSignature);

  // PURPOSE: Insert a new one-bar section on the side of a reference section that the caller asks
  //          for, so "before" and "after" share one implementation of what a new section is.
  // INPUTS: sectionId — the reference section. after — true to place the new section later in the
  //         order, false to place it earlier.
  // OUTPUTS: The new section's identity, or null when [sectionId] names no section.
  // KEYWORDS: section-insert, before-after, one-implementation, meter-inheritance
  String? _insertSectionBeside(String sectionId, {required bool after}) {
    final int index = _sectionIndex(sectionId);
    if (index < 0) {
      return null;
    }
    final Section reference = _document.song.sections[index];
    final Section section = Section(
      id: _freshSectionId(),
      label: _nextSectionLabel(),
      bars: <Bar>[
        _blankBarLike(
          reference.bars.isEmpty ? const Bar() : reference.bars.last,
        ),
      ],
    );
    apply(
      SectionInsertEvent(
        docId: _docId,
        seq: _seq,
        index: after ? index + 1 : index,
        section: section,
      ),
    );
    return section.id;
  }

  // PURPOSE: Mint an identity for a section that is being created, which no operation may leave to
  //          a caller: an id has to be unique in the song, and an id reused after a deletion would
  //          silently reattach every annotation anchored in the section that was removed.
  // INPUTS: None; reads the song's sections and this session's sequence counter.
  // OUTPUTS: An id of the form `sec-N` that no section currently carries. The counter starts at the
  //          next sequence number, so a document that never had a section added twice cannot offer
  //          the same number twice, and the loop closes the remaining case — an imported section
  //          that happens to be named `sec-N` already.
  // KEYWORDS: identity, fresh-id, collision-avoidance, monotone, section-creation
  String _freshSectionId() {
    final Set<String> used = <String>{
      for (final Section section in _document.song.sections) section.id,
    };
    int counter = _seq + 1;
    String candidate = 'sec-$counter';
    while (used.contains(candidate)) {
      counter++;
      candidate = 'sec-$counter';
    }
    return candidate;
  }

  // PURPOSE: Name a section that is being created, so a musician adding a part gets the next
  //          rehearsal letter instead of being asked for a name before there is anything to name.
  // INPUTS: None; reads the labels the song already carries.
  // OUTPUTS: The first single letter from A to Z that no section already uses as its text,
  //          upper-cased. When all twenty-six are taken, a custom label `S<n>` carrying the
  //          section count, which is a name rather than a duplicate.
  // KEYWORDS: rehearsal-letter, next-label, uniqueness, fallback, section-creation
  SectionLabel _nextSectionLabel() {
    final Set<String> used = <String>{
      for (final Section section in _document.song.sections) section.label.text,
    };
    for (int index = 0; index < 26; index++) {
      final String letter = String.fromCharCode('A'.codeUnitAt(0) + index);
      if (!used.contains(letter)) {
        return SectionLabel.letter(letter);
      }
    }
    return SectionLabel.custom('S${_document.song.sections.length + 1}');
  }
}
