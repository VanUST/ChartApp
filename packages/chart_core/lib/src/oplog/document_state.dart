// PURPOSE: Hold everything an edit to a chart document can touch in one value the reducer folds
//          events onto: the song itself plus the objects that hang off it and are addressed by
//          anchor rather than living inside a bar — the committed strokes, the annotations, the
//          text cues and the bar divisions recognised from that ink. The song model deliberately
//          carries none of them, because a stroke is not notation and an annotation is not part of
//          the music; grouping them here is what makes "apply an event and then its inverse
//          returns the previous document value" a statement about one value rather than about five.
// INPUTS: A song and the four anchored collections.
// OUTPUTS: An immutable value. A missing collection is an empty one rather than null, and an
//          empty document state is a song with no marks, which is the state every imported chart
//          starts in. Equality compares the song and each collection in order, so a reorder of
//          two strokes is a change and an undo of it is observable.
// KEYWORDS: document-state, reducer-target, ink-layer, annotations, text-cues, divisions,
//           structural-layer, value-semantics
part of 'oplog.dart';

/// The value the chart event families reduce: a song with its anchored objects.
class DocumentState {
  /// Creates a document over [song] with the given anchored [strokes], [annotations],
  /// [textCues] and [divisions].
  const DocumentState({
    required this.song,
    this.strokes = const <InkStroke>[],
    this.annotations = const <Annotation>[],
    this.textCues = const <TextCue>[],
    this.divisions = const <BarDivision>[],
  });

  /// The written music: sections, bars, chords and notes.
  final Song song;

  /// The committed handwritten strokes, in render order.
  final List<InkStroke> strokes;

  /// The marks attached to anchored places, in render order.
  final List<Annotation> annotations;

  /// The text remarks attached to anchored places, in render order.
  final List<TextCue> textCues;

  /// The bar divisions the document holds, recognised from ink or drawn by the musician.
  ///
  /// The STRUCTURED layer that stands beside [strokes] rather than replacing it: a division is the
  /// ideal line the application draws and can act on, and the stroke it was recognised from stays
  /// in [strokes] so that a misrecognition can be undone and the file keeps what was written (D37
  /// rule 5). A document with no divisions is the state every chart is in until recognition runs,
  /// which is why the default is empty and why nothing else in the document changes when it is.
  final List<BarDivision> divisions;

  /// Returns a copy of this document with the given fields replaced.
  ///
  /// A null argument leaves that field unchanged, so an empty collection must be passed
  /// explicitly as `const <T>[]` to clear one — the same rule the model's other copy helpers
  /// follow, because a nullable parameter that also means "clear" cannot be distinguished from
  /// one that means "leave alone".
  DocumentState copyWith({
    Song? song,
    List<InkStroke>? strokes,
    List<Annotation>? annotations,
    List<TextCue>? textCues,
    List<BarDivision>? divisions,
  }) => DocumentState(
    song: song ?? this.song,
    strokes: strokes ?? this.strokes,
    annotations: annotations ?? this.annotations,
    textCues: textCues ?? this.textCues,
    divisions: divisions ?? this.divisions,
  );
  @override
  bool operator ==(Object other) =>
      other is DocumentState &&
      other.song == song &&
      _sameList<InkStroke>(other.strokes, strokes) &&
      _sameList<Annotation>(other.annotations, annotations) &&
      _sameList<TextCue>(other.textCues, textCues) &&
      _sameList<BarDivision>(other.divisions, divisions);
  @override
  int get hashCode => Object.hash(
    song,
    Object.hashAll(strokes),
    Object.hashAll(annotations),
    Object.hashAll(textCues),
    Object.hashAll(divisions),
  );
  @override
  String toString() =>
      'DocumentState($song, ${strokes.length} stroke(s), '
      '${annotations.length} annotation(s), ${textCues.length} text cue(s), '
      '${divisions.length} division(s))';

  /// Whether two lists hold equal elements in the same order.
  static bool _sameList<T>(List<T> left, List<T> right) {
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
}
