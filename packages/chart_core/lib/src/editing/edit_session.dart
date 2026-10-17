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
/// What an attempt to write a chord did.
class ChordEntry {
  /// Creates an applied entry carrying the mark now in the document.
  const ChordEntry.applied(ChordMark this.mark) : refusal = null;

  /// Creates a refusal, which wrote nothing.
  const ChordEntry.refused(ChordEntryRefusal this.refusal) : mark = null;

  /// The chord the document now holds, or null when the attempt was refused.
  final ChordMark? mark;

  /// Why the attempt was refused, or null when it was applied.
  final ChordEntryRefusal? refusal;

  /// Whether a chord is now in the document.
  bool get applied => refusal == null;

  @override
  bool operator ==(Object other) =>
      other is ChordEntry && other.mark == mark && other.refusal == refusal;

  @override
  int get hashCode => Object.hash(mark, refusal);

  @override
  String toString() => applied
      ? 'ChordEntry.applied($mark)'
      : 'ChordEntry.refused(${refusal!.name})';
}

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
/// Returns [place] anchored to ([sectionId], [barIndex]), keeping its offsets.
AnchoredPlace _placeIn(String sectionId, int barIndex, AnchoredPlace place) =>
    AnchoredPlace(
      anchor: EventAnchor(sectionId: sectionId, bar: barIndex),
      offsetX: place.offsetX,
      offsetY: place.offsetY,
    );

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
  /// Puts [chord] into the bar at ([sectionId], [barIndex]) at ([offsetX], [offsetY]).
  ChordEntry applyChordAt({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double offsetY = 0,
    required Chord chord,
    ChordSize size = ChordSize.normal,
    double tolerance = chordHitTolerance,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return const ChordEntry.refused(ChordEntryRefusal.noSuchBar);
    }
    final double halfBand = chordBandHalfHeight;
    if (!offsetY.isFinite || offsetY.abs() > halfBand) {
      return const ChordEntry.refused(ChordEntryRefusal.outsideChordBand);
    }
    final ChordMark? existing = existingChordNear(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: offsetX,
      tolerance: tolerance,
    );
    if (existing == null) {
      final ChordMark inserted = ChordMark(
        place: AnchoredPlace(
          anchor: EventAnchor(sectionId: sectionId, bar: barIndex),
          offsetX: offsetX,
          offsetY: offsetY,
        ),
        chord: chord,
        size: size,
      );
      apply(ChordInsertEvent(docId: _docId, seq: _seq, chord: inserted));
      return ChordEntry.applied(inserted);
    }
    // The replacement keeps the existing chord's own place — including its height on the chord line —
    // and only the symbol and the engraving size change. A musician changing a chord is not asking
    // for it to move, and a chord that slid because its symbol got longer would be the application
    // rewriting a place he chose.
    final ChordMark updated = existing.copyWith(chord: chord, size: size);
    if (updated == existing) {
      return ChordEntry.applied(existing);
    }
    apply(
      ChordUpdateEvent(
        docId: _docId,
        seq: _seq,
        from: existing.copyWith(
          place: _placeIn(sectionId, barIndex, existing.place),
        ),
        to: updated.copyWith(
          place: _placeIn(sectionId, barIndex, updated.place),
        ),
      ),
    );
    return ChordEntry.applied(updated);
  }

  // PURPOSE: Write a chord into a bar from the SYMBOL a musician typed — `Dm7`, `G7`, `Cmaj7`,
  //          `F#7#11` — which is one action where the palette's root-then-quality sequence is
  //          three. Owner decision D28 names the musician's own habit: he calls a chord by writing
  //          it, so the surface that lets him type it is the one that matches how he thinks.
  // INPUTS: sectionId, barIndex, offsetX and offsetY — the place, as in [applyChordAt]. symbol — the
  //         text the musician typed, which is read in the chart's WRITTEN key because that is the key
  //         the document spells its chords in.
  // OUTPUTS: A [ChordSymbolParse] carrying the chord that was written, or the reason the text could
  //          not be read. On a read the chord goes into the document through [applyChordAt], which
  //          means the event is an insert or an update on exactly the terms a palette tap already
  //          uses. On a refusal NOTHING is written: a typed symbol that could not be read must not
  //          leave a half-chord behind, which is the rule the reducer and the codec follow
  //          everywhere else. A place outside the chord band is refused the same way and for the
  //          same reason — see [applyChordAt].
  // KEYWORDS: chord-symbol, typed-entry, one-action, chart-key, refusal-writes-nothing, undoable,
  //           chord-band, d28
  /// Reads [symbol] in the chart's written key and puts the chord it names at the given place.
  ChordSymbolParse applyChordSymbolAt({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double offsetY = 0,
    required String symbol,
    ChordSize size = ChordSize.normal,
  }) {
    final ChordSymbolParse parse = readTypedChord(symbol);
    final Chord? chord = parse.chord;
    if (chord == null) {
      return parse;
    }
    final ChordEntry entry = applyChordAt(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: offsetX,
      offsetY: offsetY,
      chord: chord,
      size: size,
    );
    return entry.applied
        ? parse
        : const ChordSymbolRefusal(ChordSymbolReason.cellNotWritable);
  }

  // PURPOSE: Remove the chord a musician pointed at, which is the palette's other action and the
  //          one the catalogue's `chord.delete` exists for.
  // INPUTS: sectionId, barIndex and offsetX — the bar and the place along it; tolerance — how near
  //         the place must be to a chord to name it. bar = the found mark's own place.
  // OUTPUTS: True when a chord was removed, false when the bar holds none that near or the address
  //          names no bar. The event carries the mark IN FULL, so undo restores the exact chord, its
  //          size and its height on the line.
  // KEYWORDS: chord-delete, palette-action, guard, whole-value, coordinate
  /// Removes the chord nearest ([sectionId], [barIndex], [offsetX]), reporting whether one was there.
  bool removeChordNear({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double tolerance = chordHitTolerance,
  }) {
    final ChordMark? existing = existingChordNear(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: offsetX,
      tolerance: tolerance,
    );
    if (existing == null) {
      return false;
    }
    apply(
      ChordDeleteEvent(
        docId: _docId,
        seq: _seq,
        removed: existing.copyWith(
          place: _placeIn(sectionId, barIndex, existing.place),
        ),
      ),
    );
    return true;
  }

  // PURPOSE: Answer which chord a musician pointed at, so the palette can open showing the chord he
  //          is about to change rather than an unrelated default.
  // INPUTS: sectionId, barIndex and offsetX — the bar and the place along it. tolerance — the reach,
  //         in bar-local logical pixels.
  // OUTPUTS: The nearest mark within [tolerance], or null when the bar is empty or holds nothing that
  //          near. Ties go to the earlier mark in model order, which is the order the bar was written
  //          in — the same rule `hit_test.dart`'s `nearestChordAt` applies, restated here because
  //          this library may not import the layout: the editor's reach and the palette's are one
  //          number, and the comparison is the same comparison.
  // KEYWORDS: chord-query, nearest, tolerance, coordinate, palette-open, null-when-empty
  /// Returns the chord nearest ([sectionId], [barIndex], [offsetX]), or null.
  ChordMark? existingChordNear({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double tolerance = chordHitTolerance,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return null;
    }
    ChordMark? found;
    double best = tolerance;
    for (final ChordMark placed in bar.chords) {
      final double distance = (placed.offsetX - offsetX).abs();
      if (found == null || distance < best) {
        if (distance <= tolerance) {
          found = placed;
          best = distance;
        }
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

  // --- A SELECTION: copy, paste and transpose a fragment ----------------------------------------
  //
  // The owner named this workflow as the purpose of the product (D35): "скопировать секцию из 16
  // тактов, вставить их в конец и транспонировать выбранное на полтона вверх", and added that it
  // must work "вместе с поддержкой письма". D36 fixed two of its properties: the selection is an
  // ADDRESS in the interface and never an entity of the document, and a paste must cost ONE undo.
  //
  // WHAT IS IN THE LOG AND WHAT IS NOT. Copy writes nothing: it reads the document into a [ChartClip]
  // and changes no state, so there is no event to undo and nothing in the file. Paste writes one
  // `bars.insert` (a run of bars and its ink) or one `bars.replace` (a window of cells inside one
  // bar). Transpose writes one `bars.replace` covering the whole selected run. Each of those is a
  // single event, so each is a single press of undo — the price A69 had to name for the eraser is not
  // paid again here.
  //
  // WHY THE TRANSPOSITION OF A SELECTION IS NOT A MODULATION, AND WHY THAT IS A DECISION AND NOT AN
  // OVERSIGHT. The chart's key is what the band calls the tune and what the chart is filed under; the
  // key grid exists to show the whole tune in another key (D14), and a selection transposition is a
  // local edit of some bars — a chord that came out too low, a section the singer wants a semitone
  // up. Relabelling the whole chart for that would tell the musician the tune is in a key it is not,
  // would move the twelve keys the grid offers, and would leave the bars OUTSIDE the selection
  // disagreeing with the label. So the key stays, the chords and the melody of the selected bars
  // move, and everything else in the chart is untouched.
  //
  // AND WHAT HAPPENS TO THE HANDWRITING, SAID PLAINLY BECAUSE IT IS THE ONE THING THAT CANNOT MOVE.
  // A stroke is a picture: its points are pixels measured from a bar, and a semitone is not a
  // distance in pixels. `transposition.dart` never sees a stroke and this file does not invent a
  // scale for one. D37 requires that the file keep BOTH layers and that no layer be silently
  // discarded, so the ink is neither transposed (impossible) nor hidden (worse than leaving it: a
  // musician who cannot see his own handwriting will conclude it was lost). It STAYS exactly where it
  // was drawn, the structured layer under it moves, and the numbers are reported to the surface —
  // `SelectionTransposition.strokesKept` — so the application can say so in words. That leaves a bar
  // whose chord line and handwriting disagree, which is the honest state of two layers that were
  // always two: the ink is the source (D37 point 2) and it is still there to be erased by the
  // musician if he wants it gone.

  // PURPOSE: Take a copy of a fragment — its bars and the ink that hangs on them — into a value the
  //          musician can paste somewhere else, without touching the document.
  // INPUTS: selection — the fragment, from a hit test or from the interface's own address.
  // OUTPUTS: The [ChartClip], or null when the selection names no bar of the song. Nothing is
  //          appended to the log and no undo step is created, because copying changes nothing: the
  //          clip is interface state, exactly as the selection is (D36), and only the RESULT of an
  //          operation reaches the op-log.
  //
  //          THE CLIP CARRIES WHOLE BARS. Its chords, melody, percussion, metre, size, signs, marks
  //          and staff text are inside the [Bar] value and therefore cannot be forgotten one by one;
  //          and its ink, whose anchors are rebased onto the fragment so a paste is arithmetic. See
  //          `selection_clip.dart` for what is deliberately NOT carried (a text cue) and why.
  // KEYWORDS: copy, selection-copy, clipboard, ink-carried, whole-bars, reads-only, no-event
  /// Returns the clip a copy of [selection] takes, or null when it names no bar.
  ChartClip? copySelection(ChartSelection selection) => chartClipOf(
    song: _document.song,
    strokes: _document.strokes,
    selection: selection,
  );

  // PURPOSE: Put a copied fragment into the chart at the place the musician chose, as ONE edit.
  // INPUTS: at — where it should go, in the interface's own address. clip — what copy produced.
  // OUTPUTS: A [ClipPasteOutcome]. [ClipPasteOutcome.pasted] means exactly one event was appended,
  //          carrying the whole run (bars AND ink) and — when the insertion lands in the middle of a
  //          section — the re-addressing of every anchored object the insertion pushes along, so the
  //          ink of the bars that move stays on the music that moved and the ink of the pasted bars
  //          lands on the pasted bars. Every other outcome is a refusal that appended nothing and
  //          left the document as it was, so a musician cannot lose a bar to a paste that failed.
  //
  //          WHERE IT LANDS, AND WHY THAT IS THE DECIDED BEHAVIOUR. A run of bars is INSERTED after
  //          the last bar of the target selection: existing bars are pushed later, nothing is
  //          destroyed, and "paste at the end of the section" is the same gesture on the section's
  //          last bar as paste anywhere else. Insert is chosen over replace because replace would
  //          silently destroy a bar the musician wanted — the one outcome the requirement forbids —
  //          and over refuse because refusing a legal address would make the gesture unusable in the
  //          middle of a chart, which is where a musician most often wants it.
  //
  //          A WINDOW IS DIFFERENT, and its decided behaviour is REPLACE, not insert: a window names a
  //          stretch of one bar, and the marks the paste lands on are overwritten rather than pushed
  //          aside, because pushing them aside would change a rhythm the musician did not ask to
  //          change. The whole previous bar travels in the event, so one undo puts it back exactly.
  //          See [_pasteWindow] for what a window is now that it is a coordinate range.
  // KEYWORDS: paste, insert-not-replace, one-undo, ink-reanchored, moves-carried, typed-refusal,
  //           no-partial-effect, d35, d36
  /// Pastes [clip] at [at], reporting what happened.
  ClipPasteOutcome pasteClip({
    required ChartSelection at,
    required ChartClip clip,
  }) {
    final Section? section = _document.song.sectionById(at.sectionId);
    if (section == null) {
      return ClipPasteOutcome.noSuchSection;
    }
    if (at.firstBar < 0 || at.firstBar >= section.bars.length) {
      return ClipPasteOutcome.noSuchBar;
    }
    return switch (clip.depth) {
      SelectionDepth.bars => _pasteBars(at: at, clip: clip, section: section),
      SelectionDepth.window => _pasteWindow(
        at: at,
        clip: clip,
        section: section,
      ),
    };
  }

  // PURPOSE: Insert a run of whole bars — and its ink — after the target bar, as one event.
  // INPUTS: at — the target, whose LAST bar the run goes after. clip — a bar-deep clip. section —
  //         the target section, already resolved by [pasteClip].
  // OUTPUTS: [ClipPasteOutcome.pasted] when the event was appended. The pasted bars are the clip's
  //          bars unchanged — a copy of a bar IS that bar, and giving the copy a different metre or
  //          size would be inventing a bar the musician did not copy — and they land at
  //          `at.lastBar + 1`, which is the section's bar count when the target is the last bar.
  //
  //          THE STROKES ARE RE-ANCHORED AND GIVEN FRESH IDENTITIES, which is the point the owner
  //          asked for twice. A stroke's anchor names `(section, bar, beat?)`, so the copy's anchor
  //          is the destination section, the destination bar offset by the stroke's own offset
  //          inside the fragment, and the same beat. The identity has to be NEW because a document's
  //          stroke ids are unique and the eraser removes by id: two strokes sharing one id would be
  //          one row in the store and one target for the eraser, and erasing one copy would take the
  //          other with it. The minted ids travel in the event, so replay builds the same document.
  // KEYWORDS: paste-bars, insert-after, ink-reanchor, fresh-stroke-id, moves, one-event
  ClipPasteOutcome _pasteBars({
    required ChartSelection at,
    required ChartClip clip,
    required Section section,
  }) {
    final int index = at.lastBar + 1;
    if (index > section.bars.length) {
      return ClipPasteOutcome.noSuchRun;
    }
    final Set<String> taken = <String>{
      for (final InkStroke stroke in _document.strokes) stroke.id,
    };
    final List<InkStroke> pastedStrokes = <InkStroke>[
      for (final InkStroke stroke in clip.strokes)
        InkStroke(
          id: _freshStrokeId(stroke.id, taken),
          tool: stroke.tool,
          color: stroke.color,
          size: stroke.size,
          // Only the bar is rebased. The stroke's own points are bar-local, so they travel
          // unchanged and the copy lands in the same place inside its new bar.
          anchor: EventAnchor(
            sectionId: at.sectionId,
            bar: index + stroke.anchor.bar,
          ),
          points: stroke.points,
        ),
    ];
    apply(
      BarsInsertEvent(
        docId: _docId,
        seq: _seq,
        sectionId: at.sectionId,
        index: index,
        bars: clip.bars,
        strokes: pastedStrokes,
        moves: _movesForInsertion(at.sectionId, index, clip.bars.length),
      ),
    );
    return ClipPasteOutcome.pasted;
  }

  // PURPOSE: Write a window of x into the target bar as one event, moving what the copy took onto
  //          the place the musician pointed at.
  // INPUTS: at — the target, which must name a place inside a bar. clip — a window-deep clip.
  //         section — the target section, already resolved.
  // OUTPUTS: [ClipPasteOutcome.pasted] when the event was appended;
  //          [ClipPasteOutcome.needsCell] when the target names no place;
  //          [ClipPasteOutcome.noSuchRun] when the clip is not one bar's window.
  //
  //          A PASTE IS A TRANSLATION, AND THERE IS NOTHING ELSE IN IT. Every mark of the source bar
  //          whose own x lies in the copied window moves by `target - source`; every mark of the
  //          target bar whose x lies in the target window is REMOVED first, so the paste replaces
  //          what it lands on rather than stacking on top of it. What is outside both windows is
  //          untouched, on both sides.
  //
  //          THE OLD RULE THAT REFUSED A WINDOW THE BAR COULD NOT HOLD IS GONE, and its removal is a
  //          consequence of the model rather than a relaxation. A bar's width follows its content, so
  //          a window written past the barline makes the bar wider instead of spilling off it, and
  //          there is no metre to check a width against. `windowDoesNotFit` remains in the enum for
  //          callers that branch on it; nothing here produces it.
  //
  //          THE INK MOVES WITH ITS WINDOW: a stroke whose first point lies in the source window is
  //          translated by the same distance, its points being bar-local already. That is the whole
  //          of "handwriting travels with its bar" applied to a window (owner decision D32).
  // KEYWORDS: paste-window, translation, replace-window, no-metre, ink-translated, one-event
  ClipPasteOutcome _pasteWindow({
    required ChartSelection at,
    required ChartClip clip,
    required Section section,
  }) {
    final double? targetX = at.firstX;
    final double? targetEnd = at.lastX;
    if (targetX == null || targetEnd == null) {
      return ClipPasteOutcome.needsCell;
    }
    if (clip.bars.length != 1) {
      // A window clip is always taken from one bar (`ChartSelection.window` cannot span bars), so
      // this is a clip that was not built by `chartClipOf` and cannot be placed.
      return ClipPasteOutcome.noSuchRun;
    }
    final Bar target = section.bars[at.firstBar];
    final Bar source = clip.bars.single;
    final double sourceFrom = clip.source.firstX ?? 0;
    final double sourceTo = clip.source.lastX ?? 0;
    final double shift = targetX - sourceFrom;
    bool inSource(double x) => x >= sourceFrom && x < sourceTo;
    bool inTarget(double x) => x >= targetX && x < targetEnd;

    final List<ChordMark> chords = <ChordMark>[
      for (final ChordMark placed in target.chords)
        if (!inTarget(placed.offsetX)) placed,
      for (final ChordMark placed in source.chords)
        if (inSource(placed.offsetX))
          placed.copyWith(
            place: AnchoredPlace(
              anchor: EventAnchor(sectionId: at.sectionId, bar: at.firstBar),
              offsetX: placed.offsetX + shift,
              offsetY: placed.place.offsetY,
            ),
          ),
    ]..sort(_compareChordAddresses);
    final List<NoteMark> melody = <NoteMark>[
      for (final NoteMark note in target.melody)
        if (!inTarget(note.offsetX)) note,
      for (final NoteMark note in source.melody)
        if (inSource(note.offsetX))
          note.copyWith(
            place: AnchoredPlace(
              anchor: EventAnchor(sectionId: at.sectionId, bar: at.firstBar),
              offsetX: note.offsetX + shift,
              offsetY: note.place.offsetY,
            ),
          ),
    ]..sort(_compareNoteAddresses);
    final Bar replaced = target.copyWith(chords: chords, melody: melody);
    final Set<String> taken = <String>{
      for (final InkStroke stroke in _document.strokes) stroke.id,
    };
    final List<InkStroke> pastedStrokes = <InkStroke>[
      for (final InkStroke stroke in clip.strokes)
        InkStroke(
          id: _freshStrokeId(stroke.id, taken),
          tool: stroke.tool,
          color: stroke.color,
          size: stroke.size,
          anchor: EventAnchor(sectionId: at.sectionId, bar: at.firstBar),
          points: <InkPoint>[
            for (final InkPoint point in stroke.points)
              InkPoint(x: point.x + shift, y: point.y, w: point.w, t: point.t),
          ],
        ),
    ];
    apply(
      BarsReplaceEvent(
        docId: _docId,
        seq: _seq,
        sectionId: at.sectionId,
        index: at.firstBar,
        from: <Bar>[target],
        to: <Bar>[replaced],
        addedStrokes: pastedStrokes,
      ),
    );
    return ClipPasteOutcome.pasted;
  }

  // PURPOSE: Move the chords and the melody of a SELECTED RUN of bars by an interval, leaving the
  //          rest of the chart — and the chart's key — exactly as they were, as one edit.
  // INPUTS: selection — the run, which must be bar-deep. semitones — the signed interval, normally
  //         +1 for "a semitone up".
  // OUTPUTS: A [SelectionTransposition] reporting what happened. [SelectionTransposeOutcome.applied]
  //          means ONE event was appended covering every bar of the run, so a sixteen-bar
  //          transposition is one press of undo. The key is untouched, for the reason stated in the
  //          section header above, and the ink is untouched for the reason stated there too — the
  //          count of strokes left in place is reported so the surface can say it.
  //
  //          A BAR WITH NO CHORD AND NO NOTE IS COPIED INTO THE EVENT UNCHANGED rather than dropped
  //          from it, because the event describes a RUN: dropping a bar would make the run
  //          non-contiguous and its inverse could not put the bars back where they were. Such a bar
  //          contributes nothing to [barsChanged], and a run in which NOTHING changes appends no
  //          event at all.
  // KEYWORDS: transpose-selection, bar-run, key-unchanged, melody-moves, ink-left-alone, one-undo,
  //           no-op-refusal, d35, d37
  /// Transposes the selected bars' chords and melody, reporting what happened.
  SelectionTransposition transposeSelection({
    required ChartSelection selection,
    required int semitones,
  }) {
    final Section? section = _document.song.sectionById(selection.sectionId);
    final List<InkStroke> ink = strokesOf(selection, _document.strokes);
    if (section == null) {
      return SelectionTransposition(
        selection: selection,
        semitones: semitones,
        barsTotal: 0,
        barsChanged: 0,
        strokesKept: ink.length,
        outcome: SelectionTransposeOutcome.noSuchSection,
      );
    }
    if (selection.isWindow) {
      return SelectionTransposition(
        selection: selection,
        semitones: semitones,
        barsTotal: selection.barCount,
        barsChanged: 0,
        strokesKept: ink.length,
        outcome: SelectionTransposeOutcome.beatsOnly,
      );
    }
    final List<Bar> bars = selection.barsIn(_document.song);
    if (bars.isEmpty) {
      return SelectionTransposition(
        selection: selection,
        semitones: semitones,
        barsTotal: 0,
        barsChanged: 0,
        strokesKept: ink.length,
        outcome: SelectionTransposeOutcome.noSuchSection,
      );
    }
    final Key key = _document.song.key;
    final List<Bar> moved = <Bar>[
      for (final Bar bar in bars)
        transposedBar(bar, semitones, writtenKey: key, targetKey: key),
    ];
    int changed = 0;
    for (int index = 0; index < bars.length; index++) {
      if (moved[index] != bars[index]) {
        changed++;
      }
    }
    if (changed == 0) {
      return SelectionTransposition(
        selection: selection,
        semitones: semitones,
        barsTotal: bars.length,
        barsChanged: 0,
        strokesKept: ink.length,
        outcome: SelectionTransposeOutcome.nothingToTranspose,
      );
    }
    apply(
      BarsReplaceEvent(
        docId: _docId,
        seq: _seq,
        sectionId: selection.sectionId,
        index: selection.firstBar,
        from: bars,
        to: moved,
      ),
    );
    return SelectionTransposition(
      selection: selection,
      semitones: semitones,
      barsTotal: bars.length,
      barsChanged: changed,
      strokesKept: ink.length,
      outcome: SelectionTransposeOutcome.applied,
    );
  }

  // PURPOSE: Work out which anchored objects an insertion at [index] pushes along with their bars,
  //          so the event can carry the re-addressing and its inverse can undo it exactly.
  // INPUTS: sectionId — the section being inserted into. index — where the run lands. count — how
  //         many bars are inserted, which is how far everything at or after [index] moves.
  // OUTPUTS: One [AnchorMove] per anchored object — stroke, annotation or text cue — whose bar is at
  //          or after [index]. The list is in document order, so two identical edits produce
  //          identical events.
  //
  //          WHY EVERY COLLECTION IS INCLUDED AND NOT ONLY THE INK. The address scheme is one
  //          mechanism (see `anchor.dart`), and an object left behind by an insertion is on the wrong
  //          bar whatever kind it is. The ink is the one the owner asked about, but a cue that
  //          ended up over the pasted bars would be just as wrong and just as silent.
  // KEYWORDS: anchor-readdress, moves, strokes, annotations, text-cues, deterministic-order
  List<AnchorMove> _movesForInsertion(String sectionId, int index, int count) {
    final List<AnchorMove> moves = <AnchorMove>[];
    for (final InkStroke stroke in _document.strokes) {
      if (stroke.anchor.sectionId != sectionId || stroke.anchor.bar < index) {
        continue;
      }
      moves.add(
        AnchorMove(
          kind: AnchorMoveKind.stroke,
          id: stroke.id,
          from: stroke.anchor,
          to: EventAnchor(
            sectionId: stroke.anchor.sectionId,
            bar: stroke.anchor.bar + count,
          ),
        ),
      );
    }
    for (final Annotation mark in _document.annotations) {
      if (mark.place.anchor.sectionId != sectionId ||
          mark.place.anchor.bar < index) {
        continue;
      }
      moves.add(
        AnchorMove(
          kind: AnchorMoveKind.annotation,
          id: mark.id,
          from: mark.place.anchor,
          to: EventAnchor(
            sectionId: mark.place.anchor.sectionId,
            bar: mark.place.anchor.bar + count,
          ),
        ),
      );
    }
    for (final TextCue cue in _document.textCues) {
      if (cue.place.anchor.sectionId != sectionId ||
          cue.place.anchor.bar < index) {
        continue;
      }
      moves.add(
        AnchorMove(
          kind: AnchorMoveKind.textCue,
          id: cue.id,
          from: cue.place.anchor,
          to: EventAnchor(
            sectionId: cue.place.anchor.sectionId,
            bar: cue.place.anchor.bar + count,
          ),
        ),
      );
    }
    return moves;
  }

  // PURPOSE: Mint an identity for a pasted stroke that no stroke in the document already carries,
  //          so the eraser and the store can tell the copy from the original.
  // INPUTS: base — the source stroke's id, which already names its anchor and start time and is
  //         therefore readable. taken — the ids the document holds, which this function adds to so
  //         two strokes pasted in one gesture cannot collide with each other.
  // OUTPUTS: A fresh id of the form `<base>~copy-<n>`. Deterministic given the document and the clip,
  //          which is what lets the id travel inside the event and replay to the same document.
  // KEYWORDS: stroke-id, fresh-identity, deterministic, readable, collision-free
  String _freshStrokeId(String base, Set<String> taken) {
    int ordinal = 1;
    while (taken.contains('$base~copy-$ordinal')) {
      ordinal++;
    }
    final String id = '$base~copy-$ordinal';
    taken.add(id);
    return id;
  }

  // PURPOSE: Order two chord placements by their address, so a bar rebuilt by a window paste holds
  //          its chords in the same order any other edit would leave them in.
  // INPUTS: left and right — the two placements.
  // OUTPUTS: A negative, zero or positive integer, as a comparator must return.
  // KEYWORDS: chord-address, ordering, deterministic-rebuild
  int _compareChordAddresses(ChordMark left, ChordMark right) =>
      left.offsetX.compareTo(right.offsetX);

  // PURPOSE: Order two melody notes by their address, for the same reason as
  //          [_compareChordAddresses].
  // INPUTS: left and right — the two placements.
  // OUTPUTS: A negative, zero or positive integer.
  // KEYWORDS: note-address, ordering, deterministic-rebuild
  int _compareNoteAddresses(NoteMark left, NoteMark right) =>
      left.offsetX.compareTo(right.offsetX);

  // --- Sections: the form a chart is made of -----------------------------------------------
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

  // --- The meter of a bar ----------------------------------------------------------------------
  //
  // A bar's meter is READ by everything downstream already: `Bar.timeSignature` is a field of every
  // bar, `layout_engine.dart` takes the bar's cell count from `cellsPerBar`, and the importer writes
  // a meter change it reads inside a chart. Until this method existed NOTHING could set one, so a
  // chart could arrive in 3/4 and no surface could put it there, change it, or give the next bar the
  // meter the tune moved into. That is the half of D22 the catalogue was missing.
  //
  // WHY THE WHOLE METER IS CARRIED ON BOTH SIDES. A meter is two figures and the model holds no
  // neutral one: `4/4` is a meter a musician may have chosen deliberately, not the absence of a
  // meter, so there is no value that means "leave it alone" and no way to express a change of only
  // the denominator. `MeterSetEvent` therefore records what the bar had and what it takes, exactly
  // as `repeat.set` records all four repeat fields.
  //
  // WHAT THE TWO REFUSALS ARE. An address naming no bar, and a meter equal to the one the bar
  // already carries. The second is the rule every edit here follows (see [setVolta], [setBarMark]):
  // an event whose two sides are equal is a log row that changed nothing and an offer to undo an
  // edit that did not happen. The FIGURES are not validated here — that is
  // [parseMeterFigures]'s job at the surface where they are typed — and no meter is refused for
  // being unusual, because D22 is explicit that 15/8 and whatever else a jazz musician writes must
  // be expressible.
  //
  // WHY THERE IS ALSO A RANGE FORM, AND WHY IT DOES NOT CHANGE THE STORAGE. The owner's own words
  // ask for zones — "не протыкивать каждый такт ... скорее задавать ЗОНАМИ" — so the surface works
  // on a run of bars. The run is a GESTURE and the bar stays the unit: [setTimeSignatureRange]
  // appends one `meter.set` per bar that actually changed, each carrying that bar's own previous
  // meter, exactly as the single-bar form does. Nothing here stores a zone, and no bar's meter
  // depends on the zone it was set through — which is what keeps a bar inserted at the edge of a
  // zone from inheriting a value from a range that no longer covers it.

  // PURPOSE: Set the meter written on one bar — the M/N a jazz chart changes mid-tune — through the
  //          operation log, so the change is undoable and survives a save.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. meter — the meter the bar
  //         should carry. It must be a value the model can hold; the typed-figures reader that
  //         produces one from a keyboard is [parseMeterFigures], and it is deliberately a separate
  //         step so that the refusal of `0/0` happens at the form rather than here.
  // OUTPUTS: True when an event was appended, false when the address names no bar or when the bar
  //          already carries exactly that meter. The event carries the complete meter on both
  //          sides, read from the bar here, so its inverse restores the bar exactly.
  // KEYWORDS: meter-set, time-signature, whole-value, no-op-refusal, undoable, d22
  /// Sets the meter of the bar at ([sectionId], [barIndex]), reporting whether it changed.
  bool setTimeSignature({
    required String sectionId,
    required int barIndex,
    required TimeSignature meter,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null || bar.timeSignature == meter) {
      return false;
    }
    apply(
      MeterSetEvent(
        docId: _docId,
        seq: _seq,
        sectionId: sectionId,
        barIndex: barIndex,
        from: bar.timeSignature,
        to: meter,
      ),
    );
    return true;
  }

  // PURPOSE: Set the meter written on a RUN OF BARS at once — the zone a jazz musician thinks in
  //          ("eight bars of this, then the bridge") rather than thirty-two separate decisions.
  // INPUTS: range — the run of bars, in its own section, from [resolveBarRange] or built by a
  //         caller that already knows the bars exist. meter — the meter every bar in the run should
  //         carry.
  // OUTPUTS: How many bars actually changed. A bar already in [meter] is SKIPPED rather than
  //          re-recorded, so a zone that overlaps a meter already in force appends rows only for
  //          the bars it really changes, and a zone that changes nothing appends nothing and
  //          reports zero. [range] is not validated here — [resolveBarRange] is the validating door
  //          and reports an out-of-range run to the surface that asked for it.
  //
  //          WHY ONE EVENT PER BAR AND NOT A COMPOSITE "ZONE" EVENT. `Bar.timeSignature` is the
  //          storage and the range is only the gesture. A composite event would be a second way to
  //          say what one bar's meter is, and its `from` side would have to be a list that no
  //          single-bar edit could produce. The cost is named rather than hidden: undoing a zone
  //          takes one undo per bar that changed, because this session's undo stack holds one event
  //          per step and this method deliberately does not rework that shared machinery.
  // KEYWORDS: meter-set-range, zone, per-bar-events, undo-per-bar, no-op-skip, gesture-not-storage,
  //           d22
  /// Sets [meter] on every bar of [range], reporting how many bars changed.
  int setTimeSignatureRange({
    required BarRange range,
    required TimeSignature meter,
  }) {
    int changed = 0;
    for (final int barIndex in range.barIndices) {
      if (setTimeSignature(
        sectionId: range.sectionId,
        barIndex: barIndex,
        meter: meter,
      )) {
        changed++;
      }
    }
    return changed;
  }

  // --- How much room a bar is given ------------------------------------------------------------
  //
  // The owner's own words for this operation: «менять видимый размер каждого конкретного такта, чтобы
  // уместить больше внутри». A jazz chart's bars are not equal — one holds a single chord and four
  // beats, the next holds six chords, a run of eighths and an accidental — and an engraving that
  // gives every bar the width its own content measures starves the busy one. `Bar.size` is where the
  // musician's answer to that is stored; this method is the only way it is written.
  //
  // WHY THE WHOLE SIZE IS CARRIED ON BOTH SIDES. Like the meter and the repeat signs, a size has no
  // neutral value that means "leave it alone": an event carrying only the new factor could not
  // describe its own reversal, and undo would have to reconstruct what the bar held. The event
  // therefore records the factor before and after, read from the bar here, and its inverse is a
  // swap.
  //
  // WHY THE REFUSALS ARE WHAT THEY ARE. An address that names no bar, and a size equal to the one
  // the bar already carries — the second is the rule every edit here follows (see [setBarMark],
  // [setTimeSignature], [setVolta]): an event whose two sides are equal is a log row that changed
  // nothing and an offer to undo an edit that did not happen. A value the model cannot hold is NOT
  // refused here, because [BarSize] cannot be constructed with one; a value arriving from a file is
  // checked by the reader that decodes it.

  // PURPOSE: Set how much room the page gives one bar, through the operation log, so a bar holding
  //          six chords and a run of eighths can be drawn wider than the empty bar beside it — and
  //          so that widening is undoable and survives a save.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. size — the size the bar
  //         should carry, from [BarSize.ladder] or from anywhere else the model accepts; it is a
  //         multiple of the bar's own natural width and is at least [BarSize.natural].
  // OUTPUTS: True when an event was appended, false when the address names no bar or when the bar
  //          already carries exactly that size. The event carries the complete size on both sides,
  //          read from the bar here, so its inverse restores the bar exactly.
  //
  //          A REFUSED OR IMPOSSIBLE SIZE HAS NO PARTIAL EFFECT: nothing is appended, the document
  //          is untouched, and the caller is told by the boolean. The engine applies the factor in
  //          one place, so there is no second half of this operation that could be left behind.
  // KEYWORDS: bar-size, width, whole-value, no-op-refusal, undoable, the-musician-decides
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
  /// Returns the bar's notes, ordered by x.
  List<NoteMark> notesInBar({
    required String sectionId,
    required int barIndex,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return const <NoteMark>[];
    }
    return <NoteMark>[...bar.melody]..sort(_compareNoteAddresses);
  }

  // PURPOSE: Answer which single note a musician pointed at, so an edit can name it.
  // INPUTS: As [notesNear].
  // OUTPUTS: The note nearest [offsetX] within [tolerance], or null. Ties go to the earlier note in
  //          model order — the same rule [existingChordNear] follows, so a tap names one mark the
  //          same way on both surfaces.
  // KEYWORDS: melody, note-query, nearest, tolerance, tie-break, null-when-none
  /// Returns the note nearest ([sectionId], [barIndex], [offsetX]), or null.
  NoteMark? existingNoteNear({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double tolerance = chordHitTolerance,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null) {
      return null;
    }
    NoteMark? found;
    double best = tolerance;
    for (final NoteMark note in bar.melody) {
      final double distance = (note.offsetX - offsetX).abs();
      if (found == null || distance < best) {
        if (distance <= tolerance) {
          found = note;
          best = distance;
        }
      }
    }
    return found;
  }

  // PURPOSE: Put a note a musician chose at a place on the melodic staff — the edit the note palette
  //          exists to make, and the way `Bar.melody` is written from a surface.
  // INPUTS: sectionId and barIndex — the bar, in the model's own address. offsetX — WHERE ALONG THE
  //         BAR the notehead stands, in bar-local logical pixels; a note's place is its centre, which
  //         is the number the ink reader measures and the number the engraver draws at. pitch — the
  //         written pitch and octave, which is the note's HEIGHT. value — the written duration.
  //         tiedToNext — whether the note is tied into the next one as well as inserted.
  // OUTPUTS: True when an insertion was appended, false in two cases, neither of which writes
  //          anything. A non-finite or NEGATIVE [offsetX] — a place left of the bar is not in the bar,
  //          and drawing it there would put ink over the previous barline; and a [value] longer than
  //          the whole bar, which is a note that cannot fit in the bar whatever its x. The input
  //          document is not mutated in either case: the guard runs before [apply].
  //
  //          WHAT NO LONGER HAPPENS, AND WHY ITS ABSENCE IS THE POINT. There is no beat bound and the
  //          metre is not consulted: a bar's width follows its content, so a note written past the
  //          last thing in the bar WIDENS the bar rather than being refused for falling outside a
  //          grid. And there is no `step`: several notes at one x are several marks at one place, and
  //          the order they are drawn in is their x — see `placeMelodyStaff`, which sorts by it.
  // KEYWORDS: melody, note-insert, coordinate, wheel-no-step, append, guard, undoable
  /// Inserts [pitch] of [value] at ([sectionId], [barIndex], [offsetX]).
  bool insertNote({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    required PitchedNote pitch,
    required NoteValue value,
    bool tiedToNext = false,
  }) {
    final Bar? bar = _document.song.barAt(sectionId, barIndex);
    if (bar == null || !offsetX.isFinite || offsetX < 0) {
      return false;
    }
    if (value.compareDuration(_wholeBarValue(bar)) > 0) {
      return false;
    }
    apply(
      NoteInsertEvent(
        docId: _docId,
        seq: _seq,
        note: NoteMark(
          place: AnchoredPlace(
            anchor: EventAnchor(sectionId: sectionId, bar: barIndex),
            offsetX: offsetX,
          ),
          pitch: pitch,
          value: value,
          tiedToNext: tiedToNext,
        ),
      ),
    );
    return true;
  }

  // PURPOSE: Change a note already written — its pitch, its duration or its tie — which is the edit
  //          a musician makes far more often than placing a new one, because a wrong note is
  //          corrected rather than deleted and re-placed.
  // INPUTS: sectionId, barIndex and offsetX — the place of the note to change, with [tolerance] as
  //         the reach. This method does NOT move the note: an update changes the pitch, the duration
  //         or the tie, and the note stays written where it was, which `NoteUpdateEvent` asserts by
  //         requiring both sides to name one bar. pitch, value and tiedToNext — the new written form;
  //         null leaves that field as the note already has it.
  // OUTPUTS: True when an update was appended, false in two cases. The place names no note; or the
  //          new form is EQUAL to the old one field by field, which is the rule every other edit here
  //          follows (see [setBarMark], [setVolta], [updateSong]): an event whose two sides are equal
  //          is a log row that changed nothing and an offer to undo an edit that did not happen.
  //          Equality is `NoteMark ==`, so the comparison is the whole value rather than a boolean
  //          about the one field named.
  // KEYWORDS: melody, note-update, before-after, no-op-refusal, address-stable, undoable
  /// Replaces the note nearest ([sectionId], [barIndex], [offsetX]) with the given form.
  bool updateNote({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double tolerance = chordHitTolerance,
    PitchedNote? pitch,
    NoteValue? value,
    bool? tiedToNext,
  }) {
    final NoteMark? from = existingNoteNear(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: offsetX,
      tolerance: tolerance,
    );
    if (from == null) {
      return false;
    }
    final NoteMark to = from.copyWith(
      pitch: pitch ?? from.pitch,
      value: value ?? from.value,
      tiedToNext: tiedToNext ?? from.tiedToNext,
    );
    if (to == from) {
      return false;
    }
    apply(
      NoteUpdateEvent(
        docId: _docId,
        seq: _seq,
        from: from.copyWith(place: _placeIn(sectionId, barIndex, from.place)),
        to: to,
      ),
    );
    return true;
  }

  // PURPOSE: Tie a note into the next one, or untie it — the gesture that writes a single sound
  //          across a barline, and the only frame `tiedToNext` has in the model.
  // INPUTS: sectionId, barIndex and offsetX — the note, with [tolerance] as the reach. tied — true to
  //         tie it forward, false to untie it.
  // OUTPUTS: True when an update was appended, false when the place names no note and false when the
  //          note already carries that flag. Both directions are one field of one note, which is why
  //          there is no second event: the model keeps the tie on the EARLIER note alone
  //          (`NoteMark.tiedToNext`), so [updateNote] already writes either way.
  // KEYWORDS: melody, tie, tie-forward, toggle, one-field, undoable
  /// Sets or clears the tie on the note nearest the given place, reporting whether it changed.
  bool setNoteTie({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double tolerance = chordHitTolerance,
    required bool tied,
  }) {
    final NoteMark? from = existingNoteNear(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: offsetX,
      tolerance: tolerance,
    );
    if (from == null || from.tiedToNext == tied) {
      return false;
    }
    return updateNote(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: from.offsetX,
      tolerance: 0,
      tiedToNext: tied,
    );
  }

  // PURPOSE: Take a note off the staff, which is the half `note.insert`'s inverse needs and the
  //          gesture that removes a note a musician put in the wrong place.
  // INPUTS: sectionId, barIndex and offsetX — the note, with [tolerance] as the reach.
  // OUTPUTS: True when a deletion was appended, false when the place names no note. The event carries
  //          the note IN FULL, so undoing the deletion restores the note, its place, its pitch, its
  //          duration and its tie together — the whole value, which is the invariant every inverse in
  //          this catalogue keeps.
  // KEYWORDS: melody, note-delete, whole-value, undoable, coordinate
  /// Removes the note nearest ([sectionId], [barIndex], [offsetX]), reporting whether one was there.
  bool deleteNoteNear({
    required String sectionId,
    required int barIndex,
    required double offsetX,
    double tolerance = chordHitTolerance,
  }) {
    final NoteMark? removed = existingNoteNear(
      sectionId: sectionId,
      barIndex: barIndex,
      offsetX: offsetX,
      tolerance: tolerance,
    );
    if (removed == null) {
      return false;
    }
    apply(
      NoteDeleteEvent(
        docId: _docId,
        seq: _seq,
        removed: removed.copyWith(
          place: _placeIn(sectionId, barIndex, removed.place),
        ),
      ),
    );
    return true;
  }

  // PURPOSE: State the length of a whole bar as the one written value of that length, so the guard
  //          in [insertNote] can refuse a note longer than the bar it is placed in without a second
  //          copy of the meter arithmetic living in this file.
  // INPUTS: bar — the bar the note is being placed in.
  // OUTPUTS: A [NoteValue] whose duration equals the bar's length exactly. A bar shorter than a
  //          thirty-second note — a meter this model can express and no chart uses — returns the
  //          shortest value there is rather than throwing, so the guard admits notes into it
  //          instead of refusing every one. A bar of exactly a whole note returns the whole note.
  // KEYWORDS: bar-length, exact-duration, meter, guard-support, total-function
  NoteValue _wholeBarValue(Bar bar) {
    final int numerator = bar.timeSignature.numerator;
    final int denominator = bar.timeSignature.denominator;
    for (final NoteBase base in NoteBase.values) {
      // A value of `base` lasts one whole note over `base.denominator`, and the bar lasts
      // `numerator / denominator` whole notes, so the two are the same duration exactly when the
      // cross product matches. No floating point takes part.
      if (numerator * base.denominator == denominator) {
        return NoteValue.plain(base);
      }
    }
    return const NoteValue.plain(NoteBase.thirtySecond);
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
  /// Declares or withdraws the chart's pitched melodic staff.
  bool setMelodyStaff({required bool on, String clef = 'treble'}) {
    final StaffSet from = _document.song.staffSet;
    final StaffSet to = StaffSet(
      pitched: on ? StaffSpec.pitched(clef: clef) : null,
      percussion: from.percussion,
    );
    if (to == from) {
      return false;
    }
    apply(StaffSetEvent(docId: _docId, seq: _seq, from: from, to: to));
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
