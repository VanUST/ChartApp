// PURPOSE: Model a piece of text a musician places in the chart — a rehearsal remark, a note to
//          the band, a reminder — at an anchored place rather than at a page coordinate. Keeping
//          the cue on the same anchor scheme as an annotation means both survive the same reflow,
//          and editing the words is an event separate from moving the cue.
// INPUTS: A stable id, an anchored place and the text.
// OUTPUTS: Immutable values. The text may be empty, which is a cue that has been inserted and not
//          yet typed into; that is an ordinary editing state and is not a failure. Equality
//          compares the id, the place and the text.
// KEYWORDS: text-cue, staff-text, remark, anchored-text, offset, editing
part of 'oplog.dart';

/// A text remark placed at an anchored spot in a chart.
class TextCue {
  /// Creates a cue identified by [id] at [place] carrying [text].
  const TextCue({required this.id, required this.place, this.text = ''});

  /// Rebuilds a cue from [json].
  ///
  /// Throws [EventFormatException] for a malformed place or a missing field.
  factory TextCue.fromJson(Map<String, Object?> json) => TextCue(
    id: EventJson.string(json, 'id'),
    place: AnchoredPlace.fromJson(EventJson.object(json, 'place')),
    text: EventJson.string(json, 'text'),
  );

  /// Stable identifier of this cue, unique within its document.
  final String id;

  /// Where the cue hangs, as an anchor plus an anchor-local offset.
  final AnchoredPlace place;

  /// The words written in the cue, empty while it is being typed.
  final String text;

  /// Writes this cue as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'place': place.toJson(),
    'text': text,
  };

  /// Returns a copy of this cue with the given fields replaced.
  TextCue copyWith({AnchoredPlace? place, String? text}) =>
      TextCue(id: id, place: place ?? this.place, text: text ?? this.text);
  @override
  bool operator ==(Object other) =>
      other is TextCue &&
      other.id == id &&
      other.place == place &&
      other.text == text;
  @override
  int get hashCode => Object.hash(id, place, text);
  @override
  String toString() => 'TextCue($id, $place, "$text")';
}
