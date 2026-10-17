// PURPOSE: Answer the one question a touch asks of a laid-out page: which bar, and which cell
//          inside it, is under this point. The chart is read-only today, and selection is the
//          foundation every later edit and every ink annotation stands on, so this is the piece
//          that decides whether a musician's finger names the thing they meant. It is geometry, not
//          presentation: it reads the rectangles the layout engine already produced and returns
//          the song-model address of what they cover, so it runs under `dart test` with no device
//          and no Flutter.
// INPUTS: A [PageLayout] and a point in THAT PAGE'S OWN coordinates — not a point on the glass.
//         A fitted page is engraved at a larger virtual size and drawn smaller, and a page can also
//         carry the musician's own zoom and pan; the bridge from a surface point to a page point is
//         [PageLayout.pagePointOf], which removes all three, and a caller that skips it is wrong
//         only for a transformed page — which is the kind of wrongness that survives a casual look.
// OUTPUTS: A [ChartHit] naming the bar and, when the point is over one, the cell; null when the
//          point is over no bar at all. The three ways to get null or a half answer are decided
//          and documented on [hitTestPage] rather than left to a caller to guess.
// KEYWORDS: hit-testing, tap-target, bar-address, cell, beat, page-coordinates, pure-dart,
//           selection-foundation
import 'geometry.dart';
import 'page_layout.dart';

/// What a point on a page touched: a bar, and the cell inside it when the point is over one.
///
/// [cell] is null for a point that lies on the bar but in one of the bar's own paddings, where no
/// cell has a column. That is a real answer, not a failure: a musician who touches the space
/// between the first barline and the first cell has named the bar and has not named a beat, and a
/// caller that wants to treat it as an error can, while a caller that wants to select the bar can
/// too. Collapsing the two cases into null would throw away the bar the touch did identify.
class ChartHit {
  /// Creates a hit on [bar] with an optional [cell].
  const ChartHit({required this.bar, this.cell});

  /// The bar that was touched, with its address in the song and its bounds on the page.
  final PlacedBar bar;

  /// The cell that was touched, or null when the point was over the bar but not over a cell.
  final PlacedCell? cell;

  /// The id of the section the touched bar belongs to.
  String get sectionId => bar.sectionId;

  /// The touched bar's index inside its section, in written order.
  int get barIndex => bar.barIndex;

  /// The touched cell's beat, or null when no cell was touched.
  int? get beat => cell?.beat;

  @override
  bool operator ==(Object other) =>
      other is ChartHit && other.bar == bar && other.cell == cell;

  @override
  int get hashCode => Object.hash(bar, cell);

  @override
  String toString() =>
      'ChartHit($sectionId[$barIndex]${cell == null ? ', no cell' : ', cell $beat'})';
}

// PURPOSE: Answer the one question a touch asks of the melody staff: which bar, and which beat of
//          it, is under this point. This is the second entrance to hit testing and it exists because
//          the staff is a SECOND, INDEPENDENT surface over the same bars: the chord line decides
//          where a chord is written, the staff decides where a note is, and a column of the staff
//          means beat n even though the rectangle the chord-line hit test reads does not reach down
//          to it. Owner decision D29 is the reason the staff is drawn at all before a note exists;
//          this is the reason it is touchable once it is.
// INPUTS: page — the layout to test against, in its engraved coordinates. pagePoint — a position in
//         those SAME coordinates, converted from the surface by [PageLayout.pagePointOf] exactly as
//         [hitTestPage] requires.
// OUTPUTS: A [ChartHit] naming the bar and the beat whose staff column contains the point, or null
//          when the point is over no staff at all. Null is the ordinary answer for a chords-only
//          chart — no bar carries a staff, so no point is over one — and for a tap between two
//          systems. A point inside the bar's band but in the leading padding between the barline and
//          the first column is over the bar and over no beat, which is stated rather than rounded.
//          The bar placed on the hit is the bar the staff belongs to, so the address a caller gets is
//          the same one [hitTestPage] would give for a point on that bar's chord line, and a note and
//          a chord can share one address without either side converting.
//
//          THE TARGET IS THE COLUMN, NOT THE FIVE LINES — AND THE COLUMN COMES FROM THE BAR'S OWN
//          CELLS, NOT FROM THE BEAT CAPTIONS. It used to be built out of `bar.beatMarkers`: the band
//          reached down to the caption row and each beat's column was that beat's marker. When the
//          owner read the captions as noise and they were switched off, a tap on the staff named
//          NOTHING and note entry died — found on the tablet, in one tap, after the change that
//          removed them. A caption is a LABEL and a cell is a COLUMN: the beat's column is what
//          `bar.cells` already publishes, and it always exists, whether or not anything is printed
//          under the staff.
//
//          THE BAND IS THE FIVE LINES PLUS HALF A STAFF SPACE BELOW THEM, which is the room a
//          notehead on the ledger line under the staff occupies. It is deliberately NOT the whole
//          reserved band: below the staff is now blank paper, and a touch on blank paper should not
//          be told it named a beat.
// KEYWORDS: hit-testing, melody-staff, beat-column, second-surface, address-agreement, pure-dart,
//           cells-not-captions
/// Returns the bar and beat whose staff column is under [pagePoint], or null.
ChartHit? hitTestMelodyStaff(PageLayout page, LayoutOffset pagePoint) {
  for (final PlacedSystem system in page.systems) {
    if (pagePoint.y < system.bounds.top || pagePoint.y > system.bounds.bottom) {
      continue;
    }
    for (final PlacedBar bar in system.bars) {
      if (bar.melody.isEmpty) {
        continue;
      }
      // The band the staff is touchable over: its five lines, and half a space below them where a
      // note on the ledger line under the staff sits. Nothing below that is staff.
      final LayoutRect lines = bar.melody.bounds;
      final double space = lines.size.height / 4;
      final LayoutRect band = LayoutRect.fromLTWH(
        lines.left,
        lines.top,
        lines.size.width,
        lines.size.height + space / 2,
      );
      if (!band.contains(pagePoint)) {
        continue;
      }
      for (final PlacedCell cell in bar.cells) {
        // The cell's own column, widened to the band's height, so a touch on a notehead and a touch
        // on the paper under it name the same beat.
        final LayoutRect target = LayoutRect.fromLTWH(
          cell.bounds.left,
          band.top,
          cell.bounds.size.width,
          band.size.height,
        );
        if (target.contains(pagePoint)) {
          return ChartHit(
            bar: bar,
            cell: PlacedCell(beat: cell.beat, bounds: target),
          );
        }
      }
      // A point inside the band but between two columns — the leading bar padding — is over the bar
      // and over no beat, which is the same answer the chord line gives for its own paddings.
      return ChartHit(bar: bar);
    }
  }
  return null;
}

// PURPOSE: Report which bar and cell of [page] lies under [pagePoint]. This is the single entrance
//          to hit testing, so that the three ambiguous cases below have one answer each instead of
//          one per call site.
// INPUTS: page — the layout to test against, in its engraved coordinates. pagePoint — a position
//         in those SAME coordinates. A caller holding a point on the glass converts with
//         [PageLayout.pagePointOf] first; passing a surface point directly is the one mistake this
//         API cannot detect, because both are two doubles.
// OUTPUTS: A [ChartHit] when the point is inside a bar, carrying the cell when the point is also
//          inside one. Null otherwise. The ambiguous cases, decided once here:
//            - A point in the margin between two systems, or in a section-label band, is over no
//              bar and returns null. The label is not a target: it names a section, and the
//              section is already selectable through its bars.
//            - A point past the last bar of a system — inside the margin to the right of the
//              music — is over no bar and returns null, even though it shares the stave's height.
//            - A point inside a bar but in the bar's leading or trailing padding is over the bar
//              and over no cell, so it returns a hit with a null cell rather than null.
//          Overlapping boundaries resolve to the FIRST bar in reading order, because a rectangle
//          contains its own edge and two neighbouring bars share one; the left-hand bar wins.
//          The page's nominal size is not a boundary: a bar the engine deliberately let overflow
//          the page is still hit beyond the page edge, because the clip belongs to the renderer and
//          not to the music.
// KEYWORDS: hit-testing, containment, reading-order, boundary-inclusive, margin, padding, null-hit
/// Returns the bar and cell under [pagePoint], or null when no bar contains it.
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
      for (final PlacedCell cell in bar.cells) {
        if (cell.bounds.contains(pagePoint)) {
          return ChartHit(bar: bar, cell: cell);
        }
      }
      return ChartHit(bar: bar);
    }
  }
  return null;
}
