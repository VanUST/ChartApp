// PURPOSE: Describe how long a note lasts as the chart WRITES it — a base value, optional dots
//          and an optional tuplet — rather than as a number of milliseconds or ticks. The written
//          form is what the layout engine draws and what the barfill check needs; storing only a
//          duration in ticks would make a triplet indistinguishable from whatever other
//          combination happens to sum to the same length.
// INPUTS: A NoteBase, a dot count and an optional Tuplet.
// OUTPUTS: Immutable values whose duration is reported as an exact rational number of whole
//          notes, so that a bar's contents can be checked for filling exactly. Comparisons use
//          cross-multiplication, so no rounding is involved and two triplets plus a quarter is
//          exactly a half, not approximately.
// KEYWORDS: note-value, duration, dots, tuplet, rational, bar-fill, notation
//
// WHY EXACT RATIONAL ARITHMETIC AND NOT TICKS.
//
// A tick grid large enough for triplets, quintuplets and septuplets has to be a multiple of all
// of their denominators; the usual answer (1920 per whole note) covers 2, 3, 4, 5 and 6 but not
// 7, so a septuplet would silently quantise. Since v1 has no audio at all, the only uses of a
// duration are drawing it and checking that a bar is full — and both are served better by an
// exact fraction than by a grid chosen to be large enough most of the time.

/// The written base value of a note, before dots and tuplets.
enum NoteBase {
  /// A whole note.
  whole(1),

  /// A half note.
  half(2),

  /// A quarter note.
  quarter(4),

  /// An eighth note.
  eighth(8),

  /// A sixteenth note.
  sixteenth(16),

  /// A thirty-second note.
  thirtySecond(32);

  const NoteBase(this.denominator);

  /// How many of this value fit in a whole note.
  final int denominator;
}

/// A tuplet ratio, such as three in the time of two.
class Tuplet {
  /// Creates the ratio [actual] notes in the time of [normal].
  const Tuplet({required this.actual, required this.normal})
    : assert(actual > 0, 'a tuplet counts at least one note'),
      assert(normal > 0, 'a tuplet fits into at least one normal note');

  /// Three in the time of two: the ordinary triplet.
  static const Tuplet triplet = Tuplet(actual: 3, normal: 2);

  /// Five in the time of four.
  static const Tuplet quintuplet = Tuplet(actual: 5, normal: 4);

  /// Seven in the time of four, which a tick grid chosen for triplets cannot express exactly.
  static const Tuplet septuplet = Tuplet(actual: 7, normal: 4);

  /// How many notes are played.
  final int actual;

  /// How many normal notes their total time equals.
  final int normal;

  @override
  bool operator ==(Object other) =>
      other is Tuplet && other.actual == actual && other.normal == normal;

  @override
  int get hashCode => Object.hash(actual, normal);

  @override
  String toString() => '$actual:$normal';
}

/// How long a note lasts, as written.
class NoteValue {
  /// Creates a value lasting [base], extended by [dots], scaled by [tuplet].
  const NoteValue({required this.base, this.dots = 0, this.tuplet})
    : assert(dots >= 0 && dots <= 2, 'a note carries at most two dots');

  /// A plain undotted value.
  const NoteValue.plain(this.base) : dots = 0, tuplet = null;

  /// The written base value.
  final NoteBase base;

  /// How many augmentation dots follow the note: 0, 1 or 2.
  final int dots;

  /// The tuplet the note belongs to, or null when it is not in one.
  final Tuplet? tuplet;

  /// The duration expressed in whole notes: this value over these many of them.
  ///
  /// The arithmetic is exact. A dot adds half of the value again, so one dot multiplies by 3/2
  /// and two dots by 7/4. A tuplet of `actual:normal` multiplies by `normal/actual`.
  int get wholeNumerator {
    final Tuplet? ratio = tuplet;
    return (pow2(dots + 1) - 1) * (ratio?.normal ?? 1);
  }

  /// The denominator of [wholeNumerator].
  int get wholeDenominator =>
      base.denominator * pow2(dots) * (tuplet?.actual ?? 1);

  // PURPOSE: Compare two written durations exactly, so that a bar can be checked for being full
  //          without floating point and without a tick grid.
  // INPUTS: other — the value to compare with.
  // OUTPUTS: Negative, zero or positive as this value is shorter than, equal to, or longer than
  //          [other]. Two values written differently but equal in length compare equal: a dotted
  //          quarter and a quarter tied to an eighth are the same duration, and the caller
  //          decides whether that matters musically.
  // KEYWORDS: comparison, cross-multiplication, exact-arithmetic, bar-fill
  /// Compares this value's duration with [other]'s, exactly.
  int compareDuration(NoteValue other) {
    final int left = wholeNumerator * other.wholeDenominator;
    final int right = other.wholeNumerator * wholeDenominator;
    return left.compareTo(right);
  }

  /// Whether two written values last exactly as long.
  bool hasSameDurationAs(NoteValue other) => compareDuration(other) == 0;

  @override
  bool operator ==(Object other) =>
      other is NoteValue &&
      other.base == base &&
      other.dots == dots &&
      other.tuplet == tuplet;

  @override
  int get hashCode => Object.hash(base, dots, tuplet);

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer(base.name);
    for (int i = 0; i < dots; i++) {
      buffer.write('.');
    }
    final Tuplet? ratio = tuplet;
    if (ratio != null) {
      buffer.write(' (${ratio.actual}:${ratio.normal})');
    }
    return buffer.toString();
  }
}

// PURPOSE: Raise two to [exponent], used only for dot arithmetic where the exponents are 0, 1 or
//         2. Written rather than pulled from dart:math so that the calculation stays visible and
//          the package keeps its empty dependency list.
// INPUTS: exponent — a non-negative integer.
// OUTPUTS: Two to that power. A negative exponent returns 1, because a dot count cannot be
//          negative and a silent wrong answer here would be worse than an obvious one.
// KEYWORDS: power, dots, integer-arithmetic
/// Returns two to the power [exponent], or 1 for a negative exponent.
int pow2(int exponent) {
  int result = 1;
  for (int i = 0; i < exponent; i++) {
    result *= 2;
  }
  return result;
}
