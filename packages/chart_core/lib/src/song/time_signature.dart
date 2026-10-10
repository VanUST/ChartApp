// PURPOSE: Describe the meter of a bar. A chart changes meter mid-song, so a time signature is
//          not a property of the song but state carried by each bar; modelling it as song-level
//          would force the importer to invent a "default" and then lose every change.
// INPUTS: A numerator and a denominator, both positive.
// OUTPUTS: An immutable value reporting how many chart cells a bar of this meter offers, and a
//          rendering such as "4/4" for a log line or a test failure.
// KEYWORDS: time-signature, meter, compound-meter, cells-per-bar, chart-notation
//
// The cell count is ADVISORY and nothing enforces it. iReal pads a measure to its cell count but
// real exports contain bars with fewer cells than the meter implies, so a bar stores its chords
// sparsely and a consumer that demanded exactly [cellsPerBar] entries would reject valid input.

/// A time signature, such as 4/4 or 6/8.
class TimeSignature {
  /// Creates the signature [numerator]/[denominator].
  const TimeSignature({required this.numerator, required this.denominator});

  /// Four-four, the meter a chart assumes when it says nothing.
  static const TimeSignature fourFour = TimeSignature(
    numerator: 4,
    denominator: 4,
  );

  /// Three-four.
  static const TimeSignature threeFour = TimeSignature(
    numerator: 3,
    denominator: 4,
  );

  /// Two-four.
  static const TimeSignature twoFour = TimeSignature(
    numerator: 2,
    denominator: 4,
  );

  /// Six-eight, a compound duple meter.
  static const TimeSignature sixEight = TimeSignature(
    numerator: 6,
    denominator: 8,
  );

  /// Beats per bar as written above the line.
  final int numerator;

  /// The note value that receives the beat, as written below the line.
  final int denominator;

  /// How many chart cells a bar of this meter offers.
  ///
  /// In a simple meter this is the numerator, because a chart gives one cell per beat. In a
  /// compound meter — a denominator of 8 with a numerator divisible by three — the beat is the
  /// dotted quarter, so 6/8 offers two cells and 12/8 offers four, not six and twelve. A meter
  /// that is neither, such as 7/8, falls back to the numerator: 7/8 is genuinely seven uneven
  /// beats, and pretending it is compound would be a worse lie than counting it plainly.
  ///
  /// This value is not enforced anywhere. See the note at the top of this file.
  int get cellsPerBar {
    if (denominator == 8 && numerator % 3 == 0 && numerator >= 6) {
      return numerator ~/ 3;
    }
    return numerator;
  }

  @override
  bool operator ==(Object other) =>
      other is TimeSignature &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}
