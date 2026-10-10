// PURPOSE: Group bars into the named sections a musician reads as the form of a tune — intro,
//          verse, A, B, a custom label — and give each section a stable identity so that an
//          annotation anchor can name a place without depending on where the section currently
//          sits in the song.
// INPUTS: A stable id, a label, and an ordered list of bars.
// OUTPUTS: Immutable values. Section equality compares the id, the label and the bars in order.
// KEYWORDS: section, rehearsal-mark, form, anchor-identity, chart-structure
import 'bar.dart';

/// What kind of label a section carries.
enum SectionKind {
  /// A rehearsal letter such as A, B or C. Note that in this format a letter is just a name: B
  /// is not a bridge and C is not a chorus, and reading them as such would invent a convention
  /// the format does not have.
  letter,

  /// An intro, written `*i`.
  intro,

  /// A verse, written `*V`.
  verse,

  /// Any other label the format allows, preserved as written.
  custom,
}

/// The label printed at the start of a section.
class SectionLabel {
  /// Creates a label of [kind] carrying [text].
  const SectionLabel({required this.kind, required this.text});

  /// Creates a rehearsal-letter label such as A.
  const SectionLabel.letter(this.text) : kind = SectionKind.letter;

  /// Creates an intro label.
  const SectionLabel.intro() : kind = SectionKind.intro, text = '';

  /// Creates a verse label.
  const SectionLabel.verse() : kind = SectionKind.verse, text = '';

  /// Creates a label the format permits but this model does not classify.
  const SectionLabel.custom(this.text) : kind = SectionKind.custom;

  /// What kind of label this is.
  final SectionKind kind;

  /// The label as written, empty for kinds that carry no text.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SectionLabel && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => switch (kind) {
    SectionKind.intro => 'intro',
    SectionKind.verse => 'verse',
    SectionKind.letter => text,
    SectionKind.custom => text,
  };
}

/// A run of bars under one label.
class Section {
  /// Creates the section identified by [id] with [label] and [bars].
  const Section({
    required this.id,
    required this.label,
    this.bars = const <Bar>[],
  });

  /// A stable identifier for this section, used by annotation anchors.
  ///
  /// It must NOT be derived from the section's position. Inserting an intro at the top of a tune
  /// would then renumber every section and detach every annotation in the song from the bar it
  /// was drawn on. The id is assigned once, by whoever creates the section, and survives
  /// reordering.
  final String id;

  /// The label printed at the start of this section.
  final SectionLabel label;

  /// The bars of this section, in written order.
  ///
  /// The index of a bar in this list, together with the section id, is the address an annotation
  /// anchor uses.
  final List<Bar> bars;

  @override
  bool operator ==(Object other) {
    if (other is! Section || other.id != id || other.label != label) {
      return false;
    }
    if (other.bars.length != bars.length) {
      return false;
    }
    for (int index = 0; index < bars.length; index++) {
      if (other.bars[index] != bars[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, label, Object.hashAll(bars));

  @override
  String toString() => 'Section($id, $label, ${bars.length} bar(s))';
}
