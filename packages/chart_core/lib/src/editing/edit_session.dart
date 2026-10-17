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

/// How near a place must be to an existing chord for an edit to REPLACE it rather than add another.
///
/// A REACH, NOT A GRID. It is the distance a finger has on the chord line when it aims at a symbol,
/// which is about the height of the line itself: close enough that the symbol a musician clearly
/// touched is the one he edits, far enough that two chords written side by side stay two chords. It
/// is a constant of the EDITING gesture and not of the engraving, which is why it lives here and not
/// in `LayoutStyle`.
const double chordHitTolerance = 22;

/// Half the height of the bar's chord line, which is how far a chord's own place may sit from the
/// line's centre and still be ON the line.
///
/// THE OWNER'S RULE, AS A NUMBER: above the staff is a chord, on the staff is a note, below the bar is
/// neither («Аккорды надо запретить ниже такта»). The chord band is the bar's own rectangle, whose
/// height is the engraver's `LayoutStyle.barHeight`, so half of it either side of the centre is
/// exactly the band. A chord outside it would be a chord drawn below the bar — where the rule says no
/// chord and no note exists — and both organs refuse it: this constant is what the EDITOR refuses
/// against, and `LayoutEngine._placeChords` clamps the box an old file may still carry.
///
/// IT IS THE ENGRAVER'S OWN NUMBER: half of `LayoutStyle.barHeight`'s default of 44, written as a
/// literal because a constant expression may not read a field and this library may not depend on the
/// engraving's configuration. The two are held together by a CHECK rather than by a promise —
/// `chord_band_test.dart` asserts that twice this value is `const LayoutStyle().barHeight` — so a
/// style that moves the chord line fails the suite instead of letting the editor and the engraving
/// disagree about where the band ends.
const double chordBandHalfHeight = 22;

// PURPOSE: Name why a chord could not be written, so the surface can say which rule refused it
//          instead of reporting a bare failure — and so "the bar does not exist" and "a chord may not
//          be written there" are two different answers rather than one boolean.
// INPUTS: None; produced by [EditSession.applyChordAt].
// OUTPUTS: One of two tokens. Both mean NOTHING WAS WRITTEN.
// KEYWORDS: chord-entry, refusal, named-outcome, chord-band, no-such-bar
/// Why a chord was not written.
enum ChordEntryRefusal {
  /// The address names no bar of the song.
  noSuchBar,

  /// The place is not on the bar's chord line: below the bar, or above the staff's chord row.
  outsideChordBand,
}

// PURPOSE: Report what an attempt to write a chord did, carrying the mark that is now in the document
//          so the caller does not have to search for it again.
// INPUTS: Built by [EditSession.applyChordAt] from the edit it made, or from the rule that refused it.
// OUTPUTS: An immutable value with exactly one of [mark] and [refusal] set. [applied] is true on the
//          success side, and its [mark] is the WHOLE value the document now holds — which for an
//          update is the old chord with the new symbol, not the caller's argument.
// KEYWORDS: chord-entry, outcome, applied, refused, whole-value, one-of-two

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

// PURPOSE: Give a mark's place the anchor the CALLER's address names, keeping its offsets. It
//          restates a coordinate's bar and never its position.
// INPUTS: place — the place as the document holds it. sectionId and barIndex — the address the
//         caller named and the session found the mark at.
// OUTPUTS: The same place with an anchor for that bar. The offsets are untouched, because they are
//         what the musician wrote and the address is only where it was written.
//
//         WHY THE CALLER'S ADDRESS WINS. A place's anchor restates which bar holds the mark, and the
//         document's structure is the authority on that: the session has just found the mark in the
//         bar it was asked about. An event built from the mark's own anchor instead would name a bar
//         the caller never mentioned — the failure a fixture anchored by a placeholder produces —
//         and the reducer rewrites the same field on every mutation for exactly this reason.
// KEYWORDS: anchor, rebase, caller-address-wins, event-payload, single-address

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
  //          previous value — a `ChordMark` in full, not an address — nothing is reconstructed from
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

  // PURPOSE: Put a chosen chord into a bar AT A PLACE, which is the edit the palette exists to make.
  //          It decides between the catalogue's two chord events from what the document holds, so the
  //          caller never has to know whether there was already a chord where the musician pointed.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. offsetX and offsetY — the
  //         place inside that bar, in bar-local logical pixels, exactly as a tap reported them
  //         (`ChartHit.local`). offsetY is the chord's own height on the chord line, and 0 means the
  //         middle of it, which is where every chart written before this stage sits. chord — the
  //         chosen chord. size — the engraved size, normally the size of the placement being
  //         replaced. tolerance — how near an existing chord the place must be to REPLACE it rather
  //         than add another; the default is half a chord line's height, which is the reach a finger
  //         has on the symbols it is aiming at.
  // OUTPUTS: A [ChordEntry]. [ChordEntry.applied] carries the mark now in the document — the new
  //          one, or the updated one — and nothing else happens. [ChordEntryRefusal.noSuchBar] when
  //          the address names no bar. [ChordEntryRefusal.outsideChordBand] when the place is not on
  //          the bar's own chord line.
  //
  //          THE CHORD BAND IS A LAW HERE AND NOT A THRESHOLD, and this is the organ that enforces
  //          it. The owner ruled that a chord is written above the staff — on the bar's chord line —
  //          and that below the bar there is neither a chord nor a note («Аккорды надо запретить ниже
  //          такта»). So a place whose `offsetY` is further from the chord line than the line itself
  //          is tall is REFUSED, by name, and NOTHING IS WRITTEN: a refusal that left half a chord
  //          behind would be the same defect as a chord drawn where the rule says none may be. The
  //          band's height is the engraver's own `barHeight`, read from [LayoutStyle] so that the
  //          editor and the engraving cannot disagree about where the chord line ends.
  // KEYWORDS: chord-edit, coordinate, update-or-insert, chord-band, refusal-writes-nothing,
  //           named-outcome, undoable
  /// Sets the size of the bar at ([sectionId], [barIndex]), reporting whether it changed.
  bool setBarSize({
    required String sectionId,
    required int barIndex,
    required BarSize size,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null || bar.size == size) {
      return false;
    }
    apply(
      BarSizeSetEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        from: bar.size,
        to: size,
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
  // INPUTS: sectionId and barIndex — the bar to hang it on, in the model's own address. offsetX and
  //         offsetY — where the words sit, in bar-local logical pixels; the defaults put the cue at
  //         the bar's own left edge. text — the words, empty to insert and then type into (see the
  //         section note).
  // OUTPUTS: The new cue's identity, or null when the address names no bar — in which case nothing
  //          is appended and the document is untouched. The cue is appended at the END of the cue
  //          list, which is the end of the render order: a cue put on a bar now is drawn over cues
  //          that were already there, so the musician sees what they just wrote rather than the
  //          remark it landed on top of.
  //
  //          THE POSITION IS ONE NUMBER AND IT IS THE CALLER'S. There is no column argument any more:
  //          "the third beat, two pixels in" used to be an address plus an offset and is now simply
  //          where the words go, which is what the layout draws.
  // KEYWORDS: text-cue, insert, anchored, offset, render-order, undoable, coordinate
  /// Inserts a text cue at ([sectionId], [barIndex]) at the given offset, returning its id.
  String? insertTextCue({
    required String sectionId,
    required int barIndex,
    double offsetX = 0,
    double offsetY = 0,
    String text = '',
  }) {
    if (!offsetX.isFinite || !offsetY.isFinite) {
      return null;
    }
    if (_document.song.barAt(sectionId, barIndex) == null) {
      return null;
    }
    final TextCue cue = TextCue(
      id: _freshCueId(),
      place: AnchoredPlace(
        anchor: EventAnchor(sectionId: sectionId, bar: barIndex),
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

  // PURPOSE: Move a cue to another place in the music — another bar, another column of the same bar,
  //          or another offset within the column it already sits on — which is how a musician
  //          separates two remarks that landed on top of each other and how a cue written on the
  //          wrong bar is put right without retyping its words.
  // INPUTS: id — the cue to move. sectionId and barIndex — the bar to move it to. offsetX and
  //         offsetY — the new position, in bar-local logical pixels, which is the whole answer.
  // OUTPUTS: True when a move was appended, false when no cue carries [id], when the TARGET names
  //          no bar, and when the target place equals the one the cue already occupies. The target
  //          is deliberately not restricted to the cue's own bar or section: `textcue.move` carries a
  //          whole [AnchoredPlace] on each side and the reducer accepts any address, so a cue can be
  //          moved anywhere the song has a bar, and a rule confining it here would be a second,
  //          weaker copy of the model's own address rule. A call that moves a cue one bar has the
  //          same effect as a drag, which is why the app can offer the operation as buttons without
  //          a second event type.
  //
  //          THERE IS NO `beat` ARGUMENT ANY MORE. A move names where the words go and not which
  //          column owns them: the position IS the answer, and a caller that passes the cue's own
  //          stored offset is describing the move exactly.
  // KEYWORDS: text-cue, move, re-anchor, offset, any-bar, no-op-refusal, undoable
  /// Moves the cue [id] to ([sectionId], [barIndex]) at the given offset.
  bool moveTextCue(
    String id, {
    required String sectionId,
    required int barIndex,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final int index = _cueIndex(id);
    if (index < 0) {
      return false;
    }
    if (_document.song.barAt(sectionId, barIndex) == null) {
      return false;
    }
    final AnchoredPlace from = _document.textCues[index].place;
    final AnchoredPlace to = AnchoredPlace(
      anchor: EventAnchor(sectionId: sectionId, bar: barIndex),
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

  // --- The notes of the melodic staff ------------------------------------------------------------
  //
  // NOTE TO A CONCURRENT WRITER: this region is self-contained and is deliberately placed AFTER the
  // cue operations and BEFORE the ink ones, so that it touches neither `setBarMark`'s neighbour
  // (where the meter of a bar was added) nor anything above it. Every method and helper it needs
  // is inside it; nothing outside it was changed to make room.
  //
  // `note.insert`, `note.update` and `note.delete` have been in the catalogue since the melodic
  // staff was modelled, with a codec, a reducer and identity coverage (A51), and until these
  // methods existed NOTHING appended one: `Bar.melody` was a list no surface could write, while the
  // painter had a staff to draw it on (A57). They are here, next to the one writer, for the same
  // reason the form, repeat, mark and cue operations are (A35, A38, A41, A48): an operation a
  // musician needs must have an event to carry it, and an event must be written through [apply] so
  // that the log, the inverse and the undo stack stay one mechanism.
  //
  // WHY A MELODY NOTE IS ADDRESSED EXACTLY LIKE A CHORD. A note is placed at `(beat, step)` — the
  // same cell, and the same order-within-the-cell, that a chord uses — because that is what lets one
  // tap name the same place on the chord line and on the staff, and it is why `EventAnchor` carries
  // both numbers for both. Nothing here derives a note's position from a page coordinate: the caller
  // names the cell, the reducer places the note in it, and the engraver is the only thing that turns
  // either into a y position.
  //
  // WHY THE WHOLE NOTE IS CARRIED ON EVERY SIDE. As in [setBarMark] and the cue methods, each event
  // in this family carries the complete value it replaces and the complete value it writes — a
  // `NoteMark` with its pitch, its written value, its tie AND its address — so its inverse is a swap
  // and not a reconstruction. A delta would have to be replayed against whatever the bar holds when
  // the undo arrives, and the bar may have been changed by another edit, by the undo of a different
  // event, or by another device in between.
  //
  // WHY `step` EXISTS AND WHAT IT IS FOR. Several notes may share one beat — a chord in the melody,
  // or two voices — and the reducer keeps them a DENSE sequence: an insertion at a step pushes the
  // notes already AT OR AFTER that step one place up, the cell is then sorted by `(beat, step)`, and
  // a deletion closes the gap (see `_withNoteInserted` and `_withNoteRemoved` in
  // `document_reducer.dart`).
  //
  // `step` IS THE ORDER OF THE CELL IN TIME, AND IT IS NOT A PITCH. It is an ordinal — 0 for the
  // first note of the beat, 1 for the second — and the engraver draws it as one: `_notesOf` places
  // the note at `cellX + step * stride`, so step 0 is the LEFTMOST note of the cell and a higher
  // step is a later one. The staff has a second number that is also called `step` and is a different
  // thing entirely — the DIATONIC STAFF STEP of a pitch, from `melodyStepOf`, 0 meaning E4 on a
  // treble staff. That one decides how HIGH a notehead is drawn and this one decides how far RIGHT
  // it is drawn, so confusing them makes the writer look wrong when the engraver is and the other way
  // round: both are stated here because their names alone do not tell them apart.
  //
  // WHY THE DEFAULT IS NOW "AFTER THE LAST NOTE OF THE CELL" AND WAS "AT THE FRONT OF IT". The
  // reducer pushes a cell's later notes up when something is inserted before them, which is right
  // for an insertion at an address a caller names. It was also the DEFAULT, and that made the
  // ordinary gesture wrong: a musician writing four sixteenths into one beat inserts four times, and
  // an insert at step 0 makes each new note the FIRST of the cell — so C then D then E then F came
  // out F, E, D, C, and since the engraver draws step order left to right, the page showed the run
  // right to left while the musician had written it left to right. The measurement is A75's
  // `probe.writer.model bar=0 0.0:F4 0.1:E4 0.2:D4 0.3:C4` against the typed C D E F. The default is
  // therefore the APPEND, and a caller that wants a note in front of the cell's others says
  // `step: 0` — which is the same distinction the note palette already draws between its "New note"
  // row and the row of a note already written.

  // PURPOSE: Report every note a bar carries, in the order it is drawn, so a surface can list what is
  //          there and name which of them an edit acts on.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address.
  // OUTPUTS: The bar's notes ordered by x, as a fresh list a caller may keep. Empty when the bar
  //          holds none or the address names no bar.
  //
  //          THE WHOLE BAR AND NOT A WINDOW OF IT, which is the difference a coordinate model makes.
  //          A palette used to list "the notes of this beat" because a beat was the unit of address;
  //          now that a note's address IS its place, the honest list is the bar's melody in reading
  //          order, with the note the musician pointed at marked among them. Two notes at one x are
  //          both returned — a chord in the melody is several marks at one place — and nothing is
  //          filtered by a tolerance, so an edit that moves a note a pixel cannot make it vanish from
  //          the list it was chosen from.
  // KEYWORDS: melody, note-list, reading-order, coordinate, order-by-x, whole-bar
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

  // PURPOSE: Turn the melodic staff on or off — the musician's own switch over the one thing owner
  //          decision D29 says must be his to choose, and the whole of what D25 asks for here.
  // INPUTS: on — whether the chart declares a pitched staff. clef — the clef the staff is engraved
  //         in when it is turned on, defaulting to treble; it is ignored when [on] is false.
  // OUTPUTS: True when a `staff.set` event was appended, false when the chart already declares what
  //          was asked for, which is the no-op rule every other edit here follows ([updateSong],
  //          [setBarMark], [setVolta]): an event whose two sides are equal is a log row that changed
  //          nothing and an offer to undo an edit that did not happen.
  //
  //          THE PERCUSSION SLOT IS LEFT ALONE, deliberately: this switch is the melodic staff's, and
  //          turning the melody off must not take a drum part with it. It is restored exactly as it
  //          was, so undoing a toggle cannot invent or lose a staff.
  //
  //          WHY SWITCHING IT OFF IS NOT A DESTRUCTIVE OPERATION ON THE MUSIC. `Bar.melody` is
  //          untouched: the notes stay in the document, the engraver stops reserving their band, and
  //          turning the staff back on draws every one of them again. That is what makes this a
  //          view of the chart rather than a deletion from it, and it is why there is no
  //          confirmation step.
  // KEYWORDS: staff, staves, melody-staff, toggle, declared-staff, no-op-refusal, undoable, d25, d29
}
