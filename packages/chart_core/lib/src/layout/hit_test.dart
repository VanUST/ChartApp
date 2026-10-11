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
//          THE TARGET IS THE COLUMN, NOT THE FIVE LINES. A bar's notation band is the five lines
//          where a note is drawn PLUS the row beneath them where the beats are named, and a musician
//          who puts a finger on the number of beat 2 means beat 2 rather than the paper beside the
//          staff. The target is therefore the marker's own column widened to the band's full height,
//          which is two rectangles the engine already published and no third arithmetic.
// KEYWORDS: hit-testing, melody-staff, beat-column, second-surface, address-agreement, pure-dart
/// Returns the bar and beat whose staff column is under [pagePoint], or null.
ChartHit? hitTestMelodyStaff(PageLayout page, LayoutOffset pagePoint) {
  for (final PlacedSystem system in page.systems) {
    if (pagePoint.y < system.bounds.top || pagePoint.y > system.bounds.bottom) {
      continue;
    }
    for (final PlacedBar bar in system.bars) {
      // A bar's notation column is a TALL band, not the five lines alone: the lines are where a note
      // is drawn and the pages below them are where the beats are named, so a musician who touches
      // the number of beat 2 is touching beat 2 and not the paper beside the staff. The band is
      // bounded by the staff's top line and the bottom of the caption row, both published by the
      // engine — the two rectangles the layout already decided, and no third arithmetic.
      final PlacedBeatMarker? caption = bar.beatMarkers.isEmpty
          ? null
          : bar.beatMarkers.last;
      if (bar.melody.isEmpty || caption == null) {
        continue;
      }
      final LayoutRect column = LayoutRect.fromLTWH(
        bar.melody.bounds.left,
        bar.melody.bounds.top,
        bar.melody.bounds.size.width,
        caption.bounds.bottom - bar.melody.bounds.top,
      );
      if (!column.contains(pagePoint)) {
        continue;
      }
      for (final PlacedBeatMarker marker in bar.beatMarkers) {
        // The marker's own column is widened vertically to cover the five lines as well, so a tap on
        // a notehead and a tap on the number under it name the same beat.
        final LayoutRect target = LayoutRect.fromLTWH(
          marker.bounds.left,
          column.top,
          marker.bounds.size.width,
          column.size.height,
        );
        if (target.contains(pagePoint)) {
          return ChartHit(
            bar: bar,
            cell: PlacedCell(beat: marker.beat, bounds: target),
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
