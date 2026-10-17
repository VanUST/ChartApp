// PURPOSE: Hold a whole chart as the single source of truth for what is written: its identity,
//          its metadata, its key, and its sections in order. Everything a musician sees is
//          derived from this value; nothing else stores a second version of it.
// INPUTS: Identity and metadata, a key, and an ordered list of sections.
// OUTPUTS: An immutable Song plus the lookups the rest of the system needs: a section by id, a
//          bar by section id and index, and the written bars in reading order. Song equality
//          compares every part including the sections in order.
// KEYWORDS: song, chart, document, source-of-truth, written-form, section-lookup, anchor-address
//
// What this value deliberately does NOT contain: the play order. Repeats, alternative endings
// and navigation are written into the bars, and expanding them into the order a musician plays
// is a pure function over this value. Storing the expansion as well would create a second
// version of the same music, and the two would eventually disagree about a chart that had been
// edited — with no way to tell which one the musician is reading.
import '../key.dart';
import 'bar.dart';
import 'section.dart';

/// A chart: the unit a musician saves, shares and transposes.
class Song {
  /// Creates a song with the given metadata and [sections].
  const Song({
    this.id = '',
    required this.title,
    this.composer = '',
    this.style = '',
    this.key = Key.cMajor,
    this.tempo = 0,
    this.sections = const <Section>[],
  });

  /// The document identity used by the event log, or an empty string before the store assigns
  /// one.
  final String id;

  /// The title as written.
  final String title;

  /// The composer as written, in whatever order the format stores it.
  final String composer;

  /// The style or feel as written, such as "Ballad" or "Medium Swing". Free text: the values are
  /// iReal's, not this model's, and inventing an enum would reject styles the format adds later.
  final String style;

  /// The key the chart is written in.
  final Key key;

  /// The tempo in beats per minute, or 0 when the chart sets none.
  ///
  /// Zero rather than null because 0 is what the format writes for "unset", and mapping it to
  /// null here would mean the importer converts a value and the exporter converts it back — two
  /// chances to lose the distinction between "no tempo" and "a tempo of zero", which is not a
  /// tempo any chart can have anyway.
  final int tempo;

  /// The sections of the song, in written order.
  final List<Section> sections;

  /// Every bar in reading order: sections in order, and each section's bars in order.
  ///
  /// This is the written order, NOT the order the tune is played. Use the play-order expansion
  /// for that; the two differ as soon as a chart contains a repeat.
  List<Bar> get barsInReadingOrder => <Bar>[
    for (final Section section in sections) ...section.bars,
  ];

  /// How many bars the chart contains as written.
  int get writtenBarCount => sections.fold<int>(
    0,
    (int total, Section section) => total + section.bars.length,
  );

  // PURPOSE: Find a section by the id an anchor holds, so a consumer that was given an anchor can
  //          resolve it without knowing the section's position.
  // INPUTS: id — the section identifier to look for.
  // OUTPUTS: The matching section, or null when no section has that id. Returning null rather
  //          than throwing lets a caller decide whether a dangling anchor is an error: during an
  //          import it is a data problem worth reporting, while during a merge it may be a
  //          section that has not arrived yet.
  // KEYWORDS: lookup, section-id, anchor-resolution, dangling-anchor
  /// Returns the section with [id], or null when no section has it.
  Section? sectionById(String id) {
    for (final Section section in sections) {
      if (section.id == id) {
        return section;
      }
    }
    return null;
  }

  // PURPOSE: Resolve an annotation anchor to the bar it points at, which is the operation the
  //          layout engine performs for every annotation on every render.
  // INPUTS: sectionId — the section the anchor names. barIndex — the zero-based index of the bar
  //         within that section, in written order.
  // OUTPUTS: The bar, or null when the section id is unknown or the index is out of range for
  //          that section. Both cases return null rather than throwing, for the same reason as
  //          [sectionById].
  // KEYWORDS: anchor-resolution, bar-lookup, bounds-check, layout-support
  /// Returns the bar an anchor at ([sectionId], [barIndex]) names, or null.
  Bar? barAt(String sectionId, int barIndex) {
    final Section? section = sectionById(sectionId);
    if (section == null || barIndex < 0 || barIndex >= section.bars.length) {
      return null;
    }
    return section.bars[barIndex];
  }

  @override
  bool operator ==(Object other) {
    if (other is! Song ||
        other.id != id ||
        other.title != title ||
        other.composer != composer ||
        other.style != style ||
        other.key != key ||
        other.tempo != tempo) {
      return false;
    }
    if (other.sections.length != sections.length) {
      return false;
    }
    for (int index = 0; index < sections.length; index++) {
      if (other.sections[index] != sections[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    composer,
    style,
    key,
    tempo,
    Object.hashAll(sections),
  );

  @override
  String toString() =>
      'Song(${title.isEmpty ? 'untitled' : title}, $key, ${sections.length} section(s), '
      '$writtenBarCount bar(s))';
}
