// PURPOSE: Model the setlist document — an ordered programme of charts with a transposition and
//          a note per entry — as a value the setlist event family can fold events onto. A setlist
//          is a document in its own right (`.setlist`), not a field of a song, because the same
//          chart is played in several programmes and filing the programme inside it would copy
//          the chart once per setlist.
// INPUTS: A setlist id and title, and the ordered entries. Each entry names a chart twice: by the
//         id of the chart DOCUMENT its log is keyed by, and by a content-derived IDENTITY that
//         survives a later session — plus a transposition in semitones and free-text notes.
// OUTPUTS: Immutable values. Positions are the list index and are rewritten by a move, so the
//          order is data rather than an accident of insertion. Equality compares the id, the
//          title and the entries in order.
// KEYWORDS: setlist, programme, ordered-entries, transposition, performer-notes, document-kind
part of 'oplog.dart';

/// One chart in a setlist, with how it is played there.
///
/// AN ENTRY NAMES A CHART TWICE, AND THAT IS THE DESIGN RATHER THAN AN ACCIDENT. [documentId] is the
/// identity of the chart DOCUMENT — the id the chart's own operation log is keyed by, which for an
/// iReal import is a position in the payload and is therefore exact only for the library it was
/// built from. [chartIdentity] is a fact about the chart's MUSIC (see `chartIdentityOf`), which is
/// what survives the session ending, the export being imported again and the tune being renamed. A
/// reader joining an entry to a loaded chart uses the identity when the entry carries one, because
/// that is the join that still means something tomorrow; `documentId` is the fallback an entry
/// written before identities existed still has, and the two agree for a programme built and read in
/// one session.
class SetlistItem {
  /// Creates an entry playing [documentId], transposed by [transposeSem], with [notes].
  ///
  /// [chartIdentity] defaults to the empty string, which means "this entry carries no identity":
  /// an entry built by hand, or one read from a file written before identities were persisted. An
  /// empty identity is not an identity of nothing — it is the absence of one, and a reader falls
  /// back to [documentId] for exactly those entries.
  const SetlistItem({
    required this.documentId,
    this.chartIdentity = '',
    this.transposeSem = 0,
    this.notes = '',
  });

  /// Rebuilds an entry from [json].
  ///
  /// Throws [EventFormatException] when a field is missing or of the wrong type, except for
  /// `chartIdentity`, whose absence is read as the empty string: every `.setlist` and every setlist
  /// event written before identities were persisted has no such field, and refusing those files
  /// would turn a working programme into an unreadable one.
  factory SetlistItem.fromJson(Map<String, Object?> json) => SetlistItem(
    documentId: EventJson.string(json, 'documentId'),
    chartIdentity: EventJson.optionalString(json, 'chartIdentity') ?? '',
    transposeSem: EventJson.integer(json, 'transposeSem'),
    notes: EventJson.string(json, 'notes'),
  );

  /// The identity of the chart document this entry plays, which is the `docId` the chart's own
  /// event log is keyed by.
  ///
  /// Named `documentId` rather than `docId` to keep it visibly distinct from the event's own
  /// `docId`, which for a setlist event is the SETLIST's identity: conflating the two would let
  /// an entry point at the programme it belongs to.
  ///
  /// It is a position in the export a chart was imported from for an iReal library, so it is exact
  /// for the library it was built from and is not a durable name for the tune; [chartIdentity] is
  /// that name.
  final String documentId;

  /// The chart's content-derived identity, or the empty string when the entry carries none.
  ///
  /// This is `chartIdentityOf` of the chart's music, stored at the moment the entry was made, and
  /// it is what a programme reopened in a later session — or against a differently ordered export —
  /// is resolved by. Two facts follow from it being derived from content and are decided rather
  /// than discovered: renaming a tune does not change it, because the metadata block is not part of
  /// the derivation, and EDITING a tune's music does change it, so an entry naming music that has
  /// since been changed resolves to nothing and is shown as a missing chart rather than silently
  /// playing something else.
  final String chartIdentity;

  /// Semitones this entry is transposed by, which may differ from the chart's own key.
  final int transposeSem;

  /// Notes the performer attached to this entry, free text, empty when there are none.
  final String notes;

  /// Writes this entry as a JSON object.
  ///
  /// `chartIdentity` is written only when the entry carries one, so that an entry without an
  /// identity — the ordinary case for a programme built and saved inside one library — encodes
  /// exactly as it did before identities existed, and reads back as itself. The reader's rule for
  /// the absent field is in [SetlistItem.fromJson].
  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    if (chartIdentity.isNotEmpty) 'chartIdentity': chartIdentity,
    'transposeSem': transposeSem,
    'notes': notes,
  };

  /// Returns a copy of this entry with the given fields replaced.
  SetlistItem copyWith({
    String? documentId,
    String? chartIdentity,
    int? transposeSem,
    String? notes,
  }) => SetlistItem(
    documentId: documentId ?? this.documentId,
    chartIdentity: chartIdentity ?? this.chartIdentity,
    transposeSem: transposeSem ?? this.transposeSem,
    notes: notes ?? this.notes,
  );
  @override
  bool operator ==(Object other) =>
      other is SetlistItem &&
      other.documentId == documentId &&
      other.chartIdentity == chartIdentity &&
      other.transposeSem == transposeSem &&
      other.notes == notes;
  @override
  int get hashCode =>
      Object.hash(documentId, chartIdentity, transposeSem, notes);
  @override
  String toString() =>
      'SetlistItem($documentId'
      '${chartIdentity.isEmpty ? '' : ' $chartIdentity'}'
      '${transposeSem == 0 ? '' : ' $transposeSem sem'}'
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
