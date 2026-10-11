// PURPOSE: Read the two figures a musician TYPES for a bar's meter, and refuse — as a typed
//          failure rather than a silent correction — anything that is not a meter this model can
//          hold. Owner decision D22 requires M/N entry by hand with no fixed list, so the keyboard
//          is the control and this is the one place the typed text becomes a [TimeSignature]; a
//          numerator of 0, a negative figure, a fraction and a figure nobody could mean are all
//          answered with which FIELD was wrong and WHY, in a form the interface can word in the
//          musician's own language.
// INPUTS: Two strings, exactly as they were typed: the numerator `M` and the denominator `N`.
// OUTPUTS: A [TimeSignature] when both read as a positive whole number within [maxMeterFigure], or
//          a thrown [MeterInputException] carrying the offending field and the kind of problem.
//          Nothing is defaulted, clamped or rounded: `0/0`, `-3/4`, `4/` and `999/4` all fail, and
//          each failure names itself.
// KEYWORDS: meter, time-signature, m-over-n, typed-input, validation, typed-refusal,
//           no-silent-correction, jazz
//
// WHY THERE IS NO LIST OF ALLOWED METERS. The requirement is that a jazz musician can write 15/8
// and anything else he writes; a list would turn "the tune is in 7/8" into "that meter is not in
// the app", which is a refusal of the music rather than of a typo. The only numbers refused are
// ones that are not a meter at all (0, negative, fractional) and ones so large that the bar they
// describe could not be drawn.
//
// WHY THE UPPER BOUND IS A PRODUCT DECISION AND NOT A MEASUREMENT. [maxMeterFigure] exists because a
// bar's cell count is its numerator (or a third of it in a compound meter), so a numerator of ten
// thousand would ask the layout for ten thousand columns on a page. 64 is above every figure a
// musician was observed writing and far above anything a stave can hold; a chart that really needs
// more is a chart this renderer could not print anyway, and saying so is better than silently
// producing a page of unreadable slivers.

import '../song/time_signature.dart';

/// The largest numerator or denominator the typed-meter reader accepts.
///
/// See the note above on why this is a bound at all. It bounds the TYPED input only; a meter read
/// back from a `.chart` file is bounded by nothing but positivity, because refusing a file the
/// musician already saved is a worse outcome than loading a figure this reader would not have
/// accepted.
const int maxMeterFigure = 64;

/// Which of a meter's two figures a reader or a refusal is talking about.
enum MeterField {
  /// The numerator — the number above the line, and the number of beats the bar is counted in.
  numerator,

  /// The denominator — the number below the line, naming the note value that gets the beat.
  denominator,
}

/// Why a typed figure is not one this model can hold.
enum MeterFigureProblem {
  /// The field was left empty.
  empty,

  /// The field holds something that is not a whole number — letters, a fraction, a decimal.
  notAnInteger,

  /// The field reads as a whole number that is zero or negative. A bar of no beats is not a meter.
  notPositive,

  /// The field reads as a whole number larger than [maxMeterFigure].
  tooLarge,
}

/// Thrown when the two typed figures do not read as a meter.
///
/// It carries the PROBLEM rather than a sentence, because the sentence belongs to the interface and
/// has to be written in the musician's language: this class is in a package that deliberately holds
/// no user-facing text.
class MeterInputException implements Exception {
  /// Creates a refusal of [field] for [problem].
  const MeterInputException({required this.field, required this.problem});

  /// Which figure could not be read.
  final MeterField field;

  /// What was wrong with it.
  final MeterFigureProblem problem;

  @override
  String toString() => 'MeterInputException(${field.name}: ${problem.name})';
}

// PURPOSE: Turn the two typed figures into a meter, or report which one is wrong.
// INPUTS: numerator and denominator — the text of the two fields, exactly as typed; surrounding
//         spaces are ignored, so ` 3 ` and `3` are the same figure.
// OUTPUTS: A [TimeSignature]. Otherwise throws [MeterInputException]: the NUMERATOR is checked
//          first, so a musician who typed two wrong figures is told about the first one to fix.
//          An empty field is [MeterFigureProblem.empty] rather than "not a number", because a form
//          that says "not a number" about a blank box is not telling the musician what to do.
// KEYWORDS: parse, validate, meter, typed-refusal, field-ordered, total-or-throw
/// Returns the meter the two typed figures name, or throws [MeterInputException].
TimeSignature parseMeterFigures({
  required String numerator,
  required String denominator,
}) {
  final int m = _figure(numerator, MeterField.numerator);
  final int n = _figure(denominator, MeterField.denominator);
  return TimeSignature(numerator: m, denominator: n);
}

// PURPOSE: Read one typed figure, keeping "which field" and "what is wrong" together so the caller
//          above is three lines and neither of the two fields can be validated differently.
// INPUTS: text — the field's text. field — which field it is, carried into the thrown refusal.
// OUTPUTS: The positive whole number the text names, at most [maxMeterFigure]. Throws
//          [MeterInputException] for an empty field, a non-integer, a figure below one and a figure
//          above the bound, each named by its own problem.
// KEYWORDS: figure, validation, empty-is-not-nan, no-coercion, typed-refusal
int _figure(String text, MeterField field) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw MeterInputException(field: field, problem: MeterFigureProblem.empty);
  }
  final int? value = int.tryParse(trimmed);
  if (value == null) {
    throw MeterInputException(
      field: field,
      problem: MeterFigureProblem.notAnInteger,
    );
  }
  if (value < 1) {
    throw MeterInputException(
      field: field,
      problem: MeterFigureProblem.notPositive,
    );
  }
  if (value > maxMeterFigure) {
    throw MeterInputException(
      field: field,
      problem: MeterFigureProblem.tooLarge,
    );
  }
  return value;
}
