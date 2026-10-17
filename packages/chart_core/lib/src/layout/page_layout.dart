// PURPOSE: Describe where everything landed, in a form that answers the two questions the rest of
//          the system asks of a layout: where is this chord drawn, and which chord is under this
//          touch. Every element carries both its identity in the song model and its rectangle on
//          the page, so neither question requires re-running the engine. The page also carries the
//          whole bridge to the surface it is drawn on — the page mode's `scale` and the musician's
//          `zoom`/`pan` — so both questions are answered in one coordinate system at any view.
// INPUTS: Produced by the layout engine; not constructed by callers. The view fields default to the
//         identity and are set through `withView` by whoever owns the screen's view state.
// OUTPUTS: Immutable values with value equality, which is what makes a layout comparable — a
//          cached layout can be recognised as unchanged without re-engraving it. Equality includes
//          the view, so a pan is a new page value and a painter that compares pages repaints.
// KEYWORDS: layout-result, placed-chord, hit-testing, value-equality, cache-key, anchor-address,
//           view-transform, zoom, pan, single-bridge
import 'geometry.dart';

// A bar's cells are GONE, and their absence is the point of this stage. A cell was the grid in the
// layout: it divided a bar into as many columns as the meter said and named one of them for a touch.
// The owner removed the metre as a divider («Просто надпись») and made a mark's place a coordinate,
// so there is no column to publish and no column to hit: a tap on a bar names the bar and its own x,
// and what is under it is decided by that number (see `hitTestPage` and `ChartHit.local`).

/// One text cue placed above its bar, in the row the layout reserved for it.
///
/// A cue belongs to the document and hangs above the bar it is anchored to,
/// in a row the page gives up out of its own height. What the two share is the reason this value
/// exists at all: the layout measured the words and decided the box, so the painter draws the box
/// it was handed instead of measuring a string a second time and hoping the two agree. Without a
/// reserved row the cue's plate would fall back onto the chord beneath it, which is the defect a
/// measured-and-published box closes.
class PlacedTextCue {
  /// Creates a placed cue for [text] with the given [origin] and [size].
  const PlacedTextCue({
    required this.id,
    required this.text,
    required this.origin,
    required this.size,
  });

  /// The identity the document gave this cue.
  ///
  /// It travels with the placement because two cues may share one anchor — the model keeps both
  /// rather than arbitrating — so an address cannot tell them apart and the caller needs the name.
  final String id;

  /// The words to draw, exactly as the document stores them.
  final String text;

  /// The top-left of the reserved row, in the page's engraved coordinates.
  ///
  /// The cue's own stored offset is measured from here, so this is the point that takes the place
  /// of the anchor corner the painter used to resolve for itself: its x is the anchor's own left
  /// edge, unchanged, and its y is the row the layout reserved above the stave.
  final LayoutOffset origin;

  /// The box the cue occupies, in the page's engraved coordinates.
  ///
  /// It is the PLATE's box, padding included, because the padding is part of how much room the cue
  /// takes. It is expressed at the scale the page was engraved for, so multiplying it by
  /// `PageLayout.scale` — the same one transform every other rectangle goes through — lands it on
  /// the surface exactly. That is why a cue's row grows in engraved pixels as a fitted page
  /// shrinks: the letters have their own legibility floor, so their box must be divided by the
  /// page scale to stay the same size on the glass.
  final LayoutSize size;

  @override
  bool operator ==(Object other) =>
      other is PlacedTextCue &&
      other.id == id &&
      other.text == text &&
      other.origin == origin &&
      other.size == size;

  @override
  int get hashCode => Object.hash(id, text, origin, size);

  @override
  String toString() => 'PlacedTextCue($id, "$text") at $origin size $size';
}

// The beat markers are GONE with the cells that gave them their columns. They existed as a
// reference aid — a digit and a tick under the staff — and the owner read them as noise and had them
// switched off in the style (`LayoutStyle.showBeatCaptions`), which is also why the staff's hit test
// could not be built on them. Beam grouping no longer reads the metre either, so the last thing in
// the engraving that depended on the metre's division into columns has gone with it.

/// A bar drawn at a position, together with the cues that remark on it.
class PlacedBar {
  /// Creates a placed bar for the bar at ([sectionId], [barIndex]).
  const PlacedBar({
    required this.sectionId,
    required this.barIndex,
    required this.bounds,
    this.textCues = const <PlacedTextCue>[],
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// The bar's index within its section, in written order.
  ///
  /// Together with [sectionId] this is the bar half of an annotation anchor, so a layout can be
  /// matched to an annotation without either side knowing the other's coordinate system. It is also
  /// the whole of what a tap on the bar names: see [ChartHit].
  final int barIndex;

  /// Where the bar is drawn, in page coordinates.
  ///
  /// THIS RECTANGLE IS THE CHORD BAND AND THE HIT TARGET, and the two are the same rectangle on
  /// purpose: a chord is written above the staff, so the bar's own chord line is the only place the
  /// owner's rule allows one, and a touch that lands on it names this bar. The melody staff is
  /// placed BELOW this rectangle rather than inside it, which is what keeps a tap on the chord line
  /// and a tap on the staff two different questions with one answer each.
  final LayoutRect bounds;

  /// The text cues anchored to this bar, in document order.
  ///
  /// They sit in the rows the layout reserved ABOVE this bar's stave — so above [bounds], not
  /// inside it — stacked upward from the stave so the first cue stays closest to the bar it
  /// remarks on. The bar's own [bounds] and its [chords] are untouched by a cue: a
  /// remark reserves room from the page rather than moving the music. Empty for a bar no cue
  /// names, which is the common case, and for a cue whose text is empty — a cue with nothing to
  /// say gets no row.
  final List<PlacedTextCue> textCues;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedBar ||
        other.sectionId != sectionId ||
        other.barIndex != barIndex ||
        other.bounds != bounds ||
        other.textCues.length != textCues.length) {
      return false;
    }
    for (int index = 0; index < textCues.length; index++) {
      if (other.textCues[index] != textCues[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(sectionId, barIndex, bounds, Object.hashAll(textCues));

  @override
  String toString() => 'PlacedBar($sectionId[$barIndex]) at $bounds';
}

/// One line of a page: the bars engraved side by side.
class PlacedSystem {
  /// Creates a system with the given [bounds], [bars] and optional section heading.
  const PlacedSystem({
    required this.bounds,
    required this.bars,
    this.sectionId,
    this.sectionLabel,
    this.labelBand,
  });

  /// Where the system is drawn, including any section label above the stave.
  final LayoutRect bounds;

  /// The bars of the system, left to right.
  final List<PlacedBar> bars;

  /// The section this system begins, or null when it continues a section.
  ///
  /// A system begins a section or it does not; the engine always starts a new system at a
  /// section boundary, so a section is never split across the heading that names it.
  final String? sectionId;

  /// The label drawn above this system, or null when the system continues a section.
  final String? sectionLabel;

  /// The band the section label is placed in, or null when there is no label.
  ///
  /// It is published rather than left to the painter to infer from the geometry because a system's
  /// band above the stave now holds TWO things: the heading, which owns the top
  /// `LayoutStyle.sectionLabelHeight` of it, and the cue rows, which own the rest. A painter that
  /// centred the label in the whole band would put it among the cue rows and let a plate drawn over
  /// them cover the letter that names the section. Publishing the band keeps the heading where it
  /// was on every page that carries no cue, and above the words on every page that does.
  final LayoutRect? labelBand;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedSystem ||
        other.bounds != bounds ||
        other.sectionId != sectionId ||
        other.sectionLabel != sectionLabel ||
        other.labelBand != labelBand ||
        other.bars.length != bars.length) {
      return false;
    }
    for (int index = 0; index < bars.length; index++) {
      if (other.bars[index] != bars[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    bounds,
    sectionId,
    sectionLabel,
    labelBand,
    Object.hashAll(bars),
  );

  @override
  String toString() =>
      'PlacedSystem(${bars.length} bar(s)${sectionLabel == null ? '' : ', "$sectionLabel"'})';
}

/// One page of engraved music.
///
/// THE PAGE CARRIES BOTH HALVES OF THE ONE BRIDGE TO THE GLASS, AND THAT IS NOT AN ACCIDENT OF
/// LAYERING. [scale] is the page mode's factor — FIT re-engraves the page larger and shrinks the
/// result — and [zoom] and [pan] are the musician's own view on top of it, moved by a two-finger
/// gesture or by the scene bar's zoom control (owner decision D34). All three live HERE rather than
/// in a widget because [pagePointOf] has to be the only inverse of the drawing transform: this
/// project has already paid once for a second rule for one relationship (a stroke anchored at
/// `surface x scale²`, see A47), and a view transform held beside the page is exactly that second
/// rule waiting for a call site to forget it. Putting the view in the page means the pen, the eraser
/// and the chord hit test become zoom-aware by construction, because they already call
/// [pagePointOf].
class PageLayout {
  /// Creates a page with the given [index], page [size] and [systems].
  ///
  /// [zoom] and [pan] default to the identity view, which is what the layout engine produces and
  /// what every caller that is not drawing on a surface gets.
  const PageLayout({
    required this.index,
    required this.size,
    required this.systems,
    this.scale = 1,
    this.zoom = 1,
    this.pan = LayoutOffset.zero,
  });

  /// Zero-based page number.
  final int index;

  /// The page's extent, in the coordinates the page was engraved in. This is the size the caller
  /// asked for, not the extent of its content.
  final LayoutSize size;

  /// The systems on this page, top to bottom.
  final List<PlacedSystem> systems;

  /// The factor that maps this page's coordinates onto the surface it is drawn on.
  ///
  /// Every rectangle above is in engraved page coordinates; a renderer must scale by this factor
  /// before drawing. It is 1 for an ordinary page, and below 1 for the single page the FIT mode
  /// produces: there the page was engraved at `size / scale` so that the systems could be packed
  /// wide, and shrinking the result by [scale] lands it inside the surface the caller measured.
  /// Keeping the geometry in one coordinate system and this factor as the only bridge is what
  /// lets a hit test, an annotation anchor and a golden image each apply one transform instead of
  /// each re-deriving the fit.
  final double scale;

  /// The musician's own magnification, at or above 1, on top of [scale].
  ///
  /// It is never below 1 because at 1 the page ALREADY fills the surface exactly — that is what
  /// both page modes produce — so a smaller value would only replace paper with empty desk. It is
  /// capped at [maxZoom] for the reason given there. One is the identity and the ordinary page.
  final double zoom;

  /// The musician's own pan, in SURFACE logical pixels, applied after [scale] and [zoom].
  ///
  /// The drawn position of a point is therefore `pagePoint * drawnScale + pan`. It is never allowed
  /// to take the page off the surface: [withView] clamps it, so the page always covers the surface
  /// it is drawn on and the musician cannot lose the music by dragging it away. A pan of
  /// [LayoutOffset.zero] is the identity.
  final LayoutOffset pan;

  /// The largest magnification the view may reach.
  ///
  /// A JUDGEMENT, STATED RATHER THAN TUNED. Four times a fitted page puts a single system of a long
  /// tune across the tablet's chart pane, which is what "bring the bar I am playing closer" needs;
  /// beyond that the reader sees a chord and its neighbours and has lost the bar line, and each
  /// further step multiplies the drawn page rather than showing more music. It is NOT measured
  /// against legibility the way the FIT floor (`LayoutEngine.minLegibleScale`) is, because zooming
  /// IN cannot make a chart harder to read: the floor is a floor for shrinking and has no upper
  /// sibling here.
  static const double maxZoom = 4;

  /// Every bar on this page, in reading order.
  List<PlacedBar> get bars => <PlacedBar>[
    for (final PlacedSystem system in systems) ...system.bars,
  ];

  /// The factor every engraved rectangle is multiplied by to reach the surface.
  ///
  /// The page mode's [scale] and the musician's [zoom] are one multiply for every consumer — the
  /// painters, the eraser's band, a probe reporting where a bar landed — because two multiplies at
  /// two call sites is how the two come to differ.
  double get drawnScale => scale * zoom;

  /// The extent this page covers on the surface at this view.
  ///
  /// At [zoom] 1 this is exactly the surface the page was laid out for, in both page modes, and
  /// that identity is what makes the clamp in [withView] centre a page that exactly fits.
  LayoutSize get drawnSize =>
      LayoutSize(size.width * drawnScale, size.height * drawnScale);

  // PURPOSE: Turn a point on the surface the page is drawn on into the point in this page's own
  //          coordinates that lies under it. This is the inverse of the single transform the
  //          renderer applies, and it exists here because a hit test given a surface point would
  //          otherwise have to know that [scale] exists — and a hit test that assumes scale 1 is
  //          wrong ONLY for a fitted page, which is the failure hardest to notice, because every
  //          ordinary page still answers correctly.
  // INPUTS: surfacePoint — a position measured from the top-left of the rectangle the page is
  //         drawn into, in logical pixels. This is the coordinate a pointer event arrives in when
  //         the page fills its widget.
  // OUTPUTS: The position in this page's engraved coordinates. Equal to [surfacePoint] when the
  //          view is the identity, so an ordinary page pays nothing; otherwise the pan is removed
  //          and the result divided by [drawnScale]. A non-positive [drawnScale] is not produced by
  //          the engine — it emits 1 or a value at or above its legibility floor, and [zoom] is at
  //          least 1 — so no clamp is applied here: a page a caller built by hand with a
  //          meaningless scale yields a meaningless, visible result rather than a plausible-looking
  //          wrong one.
  // KEYWORDS: coordinate-transform, page-scale, view-zoom, view-pan, fit, hit-testing,
  //           single-bridge, inverse, d34
  /// Returns the point of this page under [surfacePoint].
  LayoutOffset pagePointOf(LayoutOffset surfacePoint) {
    final double drawn = drawnScale;
    if (drawn == 1 && pan == LayoutOffset.zero) {
      return surfacePoint;
    }
    return LayoutOffset(
      (surfacePoint.x - pan.x) / drawn,
      (surfacePoint.y - pan.y) / drawn,
    );
  }

  // PURPOSE: The forward half of [pagePointOf], which is what a report needs in order to say WHERE
  //          a stored point is drawn: a probe prints the surface position of a stroke, and a
  //          verification compares it against the point the pen touched.
  // INPUTS: pagePoint — a position in this page's engraved coordinates.
  // OUTPUTS: The surface position, `pagePoint * drawnScale + pan`. The exact inverse of
  //          [pagePointOf], which is what makes "the mark was drawn where it was stored" a claim
  //          that can be checked by composing the two.
  // KEYWORDS: coordinate-transform, surface-point, report, forward, d34
  /// Returns the surface position of [pagePoint] at this view.
  LayoutOffset surfacePointOf(LayoutOffset pagePoint) => LayoutOffset(
    pagePoint.x * drawnScale + pan.x,
    pagePoint.y * drawnScale + pan.y,
  );

  // PURPOSE: Place the musician's view on this page and keep it on the surface, which is the ONE
  //          place a zoom or a pan is turned into a page a painter or a hit test can use.
  // INPUTS: zoom — the requested magnification, clamped into `[1, maxZoom]`. pan — the requested
  //         offset in surface pixels, clamped so the drawn page always covers the surface.
  // OUTPUTS: A page with the same engraving and the clamped view. The systems list is SHARED, not
  //          copied: a view change re-describes where the page is drawn and does not re-engrave it,
  //          which is what lets a two-finger gesture repaint without laying the chart out again.
  //          WHY THE PAN IS CLAMPED AND NOT SIMPLY APPLIED. A pan the musician can drive past the
  //          edge of the paper is a way to lose the chart and to be shown white space where the
  //          music was; clamping means the four edges of the page are the four limits of the drag,
  //          so the gesture always ends somewhere the music is. At [zoom] 1 the page is exactly the
  //          surface, the only legal pan is zero, and the clamp therefore also makes a reset a
  //          reset. A non-finite or non-positive zoom is treated as the identity rather than
  //          propagated: the gesture arithmetic can produce one from a degenerate span and a page
  //          drawn at NaN is invisible rather than wrong-looking.
  // KEYWORDS: view-transform, zoom-clamp, pan-clamp, edges, no-lost-page, identity, d34
  /// Returns this page with the view [zoom] and [pan], both clamped.
  PageLayout withView({required double zoom, required LayoutOffset pan}) =>
      _withView(
        zoom: !zoom.isFinite || zoom <= 1
            ? 1
            : (zoom > maxZoom ? maxZoom : zoom),
        pan: pan,
      );

  /// The unclamped-zoom half of [withView], so the clamp for the pan is written once.
  PageLayout _withView({required double zoom, required LayoutOffset pan}) {
    // The surface the page was engraved for: at zoom 1 the page covers it exactly, in both modes.
    final double viewportX = size.width * scale;
    final double viewportY = size.height * scale;
    final double contentX = viewportX * zoom;
    final double contentY = viewportY * zoom;
    final LayoutOffset clamped = LayoutOffset(
      contentX <= viewportX
          ? (viewportX - contentX) / 2
          : pan.x.clamp(viewportX - contentX, 0.0),
      contentY <= viewportY
          ? (viewportY - contentY) / 2
          : pan.y.clamp(viewportY - contentY, 0.0),
    );
    return PageLayout(
      index: index,
      size: size,
      systems: systems,
      scale: scale,
      zoom: zoom,
      pan: clamped,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! PageLayout ||
        other.index != index ||
        other.size != size ||
        other.scale != scale ||
        other.zoom != zoom ||
        other.pan != pan ||
        other.systems.length != systems.length) {
      return false;
    }
    for (int index = 0; index < systems.length; index++) {
      if (other.systems[index] != systems[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(index, size, scale, zoom, pan, Object.hashAll(systems));

  @override
  String toString() =>
      'PageLayout($index, ${systems.length} system(s), ${bars.length} bar(s)'
      '${scale == 1 ? '' : ', scale $scale'}'
      '${zoom == 1 ? '' : ', zoom $zoom'}'
      '${pan == LayoutOffset.zero ? '' : ', pan $pan'})';
}
