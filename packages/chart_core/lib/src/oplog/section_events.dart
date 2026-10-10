// PURPOSE: Record the structural edits to a song's form — add a section, remove one, relabel one,
//          copy one, move one — as events that carry the affected section in full, so that a
//          rearrangement of a tune can be undone to the letter.
// INPUTS: A section index or a section identity, the section or label itself, and for a reorder
//         the two indices involved.
// OUTPUTS: Immutable events and their inverses. A section's identity is assigned once and
//          survives a reorder, which is why every event but insertion names the section by id
//          and not by position: a reorder that renumbered identities would detach every
//          annotation anchored in the song. A duplicate gets a NEW identity, because two sections
//          sharing an id would make every anchor naming it ambiguous.
// KEYWORDS: section-event, insert, delete, update, duplicate, reorder, form, stable-identity, undo
part of 'oplog.dart';

/// Inserts a section at a given index.
class SectionInsertEvent extends ChartEvent {
  /// Creates an insertion of [section] at [index].
  const SectionInsertEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.section,
  });

  /// Zero-based index the section takes, or the section count to append.
  final int index;

  /// The section to insert, in full, including the identity it will be known by.
  final Section section;
  @override
  String get type => 'section.insert';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'section': ModelJson.section(section),
  };
  @override
  SectionDeleteEvent inverse() => SectionDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: section,
  );
  @override
  SectionInsertEvent withSeq(int seq) => SectionInsertEvent(
    docId: docId,
    seq: seq,
    index: index,
    section: section,
  );
  @override
  bool operator ==(Object other) =>
      other is SectionInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.section == section;
  @override
  int get hashCode => Object.hash(docId, seq, index, section);
}

/// Removes the section at a given index, carrying it so the deletion can be undone in place.
///
/// This event is the missing half of [SectionInsertEvent]'s inverse: a section that can be
/// inserted has to be removable, and the catalogue's `section.*` family lists no deletion. It is
/// added here rather than faked with an empty-looking update, and it is reported as an addition.
class SectionDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed] at [index].
  const SectionDeleteEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.removed,
  });

  /// Zero-based index of the section being removed.
  final int index;

  /// The section that was removed, carried for the inverse.
  final Section removed;
  @override
  String get type => 'section.delete';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'section': ModelJson.section(removed),
  };
  @override
  SectionInsertEvent inverse() => SectionInsertEvent(
    docId: docId,
    seq: seq,
    index: index,
    section: removed,
  );
  @override
  SectionDeleteEvent withSeq(int seq) => SectionDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is SectionDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, index, removed);
}

/// Relabels the section with a given identity.
class SectionUpdateEvent extends ChartEvent {
  /// Creates an update of the label of section [sectionId] from [from] to [to].
  const SectionUpdateEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.from,
    required this.to,
  });

  /// Identity of the section being relabelled.
  final String sectionId;

  /// The label being replaced.
  final SectionLabel from;

  /// The replacement label.
  final SectionLabel to;
  @override
  String get type => 'section.update';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'from': ModelJson.sectionLabel(from),
    'to': ModelJson.sectionLabel(to),
  };
  @override
  SectionUpdateEvent inverse() => SectionUpdateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    from: to,
    to: from,
  );
  @override
  SectionUpdateEvent withSeq(int seq) => SectionUpdateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is SectionUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, from, to);
}

/// Copies a section into the position after it, under a new identity.
class SectionDuplicateEvent extends ChartEvent {
  /// Creates a duplication of section [sourceId] placing [duplicate] at [index] + 1.
  ///
  /// The copy is materialised in the event, for the same reason a duplicated bar is: replay has
  /// to be deterministic, and the inverse has to name the exact section to remove. The source
  /// identity is recorded so a reader can say where the copy came from.
  const SectionDuplicateEvent({
    required super.docId,
    required super.seq,
    required this.sourceId,
    required this.index,
    required this.duplicate,
  });

  /// Identity of the section being copied.
  final String sourceId;

  /// Zero-based index of the section being copied.
  final int index;

  /// The copy, which carries its own new identity and is placed at [index] + 1.
  final Section duplicate;
  @override
  String get type => 'section.duplicate';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sourceId,
    'index': index,
    'section': ModelJson.section(duplicate),
  };
  @override
  SectionDeleteEvent inverse() => SectionDeleteEvent(
    docId: docId,
    seq: seq,
    index: index + 1,
    removed: duplicate,
  );
  @override
  SectionDuplicateEvent withSeq(int seq) => SectionDuplicateEvent(
    docId: docId,
    seq: seq,
    sourceId: sourceId,
    index: index,
    duplicate: duplicate,
  );
  @override
  bool operator ==(Object other) =>
      other is SectionDuplicateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sourceId == sourceId &&
      other.index == index &&
      other.duplicate == duplicate;
  @override
  int get hashCode => Object.hash(docId, seq, sourceId, index, duplicate);
}

/// Moves the section with a given identity to another index.
class SectionReorderEvent extends ChartEvent {
  /// Creates a move of section [sectionId] from [fromIndex] to [toIndex].
  ///
  /// [toIndex] is the section's index in the resulting order, which is what makes the inverse a
  /// plain swap of the two indices.
  const SectionReorderEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.fromIndex,
    required this.toIndex,
  });

  /// Identity of the section being moved.
  final String sectionId;

  /// Index the section currently occupies.
  final int fromIndex;

  /// Index the section takes in the resulting order.
  final int toIndex;
  @override
  String get type => 'section.reorder';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'fromIndex': fromIndex,
    'toIndex': toIndex,
  };
  @override
  SectionReorderEvent inverse() => SectionReorderEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    fromIndex: toIndex,
    toIndex: fromIndex,
  );
  @override
  SectionReorderEvent withSeq(int seq) => SectionReorderEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    fromIndex: fromIndex,
    toIndex: toIndex,
  );
  @override
  bool operator ==(Object other) =>
      other is SectionReorderEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.fromIndex == fromIndex &&
      other.toIndex == toIndex;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, fromIndex, toIndex);
}
