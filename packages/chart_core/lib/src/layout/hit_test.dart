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
// WHY A TOUCH NAMES A BAR AND NOT A SYMBOL. The owner removed the grid as a class: a mark's place is
//  its x, the metre is a label that divides nothing, and published columns were the grid surviving in
//  the layout after it had been deleted from the model. So the hit reports the point itself. The
//  question "which CHORD is under the finger" was answered here once, by comparing that point with the
//  places the model stores, and the function that answered it is gone: nothing in this tree can
//  select, edit or enter a chord, so the only question a touch asks is which BAR it named.
//
// WHY THE OWNER'S THREE BANDS ARE NOW ONE. He ruled: above the staff is a chord, on the staff is a
//  note, below the bar is neither. The staff and the notes are removed from this build, so the
//  engraving places the chord row inside the bar's own rectangle ([PlacedBar.bounds]) and nothing else
//  is under the bars at all. The rule therefore becomes geometry with no threshold in it: a point
//  inside a bar's rectangle names that bar, and a point below it names nothing, because there is no
//  second surface for it to be on.
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
  /// `y` is measured from the bar's own top edge, so a point below the bar has a `y` larger than the
  /// bar's height, which is how a caller can tell a touch below the music from one on it.
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

// PURPOSE: Report which bar of [page] lies under [pagePoint]. This is the single entrance to hit
//          testing, so that the ambiguous cases below have one answer each instead of one per call
//          site.
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
//            - A point below the bar is over no chord band. It is over nothing at all: this page
//              carries no second surface under the bars.
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
