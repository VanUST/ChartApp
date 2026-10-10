// PURPOSE: Record a change to a song's OWN metadata — the title, the composer, the style and the
//          tempo — as one event, so that the facts a musician reads above the chart and in the
//          scene bar are as editable and as undoable as the chords underneath them. Until this
//          family existed the catalogue could move a bar, relabel a section and transpose a key
//          but could not rename the tune, which meant the scene bar's tempo and style were dead
//          text and the only way to change a title was to edit the model behind the log's back.
// INPUTS: The four fields the song carried BEFORE the change and the four it carries after it.
// OUTPUTS: An immutable event whose inverse is another update with the two whole values swapped.
//          BOTH SIDES CARRY ALL FOUR FIELDS, never a delta and never an absent field: an inverse
//          built by subtracting a change would have to reconstruct the previous value, and a
//          reconstructed value can be reconstructed wrongly — a tempo set to 0 would leave a
//          negation with nothing to measure against, and an empty title is a value a chart
//          legitimately has. Whole values cost a few bytes per rename and cannot be wrong.
// KEYWORDS: song-event, metadata, title, composer, style, tempo, whole-value, inverse, undo
part of 'oplog.dart';

/// What a song says about itself: its title, its composer, the style it is played in and its tempo.
///
/// A value rather than four loose fields because the event needs a "before" and an "after" of the
/// same shape, and because equality over the four together is exactly the test "did anything
/// change?" — which is what keeps an edit that changes nothing out of the log.
class SongMetadata {
  /// Creates metadata with the given [title], [composer], [style] and [tempo].
  const SongMetadata({
    required this.title,
    required this.composer,
    required this.style,
    required this.tempo,
  });

  /// Reads the metadata [song] carries, which is the `from` side of an update.
  factory SongMetadata.of(Song song) => SongMetadata(
    title: song.title,
    composer: song.composer,
    style: song.style,
    tempo: song.tempo,
  );

  /// The title as written; empty is a title a chart legitimately has.
  final String title;

  /// The composer as written, in whatever order the format stores it.
  final String composer;

  /// The style or feel as written, such as "Ballad" or "Medium Swing". Free text, because the
  /// values are iReal's and an enum here would reject a style the format adds later.
  final String style;

  /// The tempo in beats per minute, or 0 when the chart sets none.
  final int tempo;

  @override
  bool operator ==(Object other) =>
      other is SongMetadata &&
      other.title == title &&
      other.composer == composer &&
      other.style == style &&
      other.tempo == tempo;

  @override
  int get hashCode => Object.hash(title, composer, style, tempo);

  @override
  String toString() =>
      'SongMetadata("${title.isEmpty ? 'untitled' : title}", '
      '"$composer", "$style", $tempo bpm)';
}

/// Replaces the title, composer, style and tempo of a song in one step.
///
/// It is the only event in the catalogue that carries no address at all — see [DocumentEvent.anchor]
/// — because it acts on the whole document rather than on a place inside it.
class SongUpdateEvent extends ChartEvent {
  /// Creates an update of the song's metadata from [from] to [to].
  const SongUpdateEvent({
    required super.docId,
    required super.seq,
    required this.from,
    required this.to,
  });

  /// The metadata the song carried before this event.
  ///
  /// Recorded although the reducer never reads it, because it is what the inverse is built from:
  /// undo restores these four values as they were WRITTEN, rather than deriving them from the
  /// values that replaced them.
  final SongMetadata from;

  /// The metadata the song carries after this event.
  final SongMetadata to;
  @override
  String get type => 'song.update';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'from': ModelJson.songMetadata(from),
    'to': ModelJson.songMetadata(to),
  };
  @override
  SongUpdateEvent inverse() =>
      SongUpdateEvent(docId: docId, seq: seq, from: to, to: from);
  @override
  SongUpdateEvent withSeq(int seq) =>
      SongUpdateEvent(docId: docId, seq: seq, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is SongUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, from, to);
}
