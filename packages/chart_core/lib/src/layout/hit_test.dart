// PURPOSE: Answer the one question a touch asks of a laid-out page: which bar, and WHERE INSIDE
//          IT, is under this point. The chart is read-only today, and selection is the foundation
//          every later edit and every ink annotation stands on, so this is the piece that decides
//          whether a musician's finger names the thing they meant. It is geometry, not presentation:
//          it reads the rectangles the layout engine already produced and returns the song-model
//          address of what they cover plus the point in that bar's own coordinates, so it runs under
//          `dart test` with no device and no Flutter.
// INPUTS: A [PageLayout] and a point in THAT PAGE'S OWN coordinates — not a point on the glass.
//         A fitted page is engraved at a larger virtual size and drawn smaller, and a page can also
//         carry the musician's own zoom and pan; the bridge from a surface point to a page point is
//         [PageLayout.pagePointOf], which removes all three, and a caller that skips it is wrong
//         only for a transformed page — which is the kind of wrongness that survives a casual look.
// OUTPUTS: A [ChartHit] naming the bar and the point in that bar's own coordinates; null when the
//          point is over no bar at all. There is no third answer and nothing to convert: a mark's
//          place in the model is (bar, offsetX, offsetY) and a hit is the same pair, so a tap and a
//          chord are comparable values rather than two representations one call apart.
// KEYWORDS: hit-testing, tap-target, bar-address, bar-local, coordinates, page-coordinates,
//           pure-dart, selection-foundation, no-grid
//
// WHY THE ANSWER IS A COORDINATE AND NOT A CELL, which is the whole change this file carries. The
//  layout used to publish a bar's CELLS — one column per beat of the meter — and a touch was named
//  as "beat 2 of bar 7". The owner removed the grid as a class: a mark's place is its x, the metre
//  is a label that divides nothing, and published columns were the grid surviving in the layout
//  after it had been deleted from the model. So the hit now reports the point itself, and the
//  meaning of "which chord is under the finger" is decided by comparing that number with the places
//  the model stores (see [nearestChordAt] and [nearestNoteAt]) rather than by an index that both
//  sides had to believe in.
//
// WHY THE THREE BANDS OF THE OWNER'S RULE ARE THE THREE ANSWERS OF THIS FILE. He ruled: above the
//  staff is a chord, on the staff is a note, below the bar is neither. The engraving places the
//  chord line as the bar's own rectangle ([PlacedBar.bounds]) and the melody staff BELOW it, so the
//  rule becomes geometry with no threshold in it: [hitTestPage] answers for the chord band, which is
//  the bar's rectangle and nothing else; [hitTestMelodyStaff] answers for the staff band; and a point
//  below the staff is over neither and gets null from both. "A chord cannot be engraved below the
//  bar" is therefore not a special case here — below the bar is a place this file does not name.
import '../song/bar.dart';
import 'geometry.dart';
import 'page_layout.dart';

/// What a point on a page touched: a bar, and where inside that bar the point lies.
///
/// THE SECOND FIELD IS A COORDINATE, and that is what makes it usable. `local.x` is measured from the
/// bar's own left edge, which is exactly the frame [AnchoredPlace.offsetX] is measured in, so a
/// caller that wants to write a chord where the musician touched passes `hit.local.x` straight to
/// the edit session; one that wants to know which chord he touched compares it with the chords the
/// bar holds. There is no cell index anywhere in the answer, and therefore nothing that can disagree
/// with the model's own coordinate.
class ChartHit {
  /// Creates a hit on [bar] at [local], a point in that bar's own coordinates.
  const ChartHit({required this.bar, required this.local});

  /// The bar that was touched, with its address in the song and its bounds on the page.
  final PlacedBar bar;

  /// The touched point, in the bar's own coordinates: (0, 0) is the bar's top-left corner.
  ///
  /// `y` is measured from the bar's own top edge, so a point on the melody staff below the bar has
  /// a `y` larger than the bar's height — which is how a caller can tell the two surfaces apart
  /// without a second flag, and how the chord band's edge is expressible as a comparison with
  /// `LayoutStyle.barHeight`.
  final LayoutOffset local;

  /// The id of the section the touched bar belongs to.
  String get sectionId => bar.sectionId;

  /// The touched bar's index inside its section, in written order.
  int get barIndex => bar.barIndex;

  /// The x of the touch along its bar, in bar-local logical pixels, or null for a hit that carries
  /// no point — which no hit produced by this library is, since every hit is a place.
  double? get offsetX => local.x;

  /// The y of the touch down its bar, in bar-local logical pixels.
  double? get offsetY => local.y;

  /// The touched point in PAGE coordinates.
  ///
  /// Offered because the ink layer stores a stroke's points in page coordinates and a caller holding
  /// a hit often needs to go back: the sum is the inverse of the subtraction [hitTestPage] does.
  LayoutOffset get pagePoint =>
      LayoutOffset(bar.bounds.left + local.x, bar.bounds.top + local.y);

  @override
  bool operator ==(Object other) =>
      other is ChartHit && other.bar == bar && other.local == local;

  @override
  int get hashCode => Object.hash(bar, local);

  @override
  String toString() =>
      'ChartHit($sectionId[$barIndex] at local '
      '${local.x.toStringAsFixed(1)}, ${local.y.toStringAsFixed(1)})';
}

// PURPOSE: Report the chord of [bar] whose own x is nearest [offsetX], so that "which chord is under
//          my finger" is answered from the places the document stores rather than from a column the
//          layout invented. The palette uses it to open showing the chord the musician is about to
//          change; the edit session uses the same rule to decide between an update and an insertion.
// INPUTS: chords — the bar's chords, in model order. offsetX — a bar-local x. tolerance — how far
//         the mark may be from the point and still count as touched, in bar-local logical pixels;
//         it is the caller's, because the reach a finger has on the chord line is a surface decision
//         and differs from the reach a palette's own button has.
// OUTPUTS: The nearest chord within [tolerance], or null when the bar holds none that close. Ties go
//          to the EARLIER mark in model order, which is stable and is the order the bar was written
//          in. A negative [tolerance] yields null for anything but an exact match at zero distance,
//          which is a caller's mistake rather than a case worth a second rule.
// KEYWORDS: chord-hit, nearest, tolerance, coordinate, palette-open, no-grid
/// Returns the chord of [bar] nearest [offsetX] within [tolerance], or null.
ChordMark? nearestChordAt(
  List<ChordMark> chords,
  double offsetX, {
  required double tolerance,
}) {
  ChordMark? best;
  double bestDistance = tolerance;
  for (final ChordMark mark in chords) {
    final double distance = (mark.offsetX - offsetX).abs();
    if (best == null || distance < bestDistance) {
      if (distance <= tolerance) {
        best = mark;
        bestDistance = distance;
      }
    }
  }
  return best;
}

// PURPOSE: The same question for a melody, so that a tap on the staff can name the note the musician
//          is about to change without the staff publishing columns.
// INPUTS: notes — the bar's notes, in model order. offsetX — a bar-local x. tolerance — the reach.
// OUTPUTS: The note whose x is nearest [offsetX] within [tolerance], or null. The x compared is the
//          notehead's CENTRE, which is what a note's `place.offsetX` means (see [NoteMark]).
// KEYWORDS: note-hit, nearest, tolerance, coordinate, notehead-centre, no-grid
// PURPOSE: Answer the one question a touch asks of the melody staff: which bar's staff is under this
//          point. This is the second entrance to hit testing and it exists because the staff is a
//          SECOND, INDEPENDENT surface over the same bars: the chord line decides where a chord is
//          written, the staff decides where a note is. Owner decision D29 is the reason the staff is
//          drawn at all before a note exists; this is the reason it is touchable once it is.
// INPUTS: page — the layout to test against, in its engraved coordinates. pagePoint — a position in
//         those SAME coordinates, converted from the surface by [PageLayout.pagePointOf] exactly as
//         [hitTestPage] requires.
// OUTPUTS: A [ChartHit] naming the bar whose staff band contains the point and the point in that
//          bar's own coordinates, or null when the point is over no staff at all. Null is the
//          ordinary answer for a chords-only chart — no bar carries a staff, so no point is over one
//          — and for a tap between two systems. The bar named is the bar the staff belongs to, so
//          the address a caller gets is the same one [hitTestPage] would give for a point on that
//          bar's chord line, and a note and a chord share one address without either side
//          converting: what distinguishes them is the `y` of the hit against the bar's height.
//
//          THE BAND IS THE FIVE LINES PLUS HALF A STAFF SPACE BELOW THEM, which is the room a
//          notehead on the ledger line under the staff occupies. It is deliberately NOT the whole
//          reserved band: below the staff is blank paper, and a touch on blank paper must not be
//          told it named a note — the owner's rule says so in one sentence («ниже такта — ни то ни
//          другое»).
//
//          AND THERE ARE NO COLUMNS IN THE ANSWER, which is the change this file carries. The band
//          used to be cut into one target per beat, taken first from the beat captions and then
//          from the bar's cells; the first version died the day the captions were switched off (a
//          tap named nothing and note entry became unreachable, found on the tablet in one tap) and
//          the second died with the grid. A bar's staff is one band, and WHERE in it the finger
//          landed is the `x` of the hit — which is what a note's place means.
// KEYWORDS: hit-testing, melody-staff, second-surface, address-agreement, pure-dart, no-columns
// PURPOSE: Report which bar of [page] lies under [pagePoint]. This is the single entrance to hit
//          testing for the chord line, so that the ambiguous cases below have one answer each
//          instead of one per call site.
// INPUTS: page — the layout to test against, in its engraved coordinates. pagePoint — a position
//         in those SAME coordinates. A caller holding a point on the glass converts with
//         [PageLayout.pagePointOf] first; passing a surface point directly is the one mistake this
//         API cannot detect, because both are two doubles.
// OUTPUTS: A [ChartHit] when the point is inside a bar's chord band, carrying the point's place
//          inside that bar. Null otherwise.
//
//          THE PROPERTY THIS FUNCTION EXISTS TO GUARANTEE, and the one that has failed on hardware
//          twice: A TAP NAMES THE BAR IT LOOKS LIKE IT NAMES. The answer is therefore decided by
//          CONTAINMENT IN THE RECTANGLE THE PAINTER DREW — nothing else. There is no second gate on a
//          band derived from cells (whose emptiness once made every tap name nothing), none on the
//          beat captions (whose removal did the same), and none on the point's `y` inside the bar
//          (which once left the middle of a bar unhittable). A point in the rectangle names the bar;
//          a point outside every rectangle names none. `hit_test_test.dart` asserts it for the
//          CENTRE OF EVERY BAR of a page, which is the check that would have caught all three.
//
//          The remaining decisions, stated once:
//            - A point in the margin between two systems, or in a section-label band, is over no
//              bar and returns null. The label is not a target: it names a section, and the
//              section is already selectable through its bars.
//            - A point past the last bar of a system — inside the margin to the right of the
//              music — is over no bar and returns null, even though it shares the stave's height.
//            - A point below the bar is over no chord band. It is over a staff if the song has one,
//              which is [hitTestMelodyStaff]'s question, and over nothing at all otherwise.
//          Overlapping boundaries resolve to the FIRST bar in reading order, because a rectangle
//          contains its own edge and two neighbouring bars share one; the left-hand bar wins.
//          The page's nominal size is not a boundary: a bar the engine deliberately let overflow
//          the page is still hit beyond the page edge, because the clip belongs to the renderer and
//          not to the music.
// KEYWORDS: hit-testing, containment, reading-order, boundary-inclusive, margin, null-hit,
//           tap-names-the-bar-it-looks-like
/// Returns the bar under [pagePoint], or null when no bar contains it.
ChartHit? hitTestPage(PageLayout page, LayoutOffset pagePoint) {
  for (final PlacedSystem system in page.systems) {
    // A bar never leaves its system vertically, so a point outside the system's band cannot be
    // over one of its bars; this is the margin between systems and the label band in one test.
    if (pagePoint.y < system.bounds.top || pagePoint.y > system.bounds.bottom) {
      continue;
    }
    for (final PlacedBar bar in system.bars) {
      if (!bar.bounds.contains(pagePoint)) {
        continue;
      }
      return ChartHit(
        bar: bar,
        local: LayoutOffset(
          pagePoint.x - bar.bounds.left,
          pagePoint.y - bar.bounds.top,
        ),
      );
    }
  }
  return null;
}
