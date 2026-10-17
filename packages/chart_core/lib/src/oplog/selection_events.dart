// PURPOSE: Record the three edits a SELECTION performs — insert a copied run of bars, take that run
//          back out, and replace a run of bars with another version of itself — as events that carry
//          WHOLE bars, so that "select 16 bars, copy, paste, transpose" costs one undo per gesture
//          instead of one per bar. Owner decision D35 names the workflow and D36 fixes its price:
//          "Вставка обязана быть одной операцией отмены, а не одной на такт".
// INPUTS: The section, the zero-based index the run starts at, the bars that travel, the ink that
//         travels with them, and — for an insertion — the anchored objects the insertion pushes
//         along with their bars.
// OUTPUTS: Immutable events and their inverses. `bars.insert`'s inverse is `bars.remove` carrying
//          the same bars and ink; `bars.remove`'s inverse is the insertion again; `bars.replace`'s
//          inverse is itself with both sides swapped, which is what makes a transposition exactly
//          reversible. Every event carries complete values on both sides, so an undo restores the
//          geometry rather than reconstructing it from whatever the document holds by then.
// KEYWORDS: selection-event, bars-insert, bars-remove, bars-replace, whole-value, single-undo,
//           ink-follows-its-bar, d35, d36
//
// WHY "MOVE THE ANCHORS" IS PART OF THE INSERTION AND NOT A SECOND EVENT.
//
// A stroke, a stamp and a text cue are addressed by `EventAnchor(sectionId, bar, beat?)` — the bar
// is an INDEX inside its section (D32 states the consequence: "вставка такта перед ним сдвигает
// метку вместе с индексом"). So inserting N bars at index i moves every anchored object in that
// section whose bar is at or after i, by N. The existing `measure.insert` does NOT do that, and
// D32 names that cost as accepted for a single bar dropped in by a form edit.
//
// A PASTE IS NOT THAT GESTURE. The musician copied bars 4..7, ink and all, and pasted them at bar 2;
// if the ink of bars 2..7 stayed on its old indices it would now be drawn over the copies, which is
// the one failure this whole feature exists to avoid — and it would happen silently. So the
// insertion carries the moves it causes, with both sides of every move, and its inverse carries them
// back. The re-addressing is a fact of the edit and therefore belongs in the edit's record: replaying
// the log on another device must produce the same document, and a rule that lived only in the editor
// that generated the event would not replay.
//
// WHY THE MOVED OBJECTS ARE NAMED BY ID AND NOT BY ANCHOR. Two strokes on one cell are told apart by
// their ids and by nothing else; an anchor names a place, and every object at that place would match.
// The id is the identity the capture layer minted (or the cue's own), so a move can only ever touch
// the object the editor moved.
part of 'oplog.dart';

/// What kind of anchored object a [AnchorMove] moves.
///
/// The three collections the anchored address scheme covers. Annotations are included even though
/// nothing in the application writes one today: an `.chart` file can carry them, and an insertion
/// that left them on the wrong bar would be the same silent displacement this mechanism exists to
/// prevent. The token is the wire form and is stable.
enum AnchorMoveKind {
  /// A committed handwritten stroke (`DocumentState.strokes`).
  stroke('stroke'),

  /// A mark attached to a place (`DocumentState.annotations`).
  annotation('annotation'),

  /// A text cue (`DocumentState.textCues`).
  textCue('textCue');

  const AnchorMoveKind(this.token);

  /// The canonical token written into `events.jsonl`.
  final String token;
}

/// One anchored object moving from one bar to another because bars were inserted before it.
///
/// Both anchors are carried: the destination alone would describe where the object went but not
/// where it came from, and an inverse that recomputed the source from the destination would have to
/// know the number of bars inserted — which is exactly the fact this event already holds and must
/// not derive twice.
class AnchorMove {
  /// Creates a move of the object [id] of [kind] from [from] to [to].
  const AnchorMove({
    required this.kind,
    required this.id,
    required this.from,
    required this.to,
  });

  /// Rebuilds a move from [json].
  ///
  /// Throws [EventFormatException] for an unknown kind token or a malformed anchor.
  factory AnchorMove.fromJson(Map<String, Object?> json) => AnchorMove(
    kind: _kindFromToken(EventJson.string(json, 'kind')),
    id: EventJson.string(json, 'id'),
    from: EventAnchor.fromJson(EventJson.object(json, 'from')),
    to: EventAnchor.fromJson(EventJson.object(json, 'to')),
  );

  /// Resolves a canonical [token] to its kind, reporting an unknown one.
  static AnchorMoveKind _kindFromToken(String token) {
    for (final AnchorMoveKind kind in AnchorMoveKind.values) {
      if (kind.token == token) {
        return kind;
      }
    }
    throw EventFormatException(
      'field "kind" names no anchored object: "$token"',
    );
  }

  /// Which collection the moved object belongs to.
  final AnchorMoveKind kind;

  /// The identity of the moved object inside its collection.
  final String id;

  /// The anchor the object held before the insertion.
  final EventAnchor from;

  /// The anchor it holds after it, which differs from [from] in the bar alone unless a future edit
  /// moves a beat as well.
  final EventAnchor to;

  /// Returns this move with both ends swapped, which is what an inverse carries.
  AnchorMove get reversed => AnchorMove(kind: kind, id: id, from: to, to: from);

  /// Writes this move as `{kind, id, from, to}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.token,
    'id': id,
    'from': from.toJson(),
    'to': to.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AnchorMove &&
      other.kind == kind &&
      other.id == id &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(kind, id, from, to);
  @override
  String toString() => 'AnchorMove(${kind.token} $id: $from -> $to)';
}

/// Inserts a run of bars — and the ink that travelled with them — at [index] of a section.
///
/// This is what a paste of a copied run of bars writes, and it is also what an undo of a removal
/// writes. It does NOT come from `measure.insert` repeated: the repetition would append one event
/// per bar, and D36 requires the gesture to cost one undo.
class BarsInsertEvent extends ChartEvent {
  /// Creates an insertion of [bars] at [index], with [strokes] added and [moves] applied.
  const BarsInsertEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.index,
    required this.bars,
    this.strokes = const <InkStroke>[],
    this.moves = const <AnchorMove>[],
  });

  /// The section the run is inserted into.
  final String sectionId;

  /// Zero-based index the first inserted bar takes; the section's bar count appends.
  final int index;

  /// The bars to insert, in reading order, complete in every field.
  final List<Bar> bars;

  /// The strokes the run carries, addressed against the bars it is being inserted with.
  ///
  /// They are appended to the document's stroke list in this order, which is what makes render order
  /// deterministic: a paste does not land ink in the middle of the ink it was copied from, it lands
  /// on top of everything that exists when it happens.
  final List<InkStroke> strokes;

  /// The anchored objects this insertion pushes along with their bars, with both ends.
  final List<AnchorMove> moves;

  @override
  String get type => 'bars.insert';

  /// The place of the first inserted bar, so a consumer that only reads anchors knows where the
  /// edit happened.
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: index);

  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'index': index,
    'bars': <Object?>[for (final Bar bar in bars) ModelJson.bar(bar)],
    'strokes': <Object?>[
      for (final InkStroke stroke in strokes) stroke.toJson(),
    ],
    'moves': <Object?>[for (final AnchorMove move in moves) move.toJson()],
  };

  @override
  BarsRemoveEvent inverse() => BarsRemoveEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    bars: bars,
    strokes: strokes,
    moves: moves,
  );

  @override
  BarsInsertEvent withSeq(int seq) => BarsInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    bars: bars,
    strokes: strokes,
    moves: moves,
  );

  @override
  bool operator ==(Object other) =>
      other is BarsInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.index == index &&
      sameBars(other.bars, bars) &&
      sameStrokes(other.strokes, strokes) &&
      sameMoves(other.moves, moves);
  @override
  int get hashCode => Object.hash(
    docId,
    seq,
    sectionId,
    index,
    Object.hashAll(bars),
    Object.hashAll(strokes),
    Object.hashAll(moves),
  );
}

/// Removes the run of bars at [index] of a section, carrying them so the removal can be undone.
///
/// This is the inverse of [BarsInsertEvent] and the primitive a future CUT would use. It removes
/// exactly `bars.length` bars starting at [index], deletes the [strokes] by identity and applies the
/// [moves] in reverse, which is what puts every anchored object back on the bar it came from.
class BarsRemoveEvent extends ChartEvent {
  /// Creates a removal of [bars] at [index], with [strokes] removed and [moves] reversed.
  const BarsRemoveEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.index,
    required this.bars,
    this.strokes = const <InkStroke>[],
    this.moves = const <AnchorMove>[],
  });

  /// The section the run is removed from.
  final String sectionId;

  /// Zero-based index of the first bar removed.
  final int index;

  /// The bars that were removed, complete in every field, carried for the inverse.
  final List<Bar> bars;

  /// The strokes the run carried, carried in full for the inverse and removed by identity.
  final List<InkStroke> strokes;

  /// The moves the insertion made, in the direction the INSERTION applied them.
  ///
  /// They are stored in that direction and reversed when applied, so that the two directions of one
  /// mechanism are one list rather than two that could disagree.
  final List<AnchorMove> moves;

  @override
  String get type => 'bars.remove';

  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: index);

  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'index': index,
    'bars': <Object?>[for (final Bar bar in bars) ModelJson.bar(bar)],
    'strokes': <Object?>[
      for (final InkStroke stroke in strokes) stroke.toJson(),
    ],
    'moves': <Object?>[for (final AnchorMove move in moves) move.toJson()],
  };

  @override
  BarsInsertEvent inverse() => BarsInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    bars: bars,
    strokes: strokes,
    moves: moves,
  );

  @override
  BarsRemoveEvent withSeq(int seq) => BarsRemoveEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    bars: bars,
    strokes: strokes,
    moves: moves,
  );

  @override
  bool operator ==(Object other) =>
      other is BarsRemoveEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.index == index &&
      sameBars(other.bars, bars) &&
      sameStrokes(other.strokes, strokes) &&
      sameMoves(other.moves, moves);
  @override
  int get hashCode => Object.hash(
    docId,
    seq,
    sectionId,
    index,
    Object.hashAll(bars),
    Object.hashAll(strokes),
    Object.hashAll(moves),
  );
}

/// Replaces a run of bars with another version of itself, carrying BOTH versions in full.
///
/// Two operations write it, and both are one gesture that must cost one undo: transposing a
/// selection (the same bars, moved) and pasting a window of beats into a bar (the same bar, with
/// those cells replaced). The two stroke lists exist for the second: a beat window can carry ink, and
/// ink is not part of a [Bar].
class BarsReplaceEvent extends ChartEvent {
  /// Creates a replacement of [from] by [to] at [index], adding [addedStrokes] and removing
  /// [removedStrokes].
  ///
  /// [from] and [to] must be the same length: this event says "these bars become those bars", and
  /// an event that changed the bar COUNT would be an insertion or a removal wearing the wrong name,
  /// with an inverse that could not place what it grew.
  const BarsReplaceEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.index,
    required this.from,
    required this.to,
    this.addedStrokes = const <InkStroke>[],
    this.removedStrokes = const <InkStroke>[],
  });

  /// The section the run lives in.
  final String sectionId;

  /// Zero-based index of the first bar replaced.
  final int index;

  /// The bars as they were, complete in every field.
  final List<Bar> from;

  /// The bars as they are after the edit, the same number of them.
  final List<Bar> to;

  /// Strokes the edit adds, in render order, addressed against the bars the edit leaves behind.
  final List<InkStroke> addedStrokes;

  /// Strokes the edit removes, in full, carried so the inverse can put the exact geometry back.
  final List<InkStroke> removedStrokes;

  @override
  String get type => 'bars.replace';

  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: index);

  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'index': index,
    'from': <Object?>[for (final Bar bar in from) ModelJson.bar(bar)],
    'to': <Object?>[for (final Bar bar in to) ModelJson.bar(bar)],
    'addedStrokes': <Object?>[
      for (final InkStroke stroke in addedStrokes) stroke.toJson(),
    ],
    'removedStrokes': <Object?>[
      for (final InkStroke stroke in removedStrokes) stroke.toJson(),
    ],
  };

  @override
  BarsReplaceEvent inverse() => BarsReplaceEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    from: to,
    to: from,
    addedStrokes: removedStrokes,
    removedStrokes: addedStrokes,
  );

  @override
  BarsReplaceEvent withSeq(int seq) => BarsReplaceEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    from: from,
    to: to,
    addedStrokes: addedStrokes,
    removedStrokes: removedStrokes,
  );

  @override
  bool operator ==(Object other) =>
      other is BarsReplaceEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.index == index &&
      sameBars(other.from, from) &&
      sameBars(other.to, to) &&
      sameStrokes(other.addedStrokes, addedStrokes) &&
      sameStrokes(other.removedStrokes, removedStrokes);
  @override
  int get hashCode => Object.hash(
    docId,
    seq,
    sectionId,
    index,
    Object.hashAll(from),
    Object.hashAll(to),
    Object.hashAll(addedStrokes),
    Object.hashAll(removedStrokes),
  );
}

// PURPOSE: Compare two lists of bars element by element, because the `==` of `List` in Dart is
//          identity and an event whose equality compared list identity would never be equal to its
//          own replay.
// INPUTS: left and right — the lists, either of which may be empty but neither null.
// OUTPUTS: True when both hold equal bars in the same order.
// KEYWORDS: list-equality, value-semantics, event-equality
/// Whether two bar lists hold equal bars in the same order.
bool sameBars(List<Bar> left, List<Bar> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

// PURPOSE: Compare two lists of strokes element by element, for the same reason [sameBars] exists.
// INPUTS: left and right — the lists, either of which may be empty but neither null.
// OUTPUTS: True when both hold equal strokes in the same order.
// KEYWORDS: list-equality, stroke, value-semantics, event-equality
/// Whether two stroke lists hold equal strokes in the same order.
bool sameStrokes(List<InkStroke> left, List<InkStroke> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

// PURPOSE: Compare two lists of anchor moves element by element, for the same reason [sameBars]
//          exists.
// INPUTS: left and right — the lists, either of which may be empty but neither null.
// OUTPUTS: True when both hold equal moves in the same order.
// KEYWORDS: list-equality, anchor-move, value-semantics, event-equality
/// Whether two move lists hold equal moves in the same order.
bool sameMoves(List<AnchorMove> left, List<AnchorMove> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
