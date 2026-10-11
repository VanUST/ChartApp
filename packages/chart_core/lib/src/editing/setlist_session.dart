// PURPOSE: Be the one place a setlist document changes while a musician edits a programme. Every
//          mutation goes into the setlist's operation log and then through
//          `DocumentReducer.applySetlist`; undo and redo are appends of the inverses the setlist
//          catalogue already carries. Nothing here writes a `Setlist` field directly: if a change
//          cannot be expressed as a setlist event, it cannot be made, which is the same rule the
//          chart's own `EditSession` follows and the reason the log stays the whole record.
// INPUTS: A starting [Setlist] and, for a setlist read back from a file, the events already in its
//         tail. A setlist id taken from the setlist itself, or the caller's override, because every
//         event must name the document it belongs to.
// OUTPUTS: A session that reports the current [setlist], the [log] of everything applied since it
//          started, its [seq] counter, and whether [canUndo] or [canRedo]. Applying an event and
//          then undoing it returns a setlist EQUAL to the one before it — the comparison is
//          `Setlist ==`, which compares the id, the title and the entries in order.
// KEYWORDS: setlist-session, op-log, reducer, undo, redo, inverse, append-only, single-writer
//
// WHY A SESSION OF ITS OWN RATHER THAN A CHART SESSION WITH A FLAG.
//
// `EditSession` is typed on `ChartEvent` and reduces a `DocumentState`; a setlist is a `SetlistEvent`
// branch the chart reducer deliberately cannot be handed (see `DocumentEvent`), and folding it is
// `DocumentReducer.applySetlist`. A session that carried both would have to erase that distinction
// at exactly the place it was drawn, and its log — the tail a `.setlist` file would store — would
// then hold events whose document kind a reader cannot tell apart. This class is the setlist half of
// the same shape, drawn with the same names so the two are read the same way.
//
// WHY UNDO IS AN APPEND AND NOT A POP.
//
// The setlist catalogue gives every event an inverse that is again a setlist event, so an undo is
// the inverse appended to the same log: the record keeps both the edit and its reversal, and a
// `.setlist` file written from [log] explains the document it was written beside. This class
// therefore never removes an event from [log]; it grows on every undo and redo.
//
// WHY THE LOG IS NOT THE SAME THING AS A `.setlist` FILE'S TAIL.
//
// A container stores a snapshot plus the operations AFTER that snapshot. This session's log starts
// at the value it was given, so it is exactly that tail — which is why [baseSetlist] and [log] can
// be handed to such a container untouched, the same pair `EditSession.baseDocument` and
// `EditSession.log` form for a chart. The `.setlist` container exists: it is `SetlistFile` in
// `src/container/setlist_file.dart`, over the same envelope `.chart` uses, and `docId`, [baseSetlist]
// and [log] are the three values it is built from without any change here.
part of '../oplog/oplog.dart';

/// One undoable setlist edit: the event to apply on redo, and the event to apply on undo.
class SetlistUndoOp {
  /// Creates an undoable edit whose redo event is [forward] and whose undo event is [undoEvent].
  ///
  /// Both are retained rather than one being derived from the other, for the same reason
  /// `UndoOp` retains both: an event's inverse describes the reversal and not the position, so
  /// re-topping the original as a redo and re-topping its inverse as an undo are two operations
  /// rather than one and its mirror.
  const SetlistUndoOp({required this.forward, required this.undoEvent});

  /// The event that applies this edit, as appended when it was first made.
  final SetlistEvent forward;

  /// The event that reverses this edit.
  final SetlistEvent undoEvent;
}

/// A setlist document being edited, and the log that explains it.
///
/// The sequence counter is private because a session must issue the next number itself:
/// `(docId, seq)` addresses a log row, so a caller able to set it could produce two events
/// claiming one position.
class SetlistSession {
  /// Opens a session on [setlist], continuing a log that ended at [seq].
  ///
  /// [docId] defaults to the setlist's own id, because an event must name a document and a setlist
  /// built in memory may have an empty id. [restored] is the operations a `.setlist` file would
  /// carry, which this session continues from rather than reissues. [setlist] IS THE VALUE BEFORE
  /// [restored], AND THIS CONSTRUCTOR APPLIES THEM: the container contract is a snapshot plus the
  /// operations after it, so a caller that has already folded the tail must not hand it over too.
  SetlistSession({
    required Setlist setlist,
    String? docId,
    this._seq = 0,
    List<SetlistEvent> restored = const <SetlistEvent>[],
  }) : _base = setlist,
       _docId = docId ?? _defaultSetlistId(setlist.id),
       _restored = List<SetlistEvent>.of(restored),
       _setlist = _reduceTail(setlist, restored);

  /// The value this session was opened on: the setlist BEFORE [log].
  ///
  /// It is what a save would write as the container's snapshot, so that `snapshot + tail` is the
  /// programme the musician is looking at. Writing the CURRENT setlist as the snapshot with the tail
  /// beside it would store every operation twice and re-apply it on the way back in.
  final Setlist _base;

  final String _docId;
  int _seq;
  final List<SetlistEvent> _restored;
  final List<SetlistUndoOp> _undo = <SetlistUndoOp>[];
  final List<SetlistUndoOp> _redo = <SetlistUndoOp>[];
  final List<SetlistEvent> _appliedEvents = <SetlistEvent>[];

  Setlist _setlist;

  // PURPOSE: Fold the operations a file carried into the value that file stored, so a session
  //          opened on a `.setlist` document holds the programme the writer saw rather than its
  //          snapshot alone.
  // INPUTS: setlist — the snapshot, which is the value before the tail. restored — the operations
  //         after it, in log order.
  // OUTPUTS: The reduced setlist. An empty tail returns [setlist] itself, which is the ordinary case
  //          of a session that was not opened from a file. An event the reducer cannot apply throws
  //          [DocumentReducerException] here rather than being skipped, because a tail that does not
  //          fit its snapshot is a document nobody can reconstruct.
  // KEYWORDS: reduce-tail, snapshot-plus-log, restore, fail-loud
  static Setlist _reduceTail(Setlist setlist, List<SetlistEvent> restored) {
    Setlist state = setlist;
    for (final SetlistEvent event in restored) {
      state = DocumentReducer.applySetlist(state, event);
    }
    return state;
  }

  /// The document id every event this session writes carries.
  String get docId => _docId;

  /// The value this session started from: what a save would write as the container's snapshot.
  ///
  /// Not the same value as [setlist] once anything has been edited — the difference between the two
  /// is exactly [log] — which is why a file would hold this one and the tail and reopen into
  /// [setlist].
  Setlist get baseSetlist => _base;

  /// The setlist as it stands, with every applied event folded in.
  Setlist get setlist => _setlist;

  /// The entries in playing order, which is the value most callers read.
  List<SetlistItem> get items => _setlist.items;

  /// The sequence number the next appended event will carry.
  ///
  /// One past the highest number this session has written, and never reused: a log is addressed by
  /// `(docId, seq)`, so two events sharing a number would be one row in the store.
  int get seq => _seq;

  /// The operations applied since this session opened, in order, including every undo and redo.
  ///
  /// This is the tail a `.setlist` file would store beside its snapshot, which is why it is the
  /// events as they were written and not the stack of edits that is still undoable.
  List<SetlistEvent> get log => <SetlistEvent>[..._restored, ..._appliedEvents];

  /// Whether there is an edit to undo.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is an undone edit to redo.
  bool get canRedo => _redo.isNotEmpty;

  /// Number of edits that can still be undone.
  int get undoDepth => _undo.length;

  /// Number of undone edits that can still be redone.
  int get redoDepth => _redo.length;

  /// The document id used when a setlist carries none of its own.
  static const String untitledSetlistId = 'chartapp-untitled-setlist';

  /// Returns [id] when it is not empty, and the untitled setlist id otherwise.
  static String _defaultSetlistId(String id) =>
      id.isEmpty ? untitledSetlistId : id;

  // PURPOSE: Read one entry, so a caller that is about to edit it can decide both halves of the
  //          event from the value the document actually holds rather than from a stale copy.
  // INPUTS: index — the entry's position in the programme.
  // OUTPUTS: The entry at [index], or null when the index is outside the list. A null answer is a
  //          refusal the caller can see, rather than an exception thrown from a read.
  // KEYWORDS: entry-query, bounds-checked, null-when-absent, read-modify-append
  /// Returns the entry at [index], or null when the index names none.
  SetlistItem? itemAt(int index) => index < 0 || index >= _setlist.items.length
      ? null
      : _setlist.items[index];

  // PURPOSE: Apply an event and remember how to take it back, which is the single entrance every
  //          setlist edit funnels through: a rename, an insertion, a move and a redo of any of them
  //          all arrive here.
  // INPUTS: event — the event to apply, carrying this session's document id and a sequence number.
  // OUTPUTS: Nothing. The setlist is the reduction, the event is appended to the log and the inverse
  //          is pushed as the next undo. Throws [DocumentReducerException] when the event cannot be
  //          applied, leaving this session untouched; throws [ArgumentError] when the event names
  //          another document, because applying it here would write a log row the container refuses
  //          on save. A new edit after an undo drops the redo stack, because the branch that was
  //          undone is no longer the branch being edited.
  // KEYWORDS: apply, append, undo-stack, redo-invalidation, fail-loud, single-writer
  /// Applies [event] to this session's setlist and records its inverse.
  void apply(SetlistEvent event) {
    if (event.docId != _docId) {
      throw ArgumentError.value(
        event.docId,
        'event.docId',
        'belongs to another document; this session edits "$_docId"',
      );
    }
    final Setlist next = DocumentReducer.applySetlist(_setlist, event);
    final int seq = _seq + 1;
    final SetlistEvent numbered = event.withSeq(seq) as SetlistEvent;
    _setlist = next;
    _seq = seq;
    _appliedEvents.add(numbered);
    _undo.add(SetlistUndoOp(forward: numbered, undoEvent: numbered.inverse()));
    _redo.clear();
  }

  // PURPOSE: Take back the most recent setlist edit the musician still has, by applying the inverse
  //          the catalogue carries for it.
  // INPUTS: None.
  // OUTPUTS: True when an edit was undone, false when there was none. The undo appends the inverse
  //          to the log rather than deleting the original, and pushes the original as the next redo.
  //          The setlist afterwards is EQUAL to the setlist before the original edit, because the
  //          event carried the whole previous value — an entry in full, or both titles — and nothing
  //          is reconstructed from what the list happens to hold now.
  // KEYWORDS: undo, inverse-event, append-only, exact-restore, no-op-when-empty
  /// Reverses the most recent edit, reporting whether there was one.
  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    final SetlistUndoOp op = _undo.removeLast();
    final Setlist next = DocumentReducer.applySetlist(_setlist, op.undoEvent);
    final int seq = _seq + 1;
    final SetlistEvent numbered = op.undoEvent.withSeq(seq) as SetlistEvent;
    _setlist = next;
    _seq = seq;
    _appliedEvents.add(numbered);
    _redo.add(SetlistUndoOp(forward: op.forward, undoEvent: numbered));
    return true;
  }

  // PURPOSE: Put back the setlist edit the musician just took back, exactly as it was made.
  // INPUTS: None.
  // OUTPUTS: True when an edit was redone, false when there was none. Because [apply] renumbers an
  //          event before storing it, the redo re-applies through the same door and the log stays a
  //          record of applications rather than of intentions.
  // KEYWORDS: redo, re-apply, append-only, exact-forward, no-op-when-empty
  /// Re-applies the most recently undone edit, reporting whether there was one.
  bool redo() {
    if (_redo.isEmpty) {
      return false;
    }
    final SetlistUndoOp op = _redo.removeLast();
    final Setlist next = DocumentReducer.applySetlist(_setlist, op.forward);
    final int seq = _seq + 1;
    final SetlistEvent numbered = op.forward.withSeq(seq) as SetlistEvent;
    _setlist = next;
    _seq = seq;
    _appliedEvents.add(numbered);
    _undo.add(SetlistUndoOp(forward: numbered, undoEvent: op.undoEvent));
    return true;
  }

  // --- The operations a programme is built from ------------------------------------------------
  //
  // The catalogue already carries every one of these operations (`setlist.rename`,
  // `setlist.item.insert`, `setlist.item.delete`, `setlist.item.move`, `setlist.item.update`). What
  // is here is the decision of WHAT to put in each event and WHEN to refuse one that changes
  // nothing, which is the part a caller must not restate. Each refusal follows `EditSession`: an
  // event whose two halves are equal is a log row that changed nothing and an offer to undo an edit
  // that did not happen.

  // PURPOSE: Give the programme its name, which is the fact a musician reads to tell one setlist
  //          from another.
  // INPUTS: title — the name it should carry.
  // OUTPUTS: True when the title changed, false when it is already that title, because a rename to
  //          the same name would be an undoable no-op. The event carries both titles, so undo
  //          restores the exact previous name — including an empty one — rather than a re-derived
  //          one.
  // KEYWORDS: rename, setlist-title, reversible, no-op-refusal, undoable
  /// Renames the programme to [title], reporting whether the name changed.
  bool rename(String title) {
    if (_setlist.title == title) {
      return false;
    }
    apply(
      SetlistRenameEvent(
        docId: _docId,
        seq: _seq,
        fromTitle: _setlist.title,
        toTitle: title,
      ),
    );
    return true;
  }

  // PURPOSE: Put a chart into the programme, which is how a setlist is built and how an imported
  //          playlist is extended by hand.
  // INPUTS: item — the entry in full, naming the chart and how it is played there. index — where it
  //         lands; null appends, which is what a musician adding to the end of a programme wants.
  // OUTPUTS: The index the entry took, or null when [index] is outside the list — before the first
  //          entry or more than one past the last. An index equal to the entry count appends, which
  //          is the reducer's own rule and the reason the boundary is `> length` rather than
  //          `>= length`. The event carries the whole entry, so its inverse is a deletion that
  //          restores an entry equal to this one.
  // KEYWORDS: insert-entry, append, position, bounds-check, whole-value, undoable
  /// Inserts [item] at [index], or appends it when [index] is null, returning where it landed.
  int? insertItem(SetlistItem item, {int? index}) {
    final int at = index ?? _setlist.items.length;
    if (at < 0 || at > _setlist.items.length) {
      return null;
    }
    apply(
      SetlistItemInsertEvent(docId: _docId, seq: _seq, index: at, item: item),
    );
    return at;
  }

  // PURPOSE: Take a chart out of the programme, which is how an entry that turned out not to belong
  //          — a tune the band dropped, a duplicate — is removed.
  // INPUTS: index — the entry to remove.
  // OUTPUTS: True when the entry was removed, false when [index] names none. The event carries the
  //          WHOLE entry it removed, so undo puts back exactly that entry — including its
  //          transposition and its notes — rather than a blank one re-inserted at the same position.
  // KEYWORDS: delete-entry, whole-value, bounds-check, undoable
  /// Removes the entry at [index], reporting whether one was there.
  bool deleteItem(int index) {
    final SetlistItem? removed = itemAt(index);
    if (removed == null) {
      return false;
    }
    apply(
      SetlistItemDeleteEvent(
        docId: _docId,
        seq: _seq,
        index: index,
        removed: removed,
      ),
    );
    return true;
  }

  // PURPOSE: Change the order of the programme, which is how a tune that sits in the wrong place in
  //          the running order is moved without deleting and re-adding it — a delete and an insert
  //          would also lose the entry's transposition and notes.
  // INPUTS: fromIndex — the entry's present position. toIndex — its position in the resulting order.
  // OUTPUTS: True when the entry moved, false when either index names no entry and false when the
  //          two are equal, because a move to the same place changes nothing. The event is a swap of
  //          the two indices, which is the catalogue's own inverse; there is no entry identity to
  //          name, since two entries can play the same chart.
  // KEYWORDS: move-entry, reorder, swap-inverse, bounds-check, no-op-refusal, undoable
  /// Moves the entry at [fromIndex] to [toIndex], reporting whether it moved.
  bool moveItem(int fromIndex, int toIndex) {
    if (fromIndex < 0 ||
        fromIndex >= _setlist.items.length ||
        toIndex < 0 ||
        toIndex >= _setlist.items.length ||
        fromIndex == toIndex) {
      return false;
    }
    apply(
      SetlistItemMoveEvent(
        docId: _docId,
        seq: _seq,
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
    return true;
  }

  // PURPOSE: Change how one entry is played — how far it is transposed and what the performer is
  //          told about it — which is the edit that makes a setlist more than a list of names and is
  //          the scene meaning owner decision D14 puts on an entry.
  // INPUTS: index — the entry to change. transposeSem — the new interval in semitones, or null to
  //         leave it. notes — the new free text, or null to leave it. A null argument leaves that
  //         field as it is, so a caller changing only the notes does not have to know the current
  //         transposition, and the two are computed from the entry THIS session holds rather than
  //         from a copy the caller read earlier.
  // OUTPUTS: True when the entry changed, false when [index] names none and false when the merged
  //          entry equals the one already there — a no-op is not an edit. The event carries the
  //          WHOLE entry on both sides, so its inverse restores the transposition and the notes
  //          together and neither field is reconstructed from the other.
  //
  //          ANY INTEGER IS ACCEPTED. The scene meaning is an interval from the written key, and a
  //          key is a pitch class: `+7` and `-5` reach the same key, so a value outside the
  //          twelve-key grid's `[-5, 6]` is a legal interval rather than a mistake. The display
  //          resolves it by pitch class (see `setlistSceneFor`); clamping here would silently
  //          rewrite a number a caller asked for.
  // KEYWORDS: update-entry, transposition, notes, read-modify-append, no-op-refusal, undoable
  /// Applies [transposeSem] and [notes] to the entry at [index], reporting whether it changed.
  bool updateItem(int index, {int? transposeSem, String? notes}) {
    final SetlistItem? current = itemAt(index);
    if (current == null) {
      return false;
    }
    final SetlistItem next = current.copyWith(
      transposeSem: transposeSem,
      notes: notes,
    );
    if (next == current) {
      return false;
    }
    apply(
      SetlistItemUpdateEvent(
        docId: _docId,
        seq: _seq,
        index: index,
        from: current,
        to: next,
      ),
    );
    return true;
  }
}
