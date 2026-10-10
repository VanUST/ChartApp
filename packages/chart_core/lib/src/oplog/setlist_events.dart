// PURPOSE: Record the edits to a setlist document — name it, add an entry, remove an entry, move
//          an entry, change how an entry is played — as events on the setlist's own log. A
//          setlist is a document a musician edits and undoes in its own right, so its events
//          belong to its own id and do not touch any chart.
// INPUTS: The setlist id as the event's `docId`, the entry index where an edit is positional, and
//         the entry (or the notes and transposition) that changes.
// OUTPUTS: Immutable events and their inverses. A move is a swap of two indices; an entry edit is
//          a before/after pair, so its inverse needs no access to the entry's current state. An
//          index outside the entry list is a reducer failure rather than a silent append.
// KEYWORDS: setlist-event, programme, rename, insert, delete, move, update, entries, inverse, undo
part of 'oplog.dart';

/// Renames a setlist.
class SetlistRenameEvent extends SetlistEvent {
  /// Creates a rename from [fromTitle] to [toTitle].
  const SetlistRenameEvent({
    required super.docId,
    required super.seq,
    required this.fromTitle,
    required this.toTitle,
  });

  /// The title before the rename, empty when the setlist was unnamed.
  final String fromTitle;

  /// The title after the rename.
  final String toTitle;
  @override
  String get type => 'setlist.rename';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'fromTitle': fromTitle,
    'toTitle': toTitle,
  };
  @override
  SetlistRenameEvent inverse() => SetlistRenameEvent(
    docId: docId,
    seq: seq,
    fromTitle: toTitle,
    toTitle: fromTitle,
  );
  @override
  SetlistRenameEvent withSeq(int seq) => SetlistRenameEvent(
    docId: docId,
    seq: seq,
    fromTitle: fromTitle,
    toTitle: toTitle,
  );
  @override
  bool operator ==(Object other) =>
      other is SetlistRenameEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.fromTitle == fromTitle &&
      other.toTitle == toTitle;
  @override
  int get hashCode => Object.hash(docId, seq, fromTitle, toTitle);
}

/// Inserts an entry into a setlist at a given position.
class SetlistItemInsertEvent extends SetlistEvent {
  /// Creates an insertion of [item] at [index].
  const SetlistItemInsertEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.item,
  });

  /// Zero-based position the entry takes in the programme, or the entry count to append.
  final int index;

  /// The entry to insert, in full.
  final SetlistItem item;
  @override
  String get type => 'setlist.item.insert';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'item': item.toJson(),
  };
  @override
  SetlistItemDeleteEvent inverse() => SetlistItemDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: item,
  );
  @override
  SetlistItemInsertEvent withSeq(int seq) =>
      SetlistItemInsertEvent(docId: docId, seq: seq, index: index, item: item);
  @override
  bool operator ==(Object other) =>
      other is SetlistItemInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.item == item;
  @override
  int get hashCode => Object.hash(docId, seq, index, item);
}

/// Removes the entry at a given position.
class SetlistItemDeleteEvent extends SetlistEvent {
  /// Creates a deletion of [removed] at [index].
  const SetlistItemDeleteEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.removed,
  });

  /// Zero-based position of the entry being removed.
  final int index;

  /// The entry that was removed, carried for the inverse.
  final SetlistItem removed;
  @override
  String get type => 'setlist.item.delete';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'item': removed.toJson(),
  };
  @override
  SetlistItemInsertEvent inverse() => SetlistItemInsertEvent(
    docId: docId,
    seq: seq,
    index: index,
    item: removed,
  );
  @override
  SetlistItemDeleteEvent withSeq(int seq) => SetlistItemDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is SetlistItemDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, index, removed);
}

/// Moves the entry at one position to another.
class SetlistItemMoveEvent extends SetlistEvent {
  /// Creates a move of the entry at [fromIndex] to [toIndex].
  ///
  /// [toIndex] is the entry's position in the resulting order, which is what makes the inverse a
  /// plain swap of the two indices. There is no entry identity to name: two entries can play the
  /// same chart, so position is the only identity an entry has.
  const SetlistItemMoveEvent({
    required super.docId,
    required super.seq,
    required this.fromIndex,
    required this.toIndex,
  });

  /// Position the entry currently occupies.
  final int fromIndex;

  /// Position the entry takes in the resulting order.
  final int toIndex;
  @override
  String get type => 'setlist.item.move';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'fromIndex': fromIndex,
    'toIndex': toIndex,
  };
  @override
  SetlistItemMoveEvent inverse() => SetlistItemMoveEvent(
    docId: docId,
    seq: seq,
    fromIndex: toIndex,
    toIndex: fromIndex,
  );
  @override
  SetlistItemMoveEvent withSeq(int seq) => SetlistItemMoveEvent(
    docId: docId,
    seq: seq,
    fromIndex: fromIndex,
    toIndex: toIndex,
  );
  @override
  bool operator ==(Object other) =>
      other is SetlistItemMoveEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.fromIndex == fromIndex &&
      other.toIndex == toIndex;
  @override
  int get hashCode => Object.hash(docId, seq, fromIndex, toIndex);
}

/// Changes how the entry at a given position is played.
class SetlistItemUpdateEvent extends SetlistEvent {
  /// Creates an update of the entry at [index] from [from] to [to].
  const SetlistItemUpdateEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.from,
    required this.to,
  });

  /// Position of the entry being changed.
  final int index;

  /// The entry as it was.
  final SetlistItem from;

  /// The entry as it is now.
  final SetlistItem to;
  @override
  String get type => 'setlist.item.update';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'from': from.toJson(),
    'to': to.toJson(),
  };
  @override
  SetlistItemUpdateEvent inverse() => SetlistItemUpdateEvent(
    docId: docId,
    seq: seq,
    index: index,
    from: to,
    to: from,
  );
  @override
  SetlistItemUpdateEvent withSeq(int seq) => SetlistItemUpdateEvent(
    docId: docId,
    seq: seq,
    index: index,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is SetlistItemUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, index, from, to);
}
