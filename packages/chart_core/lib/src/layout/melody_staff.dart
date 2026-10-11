// PURPOSE: Turn the pitched notes a bar carries (`Bar.melody`) into the geometry of an engraved
//          melody staff: where each notehead's centre lies on the five lines, how many ledger lines
//          its pitch needs, which way its stem points, where its accidental and its augmentation
//          dot are drawn, and the two endpoints and control point of the curve that joins a tied
//          pair. This is the arithmetic half of engraving, kept beside the layout engine rather
//          than inside the painter for the same reason the engine itself is pure: a notehead's
//          position is a musical statement, and it must be assertable without a device and without
//          a window.
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
// KEYWORDS: melody-staff, engraving-geometry, notehead, stem, ledger-line, accidental, tie, staff,
//           pure-dart, notation
import '../pitch.dart';
import '../song/bar.dart';
import '../song/note.dart';
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

  /// The curve of a flag on a stem, for an eighth note or shorter.
  flag,

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
/// curve.
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

  /// A tie's first endpoint, for [MelodyGlyphKind.tie] alone.
  final LayoutOffset from;

  /// A tie's control point, for [MelodyGlyphKind.tie] alone.
  final LayoutOffset control;

  /// A tie's second endpoint, for [MelodyGlyphKind.tie] alone.
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
/// The bound is the one `LayoutStyle.melodyBandHeight` reserves room for. A note beyond it is
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
  int step = 7 * (octave - 4) + letterSteps;
  if (clef == 'bass') {
    // The bass staff's bottom line is G2, an octave below E4 — the same letter sequence, seven
    // steps lower, so the whole staff is shifted by an octave.
    step += 7;
  }
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
  return step > topLine ? topLine + 1 : bottomLine - 1;
}

// PURPOSE: Report where the ledger lines of a note at [step] are drawn, so that the notehead, its
//          ledger lines and the room the band reserved cannot be three different answers to "how
//          far outside the staff is this note".
// INPUTS: step — a staff step from [melodyStepOf].
// OUTPUTS: The y offsets of the ledger lines, measured UPWARD from the staff's TOP LINE and
//          positive above it, in staff spaces; a caller multiplies them by the staff space and adds
//          them to the top line's y. Empty when the note lies inside the five lines. Every other
//          step is skipped, because the lines are every other step; see [melodyFirstLedgerStep] for
//          which step the run starts on and why.
// KEYWORDS: ledger-line, offsets, outside-the-staff, every-other-step
/// Returns the ledger-line offsets of a note at [step], in staff spaces above the top line.
List<double> melodyLedgerLineOffsets(int step) {
  const int topLine = 8;
  final int? first = melodyFirstLedgerStep(step);
  if (first == null) {
    return const <double>[];
  }
  // The run ends AT the note when the note sits on a line, and one step short of it when the note
  // sits in a space: a ledger line is drawn under a notehead, never through it.
  final int last = step.isEven ? step : step - (step > topLine ? 1 : -1);
  final List<double> offsets = <double>[];
  if (first > step) {
    for (int line = first; line >= last; line -= 2) {
      offsets.add((line - topLine) * 0.5);
    }
  } else {
    for (int line = first; line <= last; line += 2) {
      offsets.add((line - topLine) * 0.5);
    }
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
// KEYWORDS: melody-placement, bar-engraving, draw-order, per-cell-address, glyph-list, clef
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
    staffMiddleLineY: staffMiddleLineY,
    staffSpace: staffSpace,
    clef: clef,
    cellX: cellX,
    stepOffset: metrics.stepOffset * staffSpace,
    left: left,
  );
  for (final _MelodyNote note in notes) {
    _addNoteGlyphs(
      glyphs: glyphs,
      note: note,
      staffSpace: staffSpace,
      metrics: metrics,
      // The accidental is drawn on the first note of a beat and on no other, so a chord written as
      // several notes at one address carries one sign rather than one per note.
      withAccidental:
          note.atBeatStart && melodyAccidentalOf(note.pitch) != null,
    );
  }
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

/// The letter printed for a clef name, which is the conventional `G` for a treble staff and `F` for
/// a bass one.
///
/// The LETTER and not the sign: this renderer ships no music font, and a spaced-out `𝄞` in a text
/// font falls back to a box on most machines — the same reason the bar signs are drawn as ASCII.
/// `G` and `F` name the line the clef circles, which is the mnemonics a musician was taught.
/// Anything else is read as treble, matching [melodyStepOf].
String _clefLetter(String clef) => clef == 'bass' ? 'F' : 'G';

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
// INPUTS: As [placeMelodyStaff], minus the glyph list. [left] is the bar's own left edge, which is
//         the origin [cellX] is measured from; [cellX] holds offsets RELATIVE to it.
// OUTPUTS: The notes the staff can draw, in the bar's own storage order. A note is dropped when its
//          beat has no cell: the bar's left padding is not a position in time, and a note drawn
//          there would be one the musician can neither point at nor play where they wrote it.
// KEYWORDS: note-placement, address-filter, cell-column, draw-order
List<_MelodyNote> _notesOf({
  required Bar bar,
  required double left,
  required double staffMiddleLineY,
  required double staffSpace,
  required String clef,
  required List<double> cellX,
  required double stepOffset,
}) {
  final List<_MelodyNote> notes = <_MelodyNote>[];
  final Set<int> claimedBeats = <int>{};
  for (final BeatNote note in bar.melody) {
    if (note.beat < 0 || note.beat >= cellX.length) {
      continue;
    }
    final int step = melodyStepOf(
      note.pitch.note,
      octave: note.pitch.octave,
      clef: clef,
    );
    notes.add(
      _MelodyNote(
        pitch: note.pitch.note,
        octave: note.pitch.octave,
        note: note,
        step: step,
        centerX: left + cellX[note.beat] + note.step * stepOffset,
        centerY: melodyStepCenterY(
          staffMiddleLineY: staffMiddleLineY,
          staffSpace: staffSpace,
          step: step,
        ),
        atBeatStart: claimedBeats.add(note.beat),
      ),
    );
  }
  return notes;
}

// PURPOSE: Add every glyph one note draws except its tie: ledger lines first so the notehead lies
//          over them, then the stem so a filled head covers its own stem, then the notehead itself,
//          and last the accidental and the dot, which sit clear of the head.
// INPUTS: glyphs — the list to append to, in draw order. note — the placed note. staffSpace — the
//         distance between two staff lines. metrics — the glyph proportions. withAccidental —
//         whether this note carries the accidental for its beat.
// OUTPUTS: Nothing; [glyphs] gains between two and five entries.
// KEYWORDS: glyph-emission, ledger-line, stem, notehead, accidental, dot, draw-order
void _addNoteGlyphs({
  required List<MelodyGlyph> glyphs,
  required _MelodyNote note,
  required double staffSpace,
  required MelodyMetrics metrics,
  required bool withAccidental,
}) {
  final double stroke = metrics.strokeWidth * staffSpace;
  final double ledgerWidth = metrics.ledgerWidth * staffSpace;
  for (final double offset in melodyLedgerLineOffsets(note.step)) {
    glyphs.add(
      MelodyGlyph(
        kind: MelodyGlyphKind.ledgerLine,
        strokeWidth: stroke,
        bounds: LayoutRect.fromLTWH(
          note.centerX - ledgerWidth / 2,
          note.centerY - offset * staffSpace,
          ledgerWidth,
          stroke,
        ),
      ),
    );
  }

  final double headWidth = metrics.noteheadWidth * staffSpace;
  final double headHeight = metrics.noteheadHeight * staffSpace;
  // The stem's own x is measured from the notehead's centre rather than its edge so that the
  // stroke, which is drawn centred on that x, stays inside the head on one side and clears it on
  // the other. Its weight is published on the glyph, so the painter never measures it again.
  final double stemX = note.centerX + headWidth / 2 - stroke;
  final double stemLength = metrics.stemLength * staffSpace;
  final bool stemUp = note.step < 4;
  // A written value of an eighth or shorter carries a flag; a quarter and longer carry none. The
  // test is the value's own denominator rather than a list of the enum's members, so a value added
  // to the model later is treated as the shorter one it describes.
  final bool needsFlag = note.note.value.base.denominator >= 8;
  glyphs.add(
    MelodyGlyph(
      kind: MelodyGlyphKind.stem,
      stemUp: stemUp,
      flagLength: needsFlag ? metrics.flagLength * staffSpace : 0,
      strokeWidth: stroke,
      bounds: LayoutRect.fromLTWH(
        stemX,
        stemUp
            ? note.centerY - headHeight / 2 - stemLength
            : note.centerY + headHeight / 2,
        stroke,
        stemLength + headHeight / 2,
      ),
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
