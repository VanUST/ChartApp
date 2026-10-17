// PURPOSE: Turn the pitched notes a bar carries (`Bar.melody`) into the geometry of an engraved
//          melody staff: where each notehead's centre lies on the five lines, how many ledger lines
//          its pitch needs, which way its stem points, WHICH NOTES ONE BEAM JOINS AND WHERE THAT
//          BEAM LIES, where its accidental and its augmentation dot are drawn, and the two
//          endpoints and control point of the curve that joins a tied pair. This is the arithmetic
//          half of engraving, kept beside the layout engine rather than inside the painter for the
//          same reason the engine itself is pure: a notehead's position and a beam's grouping are
//          musical statements, and they must be assertable without a device and without a window.
// INPUTS: A `note.dart` pitch and its bar address, plus the geometry the layout engine already
//         decided — the bar's left edge and width, the y of the staff's middle line, the distance
//         between two staff lines, and the x of each of the bar's cells. The proportions of every
//         glyph live in a [MelodyMetrics] value the caller passes, so a test can make an exact
//         expected geometry obvious and a different engraving density is a different value rather
//         than an edit to this file.
// OUTPUTS: Immutable [MelodyGlyph] values and the [PlacedMelodyStaff] that holds them. Every glyph
//          carries its own bounding box in PAGE coordinates, so the painter draws the box it was
//          handed rather than re-deriving a position from a pitch. A note whose pitch lies beyond
//          what five ledger lines can write is CLAMPED to the last writable position rather than
//          dropped; see [melodyStepOf] for why that direction of failure is chosen.
// KEYWORDS: melody-staff, engraving-geometry, notehead, stem, flag, beam, ledger-line, accidental,
//           tie, staff, pure-dart, notation
import '../pitch.dart';
import '../song/bar.dart';
import '../song/note.dart';
import '../song/note_value.dart';
import '../song/time_signature.dart';
import 'geometry.dart';

/// The proportions every melody glyph is drawn at, in multiples of one staff space.
///
/// ONE VALUE RATHER THAN FIFTEEN CONSTANTS because they are one decision: how dense the engraving
/// is. A caller that wants a different density — a page engraved for a small screen, a test that
/// makes an expected coordinate round — replaces the value, and nothing in the placement arithmetic
/// has to be read again.
class MelodyMetrics {
  /// Creates a metrics value, with every proportion defaulted to the ordinary engraving.
  const MelodyMetrics({
    this.noteheadWidth = 1.2,
    this.noteheadHeight = 0.9,
    this.stemLength = 3.5,
    this.strokeWidth = 0.12,
    this.flagLength = 1.1,
    this.dotRadius = 0.22,
    this.accidentalWidth = 0.55,
    this.accidentalGap = 0.45,
    this.accidentalHeight = 1.7,
    this.tieClearance = 0.2,
    this.tieMinimumInset = 0.3,
    this.tieArch = 0.5,
    this.ledgerWidth = 2.6,
    this.beamThickness = 0.5,
    this.beamGap = 0.25,
    this.beamSlopeLimit = 0.5,
    this.beamletLength = 1,
  });

  /// How wide a notehead is, in staff spaces.
  final double noteheadWidth;

  /// How tall a notehead is, in staff spaces.
  ///
  /// A little under one space so that a notehead on a line and one in the neighbouring space do not
  /// touch, which is what makes a chord of stacked thirds read as one object rather than several.
  final double noteheadHeight;

  /// How far a stem reaches beyond its notehead, in staff spaces.
  final double stemLength;

  /// The weight of every line the staff draws: the five staff lines, a stem, a ledger line and a
  /// tie.
  final double strokeWidth;

  /// How far a flag reaches past the end of a stem, in staff spaces.
  final double flagLength;

  /// The half-width of an augmentation dot, in staff spaces.
  final double dotRadius;

  /// How wide one accidental character is, in staff spaces.
  final double accidentalWidth;

  /// The gap between an accidental and the notehead it belongs to, in staff spaces.
  ///
  /// Nearly half a space, which is what an engraved accidental keeps clear of its notehead. The
  /// box is `glyph text + this gap` wide, and the text itself is measured with the font stack, so
  /// this is the only number that decides how far the sign stands off the note.
  final double accidentalGap;

  /// The height of an accidental's box, in staff spaces.
  final double accidentalHeight;

  /// How far inside a notehead a tie's own endpoint lies, as a fraction of the notehead's width.
  ///
  /// A tie starts inside the notehead it leaves and ends inside the notehead it reaches, which is
  /// how an engraved tie looks: it grows out of the note rather than floating beside it.
  final double tieClearance;

  /// The least a tie's endpoint clears its notehead by, in staff spaces, whatever
  /// [tieClearance] works out to.
  final double tieMinimumInset;

  /// How far a tie's control point bulges away from the straight line between its ends, as a
  /// fraction of the distance between them.
  final double tieArch;

  /// How wide a ledger line is, in staff spaces.
  final double ledgerWidth;

  /// How thick a beam is, in staff spaces.
  ///
  /// HALF A SPACE IS THE CONVENTION, AND IT IS WHY A BEAM READS AS A BEAM. A stem is a hairline
  /// ([strokeWidth], about an eighth of a space) and a beam is roughly four times that, which is
  /// what tells a reader at a glance that two noteheads are joined rather than merely adjacent.
  /// Drawn at a stem's weight the group would read as two notes with a rule between them, and at a
  /// notehead's height it would read as a ledger line lying across the staff.
  final double beamThickness;

  /// The clear space between two beams of one group, in staff spaces.
  ///
  /// Half the beam's own thickness, which is the ordinary engraved proportion: the pair of beams
  /// over sixteenths must read as two strokes with a gap, because an engraver who lets them touch
  /// has drawn one beam of double weight and told the reader the value is an eighth.
  final double beamGap;

  /// The steepest a beam may slope, in staff spaces of rise per staff space of run.
  ///
  /// A BEAM FOLLOWS THE CONTOUR OF ITS GROUP AND IS NOT ALLOWED TO RUN AWAY WITH IT. Notes a step
  /// apart horizontally (which is what a beat's notes are) and a step apart vertically would give a
  /// slope of about a third at these proportions, which is inside this limit — so a scale run is
  /// drawn as it sounds. A leap of a fifth across one gap would ask for a slope near two, and a
  /// beam at that angle reads as a line drawn by mistake rather than as a joining of notes; it is
  /// limited to a half, and the stems take up the difference.
  final double beamSlopeLimit;

  /// How far a partial beam reaches from its own stem, in staff spaces.
  ///
  /// A partial beam is the short stroke a sixteenth carries when its neighbours in the group are
  /// eighths: the value's second beam has no partner to run to, so it is drawn as a stub whose
  /// length is this, always stopping short of the neighbouring stem so it cannot be read as
  /// joining it.
  final double beamletLength;

  /// How far a later note on the same beat moves right of the first, in staff spaces.
  final double stepOffset = 1.6;
}

/// What a melody glyph is, which is the whole of what the painter needs in order to draw it.
///
/// One value rather than a class per element because the painter walks one list in a fixed order
/// and switches on the kind: a second list per element type would have to be ordered against the
/// first by hand, and two orderings is exactly how a stem ends up drawn over the notehead it
/// belongs to on one page and under it on another.
enum MelodyGlyphKind {
  /// A filled or hollow ellipse centred on the note's line or space.
  notehead,

  /// The vertical stroke from a notehead's edge.
  stem,

  /// The curve of a flag on a stem, for a note that is beamed to nothing: an eighth note or shorter
  /// whose beat holds no other note it could join.
  flag,

  /// A thick, straight, possibly slanted stroke joining two or more stems: the beam that makes a run
  /// of eighth notes or shorter ONE rhythmic group rather than several.
  ///
  /// Its geometry is [MelodyGlyph.from] and [MelodyGlyph.to] — two ends of one line — plus
  /// [MelodyGlyph.strokeWidth] for its thickness, because a beam is nothing but a heavy line. A
  /// group of sixteenths carries two of these, one per beam; a mixed group carries a full-width one
  /// and shorter ones over the notes that need them.
  beam,

  /// A sharp, flat or natural drawn to the left of a notehead.
  accidental,

  /// An augmentation dot beside a notehead.
  dot,

  /// A horizontal line through a notehead that lies outside the five staff lines.
  ledgerLine,

  /// The curve joining the sound of one note to the next in [BeatNote.tiedToNext].
  tie,
}

/// One drawn piece of a melody staff.
///
/// The [bounds] box is in page coordinates and is the box the painter draws in. For a notehead the
/// box is the ellipse's bounding box; for a line or a stem it is thin in one direction and the
/// painter uses [strokeWidth] for its weight; for an accidental it is the box of the glyph text and
/// [text] carries it. A tie is the ONE kind whose box is not the whole of its geometry: its curve
/// is the three points [from], [control] and [to], and the box is the bounding box of those three,
/// published so that a caller measuring what a system needs still does not have to reconstruct the
/// curve. A beam is the same shape of statement — one line, two ends — with no curve and no control
/// point.
class MelodyGlyph {
  /// Creates a glyph of [kind] occupying [bounds].
  const MelodyGlyph({
    required this.kind,
    required this.bounds,
    this.text,
    this.stemUp = false,
    this.flagLength = 0,
    this.strokeWidth = 0,
    this.filled = true,
    this.from = LayoutOffset.zero,
    this.control = LayoutOffset.zero,
    this.to = LayoutOffset.zero,
  });

  /// What to draw.
  final MelodyGlyphKind kind;

  /// Where to draw it, in page coordinates.
  final LayoutRect bounds;

  /// The words to draw, for [MelodyGlyphKind.accidental] alone; null for every other kind.
  ///
  /// An accidental is drawn as text rather than as a shaped glyph because this renderer ships no
  /// music font: `#` and `b` read unambiguously to a musician, and it is the same choice the bar
  /// signs already make. The string is also what a screenshot can be read against.
  final String? text;

  /// Whether a stem points up out of its notehead, for [MelodyGlyphKind.stem] alone.
  final bool stemUp;

  /// How far a flag reaches past the end of a stem, in staff spaces; zero when there is none.
  ///
  /// It is carried on the stem rather than derived by the painter from the note's written value,
  /// because the painter is not told the note's value: the layout decided the flag and published
  /// its length, so drawing and reserving cannot disagree about how many flags a note has.
  final double flagLength;

  /// The weight of this glyph's stroke in page pixels; zero for a kind that is not stroked.
  ///
  /// It is STYLE-SCALED — it comes from `LayoutStyle.melodyStaffSpace` through [MelodyMetrics] — so
  /// a page engraved at a different staff size has stems of a proportional weight. A painter that
  /// used a constant of its own would draw a hairline stem on a large staff and a slab on a small
  /// one.
  final double strokeWidth;

  /// Whether a notehead is filled, for [MelodyGlyphKind.notehead] alone.
  ///
  /// False for a whole or a half note, which are engraved hollow.
  final bool filled;

  /// A tie's first endpoint, for [MelodyGlyphKind.tie] alone; a beam's first end for
  /// [MelodyGlyphKind.beam].
  final LayoutOffset from;

  /// A tie's control point, for [MelodyGlyphKind.tie] alone.
  final LayoutOffset control;

  /// A tie's second endpoint, for [MelodyGlyphKind.tie] alone; a beam's second end for
  /// [MelodyGlyphKind.beam].
  final LayoutOffset to;

  @override
  bool operator ==(Object other) =>
      other is MelodyGlyph &&
      other.kind == kind &&
      other.bounds == bounds &&
      other.text == text &&
      other.stemUp == stemUp &&
      other.flagLength == flagLength &&
      other.strokeWidth == strokeWidth &&
      other.filled == filled &&
      other.from == from &&
      other.control == control &&
      other.to == to;

  @override
  int get hashCode => Object.hash(
    kind,
    bounds,
    text,
    stemUp,
    flagLength,
    strokeWidth,
    filled,
    from,
    control,
    to,
  );

  @override
  String toString() =>
      'MelodyGlyph(${kind.name}${text == null ? '' : ' "$text"'} at $bounds)';
}

/// The melody staff of one bar: its five lines and everything drawn on them.
///
/// It is published per BAR rather than per system because a bar is what the layout already
/// addresses: a bar's cells, chords and staff text are all rectangles on the same bar, and a
/// second, system-wide geometry would have to be matched back to the bars it spans in order to draw
/// a barline. The [bounds] of consecutive bars on one system tile exactly, so the five lines read
/// as one continuous staff across the system.
class PlacedMelodyStaff {
  /// Creating a melody staff occupying [bounds].
  const PlacedMelodyStaff({
    required this.bounds,
    this.clef,
    this.glyphs = const <MelodyGlyph>[],
  });

  /// A staff with no extent, for a bar whose system reserved no melody band.
  static const PlacedMelodyStaff empty = PlacedMelodyStaff(
    bounds: LayoutRect(origin: LayoutOffset.zero, size: LayoutSize.zero),
  );

  /// Where the music is written, in page coordinates.
  ///
  /// [LayoutRect.top] is the staff's TOP LINE and [LayoutRect.bottom] is its BOTTOM LINE — the five
  /// lines themselves, not the band around them. The painter draws five lines across this box at an
  /// even spacing, so the box and the lines are one statement rather than two, and a ledger line, a
  /// stem or a barline that has to reach the staff reads its extent from here.
  final LayoutRect bounds;

  /// The clef to print at the staff's opening, or null when this bar does not open a system.
  ///
  /// A clef is a property of a STAFF and not of a bar, so it is printed once, at the system's first
  /// bar, rather than on every bar. It is carried here rather than left to the painter because the
  /// painter is not told which bar opens a system, and a renderer that guessed would print the sign
  /// nine times on a line of nine bars. The string is the conventional letter — `G` for a treble
  /// staff, `F` for a bass staff — which is what a spaced-out `𝄞` on a page with no music font
  /// degrades to anyway.
  final String? clef;

  /// Everything drawn on the staff, in the order it is drawn.
  final List<MelodyGlyph> glyphs;

  /// The distance from the staff's top line to its bottom line.
  double get height => bounds.size.height;

  /// Whether there is anything to draw: a staff with no extent is not drawn.
  bool get isEmpty => bounds.size.height <= 0 || bounds.size.width <= 0;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedMelodyStaff ||
        other.bounds != bounds ||
        other.clef != clef ||
        other.glyphs.length != glyphs.length) {
      return false;
    }
    for (int index = 0; index < glyphs.length; index++) {
      if (other.glyphs[index] != glyphs[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(bounds, clef, Object.hashAll(glyphs));

  @override
  String toString() =>
      'PlacedMelodyStaff($bounds, ${glyphs.length} glyph(s)'
      '${clef == null ? '' : ', clef $clef'})';
}

/// The furthest from the staff [melodyStepOf] will write: ten staff steps beyond the staff's own
/// extent, which is five ledger lines each way.
///
/// The bound is the one `LayoutStyle.melodyBandHeight` reserves room for — the band a song gets once
/// it carries a note. A song whose declared staff is still empty reserves the smaller
/// `LayoutStyle.melodyEmptyBandHeight`, which has no glyphs to bound and therefore never reaches
/// this limit. A note beyond it is
/// clamped to the last writable step ([melodyLowestStep] or [melodyHighestStep]) and its ledger
/// lines stop there, so it is drawn at the wrong pitch — visibly, inside the staff rather than off
/// the page. The alternative, drawing it at its true height, would put the glyph outside the band
/// the system reserved and let it collide with the system below, which is a worse failure: a note in
/// the wrong place on a page whose layout is otherwise sound is read as a wrong note, while a glyph
/// on top of the next system is read as a broken chart.
const int melodyLedgerLimit = 10;

/// The highest staff step a melody band can write, as [melodyStepOf] counts.
const int melodyHighestStep = 8 + melodyLedgerLimit;

/// The lowest staff step a melody band can write, as [melodyStepOf] counts.
const int melodyLowestStep = -melodyLedgerLimit;

// PURPOSE: Place a pitch on the staff as a number of staff steps from its bottom line, which is the
//          one coordinate every other decision on the staff is measured from.
// INPUTS: pitch — the written note. octave — its octave in scientific pitch notation, middle C =
//         C4, which the model stores beside the letter rather than inside it. clef — the staff's
//         clef name, `treble` or `bass`; anything else is read as treble, because a clef this
//         renderer cannot draw must not silently move the music by an octave.
// OUTPUTS: The number of diatonic steps from the staff's bottom line: 0 is E4 on a treble staff
//          (its bottom line), 1 is F4 (the space above it), -1 is D4 (the space below, whose own
//          ledger line is the C beneath it), and the five lines are the even values 0, 2, 4, 6 and
//          8. The result is CLAMPED to `[melodyLowestStep, melodyHighestStep]`, and the clamp is
//          documented on [melodyLedgerLimit].
//
//          THIS FUNCTION WAS OFF BY ONE STAFF LINE FOR EVERY PITCH, AND THE OWNER'S REPORT OF THE
//          RESULT IS WHY IT IS FIXED. It counted from `7 * (octave - 4)`, which puts C4 — not E4 — on
//          the treble staff's bottom line and then never subtracted E's own place in the letter
//          order, so every note was engraved ONE LINE HIGHER than it is written: a written C4 was
//          drawn on the bottom line, which a musician reads as E4, and the accidental of a Db was
//          drawn on a space that names F. Notation whose height does not mean its pitch is not
//          unclear notation, it is wrong notation, and no amount of line weight or staff size
//          repairs it. The bass clef was off by a different amount for the same reason — G2 is
//          twelve steps below E4, not seven — so the two clefs disagreed with each other as well.
//
//          The count is by LETTER and octave, not by sounding pitch: a C is always three steps above
//          the A below it, whatever its octave, which is what keeps a note on its line across the
//          whole range of the staff.
// KEYWORDS: staff-position, diatonic-step, clef, clamping, treble, bass
/// Returns where [pitch] in [octave] sits on a [clef] staff, in staff steps from the bottom line.
int melodyStepOf(
  WrittenNote pitch, {
  required int octave,
  String clef = 'treble',
}) {
  final int letterSteps = _letterOrder(pitch.letter);
  // THE ORIGIN IS THE STAFF'S OWN BOTTOM LINE, AND THE LINE IS NAMED BY THE CLEF. A staff step is
  // half a space, so a letter is two steps from its neighbour and an octave is fourteen: the count
  // is `7 * octave + letter` in absolute 35ths of a staff, and the subtraction puts the clef's bottom
  // line at zero. Treble's bottom line is E4 and bass's is G2.
  final int bottomLine = clef == 'bass'
      ? 7 * 2 + _letterOrder(NoteLetter.g)
      : 7 * 4 + _letterOrder(NoteLetter.e);
  final int step = 7 * octave + letterSteps - bottomLine;
  if (step > melodyHighestStep) {
    return melodyHighestStep;
  }
  if (step < melodyLowestStep) {
    return melodyLowestStep;
  }
  return step;
}

// PURPOSE: Give a letter its position in the C-to-B order the staff is written in, which is the
//          order of the lines rather than the order of the letters by sounding pitch.
// INPUTS: letter — one of the seven note letters.
// OUTPUTS: 0 for C, 1 for D, 2 for E, 3 for F, 4 for G, 5 for A, 6 for B.
// KEYWORDS: note-letter, diatonic-order, staff-position
int _letterOrder(NoteLetter letter) => switch (letter) {
  NoteLetter.c => 0,
  NoteLetter.d => 1,
  NoteLetter.e => 2,
  NoteLetter.f => 3,
  NoteLetter.g => 4,
  NoteLetter.a => 5,
  NoteLetter.b => 6,
};

// PURPOSE: Report the y of a staff step, so that every other position on the staff — a stem's end,
//          a ledger line, an accidental — is derived from one function instead of each repeating
//          the multiplication and the sign.
// INPUTS: staffMiddleLineY — the y of the staff's middle line in page coordinates. staffSpace —
//         the distance between two adjacent lines. step — a staff step, from [melodyStepOf] or
//         from a ledger line's own position.
// OUTPUTS: The y of that step's centre. An increasing step moves UP the page, so the y decreases;
//          the middle line is step 4 for both clefs, which is where the sign in the formula comes
//          from.
// KEYWORDS: staff-step, vertical-position, page-coordinates, middle-line
/// Returns the y on the page of staff [step].
double melodyStepCenterY({
  required double staffMiddleLineY,
  required double staffSpace,
  required int step,
}) => staffMiddleLineY + (4 - step) * (staffSpace / 2);

// PURPOSE: Give the staff step of the ledger line nearest a note that lies outside the staff, so
//          that the line the reader sees is on a LINE position and not halfway between two of them.
// INPUTS: step — a staff step from [melodyStepOf], outside the staff's 0..8 extent.
// OUTPUTS: Null when the note is inside the staff and needs no ledger line. Otherwise the step of
//          the first ledger line, which is the one nearest the staff: one step above the top line
//          when the note is above, and one step below the bottom line when it is below.
//
//          WHY THIS IS A FUNCTION AND NOT A LOOP LIKE. The five staff lines fall on the EVEN steps
//          0, 2, 4, 6 and 8, so the lines above the staff are the odd steps 9, 11, 13 …, each one
//          step (half a space) above the line beneath it. A loop that drew the ledger lines from
//          the note's own step instead would put them in the SPACES, a notehead's height away from
//          where they belong — a defect that reads as "the staff is slightly wrong" rather than as
//          a missing line, which is why the first line's step is pinned here.
// KEYWORDS: ledger-line, line-position, parity, first-ledger, half-space
/// Returns the step of the first ledger line for a note at [step], or null when none is needed.
int? melodyFirstLedgerStep(int step) {
  const int topLine = 8;
  const int bottomLine = 0;
  if (step >= bottomLine && step <= topLine) {
    return null;
  }
  return step > topLine ? topLine + 2 : bottomLine - 2;
}

// PURPOSE: Report where the ledger lines of a note at [step] are drawn, so that the notehead, its
//          ledger lines and the room the band reserved cannot be three different answers to "how
//          far outside the staff is this note".
// INPUTS: step — a staff step from [melodyStepOf].
// OUTPUTS: The offsets of the ledger lines, in staff spaces ABOVE the staff's TOP LINE and positive
//          above it, inclusive of the line the note itself sits on when it sits on one; a caller
//          turns one into a y with `topLineY - offset * staffSpace`. Empty when the note lies
//          inside the five lines, and also empty for the single step just outside them, because a
//          note in the space above or below the staff needs no ledger line at all.
//
//          THE ARITHMETIC WAS WRONG IN THIS PROJECT AND THE ERROR IS NAMED HERE SO IT CANNOT COME
//          BACK. A staff step is HALF a space, so the five lines are the EVEN steps 0, 2, 4, 6 and
//          8 and the ledger lines continue the SAME parity: the first line above the staff is step
//          10 — one whole space above the top line — and the first below is step −2. The earlier
//          version started the run at ±1, which is the SPACE next to the staff, and it counted
//          half a space per line as well; the two mistakes cancelled into a line drawn one space
//          beyond the staff, detached from its note and — for a note below the staff — running into
//          the beat captions. A ledger line that is not under its notehead is worse than no ledger
//          line: the reader uses the line to decide where the note is.
// KEYWORDS: ledger-line, offsets, outside-the-staff, every-other-step, parity, bug-named
/// Returns the ledger-line offsets of a note at [step], in staff spaces above the top line.
List<double> melodyLedgerLineOffsets(int step) {
  const int topLine = 8;
  final int? first = melodyFirstLedgerStep(step);
  if (first == null) {
    return const <double>[];
  }
  final int direction = step > topLine ? 1 : -1;
  // The run ends AT the note when the note sits on a line, and one step short of it when the note
  // sits in a space: a ledger line is drawn under a notehead, never through it.
  final int last = step.isEven ? step : step - direction;
  final List<double> offsets = <double>[];
  for (
    int line = first;
    direction > 0 ? line <= last : line >= last;
    line += 2 * direction
  ) {
    offsets.add((line - topLine) * 0.5);
  }
  return offsets;
}

/// The accidental a [WrittenNote] needs, or null for a natural.
///
/// A double sharp is written `x` and a double flat `bb`, which is the ordinary ASCII reading of
/// both. A note altered by more than two semitones cannot be written with a single sign, and it is
/// reported as `bb`/`x` rather than as a wrongly tuned single accidental, so the span the glyph
/// covers is never claimed to be a note it is not.
String? melodyAccidentalOf(WrittenNote note) => switch (note.alter) {
  0 => null,
  1 => '#',
  2 => 'x',
  -1 => 'b',
  -2 => 'bb',
  _ => note.alter > 0 ? 'x' : 'bb',
};

// PURPOSE: Report how many beams a written value carries, which is the number that makes a run of
//          sixteenths read as sixteenths rather than as eighths.
// INPUTS: value — a written duration from the model: a base, optional dots and an optional tuplet.
// OUTPUTS: 0 for a quarter note or anything longer, 1 for an eighth, 2 for a sixteenth and 3 for a
//          thirty-second, counting DOWN FROM the eighth by halving the base. Dots and tuplets change
//          how LONG a note is written, not how many beams it carries, so a dotted sixteenth takes
//          the same two beams as a plain one — which is what a musician reading it expects.
//
//          WHY THE COUNT IS DERIVED FROM THE BASE RATHER THAN LISTED. A value added to the model
//          later (a sixty-fourth, say) is then treated as the shorter note it is instead of falling
//          through a list nobody remembered to extend.
// KEYWORDS: beam, beam-count, note-value, eighth, sixteenth, thirty-second, notation
/// Returns the number of beams [value] is written with: 0 for a quarter or longer.
int melodyBeamCount(NoteValue value) {
  int beams = 0;
  int base = value.base.denominator;
  while (base > NoteBase.quarter.denominator) {
    base ~/= 2;
    beams++;
  }
  return beams;
}

// PURPOSE: Join a bar's beamed notes into groups and lay the beams over them, so that the rhythm a
//          musician reads from the page is the rhythm the model holds.
//
//          A BEAM IS NOT DECORATION, IT IS THE RHYTHM. Sixteenths written as separate flagged notes
//          are read as a different grouping from the same notes beamed in fours, and a jazz player
//          reads grouping before he reads pitch; an engraver that draws the right notes with the
//          wrong beams has written a different bar. That is why this is geometry with rules in it
//          rather than a stroke drawn between two heads.
// INPUTS: notes — the bar's placed notes, in the order the model stores them. staffSpace — the
//         distance between two staff lines, the unit every proportion here is a multiple of.
//         metrics — the beam proportions ([MelodyMetrics.beamThickness] and the three values beside
//         it). timeSignature — the meter, whose own division into beats is what says how long a beat
//         is and therefore which notes sound in the same one. staffMiddleLineY and staffSpace also
//         place the band limit.
// OUTPUTS: One `_Beams` value: for each note, the stem it must draw when it is beamed (and null when
//          it is not), and the [MelodyGlyphKind.beam] glyphs themselves. A bar with no note short
//          enough to beam yields no beam glyph at all, and every note then keeps its own flag.
//
//          THE RULES, WHICH ARE NOTATION RATHER THAN TASTE. Each is stated where it is applied:
//            1. A beam joins notes that SOUND IN ONE BEAT — never two (see [_beamRuns]). In 4/4 that
//               gives eighth notes in pairs and sixteenths in fours, because that is how a beat
//               divides; in 6/8 it gives eighths in threes, because the beat there is the dotted
//               quarter.
//            2. A beam never crosses a barline. The grouping is built from one bar's notes, and the
//               horizontal room a beat's run takes is fitted into the bar (see [_notesOf]), so the
//               rule is structural rather than checked after the fact.
//            3. A beam does not span a rest: a cell that holds no note cannot be in a run, and a
//               note that is not short enough to carry a beam ends the run it would have joined.
//            4. The number of beams over the group is the number its SHORTEST value needs, drawn
//               one below the other, and each shorter value's extra beam covers only the notes that
//               need it — see [_beamEnds] and the level loop in [_addBeamGroup].
//            5. The stems of one group all point ONE WAY, decided once for the group, and the beam
//               sits at their ends — see [_beamStemUp].
//            6. The beam is [MelodyMetrics.beamThickness] thick, and it slopes toward the side of
//               the group whose notes are higher, by no more than [MelodyMetrics.beamSlopeLimit];
//               a group of one pitch is LEVEL, exactly.
// KEYWORDS: beam, beaming, rhythm-grouping, beat-boundary, rest-break, stem-direction, beam-slope,
//           partial-beam, bar-local, notation
_Beams _beamsOf({
  required List<_MelodyNote> notes,
  required double staffSpace,
  required MelodyMetrics metrics,
  required TimeSignature timeSignature,
  required double staffMiddleLineY,
}) {
  final List<_NoteStem?> stems = List<_NoteStem?>.filled(notes.length, null);
  final List<MelodyGlyph> glyphs = <MelodyGlyph>[];
  for (final List<int> run in _beamRuns(
    notes: notes,
    timeSignature: timeSignature,
  )) {
    _addBeamGroup(
      run: run,
      notes: notes,
      stems: stems,
      glyphs: glyphs,
      staffSpace: staffSpace,
      metrics: metrics,
      staffMiddleLineY: staffMiddleLineY,
    );
  }
  return _Beams(stems: stems, glyphs: glyphs);
}

// PURPOSE: Cut a bar's notes into the runs a beam may join, which is the whole musical question of
//          beaming expressed as a partition rather than as a drawing.
// INPUTS: notes — the bar's placed notes. timeSignature — the bar's meter, which is what says how long
//         one beat is.
// OUTPUTS: The notes of each run, as indices into [notes], in bar order. A run holds at least two
//          notes; every run is inside ONE BEAT.
//
//          WHERE A RUN ENDS, AND WHY EACH ENDING IS A MUSICAL FACT RATHER THAN A CONDITION:
//            * THE BEAT CHANGES. Beams group by beat, not by the bar. In 4/4 the beat is the quarter
//              and a beat boundary therefore breaks the beam: an eighth-note run of eight notes is
//              four beams of two, not one beam of eight. In 6/8 the beat is the dotted quarter and
//              `TimeSignature` gives two cells for the bar, so the same rule writes eighths in
//              threes without a second rule being added for compound meter.
//            * THE NOTE IS TOO LONG TO BEAM. A quarter note carries no beam, so a beam cannot pass
//              over one: the run that would have spanned it is cut on both sides.
//            * THE NOTE NO LONGER SOUNDS IN THE BEAT ITS CELL STARTS. A note's place in time is the
//              sum of the written durations before it, because the model orders a cell's notes by
//              `step` and gives each one a duration; the model has no rest object, so a silence is
//              either an empty cell or a cell that ran out of room. A cell that holds more than a
//              beat's worth of notes — four eighths addressed to one beat — therefore carries notes
//              that sound in the FOLLOWING beat, and those are beamed among themselves: the rule is
//              about where a note sounds, so it survives an address that is coarser than the music.
// KEYWORDS: beam-run, beat-boundary, rest-break, non-beamed-note, cell-duration, partition
List<List<int>> _beamRuns({
  required List<_MelodyNote> notes,
  required TimeSignature timeSignature,
}) {
  final Map<int, List<int>> byBeat = <int, List<int>>{};
  for (int index = 0; index < notes.length; index++) {
    (byBeat[notes[index].note.beat] ??= <int>[]).add(index);
  }
  final List<int> beats = byBeat.keys.toList()..sort();
  // THE LENGTH OF ONE BEAT IS THE METER'S FACT AND NOT THE LAYOUT'S. A 4/4 bar is four quarters, so a
  // beat is a quarter, and a 6/8 bar is two dotted quarters, so a beat is three eighths — which is
  // what `TimeSignature.cellsPerBar` already says, and reading it from there is what keeps the beam
  // grouping of a compound meter correct without a second rule for it.
  final double beatLength =
      timeSignature.numerator /
      (timeSignature.denominator * timeSignature.cellsPerBar);
  final List<List<int>> runs = <List<int>>[];
  for (final int beat in beats) {
    List<int> run = <int>[];
    int? runBeat;
    double elapsed = 0;
    for (final int index in byBeat[beat]!) {
      final NoteValue value = notes[index].note.value;
      // Which beat of the bar this note actually sounds in: the cell it is addressed to, plus the
      // whole beats the durations before it have already filled.
      final int sounding = beatLength <= 0
          ? beat
          : beat + (elapsed / beatLength).floor();
      final bool beamable = melodyBeamCount(value) > 0;
      if (!beamable || (run.isNotEmpty && sounding != runBeat)) {
        if (run.length > 1) {
          runs.add(run);
        }
        run = <int>[];
      }
      if (beamable) {
        run.add(index);
        runBeat = sounding;
      }
      elapsed += value.wholeNumerator / value.wholeDenominator;
    }
    if (run.length > 1) {
      runs.add(run);
    }
  }
  return runs;
}

// PURPOSE: Place one beamed group: decide the direction its stems take, lay the beam line over them
//          and give every note of the group the stem that reaches it.
// INPUTS: run — the group's note indices, from [_beamRuns]. notes — the bar's notes. stems — the
//         per-note stem array being filled, and glyphs — the bar's glyph list being appended to.
//         staffSpace, metrics, staffMiddleLineY — the proportions and the staff's own height.
// OUTPUTS: Nothing; [stems] gains one entry per note of the group and [glyphs] gains one beam glyph
//          per beam the group carries.
// KEYWORDS: beam-placement, stem-direction, beam-slope, beam-level, partial-beam, page-coordinates
void _addBeamGroup({
  required List<int> run,
  required List<_MelodyNote> notes,
  required List<_NoteStem?> stems,
  required List<MelodyGlyph> glyphs,
  required double staffSpace,
  required MelodyMetrics metrics,
  required double staffMiddleLineY,
}) {
  final double headWidth = metrics.noteheadWidth * staffSpace;
  final double headHeight = metrics.noteheadHeight * staffSpace;
  final double stroke = metrics.strokeWidth * staffSpace;
  final double stemLength = metrics.stemLength * staffSpace;
  final double thickness = metrics.beamThickness * staffSpace;
  final double gap = metrics.beamGap * staffSpace;
  // Left to right, because a beam is drawn from its first stem to its last. The model stores a cell's
  // notes in step order, which is their order in time, but a chart that has been read back from a
  // file is not guaranteed to be sorted, and a beam whose ends were taken in storage order would be
  // drawn backwards on such a chart.
  final List<int> ordered = run.toList()
    ..sort((int a, int b) {
      final int byX = notes[a].centerX.compareTo(notes[b].centerX);
      return byX != 0 ? byX : notes[a].note.step.compareTo(notes[b].note.step);
    });
  final bool up = _beamStemUp(<_MelodyNote>[
    for (final int i in ordered) notes[i],
  ]);
  // The axis each stem is drawn on, and the y its standard-length stem would end at. The axis is the
  // centre of the stem's own box, because that is the line the painter draws down: a stroked glyph's
  // box is its ink, everywhere on this staff.
  final List<double> stemX = <double>[];
  final List<double> naturalEnd = <double>[];
  bool level = true;
  final int firstStep = notes[ordered.first].step;
  for (final int index in ordered) {
    final _MelodyNote note = notes[index];
    stemX.add(note.centerX + headWidth / 2 - stroke / 2);
    final double headEdge = up
        ? note.centerY - headHeight / 2
        : note.centerY + headHeight / 2;
    naturalEnd.add(up ? headEdge - stemLength : headEdge + stemLength);
    if (note.step != firstStep) {
      level = false;
    }
  }
  final double dx = stemX.last - stemX.first;
  // RULE 6, FIRST HALF: a group of one pitch is LEVEL, exactly — not "level to within rounding",
  // because a beam over repeated notes that tilts by a hundredth of a pixel is a beam that has been
  // computed from the contour of a contour with no direction.
  final double limit = metrics.beamSlopeLimit;
  double slope = 0;
  if (!level && dx.abs() > 0) {
    final double wanted = (naturalEnd.last - naturalEnd.first) / dx;
    slope = wanted.clamp(-limit, limit);
  }
  // THE BEAM SITS WHERE THE OUTERMOST NOTE PUTS IT AND EVERY OTHER STEM REACHES IT. A stem is never
  // shortened below [MelodyMetrics.stemLength]: with the stems up the beam goes above the highest
  // note's own stem end, and the lower notes grow longer stems to it — which is exactly how an
  // engraved descending group looks. Doing it per note instead would give every note a standard stem
  // and a beam broken into steps, which is a picture of the pitches and not a joining of them.
  final List<double> shifted = <double>[
    for (int i = 0; i < stemX.length; i++)
      naturalEnd[i] - slope * (stemX[i] - stemX.first),
  ];
  double base = shifted.first;
  for (final double value in shifted) {
    base = up ? (value < base ? value : base) : (value > base ? value : base);
  }
  // AND IT STAYS INSIDE THE BAND THE PAGE RESERVED. The limit is the same one [melodyStepOf] clamps
  // a pitch to, moved one step out: a beam that left the band would be drawn over the system above,
  // and a glyph on top of the next system is read as a broken chart rather than as a wrong note —
  // the trade-off [melodyLedgerLimit] already makes for a pitch.
  final double bandTop = melodyStepCenterY(
    staffMiddleLineY: staffMiddleLineY,
    staffSpace: staffSpace,
    step: melodyHighestStep + 1,
  );
  final double bandBottom = melodyStepCenterY(
    staffMiddleLineY: staffMiddleLineY,
    staffSpace: staffSpace,
    step: melodyLowestStep - 1,
  );
  final double y0 = base.clamp(bandTop, bandBottom);
  final double y1 = (base + slope * dx).clamp(bandTop, bandBottom);
  double beamYAt(double x) =>
      dx.abs() < 1e-9 ? y0 : y0 + (y1 - y0) * (x - stemX.first) / dx;
  for (int i = 0; i < ordered.length; i++) {
    stems[ordered[i]] = _NoteStem(up: up, endY: beamYAt(stemX[i]));
  }
  // RULE 4: one beam per level, each covering the notes that need that level. Level 0 is the beam a
  // group always carries; level 1 is the second beam of the sixteenths, level 2 the third of the
  // thirty-seconds. The extra beams are drawn one step INSIDE the group's own direction, toward the
  // noteheads, which is where an engraved second beam lives: outside the first it would read as a
  // longer note rather than a shorter one.
  int maxLevel = 0;
  for (final int index in ordered) {
    final int count = melodyBeamCount(notes[index].note.value);
    if (count > maxLevel) {
      maxLevel = count;
    }
  }
  for (int level = 0; level < maxLevel; level++) {
    final double offset = (up ? 1 : -1) * level * (thickness + gap);
    int start = 0;
    while (start < ordered.length) {
      if (melodyBeamCount(notes[ordered[start]].note.value) <= level) {
        start++;
        continue;
      }
      int end = start;
      while (end + 1 < ordered.length &&
          melodyBeamCount(notes[ordered[end + 1]].note.value) > level) {
        end++;
      }
      final List<double> ends = _beamEnds(
        level: level,
        start: start,
        end: end,
        ordered: ordered,
        notes: notes,
        stemX: stemX,
        stroke: stroke,
        metrics: metrics,
        staffSpace: staffSpace,
      );
      if (ends.isNotEmpty) {
        final double xa = ends[0];
        final double xb = ends[1];
        final double ya = beamYAt(xa) + offset;
        final double yb = beamYAt(xb) + offset;
        final double left = xa < xb ? xa : xb;
        final double top = (ya < yb ? ya : yb) - thickness / 2;
        glyphs.add(
          MelodyGlyph(
            kind: MelodyGlyphKind.beam,
            strokeWidth: thickness,
            from: LayoutOffset(xa, ya),
            to: LayoutOffset(xb, yb),
            // The box is the stroke's INK, so a caller measuring what the page must hold and the
            // painter drawing the line are one statement rather than two.
            bounds: LayoutRect.fromLTWH(
              left,
              top,
              (xb - xa).abs(),
              (yb - ya).abs() + thickness,
            ),
          ),
        );
      }
      start = end + 1;
    }
  }
}

// PURPOSE: Give the two x ends of one beam of a group — a full beam between two stems, or a stub when
//          the level covers a single note.
// INPUTS: level — which beam this is (0 is the group's own); start and end — the first and last note
//         of the run needing it, as positions in [ordered]; ordered, notes and stemX — the group;
//         stroke — the stem's weight, so a beam covers the stems' own ink; metrics and staffSpace —
//         the stub's length.
// OUTPUTS: Two page x values, first end then second, or an empty list when no beam can be drawn.
//          A run of ONE note gets a [MelodyMetrics.beamletLength] stub pointing toward the rest of
//          the group and stopping well short of the neighbouring stem, because a second beam with no
//          second sixteenth to sit over is drawn as a short stroke: an engraver who ran it to the
//          neighbour would be beaming a note the neighbour does not share.
// KEYWORDS: beam-span, partial-beam, stub, beamlet, direction, x-only
List<double> _beamEnds({
  required int level,
  required int start,
  required int end,
  required List<int> ordered,
  required List<_MelodyNote> notes,
  required List<double> stemX,
  required double stroke,
  required MelodyMetrics metrics,
  required double staffSpace,
}) {
  if (end > start) {
    // The beam runs from the outer edge of the first stem to the outer edge of the last, so the
    // stroke's ink and the stem's ink meet instead of overlapping.
    return <double>[stemX[start] - stroke / 2, stemX[end] + stroke / 2];
  }
  final double reach = metrics.beamletLength * staffSpace;
  final bool hasNext = end + 1 < ordered.length;
  final bool hasPrevious = start > 0;
  if (!hasNext && !hasPrevious) {
    return const <double>[];
  }
  // Toward the rest of the group, and never close enough to the neighbouring stem to be read as
  // joining it: nine tenths of the gap leaves a visible break.
  final double gapToNeighbour = hasNext
      ? stemX[end + 1] - stemX[end]
      : stemX[start] - stemX[start - 1];
  final double length = reach < gapToNeighbour * 0.9
      ? reach
      : gapToNeighbour * 0.9;
  final double from = stemX[start];
  return hasNext
      ? <double>[from, from + length]
      : <double>[from - length, from];
}

// PURPOSE: Decide, once for a beamed group, which way its stems point — the rule a group of notes
//          needs and the one most often got wrong, because a per-note rule gives a group a ladder of
//          stems turning in the middle of it.
// INPUTS: group — the group's notes, any order.
// OUTPUTS: True when the group's stems point UP.
//
//          THE NOTE FARTHEST FROM THE MIDDLE LINE DECIDES, which is the ordinary engraved rule: a
//          group sitting high on the staff takes stems down and one sitting low takes them up,
//          whatever the individual notes do. A group whose extremes are equally far from the middle
//          line takes stems DOWN, which is the same answer the per-note rule already gives for a note
//          ON the middle line (A70: a note on or above the middle line takes a stem down), so this
//          function is a generalisation of that rule and not a second rule beside it: for a group of
//          one note it returns exactly what [placeMelodyStaff] returns for an unbeamed note.
// KEYWORDS: stem-direction, group-decision, middle-line, distance-from-middle, tie-break
bool _beamStemUp(List<_MelodyNote> group) {
  int above = 0;
  int below = 0;
  for (final _MelodyNote note in group) {
    final int delta = note.step - 4;
    if (delta > above) {
      above = delta;
    }
    if (-delta > below) {
      below = -delta;
    }
  }
  return above < below;
}

// PURPOSE: Build the melody staff of ONE bar: its five-line box and every glyph on it. This is the
//          only place a pitch becomes a page position, so the notehead, its ledger lines, its stem
//          and its accidental cannot be placed by four arithmetics that disagree.
// INPUTS: bar — the bar whose `melody` list to engrave. left and width — the bar's own horizontal
//         extent, in page coordinates. staffMiddleLineY — the y of the staff's middle line.
//         staffSpace — the distance between two lines, which is the unit every other number is a
//         multiple of. clef — the staff's clef name. cellX — the x of each of the bar's cells,
//         relative to [left], from the layout engine's own cell division; a note on a beat the bar
//         has no cell for is dropped, matching what happens to a chord at the same address.
//         metrics — the glyph proportions. includeClef — whether this bar opens a system and should
//         therefore print the clef; the engine is the only thing that knows, and a clef on every bar
//         is nine clefs on a line of nine.
// OUTPUTS: The staff, its box spanning [left]..[left] + [width] between the five lines and one
//          glyph per drawn element, in draw order. A bar with no melody yields no glyphs but still
//          yields its box, because the five lines run across every bar of a system. A note on a
//          negative beat, or on a beat past the last cell, is skipped.
// KEYWORDS: melody-placement, bar-engraving, draw-order, per-cell-address, glyph-list, clef, beam
/// Returns the melody staff of [bar], with every glyph of its notes.
PlacedMelodyStaff placeMelodyStaff({
  required Bar bar,
  required double left,
  required double width,
  required double staffMiddleLineY,
  required double staffSpace,
  required String clef,
  required List<double> cellX,
  bool includeClef = false,
  MelodyMetrics metrics = const MelodyMetrics(),
}) {
  final double topLineY = melodyStepCenterY(
    staffMiddleLineY: staffMiddleLineY,
    staffSpace: staffSpace,
    step: 8,
  );
  final double bottomLineY = melodyStepCenterY(
    staffMiddleLineY: staffMiddleLineY,
    staffSpace: staffSpace,
    step: 0,
  );
  final LayoutRect bounds = LayoutRect.fromLTWH(
    left,
    topLineY,
    width,
    bottomLineY - topLineY,
  );

  final List<MelodyGlyph> glyphs = <MelodyGlyph>[];
  final List<_MelodyNote> notes = _notesOf(
    bar: bar,
    left: left,
    width: width,
    staffMiddleLineY: staffMiddleLineY,
    staffSpace: staffSpace,
    clef: clef,
    cellX: cellX,
    stepOffset: metrics.stepOffset * staffSpace,
    headHalf: metrics.noteheadWidth * staffSpace / 2,
    edgeClearance: metrics.strokeWidth * staffSpace,
    accidentalCharWidth: metrics.accidentalWidth * staffSpace,
    accidentalGap: metrics.accidentalGap * staffSpace,
  );
  final _Beams beams = _beamsOf(
    notes: notes,
    staffSpace: staffSpace,
    metrics: metrics,
    timeSignature: bar.timeSignature,
    staffMiddleLineY: staffMiddleLineY,
  );
  for (int index = 0; index < notes.length; index++) {
    final _MelodyNote note = notes[index];
    _addNoteGlyphs(
      glyphs: glyphs,
      note: note,
      stem: beams.stems[index],
      staffSpace: staffSpace,
      metrics: metrics,
      // The accidental is drawn on the first note of a beat and on no other, so a chord written as
      // several notes at one address carries one sign rather than one per note.
      withAccidental:
          note.atBeatStart && melodyAccidentalOf(note.pitch) != null,
    );
  }
  // The beams go down AFTER the stems they join, so a stroke and a stem meet cleanly instead of the
  // stem's end showing through the beam where the two overlap at a slant.
  glyphs.addAll(beams.glyphs);
  _addTies(
    glyphs: glyphs,
    notes: notes,
    staffSpace: staffSpace,
    metrics: metrics,
  );
  return PlacedMelodyStaff(
    bounds: bounds,
    clef: includeClef ? _clefLetter(clef) : null,
    glyphs: glyphs,
  );
}

/// The letter the staff is marked with, from the clef NAME the model stores.
///
/// The LETTER and not the sign, because this renderer ships no music font and a spaced-out `𝄞` in a
/// text font falls back to a box on most machines. It is kept because the PLACED staff publishes the
/// clef it was engraved in — a fact another renderer or a test may read — and it is deliberately NOT
/// DRAWN: see `ChartPainter._paintMelody` for the owner's verdict on the letter that stood in the
/// clef's place.
/// `G` and `F` name the line the clef circles, which is the mnemonic a musician was taught. Anything
/// else is read as treble, matching [melodyStepOf].
String _clefLetter(String clef) => clef == 'bass' ? 'F' : 'G';

/// How one beamed note's stem is drawn: the direction the whole group takes, and the y the stem must
/// reach — which is where the group's beam lies at that note's own x.
///
/// It is one value rather than two parameters on [_addNoteGlyphs] because the two facts are decided
/// together by [_addBeamGroup] and must not be applied one without the other: a stem turned the
/// group's way but stopping at its standard length would end in the air beside the beam, and a stem
/// long enough for the beam but turned its own way would cross the staff to reach it.
class _NoteStem {
  const _NoteStem({required this.up, required this.endY});

  /// Whether the stem points up, which for a beamed note is the GROUP's decision.
  final bool up;

  /// The y the stem's free end reaches, in page coordinates: the beam's line at this note's x.
  final double endY;
}

/// What the beaming of one bar produced: a stem for each note that is beamed, and the beam strokes
/// themselves.
class _Beams {
  const _Beams({required this.stems, required this.glyphs});

  /// One entry per note of the bar, in the bar's own order; null where the note is not beamed and
  /// therefore keeps the stem and the flag its own value asks for.
  final List<_NoteStem?> stems;

  /// The beams, in the order they are drawn: one per level per run, widest first.
  final List<MelodyGlyph> glyphs;
}

/// One melody note already placed on the staff, in page coordinates.
class _MelodyNote {
  const _MelodyNote({
    required this.pitch,
    required this.octave,
    required this.note,
    required this.step,
    required this.centerX,
    required this.centerY,
    required this.atBeatStart,
  });

  /// The written pitch, which is what an accidental is chosen from.
  final WrittenNote pitch;

  /// The written pitch's octave, which with [pitch] is what [melodyStepOf] places.
  final int octave;

  /// The model note, which is what the written value and the tie are read from.
  final BeatNote note;

  /// The staff step the note sits at, already clamped by [melodyStepOf].
  final int step;

  /// The centre of the notehead, in page coordinates.
  final double centerX;

  /// The y of the notehead's centre, in page coordinates.
  final double centerY;

  /// Whether this is the first note of its beat, which is where the accidental is drawn.
  final bool atBeatStart;
}

// PURPOSE: Turn a bar's model notes into placed notes, in the order they are drawn, so that a later
//          function can reason about one note rather than re-reading the model.
// INPUTS: As [placeMelodyStaff], minus the glyph list. [left] and [width] are the bar's own extent,
//         and [cellX] holds the cell offsets RELATIVE to [left]. [stepOffset] is the greatest stride
//         between two notes of one beat, [headHalf] the half-width of a notehead, and
//         [edgeClearance] the ink one stroke wide that a note keeps clear of the barline — the three
//         numbers the barline's clearance and the room left for a run are measured in.
// OUTPUTS: The notes the staff can draw, in the bar's own storage order. A note is dropped when its
//          beat has no cell: the bar's left padding is not a position in time, and a note drawn
//          there would be one the musician can neither point at nor play where they wrote it.
//
//          AND EVERY NOTE IS KEPT INSIDE ITS OWN BAR, which is the horizontal half of a rule the
//          beam rules state vertically: no sign of one bar may reach into the next. A beat's notes
//          march right of their column by [stepOffset] each, and a beat that holds several of them
//          — a sixteenth run, which is the case this engraving has to get right — can reach past the
//          barline on the bar's last beat. So the stride SHRINKS when the run would not fit in the
//          room the bar has left, and a note that still fell outside is pulled back to the bar's
//          edge. Cramped notes inside their own bar are a blemish of this renderer, which the layout
//          engine's note says it accepts ("a note wider than its column overhangs it"); notes outside
//          their bar are a barline a reader cannot trust.
// KEYWORDS: note-placement, address-filter, cell-column, draw-order, barline-containment,
//           stride-fitting
List<_MelodyNote> _notesOf({
  required Bar bar,
  required double left,
  required double width,
  required double staffMiddleLineY,
  required double staffSpace,
  required String clef,
  required List<double> cellX,
  required double stepOffset,
  required double headHalf,
  required double edgeClearance,
  required double accidentalCharWidth,
  required double accidentalGap,
}) {
  final List<_MelodyNote> notes = <_MelodyNote>[];
  final Set<int> claimedBeats = <int>{};
  // How many notes each cell holds, counted before anything is placed, because the stride of a beat's
  // run depends on how many notes the run has.
  final Map<int, int> notesPerBeat = <int, int>{};
  for (final BeatNote note in bar.melody) {
    if (note.beat < 0 || note.beat >= cellX.length) {
      continue;
    }
    notesPerBeat[note.beat] = (notesPerBeat[note.beat] ?? 0) + 1;
  }
  for (final BeatNote note in bar.melody) {
    if (note.beat < 0 || note.beat >= cellX.length) {
      continue;
    }
    final int step = melodyStepOf(
      note.pitch.note,
      octave: note.pitch.octave,
      clef: clef,
    );
    // WHICH NOTE OF A BEAT CARRIES THE ACCIDENTAL, decided before the position because the position
    // depends on it — see below.
    final bool firstOfBeat = claimedBeats.add(note.beat);
    final String? accidental = melodyAccidentalOf(note.pitch.note);
    // THE FIRST NOTE OF A BAR IS PUSHED CLEAR OF THE BARLINE BY HALF A NOTEHEAD, so that what lines
    // up with the cell's column is the note's LEFT EDGE — which is what a chord symbol's box also
    // does — instead of its centre. Drawn centred on the cell's own x, the notehead of a bar's first
    // beat straddles the barline (measured: 0.2 page pixels on the staff's side of it at 13 staff
    // units), and a note that touches the barline reads as a note in the previous bar.
    final double headroom = headHalf;
    // AND AN ACCIDENTAL ON THAT FIRST BEAT GETS WHATEVER ROOM THE BAR HAS LEFT, because the bar's own
    // padding is smaller than the sign: measured at 13 staff units an accidental needs 13 page pixels
    // and the padding is 8, so the sign would be drawn ACROSS the barline. Only the overflow is
    // added, so an ordinary single sign moves nothing and the note keeps its column.
    double accidentalShift = 0;
    if (firstOfBeat && accidental != null && note.beat == 0) {
      // The room between the barline and the sign's own right edge is the bar's padding: the head's
      // left edge lies ON the cell's column (the headroom above put it there), and the sign is drawn
      // one gap further left again. Only the overflow moves the note.
      final double needed =
          accidental.length * accidentalCharWidth + accidentalGap;
      if (needed > cellX[0]) {
        accidentalShift = needed - cellX[0];
      }
    }
    // WHERE A BEAT'S RUN GOES HORIZONTALLY. [stepOffset] is the spacing a pair of notes gets when the
    // bar has room for it, and a bar with room keeps exactly the geometry it had before this was
    // written. When the run would overrun the bar, the notes are drawn NEARER EACH OTHER rather than
    // past the barline, so the group ends inside its own bar and still starts where its beat is.
    //
    // THE COMPROMISE IS NAMED HERE BECAUSE IT IS ONE. A row that is squeezed this way has noteheads
    // that overlap, which is a blemish no engraver would accept — but the alternative is worse in the
    // two ways that matter: sliding the group left so it keeps its spacing would put it over the
    // PREVIOUS beat's notes (two beats interleaved is a wrong rhythm, not a cramped one), and letting
    // it run on would cross the barline. The room is short because the layout engine reserves a
    // cell's width for its CHORDS and refuses to let a melody widen one — see `_cellWidths`, whose
    // note says a note that is wider than its column overhangs it. A bar spaced for its melody would
    // be the real fix, and it is not this change.
    final double firstX = cellX[note.beat] + headroom + accidentalShift;
    final int peers = notesPerBeat[note.beat] ?? 1;
    // A NOTE'S INK STOPS ONE STROKE SHORT OF THE BARLINE, and that stroke is the beam's own end: the
    // outermost stem sits inside its head by half a stroke and the beam reaches half a stroke past
    // the stem, so exactly one stroke of room is what keeps a beam ENDING at a barline instead of
    // merging with it. Drawn flush the two marks read as one line, and a barline a reader cannot see
    // the end of is the same defect as a beam crossing it.
    final double inside = headHalf + edgeClearance;
    final double room = width - inside - firstX;
    final double stride = peers <= 1 || room <= 0
        ? stepOffset
        : (room / (peers - 1) < stepOffset ? room / (peers - 1) : stepOffset);
    notes.add(
      _MelodyNote(
        pitch: note.pitch.note,
        octave: note.pitch.octave,
        note: note,
        step: step,
        // Contained in the bar as a hard guarantee, whatever the stride worked out to: the head's own
        // half-width inside the bar's edge, less the stroke, so not even the beam's ink reaches the
        // barline.
        centerX: (left + firstX + note.step * stride).clamp(
          left + headHalf,
          left + width - inside,
        ),
        centerY: melodyStepCenterY(
          staffMiddleLineY: staffMiddleLineY,
          staffSpace: staffSpace,
          step: step,
        ),
        atBeatStart: firstOfBeat,
      ),
    );
  }
  return notes;
}

// PURPOSE: Add every glyph one note draws except its tie: ledger lines first so the notehead lies
//          over them, then the stem so a filled head covers its own stem, then the notehead itself,
//          and last the accidental and the dot, which sit clear of the head.
// INPUTS: glyphs — the list to append to, in draw order. note — the placed note. stem — the stem the
//         note must draw when it belongs to a beamed group, or null when it does not; see
//         [_NoteStem]. staffSpace — the distance between two staff lines. metrics — the glyph
//         proportions. withAccidental — whether this note carries the accidental for its beat.
// OUTPUTS: Nothing; [glyphs] gains between two and five entries. A beamed note draws NO flag: the
//          beam is what joins it to its neighbours, and a flag beside a beam would tell the reader
//          the note were alone.
// KEYWORDS: glyph-emission, ledger-line, stem, beam-vs-flag, notehead, accidental, dot, draw-order
void _addNoteGlyphs({
  required List<MelodyGlyph> glyphs,
  required _MelodyNote note,
  required _NoteStem? stem,
  required double staffSpace,
  required MelodyMetrics metrics,
  required bool withAccidental,
}) {
  final double stroke = metrics.strokeWidth * staffSpace;
  final double ledgerWidth = metrics.ledgerWidth * staffSpace;
  // THE LEDGER LINE'S Y IS MEASURED FROM THE STAFF'S TOP LINE, which is what
  // [melodyLedgerLineOffsets] publishes its offsets against: a step is half a space, so the distance
  // from a note's own centre up to the top line is `(step - 8)` half-spaces and the line sits
  // `offset` spaces above that line. Measuring from the notehead's own centre instead — which is
  // what this did — puts every ledger line half its own distance away from the note it belongs to.
  final double topLineY = note.centerY + (note.step - 8) * staffSpace / 2;
  for (final double offset in melodyLedgerLineOffsets(note.step)) {
    final double lineY = topLineY - offset * staffSpace;
    glyphs.add(
      MelodyGlyph(
        kind: MelodyGlyphKind.ledgerLine,
        strokeWidth: stroke,
        // THE BOX IS THE STROKE'S OWN INK, WHICH MEANS IT IS CENTRED ON THE LINE IT NAMES. Every box
        // on this staff is the ink it draws — a notehead's box is its ellipse, a stem's box is its
        // stroke — and the painter draws a stroked glyph down the centre of the box it is handed.
        // This one box put its TOP on the line's y instead and was therefore painted half a stroke
        // LOW: 0.78 page pixels at a 13-pixel space, found and named rather than fixed when the
        // engraving tests were written (A70), and fixed here by making the box mean what every other
        // box means instead of by moving the painter's arithmetic for one kind of glyph.
        bounds: LayoutRect.fromLTWH(
          note.centerX - ledgerWidth / 2,
          lineY - stroke / 2,
          ledgerWidth,
          stroke,
        ),
      ),
    );
  }

  final double headWidth = metrics.noteheadWidth * staffSpace;
  final double headHeight = metrics.noteheadHeight * staffSpace;
  // The stem is drawn as a line down the CENTRE of its own box, so its axis is the box's centre and
  // the head it leaves is its own centre plus half a head — less half a stroke, so the stroke's ink
  // sits inside the head on one side and clears it on the other. A beam is laid over the same axis,
  // which is why the axis is stated here rather than left implicit in the box's left edge.
  final double stemAxisX = note.centerX + headWidth / 2 - stroke / 2;
  final double stemX = stemAxisX - stroke / 2;
  final double stemLength = metrics.stemLength * staffSpace;
  // THE GROUP DECIDES, OR THE NOTE DECIDES WHEN IT IS NOT IN ONE. A beamed group's stems all run one
  // way — the beam sits at their ends, so a group whose notes turned individually would have no end
  // to sit at — and a note alone keeps the rule A70 pinned: below the middle line a stem points up,
  // on it or above it points down.
  final bool stemUp = stem?.up ?? note.step < 4;
  final double headEdgeY = stemUp
      ? note.centerY - headHeight / 2
      : note.centerY + headHeight / 2;
  // A written value of an eighth or shorter carries a flag UNLESS IT IS BEAMED; a quarter and longer
  // carry neither. The test is the value's own denominator rather than a list of the enum's members,
  // so a value added to the model later is treated as the shorter one it describes.
  final bool needsFlag = stem == null && melodyBeamCount(note.note.value) > 0;
  // A beamed stem reaches the beam and stops at the notehead's edge; an unbeamed stem is the standard
  // length and runs into the head, where a filled head hides its end. The beamed case needs no
  // overlap with the head: the beam, not the head, is what hides the far end.
  final LayoutRect stemBounds;
  if (stem != null) {
    stemBounds = LayoutRect.fromLTWH(
      stemX,
      stemUp ? stem.endY : headEdgeY,
      stroke,
      (headEdgeY - stem.endY).abs(),
    );
  } else {
    stemBounds = LayoutRect.fromLTWH(
      stemX,
      stemUp ? headEdgeY - stemLength : headEdgeY,
      stroke,
      stemLength + headHeight / 2,
    );
  }
  glyphs.add(
    MelodyGlyph(
      kind: MelodyGlyphKind.stem,
      stemUp: stemUp,
      flagLength: needsFlag ? metrics.flagLength * staffSpace : 0,
      strokeWidth: stroke,
      bounds: stemBounds,
    ),
  );
  glyphs.add(
    MelodyGlyph(
      kind: MelodyGlyphKind.notehead,
      // A whole or a half note is engraved hollow; everything shorter is filled. The test is the
      // written BASE and not the value's total duration, because a dotted half is still hollow.
      filled: note.note.value.base.denominator > 2,
      bounds: LayoutRect.fromLTWH(
        note.centerX - headWidth / 2,
        note.centerY - headHeight / 2,
        headWidth,
        headHeight,
      ),
    ),
  );

  if (withAccidental) {
    final String? text = melodyAccidentalOf(note.pitch);
    if (text != null) {
      // The accidental's box grows leftward with the glyph's own length, so `bb` does not run onto
      // its notehead while `#` sits close to it.
      final double width = text.length * metrics.accidentalWidth * staffSpace;
      glyphs.add(
        MelodyGlyph(
          kind: MelodyGlyphKind.accidental,
          text: text,
          bounds: LayoutRect.fromLTWH(
            note.centerX -
                headWidth / 2 -
                metrics.accidentalGap * staffSpace -
                width,
            note.centerY - metrics.accidentalHeight * staffSpace / 2,
            width,
            metrics.accidentalHeight * staffSpace,
          ),
        ),
      );
    }
  }

  // An augmentation dot sits clear of the notehead on the side away from the stem, which is the one
  // position where it cannot be read as part of another note.
  if (note.note.value.dots >= 1) {
    final double dotRadius = metrics.dotRadius * staffSpace;
    final double dotX = stemUp
        ? note.centerX - headWidth / 2 - metrics.accidentalGap * staffSpace
        : note.centerX + headWidth / 2 + metrics.accidentalGap * staffSpace;
    glyphs.add(
      MelodyGlyph(
        kind: MelodyGlyphKind.dot,
        bounds: LayoutRect.fromLTWH(
          dotX,
          note.centerY - dotRadius,
          dotRadius * 2,
          dotRadius * 2,
        ),
      ),
    );
  }
}

// PURPOSE: Join a note to the next one when the model says the sound is tied, which is how one
//          sound is written across a beat or a barline.
// INPUTS: glyphs — the list to append to. notes — the placed notes of this bar, in storage order.
//         staffSpace — the distance between two staff lines. metrics — the glyph proportions.
// OUTPUTS: Nothing; [glyphs] gains one tie per adjacent pair the model ties. Only a pair inside ONE
//          BAR is joined: a tie whose next note is in the next bar would need that bar's geometry,
//          which this bar does not have. That limitation is named in the decision record rather than
//          hidden, and the earlier note still carries its own ledger lines, stem and accidental, so
//          a cross-bar tie is drawn as an untied pair and is not mistaken for anything else.
// KEYWORDS: tie, adjacent-pair, bar-local, named-limitation, curve-endpoints
void _addTies({
  required List<MelodyGlyph> glyphs,
  required List<_MelodyNote> notes,
  required double staffSpace,
  required MelodyMetrics metrics,
}) {
  final double headWidth = metrics.noteheadWidth * staffSpace;
  for (int index = 0; index + 1 < notes.length; index++) {
    final _MelodyNote from = notes[index];
    final _MelodyNote to = notes[index + 1];
    if (!from.note.tiedToNext) {
      continue;
    }
    final double gap = to.centerX - from.centerX;
    if (gap <= 0) {
      // Two notes at the same x cannot be joined by a curve that leaves one and reaches the other.
      // The tie is dropped rather than drawn as a vertical stroke, which a musician would read as a
      // stem.
      continue;
    }
    final double inset =
        (headWidth * metrics.tieClearance +
                metrics.tieMinimumInset * staffSpace)
            .clamp(0, gap / 2);
    final LayoutOffset start = LayoutOffset(from.centerX + inset, from.centerY);
    final LayoutOffset end = LayoutOffset(to.centerX - inset, to.centerY);
    final double span = end.x - start.x;
    if (span <= 0) {
      continue;
    }
    // The curve bulges away from the line between the notes on the side the eye expects a tie to
    // hang on — opposite the stems — so a tie is never read as a beam.
    final double arch = span * metrics.tieArch * (from.step < 4 ? -1 : 1);
    final LayoutOffset control = LayoutOffset(
      (start.x + end.x) / 2,
      (start.y + end.y) / 2 + arch,
    );
    glyphs.add(
      MelodyGlyph(
        kind: MelodyGlyphKind.tie,
        strokeWidth: metrics.strokeWidth * staffSpace,
        from: start,
        control: control,
        to: end,
        bounds: LayoutRect.fromLTWH(
          start.x,
          _min3(start.y, control.y, end.y),
          span,
          _max3(start.y, control.y, end.y) - _min3(start.y, control.y, end.y),
        ),
      ),
    );
  }
}

/// The least of three y values, used to bound a tie's curve without a list allocation.
double _min3(double a, double b, double c) {
  double least = a;
  if (b < least) {
    least = b;
  }
  if (c < least) {
    least = c;
  }
  return least;
}

/// The greatest of three y values, the counterpart of [_min3].
double _max3(double a, double b, double c) {
  double greatest = a;
  if (b > greatest) {
    greatest = b;
  }
  if (c > greatest) {
    greatest = c;
  }
  return greatest;
}
