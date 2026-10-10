// PURPOSE: Model the setlist document — an ordered programme of charts with a transposition and
//          a note per entry — as a value the setlist event family can fold events onto. A setlist
//          is a document in its own right (`.setlist`), not a field of a song, because the same
//          chart is played in several programmes and filing the programme inside it would copy
//          the chart once per setlist.
// INPUTS: A setlist id and title, and the ordered entries. Each entry names a chart document, a
//         transposition in semitones and free-text notes for the performer.
// OUTPUTS: Immutable values. Positions are the list index and are rewritten by a move, so the
//          order is data rather than an accident of insertion. Equality compares the id, the
//          title and the entries in order.
// KEYWORDS: setlist, programme, ordered-entries, transposition, performer-notes, document-kind
part of 'oplog.dart';

/// One chart in a setlist, with how it is played there.
class SetlistItem {
  /// Creates an entry playing [documentId], transposed by [transposeSem], with [notes].
  const SetlistItem({
    required this.documentId,
    this.transposeSem = 0,
    this.notes = '',
  });

  /// Rebuilds an entry from [json].
  ///
  /// Throws [EventFormatException] when a field is missing or of the wrong type.
  factory SetlistItem.fromJson(Map<String, Object?> json) => SetlistItem(
    documentId: EventJson.string(json, 'documentId'),
    transposeSem: EventJson.integer(json, 'transposeSem'),
    notes: EventJson.string(json, 'notes'),
  );

  /// The identity of the chart document this entry plays.
  ///
  /// Named `documentId` rather than `docId` to keep it visibly distinct from the event's own
  /// `docId`, which for a setlist event is the SETLIST's identity: conflating the two would let
  /// an entry point at the programme it belongs to.
  final String documentId;

  /// Semitones this entry is transposed by, which may differ from the chart's own key.
  final int transposeSem;

  /// Notes the performer attached to this entry, free text, empty when there are none.
  final String notes;

  /// Writes this entry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    'transposeSem': transposeSem,
    'notes': notes,
  };

  /// Returns a copy of this entry with the given fields replaced.
  SetlistItem copyWith({
    String? documentId,
    int? transposeSem,
    String? notes,
  }) => SetlistItem(
    documentId: documentId ?? this.documentId,
    transposeSem: transposeSem ?? this.transposeSem,
    notes: notes ?? this.notes,
  );
  @override
  bool operator ==(Object other) =>
      other is SetlistItem &&
      other.documentId == documentId &&
      other.transposeSem == transposeSem &&
      other.notes == notes;
  @override
  int get hashCode => Object.hash(documentId, transposeSem, notes);
  @override
  String toString() =>
      'SetlistItem($documentId${transposeSem == 0 ? '' : ' $transposeSem sem'}'
      '${notes.isEmpty ? '' : ', "$notes"'})';
}

/// A programme of charts: a title and the ordered entries played.
class Setlist {
  /// Creates the setlist identified by [id] with [title] and [items].
  const Setlist({
    required this.id,
    this.title = '',
    this.items = const <SetlistItem>[],
  });

  /// Rebuilds a setlist from [json].
  ///
  /// Throws [EventFormatException] when a field is missing or malformed.
  factory Setlist.fromJson(Map<String, Object?> json) => Setlist(
    id: EventJson.string(json, 'id'),
    title: EventJson.string(json, 'title'),
    items: <SetlistItem>[
      for (final Object? entry in EventJson.array(json, 'items'))
        SetlistItem.fromJson(_entryObject(entry)),
    ],
  );

  /// Reads one entry of the `items` array as a JSON object.
  static Map<String, Object?> _entryObject(Object? entry) {
    if (entry is! Map<String, Object?>) {
      throw EventFormatException('an entry of "items" is not a JSON object');
    }
    return entry;
  }

  /// The setlist's identity, which is also the `docId` its events carry.
  final String id;

  /// The setlist's name, empty while it has not been named.
  final String title;

  /// The entries in playing order.
  final List<SetlistItem> items;

  /// Writes this setlist as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'items': <Object?>[for (final SetlistItem item in items) item.toJson()],
  };

  /// Returns a copy of this setlist with the given fields replaced.
  Setlist copyWith({String? title, List<SetlistItem>? items}) =>
      Setlist(id: id, title: title ?? this.title, items: items ?? this.items);
  @override
  bool operator ==(Object other) {
    if (other is! Setlist ||
        other.id != id ||
        other.title != title ||
        other.items.length != items.length) {
      return false;
    }
    for (int index = 0; index < items.length; index++) {
      if (other.items[index] != items[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(items));
  @override
  String toString() =>
      'Setlist($id, "${title.isEmpty ? 'untitled' : title}", '
      '${items.length} entr${items.length == 1 ? 'y' : 'ies'})';
}
