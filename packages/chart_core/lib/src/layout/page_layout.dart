// PURPOSE: Describe where everything landed, in a form that answers the two questions the rest of
//          the system asks of a layout: where is this chord drawn, and which bar is under this
//          touch. Every element carries both its identity in the song model and its rectangle on
//          the page, so neither question requires re-running the engine. The page also carries the
//          whole bridge to the surface it is drawn on — the page mode's `scale` and the musician's
//          `zoom`/`pan` — so both questions are answered in one coordinate system at any view.
// INPUTS: Produced by the layout engine; not constructed by callers. The view fields default to the
//         identity and are set through `withView` by whoever owns the screen's view state.
// OUTPUTS: Immutable values with value equality, which is what makes a layout comparable — a
//          cached layout can be recognised as unchanged without re-engraving it. Equality includes
//          the view, so a pan is a new page value and a painter that compares pages repaints.
// KEYWORDS: layout-result, placed-chord, placed-bar, hit-testing, value-equality, cache-key,
//           anchor-address, view-transform, zoom, pan, single-bridge, placed-sign, volta
import 'chart_header.dart';
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

// PURPOSE: Say where one chord symbol goes and which words to draw there, so that the painter draws
//          the string the layout MEASURED instead of measuring the chord a second time and hoping
//          the two agree.
// INPUTS: Produced by the layout engine; not constructed by callers. `text` is the chord rendered
//         in the song's key, `bounds` is the box that string measured to at the mark's own x.
// OUTPUTS: An immutable value with value equality, carried on [PlacedBar.chords] in the model's
//          own order, so a caller can pair the i-th placement with the i-th [ChordMark].
// KEYWORDS: layout-result, placed-chord, chord-row, display-only, measured-once, written-spelling
//
// DISPLAY ONLY, AND THAT IS A CONSTRAINT ON THIS VALUE RATHER THAN A COMMENT. A placement is
// something to DRAW. It carries no hit target and no editing handle, because a chord cannot be
// added, changed or moved through the interface: the mark that produced it is written by the iReal
// importer and by nothing else. If a future change wants to select a chord by touching it, it has
// to add that deliberately, and the absence here is what will make it a decision rather than an
// accident.
//
// THE TEXT IS THE SPELLING. `F#h` is drawn as `F#h` and `Cb` as `Cb`, because the string in [text]
// came out of `Chord.render`, which returns the written note a mark carries and consults the key
// only for a root that arrived without one (see `ChordRoot.written`). Nothing in the painter
// re-spells anything: it is handed a string and draws it.

/// One chord symbol drawn at a position: the words to draw and the box they occupy.
class PlacedChord {
  /// Creates a placement of [text] in [bounds], drawn small when [small] is true.
  const PlacedChord({
    required this.text,
    required this.bounds,
    this.small = false,
    this.clampedIntoBand = false,
  });

  /// The symbol to draw, exactly as the chart writes it.
  ///
  /// It is the rendered chord and not the [Chord] value, on purpose: the engine measured THIS
  /// string to reserve the room around it, so handing the painter the string is what makes the
  /// drawn symbol and the measured box the same value rather than two calls that happen to agree.
  /// Empty is never produced — a mark always renders to at least its root — so a painter need not
  /// test it, although drawing an empty string is harmless.
  final String text;

  /// Where the symbol is drawn, in the page's engraved coordinates.
  ///
  /// Its LEFT EDGE is the bar's left edge plus the mark's own stored x, which under the coordinate
  /// model is simply where the musician wrote it — the chord's time. Its VERTICAL extent is the
  /// chord row inside the bar's band: the row begins [LayoutStyle.chordRowTopInset] below the
  /// band's top and follows the mark's own vertical offset from there.
  final LayoutRect bounds;

  /// Whether the model marks this chord as engraved small (`ChordSize.small`).
  ///
  /// A chart writes a small chord to say "this is a passing chord" — iReal spells it with an `s` —
  /// so it is part of what the file says and is drawn one size down. It is NOT a hit target and
  /// not a piece of state: the size travels with the mark and nothing in the interface can change
  /// it.
  final bool small;

  /// Whether the mark's own vertical offset put this symbol outside its bar's band, so the row was
  /// pulled back in.
  ///
  /// THE ROW NEVER LEAVES THE BAND. Above the bar's band is the section heading's row and below it
  /// is the next system, so a symbol drawn outside would land on someone else's music; the offset
  /// is clamped to the band's edge and this flag says the stored number was not honoured. It is
  /// only reachable from a file written by an editor that no longer exists — the importer writes a
  /// zero offset — which is why it is a flag on a placement rather than a refusal.
  final bool clampedIntoBand;

  @override
  bool operator ==(Object other) =>
      other is PlacedChord &&
      other.text == text &&
      other.bounds == bounds &&
      other.small == small &&
      other.clampedIntoBand == clampedIntoBand;

  @override
  int get hashCode => Object.hash(text, bounds, small, clampedIntoBand);

  @override
  String toString() =>
      'placed("$text") at $bounds${small ? ' small' : ''}'
      '${clampedIntoBand ? ' (clamped into the chord band)' : ''}';
}

/// The signs a bar can carry that are not chords.
///
/// One value per SIGN and not per model field, because the page draws signs and the model stores
/// them in four different places: `Bar.repeatPrevious`, `Bar.slashRepeat`, `Bar.noChord`, and the
/// two facts this renderer derives — the bar's [BarMark]s and the meter it changes to. Collapsing
/// them here is what lets the painter draw one list in one pass instead of reaching into the song
/// for each kind and deciding for itself where each one goes.
enum BarSignKind {
  /// The simile sign: "play the previous bar again" (`%`), written [Bar.repeatPrevious] one bar.
  repeatPreviousOneBar,

  /// The two-bar simile sign, written [Bar.repeatPrevious] two bars. iReal writes it as the same
  /// sign with a second stroke through it, which is what distinguishes the two on the page.
  repeatPreviousTwoBars,

  /// The slash repeat: "keep comping", written [Bar.slashRepeat].
  slashRepeat,

  /// `N.C.` — no chord sounds for this bar, written [Bar.noChord].
  noChord,

  /// A segno sign, from [BarMark.segno].
  segno,

  /// A coda sign, from [BarMark.coda].
  coda,

  /// A fermata, from [BarMark.fermata].
  fermata,

  /// The meter this bar changes to, stated at the bar where it changes.
  ///
  /// NOT A DIVISION. The owner ruled the meter is «Просто надпись» — a label that divides nothing —
  /// so this sign is drawn and nothing is measured from it: the bar's width, its chord positions and
  /// the page's pagination are decided without ever reading the meter.
  meterChange,
}

// PURPOSE: Say where one of a bar's signs goes and which signs carries words, so the painter draws
//          the box the LAYOUT decided instead of deciding a second time where a sign belongs.
// INPUTS: Produced by the layout engine; not constructed by callers. [kind] is what to draw,
//         [bounds] is the box it is drawn in, and [text] carries the words for the two kinds that
//         are written rather than drawn.
// OUTPUTS: An immutable value with value equality, carried on [PlacedBar.signs] in the order the
//          layout placed them (left to right inside the bar).
// KEYWORDS: layout-result, bar-sign, repeat-previous, slash-repeat, no-chord, segno, coda, fermata,
//           meter-sign, display-only
//
// DISPLAY ONLY, LIKE A CHORD. A sign is something to DRAW: it carries no hit target and no handle,
// because no sign on this page can be added, changed or deleted through the interface. Every one of
// them arrived with the file.
//
// THE TWO GLYPH KINDS THAT HAVE NO FONT ARE DRAWN AS SHAPES, and that is a decision rather than a
// shortfall: this renderer has no music font (see `ChartPainter`), and a substituted character — an
// `S` for a segno, a `C` for a coda — is a glyph a musician has to guess at, which A68 ruled worse
// than nothing. The simile sign, the slash, the segno, the coda and the fermata are therefore drawn
// from [bounds] as geometry: the same shapes an engraver cuts, with no font in the path.

/// One sign drawn in a bar, with the box it is drawn in.
class PlacedBarSign {
  /// Creates a placement of a [kind] sign in [bounds], carrying [text] when the kind needs words.
  const PlacedBarSign({
    required this.kind,
    required this.bounds,
    this.text = '',
  });

  /// What the painter draws.
  final BarSignKind kind;

  /// The words the sign reads as, for [BarSignKind.noChord] (`N.C.`) and
  /// [BarSignKind.meterChange] (`3/4`), and the empty string for every kind drawn as a shape.
  ///
  /// The string is composed and measured here rather than by the painter, so the box the engine
  /// reserved and the words drawn in it are one value — the rule every placed value in this file
  /// follows.
  final String text;

  /// Where the sign is drawn, in the page's engraved coordinates.
  ///
  /// Its exact meaning depends on the kind: for a shape it is the SQUARE the shape is inscribed in,
  /// so the painter needs no size rule of its own; for a kind that is read as words it is the box
  /// those words measured to.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedBarSign &&
      other.kind == kind &&
      other.text == text &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(kind, text, bounds);

  @override
  String toString() =>
      'placed sign ${kind.name}${text.isEmpty ? '' : ' "$text"'} at $bounds';
}

// PURPOSE: Say where one line of a bar's own staff text goes, so the words a chart carries about a
//          bar — `Solo`, `х4`, `проигрыш` — are drawn from the box the layout reserved and measured
//          them in.
// INPUTS: Produced by the layout engine; not constructed by callers. [text] is the DISPLAY form,
//         with the written position prefix and the exporter's padding already gone (see
//         `displayStaffText`), so it is the string that was measured.
// OUTPUTS: An immutable value with value equality, carried on [PlacedBar.staffText] stacked from the
//          bar's bottom edge upward.
// KEYWORDS: layout-result, staff-text, display-form, stacked-rows, display-only
//
// WHY THIS IS NOT A [PlacedTextCue]. A cue is a remark the MUSICIAN wrote in the document, and it
// therefore lives in a row the page gives up above the bar. Staff text is what the FILE says about
// the bar, it is part of the music, and it is drawn inside the bar's own band at the head of the
// lane the chords leave — which is where a chart prints `Solo`. Two things that are written by
// different people about different subjects do not share one placement rule.

/// One line of a bar's own staff text, in display form, with the box the layout measured for it.
class PlacedStaffText {
  /// Creates a placed staff-text line reading [text] inside [bounds].
  const PlacedStaffText({required this.text, required this.bounds});

  /// The words to draw, exactly as `displayStaffText` returns them.
  final String text;

  /// The box the words occupy, in the page's engraved coordinates.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedStaffText && other.text == text && other.bounds == bounds;

  @override
  int get hashCode => Object.hash(text, bounds);

  @override
  String toString() => 'placed staff text "$text" at $bounds';
}

/// One alternative-ending bracket drawn over the bars it covers.
///
/// A bracket belongs to a RUN of bars — `[1.` covers the first ending, `[2.` the second — so it is
/// published by the system rather than by each of its bars: a painter given one bar could draw a
/// segment, but the tick that starts a bracket is a fact about where the run BEGINS, and a bar does
/// not know that. Number 0 is an unnumbered bracket, which iReal writes as `N0` and which is a
/// different thing from no bracket at all.
class PlacedVolta {
  /// Creates a bracket numbered [number] spanning [bounds].
  const PlacedVolta({required this.number, required this.bounds});

  /// The figure written in the bracket, or 0 when it carries none.
  final int number;

  /// The band and horizontal span the bracket occupies, in the page's engraved coordinates.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedVolta && other.number == number && other.bounds == bounds;

  @override
  int get hashCode => Object.hash(number, bounds);

  @override
  String toString() =>
      'placed ${number == 0 ? 'unnumbered' : number} volta over $bounds';
}

/// A bar drawn at a position, together with the chords written in it, its signs and the words on it.
class PlacedBar {
  /// Creates a placed bar for the bar at ([sectionId], [barIndex]).
  const PlacedBar({
    required this.sectionId,
    required this.barIndex,
    required this.bounds,
    this.chords = const <PlacedChord>[],
    this.signs = const <PlacedBarSign>[],
    this.staffText = const <PlacedStaffText>[],
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
  /// purpose: a chord is written in the band above the bar's own lines, and a touch that lands on
  /// the band names this bar. The chord row is placed INSIDE this rectangle rather than above it,
  /// which is what keeps a tap on a chord and a tap on the bar one question with one answer: the
  /// top of the band is the row the symbols hang from, and everything below them is the bar lane.
  final LayoutRect bounds;

  /// The chord symbols written in this bar, in the model's own order.
  ///
  /// A bar with no chord has none — and it then shows nothing in its chord row, which is the state
  /// of most bars of most charts and the reason this is a list rather than a required symbol. The
  /// order is the order of `Bar.chords`, so the i-th placement came from the i-th mark and a
  /// verification can compare the two lists positionally.
  ///
  /// THEY ARE HERE TO BE DRAWN AND FOR NOTHING ELSE. See [PlacedChord] for why that is a constraint
  /// and not a description.
  final List<PlacedChord> chords;

  /// The signs this bar carries that are not chords, in the order they are drawn.
  ///
  /// A bar with none has none, which is the state of most bars: a chart does not sign every measure.
  /// The order is left to right inside the bar, so a caller reading the list is reading the page.
  final List<PlacedBarSign> signs;

  /// The bar's own staff text, in display form, stacked from the bar's bottom edge upward.
  ///
  /// The first entry is the one closest to the bar's bottom, because the rows are stacked upward and
  /// a chart reads the phrase nearest the stave first. Empty for a bar whose file carries no text and
  /// for a text that is only a written position (`*69` with no words), which has nothing to say.
  final List<PlacedStaffText> staffText;

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
        other.chords.length != chords.length ||
        other.signs.length != signs.length ||
        other.staffText.length != staffText.length ||
        other.textCues.length != textCues.length) {
      return false;
    }
    for (int index = 0; index < chords.length; index++) {
      if (other.chords[index] != chords[index]) {
        return false;
      }
    }
    for (int index = 0; index < signs.length; index++) {
      if (other.signs[index] != signs[index]) {
        return false;
      }
    }
    for (int index = 0; index < staffText.length; index++) {
      if (other.staffText[index] != staffText[index]) {
        return false;
      }
    }
    for (int index = 0; index < textCues.length; index++) {
      if (other.textCues[index] != textCues[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    sectionId,
    barIndex,
    bounds,
    Object.hashAll(chords),
    Object.hashAll(signs),
    Object.hashAll(staffText),
    Object.hashAll(textCues),
  );

  @override
  String toString() =>
      'PlacedBar($sectionId[$barIndex]) at $bounds'
      '${chords.isEmpty ? '' : ', ${chords.length} chord(s)'}'
      '${signs.isEmpty ? '' : ', ${signs.length} sign(s)'}'
      '${staffText.isEmpty ? '' : ', ${staffText.length} staff text line(s)'}';
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
    this.voltas = const <PlacedVolta>[],
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
  /// band above the stave now holds THREE things: the heading, which owns the top
  /// `LayoutStyle.sectionLabelHeight` of it; the cue rows, which own the rest; and — on a system
  /// that carries endings — the volta brackets, which own their own `LayoutStyle.voltaBandHeight`
  /// slab immediately above the stave. A painter that centred the label in the whole band would put
  /// it among the cue rows and let a plate drawn over them cover the letter that names the section.
  /// Publishing the band keeps the heading where it was on every page that carries no cue, and above
  /// the words on every page that does.
  final LayoutRect? labelBand;

  /// The alternative-ending brackets drawn over the bars of this system, in reading order.
  ///
  /// One entry per RUN of adjacent bars carrying the same `Volta` number, so a bracket that covers
  /// two bars is one value spanning both rather than two segments a painter would have to join. A
  /// run never crosses a system break: a bracket is a mark above a line of music, and a printed
  /// chart draws one bracket per line for an ending that spans the break, which is what this does.
  /// Empty for a system in which no bar sits under an ending.
  final List<PlacedVolta> voltas;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedSystem ||
        other.bounds != bounds ||
        other.sectionId != sectionId ||
        other.sectionLabel != sectionLabel ||
        other.labelBand != labelBand ||
        other.voltas.length != voltas.length ||
        other.bars.length != bars.length) {
      return false;
    }
    for (int index = 0; index < voltas.length; index++) {
      if (other.voltas[index] != voltas[index]) {
        return false;
      }
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
    Object.hashAll(voltas),
    Object.hashAll(bars),
  );

  @override
  String toString() =>
      'PlacedSystem(${bars.length} bar(s)'
      '${sectionLabel == null ? '' : ', "$sectionLabel"'}'
      '${voltas.isEmpty ? '' : ', ${voltas.length} volta(s)'})';
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
    this.header,
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

  /// The line stating this chart's key and opening meter, on the page where its music begins.
  ///
  /// ONE PAGE'S VALUE AND NOT ONE CHART'S: a chart states what it is written in where its music
  /// starts, and that is a fact a reader needs once. Every later page therefore carries null and
  /// gives up no room for it. Null on the first page too when the caller asked for a page a chart
  /// has no music for — the engine returns no page at all in that case, so null here always means
  /// "a page after the first".
  final PlacedChartHeader? header;

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
      header: header,
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
        other.header != header ||
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
  int get hashCode => Object.hash(
    index,
    size,
    header,
    scale,
    zoom,
    pan,
    Object.hashAll(systems),
  );

  @override
  String toString() =>
      'PageLayout($index, ${systems.length} system(s), ${bars.length} bar(s)'
      '${header == null ? '' : ', ${header!.text}'}'
      '${scale == 1 ? '' : ', scale $scale'}'
      '${zoom == 1 ? '' : ', zoom $zoom'}'
      '${pan == LayoutOffset.zero ? '' : ', pan $pan'})';
}
