// PURPOSE: Name a RUN OF BARS — a zone — that one edit acts on, and read one back from the bar
//          numbers a musician types. Owner decision D22 was extended by the owner's own words to
//          ask for zones rather than a per-bar decision: "задавать ЗОНАМИ как тональность, так и
//          размер". This file is the VALUE-NEUTRAL half of that surface: it knows which bars an
//          edit covers and nothing about what is written on them, so the same range can carry a
//          meter today and a key when the model grows a per-bar key.
// INPUTS: A section id and two bar numbers, either as the zero-based indices the model addresses
//         ([resolveBarRange]) or as the ONE-BASED figures a musician typed ([readBarRange], with the
//         song those figures must exist in).
// OUTPUTS: An immutable [BarRange] reporting its length and the bars it covers, or a thrown
//          [BarRangeException] carrying a [BarRangeProblem] and — when the refusal is about one end
//          of the run — the [BarRangeField] it is about. Nothing is clamped and nothing is
//          reordered: a run whose last bar is before its first is REFUSED rather than quietly
//          swapped, because a zone the musician described backwards is a zone they will want to
//          correct, not one the application should reinterpret.
// KEYWORDS: bar-range, zone, range-edit, whole-section, typed-refusal, value-neutral, d22
//
// WHY THE BAR IS STILL THE UNIT AND THE RANGE IS ONLY A GESTURE.
//
// `Bar.timeSignature` is a field of every bar, so a meter is stored per bar and stays that way: the
// range is not a second kind of state, it is the shape of the EDIT a musician makes. Nothing here
// introduces a "zone" that a bar belongs to — that would be a second answer to "what meter is this
// bar in", and the two answers could disagree after a bar is inserted at the edge of one.
//
// WHY THE TYPED FIGURES ARE ONE-BASED AND THE MODEL'S INDICES ARE NOT. A musician counts the first
// bar of a section as bar 1 and says so; every address in this model is zero-based. Converting in
// ONE function ([readBarRange]) is what keeps the conversion from being repeated at each call site,
// where the first call site to get it wrong would be off by one bar without anything failing.
import '../song/section.dart';
import '../song/song.dart';

/// A run of bars inside one section, both ends inclusive.
class BarRange {
  /// Creates a range covering [firstBar]..[lastBar] of [sectionId], zero-based.
  ///
  /// The constructor does not validate: it is the value a resolved range is made of, and the
  /// validating doors are [resolveBarRange] and [readBarRange]. A caller that builds one directly is
  /// a caller that already knows the bars exist — the sheet's own "the whole section" and a test
  /// fixture.
  const BarRange({
    required this.sectionId,
    required this.firstBar,
    required this.lastBar,
  });

  /// The section the bars belong to.
  final String sectionId;

  /// Zero-based index of the first bar the run covers.
  final int firstBar;

  /// Zero-based index of the last bar the run covers, which is not before [firstBar] in any range
  /// the validating doors produced.
  final int lastBar;

  /// How many bars the run covers.
  int get length => lastBar - firstBar + 1;

  /// The bars the run covers, in reading order.
  List<int> get barIndices => <int>[
    for (int index = firstBar; index <= lastBar; index++) index,
  ];

  @override
  bool operator ==(Object other) =>
      other is BarRange &&
      other.sectionId == sectionId &&
      other.firstBar == firstBar &&
      other.lastBar == lastBar;

  @override
  int get hashCode => Object.hash(sectionId, firstBar, lastBar);

  @override
  String toString() => '$sectionId#$firstBar..$lastBar';
}

/// Which end of a run a refusal is about, so the surface can point at the field to correct.
enum BarRangeField {
  /// The first bar of the run.
  first,

  /// The last bar of the run.
  last,
}

/// Why the bars a musician described are not a run this model can name.
enum BarRangeProblem {
  /// One of the two bar numbers was left blank.
  empty,

  /// One of the two bar numbers is not a whole number — letters, a fraction, a decimal.
  notAnInteger,

  /// The run names a section the song does not have.
  noSuchSection,

  /// The section has no bars at all, so no run inside it exists.
  emptySection,

  /// One of the two bar numbers is outside the section's bars.
  barOutOfRange,

  /// The last bar comes before the first one.
  reversed,
}

/// Thrown when a described run of bars cannot be named.
///
/// It carries the PROBLEM and the FIELD rather than a sentence, because the sentence belongs to the
/// interface and has to be written in the musician's language.
class BarRangeException implements Exception {
  /// Creates a refusal of [problem], naming the end of the run it is about when there is one.
  const BarRangeException(this.problem, {this.field});

  /// What was wrong with the described run.
  final BarRangeProblem problem;

  /// Which end of the run the refusal is about, or null when it is about the section rather than
  /// about either figure.
  final BarRangeField? field;

  @override
  String toString() =>
      'BarRangeException(${problem.name}${field == null ? '' : ', ${field!.name}'})';
}

// PURPOSE: Read a run a musician described into a run that exists, or report why it does not.
// INPUTS: song — the chart. sectionId — the section the two figures count in. firstBar and lastBar —
//         ZERO-BASED bar indices inside that section, inclusive, exactly as the model addresses
//         them; [readBarRange] does the conversion from the musician's one-based counting.
// OUTPUTS: The [BarRange]. Otherwise throws [BarRangeException]:
//            - a section the song does not have: [BarRangeProblem.noSuchSection];
//            - a section with no bars: [BarRangeProblem.emptySection];
//            - either index outside `0..bars-1`: [BarRangeProblem.barOutOfRange], with the FIELD
//              naming the end that was wrong — the first one if both are;
//            - a last bar before the first: [BarRangeProblem.reversed], with FIELD `last`, checked
//              LAST so a backwards pair that is also out of range reports the range first, the fact
//              the musician has to fix before the order matters.
// KEYWORDS: resolve, validate, typed-refusal, no-clamp, order-aware, total-or-throw
/// Returns the run the two indices name, or throws [BarRangeException].
BarRange resolveBarRange({
  required Song song,
  required String sectionId,
  required int firstBar,
  required int lastBar,
}) {
  final Section? section = song.sectionById(sectionId);
  if (section == null) {
    throw const BarRangeException(BarRangeProblem.noSuchSection);
  }
  final int count = section.bars.length;
  if (count == 0) {
    throw const BarRangeException(BarRangeProblem.emptySection);
  }
  if (firstBar < 0 || firstBar >= count) {
    throw const BarRangeException(
      BarRangeProblem.barOutOfRange,
      field: BarRangeField.first,
    );
  }
  if (lastBar < 0 || lastBar >= count) {
    throw const BarRangeException(
      BarRangeProblem.barOutOfRange,
      field: BarRangeField.last,
    );
  }
  if (lastBar < firstBar) {
    throw const BarRangeException(
      BarRangeProblem.reversed,
      field: BarRangeField.last,
    );
  }
  return BarRange(sectionId: sectionId, firstBar: firstBar, lastBar: lastBar);
}

// PURPOSE: Read the two bar numbers a musician TYPED into a run of bars, so the zone surface and the
//          model agree about which bars a gesture covers.
// INPUTS: song — the chart. sectionId — the section the numbers count in, normally the sheet's
//         cursor. first and last — the text of the two fields, ONE-BASED as a musician counts a
//         section's bars, with surrounding spaces ignored.
// OUTPUTS: The [BarRange] the two figures name, zero-based. Otherwise throws
//          [BarRangeException]: a blank field is [BarRangeProblem.empty] for its own FIELD, a
//          non-integer is [BarRangeProblem.notAnInteger], and the domain checks are
//          [resolveBarRange]'s, with the field it identifies. A figure of `0` or a negative figure
//          is therefore `barOutOfRange`, which is what it is: a bar number a musician cannot point
//          at. Nothing is clamped: `0` does not become bar 1.
// KEYWORDS: typed-input, one-based, conversion, validation, typed-refusal, single-conversion-point
/// Returns the run the two typed bar numbers name, or throws [BarRangeException].
BarRange readBarRange({
  required Song song,
  required String sectionId,
  required String first,
  required String last,
}) {
  final int firstNumber = _barNumber(first, BarRangeField.first);
  final int lastNumber = _barNumber(last, BarRangeField.last);
  return resolveBarRange(
    song: song,
    sectionId: sectionId,
    firstBar: firstNumber - 1,
    lastBar: lastNumber - 1,
  );
}

// PURPOSE: Read one typed bar number, keeping "which field" and "what is wrong" together so the two
//          figures cannot be validated differently.
// INPUTS: text — the field's text. field — which end it is, carried into the thrown refusal.
// OUTPUTS: The whole number the text names, or a thrown [BarRangeException] for a blank field
//          ([BarRangeProblem.empty]) or a non-integer ([BarRangeProblem.notAnInteger]). The range
//          checks are NOT done here: whether the number names a bar depends on the song, which this
//          function does not have, and a second copy of that check would drift from
//          [resolveBarRange].
// KEYWORDS: figure, parse, empty-is-not-nan, no-coercion, field-aware
int _barNumber(String text, BarRangeField field) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw BarRangeException(BarRangeProblem.empty, field: field);
  }
  final int? value = int.tryParse(trimmed);
  if (value == null) {
    throw BarRangeException(BarRangeProblem.notAnInteger, field: field);
  }
  return value;
}
