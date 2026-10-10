// PURPOSE: Show the songs an iReal export contains, render the selected one as a chart a musician
//          can read — in the key they choose, with the whole tune on one page or paginated, and
//          with the performance facts on one bar — and let them CHANGE a chord in it or WRITE ON it
//          with a pen.
//          It is a reader and an editor: it shows the layout the engine produced, the issue list the
//          import reported, the chord palette for the cell they selected, and the handwriting layer
//          an ink mode turns on.
// INPUTS: A reference the reader supplies, an [IRealLibraryLoader] that turns that reference into
//         an [IRealLibrary], a starting reference, whether a reference is a filesystem path at all,
//         and whether to load the starting reference on the first frame. The loader is injected so
//         a widget test can pump this screen with a synthetic payload and never touch the
//         filesystem, and so the web build can hand it a browser file chooser instead of a path.
// OUTPUTS: A screen with a source bar, a chart save/open bar, an ink switch, an eraser switch, undo
//          and redo, a
//          bars-and-sections switch, a song list, a scene bar and the selected song's page or pages,
//          each drawn by `ChartPainter` at
//          the size the window gives it and covered by an `InkPainter` carrying the document's
//          strokes and a `TextCuePainter` carrying the words written on the chart. A tap on a page
//          selects the bar and cell under it, the painter highlights them,
//          and a line above the page states the selected position in words. Tapping that line opens
//          the chord palette for a selected cell and the bars-and-sections sheet for a bar-level
//          selection; a chord chosen in the palette is applied through the
//          operation log and redrawn, and undo and redo move that same log back and forth. With ink
//          on, a contact the palm rule admits is drawn into a stroke and appended to the same log,
//          and a contact it refuses still selects. With the eraser on, an admitted tap removes the
//          whole stroke it is on through that same log — undo puts it back exactly — and NO touch
//          selects at all, whether it hit ink or missed it. An app-bar action opens the words sheet
//          for the selected bar, where `To Coda`, `D.C. al Fine`, `Solo` and the like are written,
//          changed, moved and removed — also through that same log.
// KEYWORDS: viewer, ireal, reader, editor, screen, page-view, transposition, scene-bar, page-modes,
//           chord-palette, ink-mode, eraser-mode, ink-layer, op-log, undo, redo, chart-file, save,
//           open, song-form, bars, sections, text-cue, words, widget-test-seam, platform-seam,
//           verification
//
// WHERE THE INK LIVES. A stroke reaches the document through the same door a chord does: the ink
// layer assembles it and calls `EditSession.apply`, and nothing else writes to the document. What
// the page shows is the document's own stroke list, placed by each stroke's anchor, so an undo, a
// redo, a transposition and a save all agree about the ink for the same reason they agree about the
// music.
//
// WHERE AN EDIT LIVES. Each song shown has one [EditSession], created the first time the song is
// reached and kept until a different library is loaded. The session — not this widget's state and
// not the loaded [IRealSong] — holds the document, because the document is the reduction of a log
// and the log is what undo, redo and the saved tail all read. The page is drawn from
// `session.song`, the save action is given `session.document` and `session.log`, and an opened
// `.chart` file seeds a session from the tail it carried. There is no path by which a chord reaches
// the screen except through `EditSession`.
//
// WHAT CHANGES ON THE WEB, AND WHAT DOES NOT. Everything below the source bar is identical on
// every platform, because nothing below it touches a file: the loader is the seam and it is the
// same seam the widget tests use. Only the source bar differs — a path field where a path exists
// and a file-picker button where the browser can only offer a choice — which is what
// [sourceIsFilePath] selects. A screen that cannot name a file must not pretend to.
//
// WHERE THE CHART FILE IS SAVED AND OPENED. [`ChartFileAction`] owns that, not this screen: it is
// an app-bar action that opens a dialog holding the name field, the two buttons, a sentence saying
// what a save does on this platform and the status line. It is shown on every platform: the two
// functions behind it work in a browser too, where the field holds a file name to offer the
// browser's chooser rather than a path. This screen contributes only the WRITTEN song to save and
// takes the song an opened file decodes to. Keeping it in the APP BAR rather than in the body is
// deliberate: a bar above the chart takes height away from it, and D13's FIT mode refuses to shrink
// a chart past a legible floor, so a body bar turned a 200-bar song that fitted on one page into one
// that did not.
//
// WHICH TRANSPOSITION THIS IS. Owner decision D14 gives transposition two meanings, and this screen
// implements the EDITOR meaning: the chart is shown in another key, its key badge changes, and every
// chord is re-spelled, while the loaded library keeps the written form and a per-song interval
// remembers how far the shown chart has been moved. The SCENE meaning — an offset on one setlist
// position that leaves the song's written key alone — is NOT implemented here; it needs a setlist,
// and the model already carries the interval for it as `SetlistItem.transposeSem`, which a scene
// view would apply per chord while keeping `Song.key` as written. See
// `packages/chart_core/lib/src/transposition.dart` for the same note beside the operation itself.

import 'dart:async';
import 'dart:convert';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this screen
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'chart_file_bar.dart';
import 'chord_palette_sheet.dart';
import 'ink_capture_surface.dart';
import 'ink_layer.dart';
import 'ink_pointer_probe.dart';
import 'ink_pointer_probe_contract.dart';
import 'ireal_library.dart';
import 'ireal_source.dart';
import 'key_grid.dart';
import 'scene_bar.dart';
import 'song_form_sheet.dart';
import 'song_metadata_sheet.dart';
import 'text_cue_sheet.dart';

/// Turns a reference into the library it holds.
///
/// On a platform with a filesystem the reference is a path. In a browser it is whatever the web
/// implementation needs it to be — currently nothing, because the reader picks a file — but the
/// shape is kept so that there is ONE loading seam rather than one per platform.
typedef IRealLibraryLoader = Future<IRealLibrary> Function(String reference);

/// The screen that loads an iReal export and renders its songs.
class IRealViewerScreen extends StatefulWidget {
  /// Creates the viewer.
  ///
  /// [sourceIsFilePath] and the default of [autoLoad] both come from `ireal_source.dart`, so a
  /// build on any target gets the affordance its platform can honour without the caller passing
  /// anything.
  const IRealViewerScreen({
    super.key,
    this.loader = loadIRealLibrary,
    this.initialPath = defaultIRealPath,
    this.autoLoad = iRealSourceIsFilePath,
    this.sourceIsFilePath = iRealSourceIsFilePath,
  });

  /// How a reference becomes a library.
  final IRealLibraryLoader loader;

  /// The reference the source bar starts with.
  ///
  /// A path where one exists, and the empty string in a browser, where there is no reference to
  /// type and the bar shows no field to type it into.
  final String initialPath;

  /// Whether to load [initialPath] once, after the first frame.
  ///
  /// True where [initialPath] is a path, so a launch shows a chart without a click. False in a
  /// browser: the source is a file chooser, and a browser refuses to open one outside a user
  /// gesture, so a load on the first frame would be refused rather than deferred. A test that
  /// wants to decide exactly when the loader runs passes false and presses the button itself.
  final bool autoLoad;

  /// Whether [initialPath] is a filesystem path the reader may type.
  ///
  /// True selects the path field and the Load button; false selects a button that opens the
  /// platform's own file chooser and tells the reader the file is read where it already is.
  final bool sourceIsFilePath;

  @override
  State<IRealViewerScreen> createState() => _IRealViewerScreenState();
}

/// The viewer's state: the loaded library, which song is selected, how far each song has been
/// transposed for the screen, the page mode once the musician chooses one, and the last load error.
class _IRealViewerScreenState extends State<IRealViewerScreen> {
  /// The one metrics instance. It is shared with every [ChartPainter] below so that a chord is
  /// drawn in exactly the box the engine measured for it.
  static const FlutterTextMetrics _metrics = FlutterTextMetrics();

  /// The engine the pages are produced with. The bar is taller than the default so the signs drawn
  /// above and below the chord line have a band of their own.
  static const LayoutEngine _engine = LayoutEngine(
    style: LayoutStyle(
      textMetrics: _metrics,
      pageMargin: 20,
      barMinWidth: 64,
      barPadding: 8,
      chordSpacing: 12,
      minCellWidth: 18,
      barHeight: 52,
      systemSpacing: 18,
      sectionLabelHeight: 26,
    ),
  );

  /// The spelling rule the twelve-key grid uses.
  static const TranspositionGrid _grid = TranspositionGrid();

  late final TextEditingController _pathController;
  IRealLibrary? _library;
  int _selectedSong = 0;
  String? _error;
  bool _loading = false;

  /// How far each song is shown from its written key, by [IRealSong.index].
  ///
  /// The library keeps the written form, so this is the only thing a transposition changes; an
  /// absent entry means "as written". Cleared when a different library is loaded, because an index
  /// means a different song then.
  final Map<int, int> _semitonesBySong = <int, int>{};

  /// The page mode the musician chose, or null while the default is in force.
  ///
  /// Null rather than a stored default so the default can follow the surface: a tablet opens in
  /// FIT and a phone in PAGES, and once the musician picks a mode it stays picked.
  PageMode? _chosenPageMode;

  /// The bar and cell the musician last touched, or null when nothing is selected.
  ///
  /// This is the whole state of selection. It is a hit-test result rather than a copy of the
  /// selection's geometry, so the highlight is drawn from the layout that is on screen NOW: a
  /// rebuild from a transposition, a page-mode switch or a resize produces a new layout, and the
  /// address in this hit is matched against it instead of a stale rectangle being painted at the
  /// old position. Cleared when a different song or library is shown, because a section id and a
  /// bar index then name different music.
  ChartHit? _selection;

  /// The editing session of each loaded song, by [IRealSong.index].
  ///
  /// An entry is created the first time a song is shown and then lives until a different library is
  /// loaded, which is what makes an edit survive switching songs and coming back — the log, not a
  /// copy of the song, is what is kept. The map is keyed by the payload index rather than by the
  /// list position because that index is the identity the song list already uses, and a library
  /// replacement renumbers positions.
  final Map<int, EditSession> _sessions = <int, EditSession>{};

  /// The ink capture layer of each loaded song, by [IRealSong.index].
  ///
  /// Held beside [_sessions] rather than inside it for the same reason `_selection` is held outside:
  /// it is per-screen state about a session, not part of the document. It is recreated with its
  /// session, because a layer that outlived the session it writes to would append strokes to a
  /// document that no longer exists.
  final Map<int, InkCaptureLayer> _inkLayers = <int, InkCaptureLayer>{};

  /// The layer the raw pointer probe currently reports to, or null before a song is shown.
  ///
  /// One probe is installed for the lifetime of the screen and it must reach whichever song is on
  /// screen; this is the wire between them, set whenever a layer is reached for.
  InkCaptureLayer? _activeInkLayer;

  /// The installed raw pointer probe, or null on a target that has no browser to observe.
  ///
  /// It is read by [_inkInputReport], which is the application's side of the delivery measurement:
  /// the browser's own numbers and the framework's, taken from the same page at the same moment.
  InkProbeControl? _inkProbe;

  /// The page scale of the page last drawn, which the probe state reports.
  ///
  /// Kept as a field because the state is published from a pointer handler, where the painter that
  /// produced the page is no longer in scope, and because a scale is the one layout fact a
  /// verification of the ink transform needs to know.
  double _lastPageScale = 1;

  /// The surface the page was last laid out for, in logical pixels.
  ///
  /// Kept for the same reason as [_lastPageScale], and used by [_pageGeometry] to reproduce the
  /// layout a verification is aiming at. It starts as zero, so a geometry asked for before the first
  /// layout answers with an empty page rather than with a guess.
  Size _lastPageSurface = Size.zero;

  /// The page mode the last frame was drawn in, or null before one was.
  ///
  /// Read rather than re-derived, because the mode follows the pane width and only the pane's own
  /// layout pass knows it: a guess here would report a fitted page's geometry for an ordinary one,
  /// and the two disagree about where every cell is.
  PageMode? _lastPageMode;

  /// The last probe state published, so a rebuild that changes nothing writes nothing.
  String? _publishedInkState;

  /// Whether the contact that started the current tap was one the ink rule admitted.
  ///
  /// Set when the tap begins and read when it completes, because the two callbacks are the only two
  /// moments at which the answer is known: the rule decided at the pointer's own down, and by the up
  /// the layer has already committed the stroke and cleared the decision.
  bool _tapWasInk = false;

  // PURPOSE: Return the session of one song, opening it against the song as loaded the first time
  //          the song is reached.
  // INPUTS: entry — the loaded song.
  // OUTPUTS: The session, created on first use and reused afterwards. An existing session is
  //          returned untouched: a session holds the document, and rebuilding it from the loaded
  //          song would silently discard every edit made to that song.
  // KEYWORDS: session, lazy-creation, per-song, edit-persistence
  EditSession _sessionFor(IRealSong entry) => _sessions.putIfAbsent(
    entry.index,
    () => EditSession(
      document: DocumentState(song: entry.song),
      docId: entry.song.id,
    ),
  );

  // PURPOSE: Return the ink capture layer of one song, created against that song's session the first
  //          time a stroke needs it and reused afterwards.
  // INPUTS: entry — the loaded song, whose session the layer writes through.
  // OUTPUTS: The layer, created on first use. It is keyed by the same index as the session and is
  //          built FROM the session, so a stroke appended here lands in the log the page is drawn
  //          from and the undo button reverses. It also becomes the layer the raw pointer probe
  //          reports to, which is why this assignment exists at all: the probe outlives a song and
  //          the layer does not.
  // KEYWORDS: ink-layer, lazy-creation, per-song, session-bound, probe-target
  InkCaptureLayer _inkFor(IRealSong entry) {
    final InkCaptureLayer layer = _inkLayers.putIfAbsent(
      entry.index,
      () => InkCaptureLayer(session: _sessionFor(entry)),
    );
    _activeInkLayer = layer;
    return layer;
  }

  // PURPOSE: Report whether THE PEN is on for the song on screen, for the app-bar control.
  // INPUTS: None; reads the layer of the selected song.
  // OUTPUTS: True when a layer exists and its mode is the pen. False before any layer exists, and
  //          false while the eraser is on, because exactly one tool acts on a contact.
  // KEYWORDS: ink-mode, app-bar-state, default-off, null-when-empty, pen-only
  bool get _inkOn => _selectedInkLayer?.inkMode ?? false;

  // PURPOSE: Report whether the ERASER is on for the song on screen, for its app-bar control.
  // INPUTS: None; reads the layer of the selected song.
  // OUTPUTS: True when a layer exists and its mode is the eraser, false otherwise — before any
  //          layer exists, and while the pen is the active tool.
  // KEYWORDS: eraser-mode, app-bar-state, default-off, null-when-empty, exclusive-with-pen
  bool get _eraserOn => _selectedInkLayer?.eraserMode ?? false;

  // PURPOSE: Return the ink layer of the song on screen WITHOUT creating one, which is what a
  //          read-only control needs: listing a chart must not open a capture layer, and an absent
  //          layer and a layer that is off must both read as "not on" rather than as two states.
  // INPUTS: None; reads the library and the selected index, following the clamp the body uses.
  // OUTPUTS: The layer, or null when nothing is loaded or no layer has been created yet. This is the
  //          one place the app-bar controls resolve "the layer the selected song is drawn with", so
  //          the pen and the eraser cannot disagree about which song they describe.
  // KEYWORDS: current-layer, selection-clamp, no-eager-creation, null-when-empty, one-lookup
  InkCaptureLayer? get _selectedInkLayer {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return null;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    return _inkLayers[library.songs[index].index];
  }

  // PURPOSE: Return the session of the song currently selected, for the app bar, which has no song
  //          entry of its own.
  // INPUTS: None; reads the library and the selected index, following the same clamp the body uses.
  // OUTPUTS: The session, or null when nothing is loaded. Opening it here rather than only in the
  //          body keeps the undo and redo controls bound to the same session the page is drawn
  //          from; the two must never be two objects, or the buttons would offer to undo an edit
  //          the page is not showing.
  // KEYWORDS: current-session, app-bar, selection-clamp, null-when-empty
  EditSession? get _currentSession {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return null;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    return _sessionFor(library.songs[index]);
  }

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath);
    // The probe is installed HERE, once, and not in a build method: a listener added on every build
    // would be added a hundred times, and the browser would then call the handler a hundred times
    // per event while the counters still looked plausible.
    _inkProbe = InkInputProbe.install(onRawSample: _recordRawInkSample);
    // The live reader, so an inspecting tool reads the state of THIS screen at the moment it asks.
    // A detached callback is cleared in dispose, or a disposed state would answer a call with
    // setState on an unmounted widget the next time anything asked.
    inkStateReader = _inkProbeState;
    strokeCountReader = () => (_inkProbeState()['n'] as int?) ?? 0;
    inkInputCountersReader = () =>
        _activeInkLayer?.inputReport ?? const <String, Object?>{};
    pageGeometryReader = _pageGeometry;
    if (widget.autoLoad) {
      // Deferred to after the first frame so the window paints before a file read is started.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          unawaited(_load());
        }
      });
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    // Cleared rather than left dangling: a reader that outlived the screen would answer an
    // inspecting tool with the last state this screen ever held, which reads as a live chart.
    inkStateReader = noInkStatePublished;
    strokeCountReader = noStrokesPublished;
    inkInputCountersReader = noInkStatePublished;
    pageGeometryReader = noInkStatePublished;
    super.dispose();
  }

  // PURPOSE: Take one raw browser pointer sample and forward the contact width it carries to the
  //          layer that will decide what the contact means.
  // INPUTS: sample — one sample exactly as the browser delivered it, before Flutter mapped it.
  // OUTPUTS: Nothing. Only the width is forwarded: the position, the pressure and the tilt reach
  //          the layer through the framework's own event, and forwarding them twice would let the
  //          two streams disagree about a stroke that is already being assembled from one of them.
  //
  //          The width is forwarded because the framework drops it — Flutter's web pointer binding
  //          never reads the DOM event's `width`, so the framework's own contact radius arrives as
  //          zero and the width half of the palm rule would never fire without this.
  // KEYWORDS: raw-width-bridge, browser-to-dart, one-field-only, palm-rule-input
  void _recordRawInkSample(InkProbeSample sample) {
    final InkCaptureLayer? layer = _activeInkLayer;
    if (layer == null || sample.pointerType == 'pen') {
      return;
    }
    layer.recordRawContact(
      pointerType: sample.pointerType,
      width: sample.width,
      browserTimeMs: sample.browserTimeMs,
    );
  }

  // PURPOSE: Report the ink input measurement, which is the application's answer to "what does this
  //          platform actually deliver to the pen" — taken from the two streams on the same page at
  //          the same moment rather than from one of them.
  // INPUTS: None; reads the installed probe and the active layer.
  // OUTPUTS: A map with the browser's own tallies under `raw` and the framework's under `flutters`,
  //          plus the ink state that says whether a run drew anything. On a target with no browser
  //          the probe reports `supported: false` and both halves are empty, which is "not measured"
  //          rather than zero.
  // KEYWORDS: delivery-measurement, two-streams, pressure, tilt, width, honest-zero, report
  Map<String, Object?> inkInputReport() {
    final InkProbeControl? probe = _inkProbe;
    final InkCaptureLayer? layer = _activeInkLayer;
    return <String, Object?>{
      'name': 'ink.input.report',
      'probeSupported': probe?.supported ?? false,
      'raw': probe?.report() ?? const <String, Object?>{},
      'flutters': layer?.inputReport ?? const <String, Object?>{},
      'rule': layer?.ruleReport ?? const <String, Object?>{},
    };
  }

  // PURPOSE: Describe what a browser-driving verification needs to read: the pen's state, the two
  //          input streams' tallies, the page transform, and every stroke with the anchor it was
  //          stored against. Without this a headless run can draw and photograph but cannot check a
  //          single number, because the application's Dart objects are unreachable from outside.
  // INPUTS: None; reads the current session, page, layer and probe.
  // OUTPUTS: A map, empty when nothing is on screen. It is built on demand and never cached: a
  //          cached copy would be read right after input and answer with the state from before it,
  //          which looks exactly like input that did nothing.
  // KEYWORDS: verification-handoff, live-state, stroke-list, anchor, page-scale, no-cache
  Map<String, Object?> _inkProbeState() {
    final IRealLibrary? library = _library;
    final InkCaptureLayer? layer = _activeInkLayer;
    if (library == null || library.songs.isEmpty || layer == null) {
      return const <String, Object?>{};
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final EditSession session = _sessionFor(library.songs[index]);
    final InkProbeControl? probe = _inkProbe;
    return <String, Object?>{
      'n': session.document.strokes.length,
      'undo': session.undoDepth,
      'redo': session.redoDepth,
      'seq': session.seq,
      'ink': layer.inkMode,
      'eraser': layer.eraserMode,
      'mode': layer.mode.token,
      'erase': layer.inputReport['lastErase'],
      'scale': _lastPageScale,
      'contact': layer.lastPointWasInk,
      'flutters': layer.inputReport,
      'raw': probe?.report() ?? const <String, Object?>{},
      'rule': layer.ruleReport,
      // --- TEXT CUES (the words written on the chart) ----------------------------------------
      // Reported beside the strokes for the same reason the strokes are: a browser-driving tool
      // cannot reach a Dart object, and "the cue is still on the bar it was put on" is a claim only
      // the document can settle. Each cue is reported with the ADDRESS it is anchored to and the
      // offset it stores, which are the two things a FIT or a transposition must not change.
      // This block, the `viewer-text-cue` app-bar action, `_openTextCueSheet`, `_resolveCues` and
      // the cue painter inside `_layeredPage` are the whole of the text-cue feature in this file.
      'cues': <Object?>[
        for (final TextCue cue in session.document.textCues)
          <String, Object?>{
            'id': cue.id,
            'text': cue.text,
            'sec': cue.place.anchor.sectionId,
            'bar': cue.place.anchor.bar,
            'beat': cue.place.anchor.beat,
            'dx': cue.place.offsetX,
            'dy': cue.place.offsetY,
          },
      ],
      'strokes': <Object?>[
        for (final InkStroke stroke in session.document.strokes)
          <String, Object?>{
            'id': stroke.id,
            'sec': stroke.anchor.sectionId,
            'bar': stroke.anchor.bar,
            'beat': stroke.anchor.beat,
            'step': stroke.anchor.step,
            'pts': stroke.points.length,
            'p0': <double>[stroke.points.first.x, stroke.points.first.y],
            't': stroke.points.last.t,
            // THE CANONICAL FORM, because the fields above are a summary and an eraser
            // verification has to compare the STROKE: a removal and an undo that restored a
            // re-derived stroke with the same id and the same first point would agree with every
            // summary field and disagree about the ink. This is the same JSON a `.chart` file
            // carries, so what a driver reads here is what the document actually holds.
            'canonical': stroke.toJson(),
          },
      ],
    };
  }

  // PURPOSE: Describe the page on screen in the coordinates an input event arrives in, so a
  //          verification can aim a pen at a named cell instead of estimating a pixel from a picture.
  // INPUTS: None; reads the painter and layout of the page currently shown.
  // OUTPUTS: A map with the page's index and scale, the surface rectangle implied by that scale, the
  //          first cell of the first bar as an aim point, and every bar with the centre of its cells.
  //          An empty map when no page is on screen.
  //
  //          THE COORDINATES ARE SURFACE logical pixels: the page's engraved rectangles multiplied by
  //          its own scale, which is exactly the space `_onPagePointerDown` receives a contact in.
  //          Reporting the engraved rectangles instead would be right on an ordinary page and wrong
  //          on a fitted one, which is the same trap `pagePointOf` exists to close.
  //
  //          HOW A BROWSER-DRIVING TOOL MUST CLICK, MEASURED RATHER THAN ASSUMED. These numbers are
  //          relative to the PAGE WIDGET, and the tool needs coordinates relative to the window, so
  //          it has to add the widget's origin once. Two facts about that, both observed while
  //          driving the built web app headlessly:
  //
  //          1. WITH FLUTTER WEB SEMANTICS ENABLED, A CLICK ON A TAPPABLE NODE IS DELIVERED AS A
  //             CENTRE TAP: the framework synthesises a pointer at the middle of the semantic node
  //             instead of using the point that was clicked, so aiming at the chart by coordinate
  //             lands on the centre of the page whatever was clicked. Chart aiming must therefore be
  //             done with semantics OFF and raw pointer coordinates; buttons are the opposite case
  //             and are best clicked through their semantic node, where the centre is the target.
  //          2. THE PAGE WIDGET'S ORIGIN IS FOUND ONCE PER LAYOUT AND ADDED TO EVERY CELL. On the
  //             1400x900 window used for that run the song list and divider put it at x = 261, and
  //             the rows above the chart put it at y = 311, so a cell reported at (139.3, 72.0) is
  //             clicked at (400, 383) — which the app logged back as `surface=(139.3,72.0)`. Those
  //             two numbers are a measurement of THAT window, not constants: recompute them if the
  //             viewport, the theme or the rows above the chart change.
  // KEYWORDS: verification-handoff, page-geometry, surface-coordinates, fit-scale, aim-point,
  //           semantics-centre-tap, driving-calibration, measured-origin
  Map<String, Object?> _pageGeometry() {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return const <String, Object?>{};
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final Song displayed = _displayedSong(
      library.songs[index],
      _semitonesBySong[library.songs[index].index] ?? 0,
    );
    final PageMode mode = _lastPageMode ?? PageMode.pages;
    // The cues belong in the calibration layout for the same reason they belong in the drawn one:
    // the rows they reserve change where the bars sit, and a geometry probe that measured a
    // cue-free page would aim a driving tool at a page nobody is looking at.
    final List<TextCue> cues = _sessionFor(library.songs[index])
        .document
        .textCues;
    final List<PageLayout> pages;
    if (mode == PageMode.fit) {
      final FitOutcome outcome = _engine.fitToPage(
        displayed,
        pageWidth: _lastPageSurface.width,
        pageHeight: _lastPageSurface.height,
        cues: cues,
      );
      final PageLayout? page = outcome.page;
      if (page == null) {
        return const <String, Object?>{};
      }
      pages = <PageLayout>[page];
    } else {
      pages = _engine.layout(
        displayed,
        pageWidth: _lastPageSurface.width,
        pageHeight: _lastPageSurface.height,
        cues: cues,
      );
    }
    if (pages.isEmpty) {
      return const <String, Object?>{};
    }
    final PageLayout page = pages.first;
    final double scale = page.scale;
    return <String, Object?>{
      'page': page.index,
      'mode': mode.name,
      'scale': scale,
      'surface': <double>[page.size.width * scale, page.size.height * scale],
      'cells': <Object?>[
        for (final PlacedBar bar in page.bars)
          for (final PlacedCell cell in bar.cells)
            <String, Object?>{
              'sec': bar.sectionId,
              'bar': bar.barIndex,
              'beat': cell.beat,
              'x': (cell.bounds.left + cell.bounds.size.width / 2) * scale,
              'y': (cell.bounds.top + cell.bounds.size.height / 2) * scale,
            },
      ],
    };
  }

  // PURPOSE: Publish the state, so a browser-driving tool that cannot call into Dart still has a
  //          copy of it, and so a log line records the moment it changed.
  // INPUTS: None.
  // OUTPUTS: Nothing when the state is empty or unchanged. The published line is a convenience, not
  //          the source of truth: the live reader is what a verification should call, because this
  //          one is written during a build and is therefore as old as the last frame.
  // KEYWORDS: verification-handoff, publish, change-guard, convenience-copy
  void _publishInkState() {
    final Map<String, Object?> state = _inkProbeState();
    if (state.isEmpty) {
      return;
    }
    final String line = jsonEncode(state);
    if (line == _publishedInkState) {
      return;
    }
    _publishedInkState = line;
    publishInkProbeState(line);
  }

  // PURPOSE: Replace the shown library with the one the current path holds, or record why it could
  //          not be read.
  // INPUTS: None; the path comes from [_pathController].
  // OUTPUTS: Nothing. Sets [_loading] around the read and either [_library] or [_error] afterwards.
  //          A result that arrives after the screen is gone is dropped rather than calling setState
  //          on an unmounted state. A successful load clears every remembered transposition.
  // KEYWORDS: load, error-handling, unmounted-guard, structured-log
  Future<void> _load() async {
    final String path = _pathController.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    debugPrint('viewer.load.start path_chars=${path.length}');
    try {
      final IRealLibrary library = await widget.loader(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _library = library;
        _selectedSong = 0;
        _semitonesBySong.clear();
        // An index means a different song in a new library, so every session in the old one names
        // music that is no longer loaded. Dropping them is what keeps an edit from being applied to
        // whatever happens to sit at that index now. The ink layers go with them for the same
        // reason: a layer holds the session it writes through.
        _sessions.clear();
        _inkLayers.clear();
        // A section id and a bar index from the previous library name different music here, so a
        // selection carried across a load would point at whatever happens to sit at that address.
        _selection = null;
        _loading = false;
      });
      debugPrint(
        'viewer.load.ok songs=${library.songs.length} '
        'playlist_chars=${library.playlistName.length}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
      debugPrint('viewer.load.error error=$error');
    }
  }

  // PURPOSE: Open the issue list for one song, which is where a requested transposition is
  //          reported, so the reader can see why a chart is in a different key than expected.
  // INPUTS: context — the dialog's context. entry — the song whose issues to list.
  // OUTPUTS: A future that completes when the dialog is dismissed.
  // KEYWORDS: issues, transposition, dialog, diagnostics
  Future<void> _showIssues(BuildContext context, IRealSong entry) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Import issues — ${entry.title}'),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final IRealParseIssue issue in entry.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('@${issue.offset}: ${issue.message}'),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // PURPOSE: Give the musician the twelve keys and remember the one they pick, which is the whole
  //          two-tap transposition path: this is the second tap.
  // INPUTS: entry — the song being transposed, whose written key is what the grid spells from.
  // OUTPUTS: A future that completes when the grid closes. Picking a key stores its interval for
  //          this song and rebuilds, so the chart, the key badge and the page are re-rendered in
  //          the new key. A dismissed grid, an unavailable target, or a grid closed after the
  //          screen is gone changes nothing.
  // KEYWORDS: transposition, key-grid, two-taps, state-update, structured-log
  Future<void> _chooseKey(IRealSong entry) async {
    final int current = _semitonesBySong[entry.index] ?? 0;
    final Key shownKey = _keyFor(entry.song.key, current);
    final TranspositionTarget? picked = await showKeyGrid(
      context,
      writtenKey: entry.song.key,
      currentPitchClass: shownKey.tonicPitchClass,
    );
    if (!mounted || picked == null || !picked.available) {
      debugPrint(
        'viewer.transpose.cancelled song="${_titleFor(entry)}" '
        'picked=${picked == null ? 'none' : picked.key}',
      );
      return;
    }
    setState(() => _semitonesBySong[entry.index] = picked.semitones);
    debugPrint(
      'viewer.transpose.ok song="${_titleFor(entry)}" written=${entry.song.key} '
      'shown=${picked.key} semitones=${picked.semitones}',
    );
  }

  // PURPOSE: Find the target that reaches a stored interval, so a key remembered as a number is
  //          rendered with the same practical spelling the grid offered.
  // INPUTS: written — the key the chart is written in. semitones — the stored interval, in the
  //         grid's own `[-5, 6]` range.
  // OUTPUTS: The target's key. Every interval in that range is produced by exactly one of the
  //          twelve targets, so the lookup always succeeds; a value outside the range (which
  //          nothing in this screen produces) falls back to the written key rather than throwing.
  // KEYWORDS: lookup, interval, key-spelling, fallback
  Key _keyFor(Key written, int semitones) {
    for (final TranspositionTarget target in _grid.targets(written)) {
      if (target.semitones == semitones) {
        return target.key;
      }
    }
    return written;
  }

  // PURPOSE: Produce the chart to show for one song, which is the EDITED chart moved by the
  //          interval the musician chose, or the edited chart itself when they chose nothing.
  // INPUTS: entry — the song as loaded. semitones — the stored interval.
  // OUTPUTS: The displayed song. The base is the session's document rather than the loaded song,
  //          because the session is where an edit lives; at zero semitones it is returned
  //          unchanged, so the common case does no work and the drawn result is identical to the
  //          edited one.
  // KEYWORDS: display-song, session-document, transposition, identity-fast-path
  Song _displayedSong(IRealSong entry, int semitones) {
    final Song song = _sessionFor(entry).song;
    return semitones == 0
        ? song
        : transposeSong(song, semitones, toKey: _keyFor(song.key, semitones));
  }

  // PURPOSE: Give the title to SHOW for one loaded song, which is the edited one once the song has
  //          been opened — a rename has to reach every place the name is read, or one screen says
  //          the new name and the list beside it says the old one.
  // INPUTS: entry — the song as loaded, whose index names a session if one exists.
  // OUTPUTS: The session's title when that song has a session, the loaded title otherwise, and
  //          `Untitled` for an empty one — the same fallback `IRealSong.title` applies, so the two
  //          agree before anything is edited. The session is looked up in the map and NOT created:
  //          listing a library must not open a document for every song in it just to read a name.
  // KEYWORDS: title, edited-metadata, session-source, untitled-fallback, no-eager-session
  String _titleFor(IRealSong entry) {
    final String title = _sessions[entry.index]?.song.title ?? entry.song.title;
    return title.isEmpty ? 'Untitled' : title;
  }

  @override
  Widget build(BuildContext context) {
    final Widget screen = _buildScreen(context);
    // AFTER the tree is described, not before: the ink layer is created on the way down, by the pane
    // that needs it, so a publish that ran first would always read a layer that does not exist yet.
    // The call is a no-op on every target without a browser, and a no-op here when the line matches
    // the last one published.
    _publishInkState();
    return screen;
  }

  /// Describes the screen: the app bar, the source bar, the body and the status line.
  Widget _buildScreen(BuildContext context) {
    final String? error = _error;
    final EditSession? session = _currentSession;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChartApp — iReal reader'),
        // Undo and redo stand beside the save action because all three are about the document
        // rather than about the page: the two reversals move the log, and the save writes what the
        // log produced. They are disabled rather than hidden when there is nothing to reverse, so
        // the pair keeps its place in the bar and a musician's hand learns where it is.
        actions: <Widget>[
          // The ink switch stands first because it changes what a pen DOES, and a musician about to
          // write needs it under their thumb before anything else in this bar. It is disabled when
          // there is no chart, and its icon and tooltip state the mode in words, because a toggle
          // whose only signal is a colour is not discoverable.
          IconButton(
            key: const ValueKey<String>('viewer-ink-toggle'),
            icon: Icon(_inkOn ? Icons.draw : Icons.edit_outlined),
            tooltip: _inkOn
                ? 'Drawing: the pen draws, a finger still selects'
                : (_eraserOn
                      ? 'Pen off: the eraser is on'
                      : 'Selecting: the pen and a finger both select'),
            onPressed: session == null ? null : () => _toggleInk(session),
          ),
          // --- ERASER ---------------------------------------------------------------------------
          // The eraser stands next to the pen because the two are the two things a contact on the
          // chart can do to the ink, and there is exactly one of them at a time: pressing it turns
          // the pen off, and pressing the pen turns it off. It is disabled when there is no chart
          // for the same reason the pen is, and its tooltip states the gesture in words — a tap on
          // a stroke removes that whole stroke — because a musician cannot be expected to discover
          // a mode from an icon. This button, `_toggleEraser` below `_toggleInk`, the `_eraserOn`
          // getter beside `_inkOn`, the `eraser` keys in `_inkProbeState`, and the eraser branch of
          // `_onPageTapUp` are the whole of this feature's footprint in this file.
          IconButton(
            key: const ValueKey<String>('viewer-eraser-toggle'),
            icon: const Icon(Icons.auto_fix_normal),
            tooltip: _eraserOn
                ? 'Erasing: tap a stroke and its whole length goes'
                : 'Eraser off',
            onPressed: session == null ? null : () => _toggleEraser(session),
          ),
          IconButton(
            key: const ValueKey<String>('viewer-undo'),
            icon: const Icon(Icons.undo),
            tooltip: 'Undo the last chart edit',
            onPressed: session != null && session.canUndo
                ? () => _undo(session)
                : null,
          ),
          IconButton(
            key: const ValueKey<String>('viewer-redo'),
            icon: const Icon(Icons.redo),
            tooltip: 'Redo the last undone chart edit',
            onPressed: session != null && session.canRedo
                ? () => _redo(session)
                : null,
          ),
          // --- BARS AND SECTIONS (form editing, owner decision D17) -----------------------------
          // An app-bar action rather than a row in the body: a body row costs the chart height, and
          // D13's FIT refuses to shrink a chart past the legible floor (the `.chart` control's move
          // into this bar, in `chart_file_bar.dart`, is that mistake measured). It is disabled until
          // a bar is selected, because every operation in its sheet acts on the selected bar's
          // section and index. This button, the `_openSongForm` method below `_redo`, and the
          // bar-level branch of `_buildSelectionLine` are the whole of this feature's footprint in
          // this file.
          IconButton(
            key: const ValueKey<String>('viewer-form'),
            icon: const Icon(Icons.segment),
            tooltip: 'Bars and sections (the form)',
            onPressed: session == null || _selection == null
                ? null
                : () => _openSongForm(context, session),
          ),
          // --- WORDS ON THE CHART (text cues, `textcue.*`) --------------------------------------
          // Placed beside the form action because both act on the bar the page's hit test named,
          // and disabled under the same condition: a cue is anchored to an address, so there is
          // nothing to write on until a bar is selected. It opens a sheet that holds its own
          // address cursor, so a musician can move to another bar and write there without leaving.
          // Its icon is a speech mark rather than a pencil, because the pencil is what the ink
          // switch already means and two controls named "write" would be one too many.
          IconButton(
            key: const ValueKey<String>('viewer-text-cue'),
            icon: const Icon(Icons.format_quote),
            tooltip: 'Words on the chart (To Coda, Solo, 4×)',
            onPressed: session == null || _selection == null
                ? null
                : () => _openTextCueSheet(context, session),
          ),
          // The chart document itself can be named and moved, on every platform: where a path
          // exists the field holds it, and in a browser it holds the name offered to the browser's
          // chooser and download. It lives in the app bar because a control in the body takes height
          // away from the chart, and D13's FIT mode refuses to shrink a chart past a legible floor —
          // the bar turned a song that fitted on one page into one that did not.
          ChartFileAction(
            document: _documentOfSelection,
            events: session?.log ?? const <ChartEvent>[],
            initialPath: chartPathBeside(widget.initialPath),
            onOpened: _adoptOpenedSong,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildPathBar(context),
          if (error != null) _buildError(context, error),
          Expanded(child: _buildBody(context)),
          _buildStatusBar(context),
        ],
      ),
    );
  }

  // PURPOSE: Turn pen drawing on or off for the song on screen, which is the whole of the mode
  //          switch a musician needs: with it on a pen lays ink and a finger still selects, with it
  //          off a pen selects like a finger.
  // INPUTS: session — the session of the song on screen, from which the layer is reached.
  // OUTPUTS: Nothing. Rebuilds the screen so the control's own state is shown. The layer is looked up
  //          through the selected song rather than passed in, because the app bar has no song entry
  //          of its own and the layer belongs to whichever song the body is drawing.
  // KEYWORDS: ink-mode, toggle, pen-vs-finger, rebuild, structured-log
  void _toggleInk(EditSession session) {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final IRealSong entry = library.songs[index];
    final InkCaptureLayer layer = _inkFor(entry);
    final bool next = !layer.inkMode;
    layer.inkMode = next;
    setState(() {});
    _publishInkState();
    debugPrint(
      'viewer.ink.toggle song="${_titleFor(entry)}" on=$next '
      'strokes=${layer.strokeCount} session_matches=${identical(session, _sessionFor(entry))}',
    );
  }

  // PURPOSE: Turn the ERASER on or off for the song on screen, which is the second half of the ink
  //          switch pair: with it on, a contact the palm rule admits removes the whole stroke it
  //          taps, and a contact it refuses does nothing at all — neither erase nor select.
  // INPUTS: session — the session of the song on screen, used only to check which song the layer
  //         belongs to, exactly as [_toggleInk] uses it.
  // OUTPUTS: Nothing. Rebuilds so the two controls show the new mode. Turning the eraser on turns
  //          the pen off and the other way round, because the layer holds one mode; the two buttons
  //          therefore cannot both read as on.
  // KEYWORDS: eraser-mode, toggle, pen-vs-eraser, rebuild, structured-log
  void _toggleEraser(EditSession session) {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final IRealSong entry = library.songs[index];
    final InkCaptureLayer layer = _inkFor(entry);
    final bool next = !layer.eraserMode;
    layer.eraserMode = next;
    setState(() {});
    _publishInkState();
    debugPrint(
      'viewer.eraser.toggle song="${_titleFor(entry)}" on=$next '
      'mode=${layer.mode.token} strokes=${layer.strokeCount} '
      'session_matches=${identical(session, _sessionFor(entry))}',
    );
  }

  // PURPOSE: Give the save/open action the state a `.chart` file must store as its snapshot, which
  //          is the WRITTEN chart before its own operation tail rather than the chart on screen.
  // INPUTS: None; reads the library and the selection.
  // OUTPUTS: The selected song's session BASE document, or null when nothing is loaded. The base and
  //          not the current document, because the container's document is the snapshot PLUS the
  //          operations: writing the current one with the tail beside it stores every edit twice,
  //          and reopening then inserts every bar again and removes a second one. The document is
  //          handed over as a whole rather than as a song because a `.chart` file stores a snapshot
  //          plus a log, and the log lives on the session; a selected index outside the library —
  //          which only a library replacement can produce — is treated as the first song, the same
  //          rule [_buildBody] uses.
  // KEYWORDS: written-form, selection, save-source, base-document, operation-tail, null-when-empty
  DocumentState? get _documentOfSelection {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return null;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    return _sessionFor(library.songs[index]).baseDocument;
  }

  // PURPOSE: Replace the shown library with the one song a `.chart` file produced, so the chart the
  //          file describes is the one on screen, and seed its session from the operation tail the
  //          file carried.
  // INPUTS: opened — the file's SNAPSHOT, which is the state before the tail, and the tail itself.
  // OUTPUTS: Nothing. The library becomes a single-song one, the selection returns to the first
  //          song, and every remembered transposition and the current hit selection are cleared:
  //          both are addressed by an index or a section id that names different music now. The
  //          file's tail is carried into the session as RESTORED events, which the session folds
  //          over the snapshot so the page shows the chart the writer saw, and whose sequence
  //          numbers are then not reissued: `(docId, seq)` addresses a log row, and a session that
  //          restarted at 1 would produce two events claiming the same position.
  // KEYWORDS: open-chart, adopt-snapshot, restored-log, seq-continuation, state-reset
  void _adoptOpenedSong(OpenedChart opened) {
    setState(() {
      _library = IRealLibrary(
        playlistName: '',
        songs: <IRealSong>[IRealSong(index: 0, song: opened.document.song)],
      );
      _selectedSong = 0;
      _semitonesBySong.clear();
      _sessions
        ..clear()
        ..[0] = EditSession(
          document: opened.document,
          docId: opened.document.song.id,
          seq: _highestSeq(opened.events),
          restored: opened.events,
        );
      // A layer holds the session it writes through, so the one belonging to the replaced library
      // must not survive: a stroke appended through it would go to a document nothing is showing.
      _inkLayers.clear();
      _selection = null;
      _error = null;
    });
  }

  // PURPOSE: Find the sequence number a restored log ends at, so a session continuing it issues the
  //          next free number rather than a used one.
  // INPUTS: events — the operations read from a file, in log order.
  // OUTPUTS: The highest `seq` the events carry, or 0 when there are none. A log from a file is
  //          written in ascending order, so the last event's number is the answer; the maximum is
  //          taken rather than the last element alone so that a hand-assembled list is still safe.
  // KEYWORDS: seq, restored-log, continuation, max
  static int _highestSeq(List<ChartEvent> events) {
    int highest = 0;
    for (final ChartEvent event in events) {
      if (event.seq > highest) {
        highest = event.seq;
      }
    }
    return highest;
  }

  // PURPOSE: Give the reader the control that starts a load, in the form the platform can honour.
  // INPUTS: context — the build context.
  // OUTPUTS: The bar widget. Where a path exists this is the path field and the Load button; in a
  //          browser it is a single button that opens the file chooser, because a text field for a
  //          path no browser can resolve would invite the reader to type something meaningless. The
  //          button is disabled while a load is running, so two reads cannot race for the same
  //          state.
  // KEYWORDS: source-bar, path-field, load-button, file-picker, busy-guard, platform-affordance
  Widget _buildPathBar(BuildContext context) {
    if (!widget.sourceIsFilePath) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.folder_open),
            label: const Text('Open .html file'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'iReal .html file',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (String _) => unawaited(_load()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.folder_open),
            label: const Text('Load'),
          ),
        ],
      ),
    );
  }

  // PURPOSE: Show why a load failed, in the same window rather than only on a console the reader
  //          may not be looking at.
  // INPUTS: context — the build context. message — the error text.
  // OUTPUTS: A banner widget.
  // KEYWORDS: error-banner, feedback, file-not-found
  Widget _buildError(BuildContext context, String message) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
    );
  }

  // PURPOSE: Decide what occupies the window below the path bar: a message, or the song list beside
  //          the selected song's pages.
  // INPUTS: context — the build context.
  // OUTPUTS: The body widget. Before a load it explains what to do, and after an empty library it
  //          says so rather than showing an empty list.
  // KEYWORDS: body, empty-state, split-view
  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final IRealLibrary? library = _library;
    if (library == null) {
      // The prompt names the platform's own way in, because the alternative — telling a browser
      // reader to type a Windows path — is the one instruction they cannot follow.
      final String prompt = widget.sourceIsFilePath
          ? 'Load an iReal .html file to see its songs.\n'
                'Default: $defaultIRealPath'
          : 'Open an iReal .html file exported from iReal Pro.\n'
                'It is read in the browser and is not uploaded.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(prompt, textAlign: TextAlign.center),
        ),
      );
    }
    if (library.songs.isEmpty) {
      return const Center(child: Text('The payload carried no songs.'));
    }
    final int songIndex =
        _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 260, child: _buildSongList(context, library)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildSongPane(context, library, songIndex)),
      ],
    );
  }

  // PURPOSE: List the loaded songs so one can be selected.
  // INPUTS: context — the build context. library — the loaded songs.
  // OUTPUTS: A scrollable list. Each row names the song, its bar count, the key it is shown in and,
  //          when there are any, its issue count. A transposed song shows the move, so the list
  //          says which charts are no longer in their written key. A song whose session exists
  //          reports the NAME and bar count of the EDITED chart, so the row and the pane beside it
  //          cannot disagree about a chart the musician just changed — a rename that reached the
  //          page's own header and not this list would be two names for one song. A song nobody has
  //          opened reports the loaded values, and no session is created just to read them.
  // KEYWORDS: song-list, selection, issue-count, shown-key, written-key, edited-title, edited-count
  Widget _buildSongList(BuildContext context, IRealLibrary library) {
    return ListView.builder(
      itemCount: library.songs.length,
      itemBuilder: (BuildContext context, int index) {
        final IRealSong entry = library.songs[index];
        final int semitones = _semitonesBySong[entry.index] ?? 0;
        final String keyLabel = semitones == 0
            ? '${entry.song.key}'
            : '${entry.song.key} → ${_keyFor(entry.song.key, semitones)}';
        final Song summarySong = _sessions[entry.index]?.song ?? entry.song;
        final String subtitle =
            '${summarySong.writtenBarCount} bar(s) · $keyLabel'
            '${entry.issues.isEmpty ? '' : ' · ${entry.issues.length} issue(s)'}';
        return ListTile(
          dense: true,
          selected: index == _selectedSong,
          title: Text(
            _titleFor(entry),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => setState(() {
            _selectedSong = index;
            // A selection belongs to the song it was made in; another song's bar at the same
            // address is a different bar.
            _selection = null;
          }),
        );
      },
    );
  }

  // PURPOSE: Show one song: its identity, the scene bar with everything a performer reads, and the
  //          chart in the chosen key and page mode.
  // INPUTS: context — the build context. library — the loaded songs. songIndex — which one.
  // OUTPUTS: A column widget. The title stays visible above the scene bar because the song's name
  //          is the one thing the scene bar does not repeat, and it is also the handle that opens
  //          the song-info sheet: the title is where a song's own facts are read, so it is where
  //          they are edited. The bar count beside it counts the
  //          chart the SESSION holds, not the one that was loaded: inserting or deleting a bar
  //          changes that number, and a header still claiming the imported count would be
  //          describing a page the musician is no longer looking at.
  // KEYWORDS: song-pane, title, bar-count, edited-form, scene-bar, issue-button, pages
  Widget _buildSongPane(
    BuildContext context,
    IRealLibrary library,
    int songIndex,
  ) {
    final IRealSong entry = library.songs[songIndex];
    final int semitones = _semitonesBySong[entry.index] ?? 0;
    final Song displayed = _displayedSong(entry, semitones);
    final EditSession session = _sessionFor(entry);
    // The strokes come from the document the SESSION holds, which is the written chart, and they are
    // placed by address against the page on screen. A transposition therefore moves the music and
    // the ink together without either being transformed.
    final InkCaptureLayer layer = _inkFor(entry);
    final List<InkStroke> strokes = session.document.strokes;
    // The cues come from the same document and are placed the same way: by address, against the
    // page on screen, so a transposition moves the music and the words together. They are read
    // here rather than inside the painter for the same reason the strokes are.
    final List<TextCue> textCues = session.document.textCues;
    // The mode follows the PANE the chart is drawn in, not the window. The song list takes a fixed
    // slice off the left, so a window the mode would call a tablet can leave a chart area narrower
    // than the default assumes — on the owner's tablet that is 824 logical pixels of window against
    // 564 of pane, either side of the 600 threshold. Measuring the pane rather than deriving it
    // from the window is what keeps the two from drifting apart when the pane's width changes.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final PageMode mode = _pageModeFor(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  // The title is where the song's own facts are read, so it is where they are
                  // edited: tapping it opens the sheet that holds the title, the composer, the style
                  // and the tempo. The pencil is what says so — a title that silently turns out to
                  // be a button is not discoverable on its own.
                  Expanded(
                    child: Tooltip(
                      message: 'Song info: title, composer, style and tempo',
                      child: InkWell(
                        key: const ValueKey<String>('viewer-song-info'),
                        onTap: () => _openSongInfo(
                          context,
                          session,
                          SongMetadataField.title,
                        ),
                        child: Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                _titleFor(entry),
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: Color(0xFF486581),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // The EDITED count, which is what the page under it is drawn from. Transposition
                  // does not change how many bars a chart has, so `displayed` and the written
                  // session document agree on this number and either would do; the displayed one is
                  // already here.
                  Text('${displayed.writtenBarCount} bar(s)'),
                  if (entry.issues.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => unawaited(_showIssues(context, entry)),
                      child: Text('${entry.issues.length} issue(s)'),
                    ),
                  ],
                ],
              ),
            ),
            SceneBar(
              position: songIndex + 1,
              songCount: library.songs.length,
              song: displayed,
              semitones: semitones,
              pageMode: mode,
              onOpenKeyGrid: () => unawaited(_chooseKey(entry)),
              onPageModeChanged: (PageMode picked) =>
                  setState(() => _chosenPageMode = picked),
              // The tempo and the style are edited where they are shown. The sheet is one surface
              // for all four facts and opens with the tapped field focused, so the tempo a musician
              // pressed is the tempo the cursor is in.
              onEditTempo: () =>
                  _openSongInfo(context, session, SongMetadataField.tempo),
              onEditStyle: () =>
                  _openSongInfo(context, session, SongMetadataField.style),
            ),
            const SizedBox(height: 6),
            _buildSelectionLine(context, displayed),
            Expanded(
              child: _buildPages(
                entry,
                displayed,
                mode,
                layer,
                strokes,
                textCues,
              ),
            ),
          ],
        );
      },
    );
  }

  // PURPOSE: Decide which page mode is in force, so the default follows the surface and a choice
  //          the musician made survives.
  // INPUTS: paneWidth — the width of the space the chart itself is drawn in, which is the window
  //         MINUS the song list, not the window.
  // OUTPUTS: The mode the musician chose, or — before they have chosen — FIT on a chart pane at
  //          least [sceneBarTabletWidth] logical pixels wide and PAGES on anything narrower. That
  //          is owner decision D13's "tablet edit = FIT" expressed against the surface the chart
  //          is actually drawn on rather than the device's label.
  // KEYWORDS: page-mode, default, tablet, fit, pages, responsive, pane-width
  PageMode _pageModeFor(double paneWidth) =>
      _chosenPageMode ??
      (paneWidth >= sceneBarTabletWidth ? PageMode.fit : PageMode.pages);

  // PURPOSE: One page of the chart: the music, the ink committed to this page, the stroke currently
  //          under the pen, and the touch that turns a point on the glass into a selection.
  // INPUTS: page — the laid-out page to draw and hit-test against. song — the model it came from,
  //         handed to the painter for the signs the layout does not carry. layer — the ink capture
  //         layer of the song on screen, which decides what a contact means and which strokes this
  //         page carries. strokes — every committed stroke of the document, filtered to this page.
  // OUTPUTS: The page as a stack of the chart painter and the ink painter, wrapped in an outer
  //          listener that feeds the ink layer and an inner gesture detector that turns a tap into a
  //          selection.
  //
  //          WHY THE INK OUTER AND THE TAP INNER, AND WHY THAT ORDER IS NOT ARBITRARY. Flutter
  //          dispatches a pointer event to the hit-test path from the deepest target outward, so the
  //          ink layer — being the OUTER widget — sees the lift AFTER the inner tap recogniser
  //          requested its pointer, but a gesture is only resolved once every handler for that event
  //          has run. That is what puts the commit before the selection decision, and it is
  //          load-bearing: with the two the other way round, the lift handler ran before
  //          `endStroke` had added the stroke, asked the document how many strokes it held, was told
  //          zero, and skipped the rebuild. The stroke reached the log and not the screen, and the
  //          undo button stayed greyed out until something unrelated happened to rebuild the page —
  //          measured on the web target with the app's own log line reading `strokes=0 rebuild=false`
  //          immediately before `ink.stroke.commit`.
  //
  //          The tap path is OPAQUE through the outer listener, so a contact on the white space
  //          between two systems — exactly where a musician may miss — is still reported and clears
  //          the selection.
  // KEYWORDS: page-widget, pointer-listener, dispatch-order, ink-overlay, tap-vs-stroke,
  //           selection-entry, commit-before-select
  Widget _tappablePage(
    PageLayout page,
    Song song,
    InkCaptureLayer layer,
    List<InkStroke> strokes,
    List<TextCue> textCues,
  ) => RawPointerCapture(
    layer: layer,
    page: page,
    child: Listener(
      // Only the live stroke is handled here: the layer above has already been given the sample, and
      // this listener exists so the page repaints while the pen is down. A move the layer did not
      // take — a finger, or a pen with the mode off — rebuilds nothing.
      onPointerMove: (PointerMoveEvent event) => _onPagePointerMove(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails details) => _onPageTapDown(layer, details),
        onTapUp: (TapUpDetails details) => _onPageTapUp(page, layer, details),
        onTapCancel: _onPageTapCancel,
        child: _layeredPage(page, song, layer, strokes, textCues),
      ),
    ),
  );

  // PURPOSE: Repaint the page while a stroke is being drawn, so the musician sees their own line
  //          before they lift the pen.
  // INPUTS: None; the ink layer is asked whether a contact is drawing.
  // OUTPUTS: Nothing. The rebuild happens only while a contact is actually drawing, so a finger tap
  //          and a pen with the mode off do not rebuild on every sample.
  // KEYWORDS: live-preview-repaint, guarded-rebuild
  void _onPagePointerMove() {
    if (_activeInkLayer?.isDrawingInk ?? false) {
      setState(() {});
      _publishInkState();
    }
  }

  // PURPOSE: Stack the chart, the words written on it and the ink, with all three positioned by the
  //          same page transform.
  // INPUTS: page, song, layer, strokes and textCues, as in [_tappablePage].
  // OUTPUTS: The page widget. The cue layer is drawn AFTER the chart, so a remark lies over the
  //          music it annotates, and BEFORE the ink, so the ink stays the topmost layer and the
  //          ordering this file already documents for it (see [_tappablePage] and A37) is left
  //          exactly as it was. Each layer is given the page's own scale, which is what keeps them
  //          in one coordinate system rather than three that agree until the page is fitted.
  // KEYWORDS: painter-stack, cues-over-chart, ink-stays-on-top, shared-scale, one-coordinate-system
  Widget _layeredPage(
    PageLayout page,
    Song song,
    InkCaptureLayer layer,
    List<InkStroke> strokes,
    List<TextCue> textCues,
  ) {
    final List<ResolvedInkStroke> committed = _resolveStrokes(page, strokes);
    final List<ResolvedInkStroke> live = layer.liveStrokes
        .where((ResolvedInkStroke resolved) => _isOnPage(page, resolved))
        .toList();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(
          painter: ChartPainter(
            song: song,
            page: page,
            metrics: _metrics,
            selection: _selection,
          ),
          child: const SizedBox.expand(),
        ),
        CustomPaint(
          painter: TextCuePainter(
            cues: _resolveCues(page, textCues),
            pageScale: page.scale,
          ),
          child: const SizedBox.expand(),
        ),
        CustomPaint(
          painter: InkPainter(
            strokes: <ResolvedInkStroke>[...committed, ...live],
            pageScale: page.scale,
          ),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }

  // PURPOSE: Turn every cue of the document into the triple the cue painter needs, skipping the
  //          ones this page has no row for.
  //
  //          THE ROW IS READ OFF THE LAYOUT, ONCE PER REBUILD. The page was engraved WITH this
  //          document's cues (`layout`/`fitToPage` are handed `session.document.textCues`), so the
  //          engine already measured each cue and decided the box above the bar it hangs on. Looking
  //          the box up here rather than re-deriving a position keeps the row the page gave up and
  //          the plate the reader sees the same value: the address is still an `EventAnchor`, the
  //          cue's own offset is still measured from the anchor's column, and the VERTICAL home is
  //          the reserved row rather than the bar's top edge, which is what stops the words lying on
  //          the chord under them. A cue whose address is on another page, or which was inserted
  //          after the page was engraved, has no row here and is simply not drawn.
  // INPUTS: page — the page being drawn, engraved with this document's cues. cues — every cue of the
  //         document, in render order.
  // OUTPUTS: The cues that have a row on this page, in the document's own order — so two cues on one
  //          bar are drawn in the order they were written, the later one over the earlier one.
  // KEYWORDS: cue-row-lookup, page-filter, render-order, fit-survival, transposition-survival
  List<ResolvedTextCue> _resolveCues(PageLayout page, List<TextCue> cues) {
    final Map<String, PlacedTextCue> placedById = <String, PlacedTextCue>{};
    for (final PlacedBar bar in page.bars) {
      for (final PlacedTextCue placed in bar.textCues) {
        placedById[placed.id] = placed;
      }
    }
    final List<ResolvedTextCue> resolved = <ResolvedTextCue>[];
    for (final TextCue cue in cues) {
      final PlacedTextCue? placed = placedById[cue.id];
      if (placed == null) {
        continue;
      }
      resolved.add(
        ResolvedTextCue(cue: cue, origin: placed.origin, size: placed.size),
      );
    }
    return resolved;
  }

  // PURPOSE: Turn every committed stroke into the pair a painter needs, skipping the ones this page
  //          cannot place.
  //
  //          THE ANCHOR IS RESOLVED HERE, ONCE PER REBUILD, AGAINST THE PAGE ON SCREEN, and that is
  //          the whole reason a stroke stays where the musician put it. The stored coordinates are
  //          measured from the anchor's own corner, so adding the corner's position on THIS page
  //          moves the ink with the music: a transposition re-engraves the bars, the anchor resolves
  //          to the bar's new rectangle, and the stroke's own geometry is untouched. A stroke whose
  //          address is on another page of a paginated document is simply not drawn here.
  // INPUTS: page — the page being drawn. strokes — every stroke of the document, in render order.
  // OUTPUTS: The strokes that resolved, with the anchor's origin, in the document's own order.
  // KEYWORDS: anchor-resolution, page-filter, render-order, transposition-survival, fit-survival
  List<ResolvedInkStroke> _resolveStrokes(
    PageLayout page,
    List<InkStroke> strokes,
  ) {
    final List<ResolvedInkStroke> resolved = <ResolvedInkStroke>[];
    for (final InkStroke stroke in strokes) {
      final InkPlacement? placement = resolveEventAnchor(page, stroke.anchor);
      if (placement == null) {
        continue;
      }
      resolved.add(ResolvedInkStroke(stroke: stroke, origin: placement.origin));
    }
    return resolved;
  }

  // PURPOSE: Report whether a live stroke belongs on the page being drawn.
  // INPUTS: page — the page. resolved — a stroke being drawn, whose anchor is known.
  // OUTPUTS: True when this page holds the anchor's address.
  // KEYWORDS: live-preview-filter, page-identity, anchor-address
  bool _isOnPage(PageLayout page, ResolvedInkStroke resolved) =>
      resolveEventAnchor(page, resolved.stroke.anchor) != null;

  // PURPOSE: Note whether the contact that is about to tap was one the ink rule admitted, so a
  //          stroke does not also select the bar under it.
  // INPUTS: layer — the ink layer, whose last decision is the answer. details — the tap's start.
  // OUTPUTS: Nothing. The layer is asked rather than the event, because the rule that decided is the
  //          layer's and evaluating it a second time here is how the two could come to disagree.
  // KEYWORDS: tap-down, ink-suppresses-selection, single-evaluation
  void _onPageTapDown(InkCaptureLayer layer, TapDownDetails details) {
    _tapWasInk = layer.lastPointWasInk;
  }

  // PURPOSE: Report that a tap was refused by the gesture arena — a drag, or a second pointer — so
  //          the flag set at its start does not leak into the next tap.
  // INPUTS: None.
  // OUTPUTS: Nothing.
  // KEYWORDS: tap-cancel, flag-reset
  void _onPageTapCancel() {
    _tapWasInk = false;
  }

  // PURPOSE: Turn a completed tap into a selection, and do nothing for a contact that was consumed
  //          by the ink layer — either because it drew a stroke or because the eraser is on.
  //
  //          IT RUNS AFTER THE STROKE WAS COMMITTED, and that ordering is what lets it repaint: a
  //          gesture is resolved only once every pointer handler for the lift has run, and the ink
  //          layer's own handler is on a widget ABOVE this recogniser in the hit-test path, so
  //          `endStroke` has already appended the stroke to the document by the time this is called
  //          — and `endErase` has already appended a deletion for the same reason.
  //
  //          WHY THE ERASER MODE SUPPRESSES SELECTION WHATEVER THE RULE DECIDED. With the eraser on,
  //          a touch on the chart is aimed at the ink, not at the music: a stroke has no other
  //          meaning, and a touch that missed the ink must not silently select the bar underneath
  //          it. That is also the honest answer for a contact the palm rule REFUSED — the palm is
  //          neither allowed to erase nor invited to select, so it leaves the chart exactly as it
  //          found it. With the eraser off this branch is unchanged and everything selects as before.
  // INPUTS: page — the page the tap landed on. layer — the ink layer of the song on screen, whose
  //         mode is the only thing that can consume a tap without a stroke being drawn. details —
  //         the tap, whose local position is in the page's surface.
  // OUTPUTS: Nothing. It rebuilds when the contact was consumed, so a new stroke is painted, a
  //          deletion shows, and the undo control becomes live; it selects otherwise, and clears the
  //          selection on a miss.
  // KEYWORDS: tap-up, commit-then-repaint, eraser-suppresses-selection, selection, fit-scale
  void _onPageTapUp(
    PageLayout page,
    InkCaptureLayer layer,
    TapUpDetails details,
  ) {
    final bool drew = _tapWasInk;
    final bool erasing = layer.eraserMode;
    _tapWasInk = false;
    if (drew || erasing) {
      // The contact was the ink layer's: the document may have changed under this frame, so the page
      // and the app bar are both out of date. No selection is made — the bar under a stroke is not
      // what the musician asked for, and under the eraser not even a miss is a selection.
      setState(() {});
      _publishInkState();
      return;
    }
    _select(page, details.localPosition);
  }

  // PURPOSE: Turn a completed tap on a page into a selection, converting the surface point into the
  //          page's own coordinates first, so a fitted page is hit where it is DRAWN rather than
  //          where it was engraved.
  // INPUTS: page — the page the tap landed on. localPosition — the point in the page widget's own
  //         coordinate space, which is the surface the painter scaled into.
  // OUTPUTS: Nothing. Sets [_selection] to the hit, or to null when the tap missed every bar; a miss
  //          clears the selection rather than leaving a stale one, because a highlight that survives
  //          the tap meant to dismiss it is a lie about what is selected. The surface point, the
  //          converted page point and the answer are logged as key-value pairs, so the arithmetic
  //          can be checked against what is on screen.
  // KEYWORDS: tap-handling, coordinate-transform, page-point, hit-test, selection-state, structured-log
  void _select(PageLayout page, Offset localPosition) {
    final LayoutOffset surface = LayoutOffset(
      localPosition.dx,
      localPosition.dy,
    );
    final LayoutOffset pagePoint = page.pagePointOf(surface);
    final ChartHit? hit = hitTestPage(page, pagePoint);
    setState(() => _selection = hit);
    debugPrint(
      'viewer.select page=${page.index} scale=${page.scale} '
      'surface=(${surface.x.toStringAsFixed(1)},${surface.y.toStringAsFixed(1)}) '
      'page_point=(${pagePoint.x.toStringAsFixed(1)},'
      '${pagePoint.y.toStringAsFixed(1)}) '
      'hit=${hit == null ? 'none' : '${hit.sectionId}#${hit.barIndex} '
                'beat=${hit.beat}'}',
    );
  }

  // PURPOSE: Open the chord palette for the selected cell, which is the second tap of the edit
  //          budget D2 sets: the first named the cell, this one opens what can be written in it.
  // INPUTS: context — the build context.
  // OUTPUTS: Nothing. Does nothing when no cell is selected — a bar-level selection names no cell
  //          to write into, and a tap in a bar's padding must not silently pick a beat — or when
  //          nothing is loaded. Otherwise the sheet edits through the session and rebuilds this
  //          screen after each applied chord, so the page shows the change as it is made.
  // KEYWORDS: edit-entry, second-tap, cell-required, session, rebuild-on-apply
  void _editSelection(BuildContext context) {
    final ChartHit? hit = _selection;
    final IRealLibrary? library = _library;
    final EditSession? session = _currentSession;
    if (hit == null || hit.cell == null || library == null || session == null) {
      debugPrint(
        'viewer.edit.skipped hit=${hit ?? 'none'} '
        'cell=${hit?.beat ?? 'none'}',
      );
      return;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final IRealSong entry = library.songs[index];
    final int semitones = _semitonesBySong[entry.index] ?? 0;
    unawaited(
      showChordPalette(
        context,
        session: session,
        sectionId: hit.sectionId,
        barIndex: hit.barIndex,
        beat: hit.beat!,
        shownKey: _displayedSong(entry, semitones).key,
        semitoneShift: semitones,
        // The page is drawn from the session, so a rebuild after each applied chord is the whole of
        // what "show the edit" means here. The selection is deliberately NOT recomputed: the
        // address did not move, and re-running the hit test would need a point the sheet never had.
        onChanged: () => setState(() {}),
      ),
    );
  }

  // PURPOSE: Reverse the last edit through the session's inverse and show the page it produces.
  // INPUTS: session — the session of the song on screen.
  // OUTPUTS: Nothing. Rebuilds the screen when an edit was reversed. The document afterwards is
  //          EQUAL to the document before the reversed edit — the comparison is `DocumentState ==`,
  //          so it covers the song, the strokes, the annotations and the text cues — which is what
  //          the log-and-reducer design buys and what an undo that restored a re-rendered chart
  //          would not.
  // KEYWORDS: undo, inverse-event, exact-restore, rebuild, structured-log
  void _undo(EditSession session) {
    final bool undone = session.undo();
    setState(() {});
    debugPrint(
      'viewer.undo done=$undone seq=${session.seq} '
      'undo_depth=${session.undoDepth} redo_depth=${session.redoDepth} '
      'events=${session.log.length}',
    );
  }

  // PURPOSE: Put back the edit the musician just reversed.
  // INPUTS: session — the session of the song on screen.
  // OUTPUTS: Nothing. Rebuilds the screen when an edit was redone.
  // KEYWORDS: redo, re-apply, rebuild, structured-log
  void _redo(EditSession session) {
    final bool redone = session.redo();
    setState(() {});
    debugPrint(
      'viewer.redo done=$redone seq=${session.seq} '
      'undo_depth=${session.undoDepth} redo_depth=${session.redoDepth} '
      'events=${session.log.length}',
    );
  }

  // PURPOSE: Open the bars-and-sections sheet for the bar the musician selected, which is the entry
  //          to every operation that changes the FORM of the tune rather than the chords in it.
  // INPUTS: context — where to open the sheet. session — the session of the song on screen, reached
  //         from the app bar, which has no song entry of its own.
  // OUTPUTS: Nothing. Does nothing when no bar is selected, or when the selection's address no
  //          longer names a bar — which a form edit made earlier in the same sheet can produce.
  //          Otherwise the sheet edits through the session and the screen rebuilds after every
  //          applied operation.
  //
  //          WHY THE SELECTION IS DROPPED AND NOT MOVED. The selection is a hit-test result against
  //          the layout on screen, and a form edit moves the very address that produced it: an
  //          inserted bar shifts every later index by one, so the hit would go on naming its old
  //          index and the painter would highlight the bar next door — a highlight that was right
  //          when it was taken and is wrong now. The sheet keeps its own cursor and prints on its
  //          own header which bar the next operation acts on, so the address is not lost; only the
  //          highlight, which is a photograph of an older layout, is.
  // KEYWORDS: form-entry, bars, sections, selection-drop, rebuild-on-apply, structured-log
  void _openSongForm(BuildContext context, EditSession session) {
    final ChartHit? hit = _selection;
    if (hit == null) {
      debugPrint('viewer.form.open.skipped reason=no-selection');
      return;
    }
    if (session.song.barAt(hit.sectionId, hit.barIndex) == null) {
      debugPrint(
        'viewer.form.open.skipped reason=stale-address '
        'section=${hit.sectionId} bar=${hit.barIndex}',
      );
      return;
    }
    final int? beat = hit.beat;
    debugPrint(
      'viewer.form.open section=${hit.sectionId} bar=${hit.barIndex} '
      'beat=$beat',
    );
    unawaited(
      showSongForm(
        context,
        session: session,
        sectionId: hit.sectionId,
        barIndex: hit.barIndex,
        onChanged: () => setState(() => _selection = null),
      ),
    );
  }

  // PURPOSE: Open the words sheet for the bar the musician selected, which is where a remark a band
  //          reads — `To Coda`, `D.C. al Fine`, `Solo`, `Vamp`, `4×` — is written, changed, moved
  //          and removed, all through the operation log.
  // INPUTS: context — where to open the sheet. session — the session of the song on screen, reached
  //         from the app bar, which has no song entry of its own.
  // OUTPUTS: Nothing. Does nothing when no bar is selected, or when the selection's address no
  //          longer names a bar — which a form edit made in the other sheet can produce. The
  //          selected CELL decides where a new cue is anchored: a touch that named a cell gives a
  //          cue about that beat, and a touch in a bar's padding gives one about the whole bar.
  //          The page rebuilds after every applied edit but the SELECTION IS KEPT, unlike a form
  //          edit: a cue changes neither the address the selection names nor the geometry that
  //          produced it, so the highlight is still true and dropping it would make the musician
  //          re-aim at a bar that never moved.
  // KEYWORDS: text-cue-entry, app-bar, address-from-selection, cell-or-bar, rebuild-on-apply,
  //           selection-kept, structured-log
  void _openTextCueSheet(BuildContext context, EditSession session) {
    final ChartHit? hit = _selection;
    if (hit == null) {
      debugPrint('viewer.textcue.open.skipped reason=no-selection');
      return;
    }
    if (session.song.barAt(hit.sectionId, hit.barIndex) == null) {
      debugPrint(
        'viewer.textcue.open.skipped reason=stale-address '
        'section=${hit.sectionId} bar=${hit.barIndex}',
      );
      return;
    }
    final int? beat = hit.beat;
    debugPrint(
      'viewer.textcue.open section=${hit.sectionId} bar=${hit.barIndex} '
      'beat=${beat ?? 'bar'} cues=${session.document.textCues.length}',
    );
    unawaited(
      showTextCueSheet(
        context,
        session: session,
        sectionId: hit.sectionId,
        barIndex: hit.barIndex,
        beat: beat,
        onChanged: () => setState(() {}),
      ),
    );
  }

  // PURPOSE: Open the song-info sheet, which is where the song's own four facts — title, composer,
  //          style and tempo — are edited.
  // INPUTS: context — where to open the sheet. session — the session of the song on screen. focus —
  //         the field the reader pressed, so the sheet opens with the cursor already in it.
  // OUTPUTS: Nothing. The sheet applies through `EditSession.updateSong`, and the screen rebuilds
  //          after an applied edit so the pane header, the scene bar and the song list all show the
  //          new values. The selection is deliberately NOT cleared, unlike a form edit: a title, a
  //          composer, a style and a tempo move no bar and no section, so the address the selection
  //          names still names the same music and the highlight is still true.
  // KEYWORDS: song-info, metadata, entry-point, scene-bar, title, rebuild-on-apply, structured-log
  void _openSongInfo(
    BuildContext context,
    EditSession session,
    SongMetadataField focus,
  ) {
    debugPrint(
      'viewer.song.info.open focus=${focus.name} '
      'title_chars=${session.song.title.length} tempo=${session.song.tempo}',
    );
    unawaited(
      showSongInfo(
        context,
        session: session,
        focus: focus,
        onChanged: () => setState(() {}),
      ),
    );
  }

  // PURPOSE: State the selection in words beside the chart, because a highlight proves that
  //          SOMETHING is selected and not which thing: a screenshot cannot falsify "the bar I
  //          touched", and a labelled number can. The line is also the control that reaches the
  //          edit which fits the selection: the chord palette for a cell, the bars-and-sections
  //          sheet for a bar.
  // INPUTS: context — the build context, for the text theme. song — the chart on screen, read to
  //         number the bar the way a musician counts it.
  // OUTPUTS: A one-line widget. With a selection it reads `selected: bar 12 cell 2`; without one it
  //          invites a tap. A bar-level selection says so instead of inventing a cell number, and it
  //          leads to the FORM sheet rather than to the chord palette, because a bar and its
  //          section are what the form operations act on and a bar-level selection names both.
  //          The hint beside the label states the affordance in words, since a label that changes
  //          what it is when touched is not discoverable on its own.
  // KEYWORDS: selection-label, edit-entry, falsifiable-feedback, musician-numbering, empty-state
  Widget _buildSelectionLine(BuildContext context, Song song) {
    final ChartHit? hit = _selection;
    final EditSession? session = _currentSession;
    final bool editable = hit != null && hit.cell != null;
    // A bar-level selection names no cell to write a chord into, but it names exactly what the form
    // sheet acts on — a section and a bar — so the line is a control in both cases instead of being
    // dead text whenever the touch landed on a bar's padding rather than on one of its cells.
    final VoidCallback? onTap = hit == null
        ? null
        : (editable
              ? () => _editSelection(context)
              : (session == null
                    ? null
                    : () => _openSongForm(context, session)));
    final String hint = editable
        ? '— tap to change the chord'
        : '— tap for bars & sections';
    final String text = hit == null
        ? 'Tap a bar to select it.'
        : _selectionLabel(song, hit);
    final TextStyle? style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: hit == null ? FontWeight.normal : FontWeight.bold,
    );
    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // FLEXIBLE, so a narrow pane truncates the line instead of overflowing it. The row is
        // unbounded in width — it sits in an Align — and the position it states grows with the bar
        // number and the hint beside it, so on a phone-width pane the two together are wider than
        // the chart: measured at 415 logical pixels of available width against 591 wanted. A label
        // that overflows is not a cosmetic problem in a widget test, it is a red-and-black bar over
        // the chart in the application.
        Flexible(
          child: Text(
            text,
            key: const ValueKey<String>('viewer-selection-label'),
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onTap != null) ...<Widget>[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              hint,
              key: const ValueKey<String>('viewer-selection-edit-hint'),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: onTap == null
            ? label
            : InkWell(
                key: const ValueKey<String>('viewer-selection-edit'),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: label,
                ),
              ),
      ),
    );
  }

  // PURPOSE: Render a selection the way the musician counts — bars from the top of the chart and
  //          cells from the start of the bar, both one-based — while the model keeps zero-based
  //          indices. The conversion lives here so the label and the log cannot disagree silently.
  // INPUTS: song — the chart. hit — the selection, holding the model's zero-based address.
  // OUTPUTS: The label. A null cell means the touch landed on the bar and not on a cell, which is
  //          stated rather than rounded to the nearest cell.
  // KEYWORDS: label-format, one-based, global-bar-ordinal, model-address
  String _selectionLabel(Song song, ChartHit hit) {
    final int bar = _writtenBarOrdinal(song, hit.sectionId, hit.barIndex);
    final int? beat = hit.beat;
    return beat == null
        ? 'selected: bar $bar (whole bar)'
        : 'selected: bar $bar cell ${beat + 1}';
  }

  // PURPOSE: Number a bar the way a musician counts, across sections from the top, because the model
  //          addresses a bar by its index inside its section and that number restarts at every
  //          section.
  // INPUTS: song — the chart. sectionId — the section the bar is in. barIndex — its index there.
  // OUTPUTS: The one-based ordinal of the bar in the whole written chart. A section id the song does
  //          not have — a layout and a model that disagree — still returns a finite number counted
  //          from the end rather than throwing inside build.
  // KEYWORDS: bar-ordinal, section-walk, total-function, defensive
  int _writtenBarOrdinal(Song song, String sectionId, int barIndex) {
    int ordinal = 0;
    for (final Section section in song.sections) {
      if (section.id == sectionId) {
        return ordinal + barIndex + 1;
      }
      ordinal += section.bars.length;
    }
    return ordinal + barIndex + 1;
  }

  // PURPOSE: Lay the displayed song out at the size the window gives it and show it as one fitted
  //          page or as a page at a time.
  // INPUTS: entry — the selected song, for identity. displayed — the chart to draw, in its chosen
  //         key. mode — FIT or PAGES. layer — the ink layer of the song on screen, which decides
  //         what a contact on a page means. strokes — the committed strokes of the WRITTEN document,
  //         which are placed by address and so are unaffected by the transposition on screen.
  //         textCues — the cues of the same document, placed by address for the same reason.
  // OUTPUTS: The chart. PAGES is the layout engine's ordinary pagination in a [PageView]. FIT is
  //          one scaled page, or a message saying the song would have to be shrunk below the
  //          legible floor, which is reported on screen rather than delivered as an unreadable
  //          page. A song the layout engine produces no pages for says so instead of showing an
  //          empty page, because an empty song and a blank page must not look alike.
  // KEYWORDS: pagination, fit, page-scale, layout-call, page-view, empty-song, legibility-message,
  //           ink-layering, cue-layering
  Widget _buildPages(
    IRealSong entry,
    Song displayed,
    PageMode mode,
    InkCaptureLayer layer,
    List<InkStroke> strokes,
    List<TextCue> textCues,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double pageWidth = constraints.maxWidth;
        final double pageHeight = constraints.maxHeight;
        _lastPageSurface = Size(pageWidth, pageHeight);
        _lastPageMode = mode;
        if (!pageWidth.isFinite ||
            !pageHeight.isFinite ||
            pageWidth <= 0 ||
            pageHeight <= 0 ||
            displayed.writtenBarCount == 0) {
          return const Center(child: Text('This song has no bars.'));
        }
        if (mode == PageMode.fit) {
          final FitOutcome outcome = _engine.fitToPage(
            displayed,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            cues: textCues,
          );
          final PageLayout? page = outcome.page;
          if (page == null) {
            return _buildNoFit(context, outcome);
          }
          _lastPageScale = page.scale;
          return _tappablePage(page, displayed, layer, strokes, textCues);
        }
        final List<PageLayout> pages = _engine.layout(
          displayed,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          cues: textCues,
        );
        if (pages.isEmpty) {
          return const Center(child: Text('This song has no bars.'));
        }
        _lastPageScale = pages.first.scale;
        return PageView.builder(
          key: ValueKey<int>(entry.index),
          itemCount: pages.length,
          itemBuilder: (BuildContext context, int index) =>
              _tappablePage(pages[index], displayed, layer, strokes, textCues),
        );
      },
    );
  }

  // PURPOSE: Say on screen that a song will not fit one page at a legible size, instead of drawing
  //          a page nobody can read.
  // INPUTS: context — the build context. outcome — the failed fit, carrying the scale floor the
  //         engine tried.
  // OUTPUTS: A centred message naming the floor and pointing at PAGES.
  // KEYWORDS: fit, legibility-floor, on-screen-message, honest-failure
  Widget _buildNoFit(BuildContext context, FitOutcome outcome) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'This song does not fit on one page legibly.\n'
        'It would need to be smaller than '
        '${(outcome.scale * 100).round()}% of the page, so it is not '
        'shrunk to nothing.\n'
        'Use PAGES to read it page by page.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );

  // PURPOSE: State what is loaded, so the reader can tell a 22-song playlist from a single song
  //          without counting the list.
  // INPUTS: context — the build context.
  // OUTPUTS: A one-line status bar.
  // KEYWORDS: status-bar, summary, playlist-name
  Widget _buildStatusBar(BuildContext context) {
    final IRealLibrary? library = _library;
    final String summary = library == null
        ? 'No file loaded.'
        : '${library.songs.length} song(s)'
              '${library.isPlaylist ? ' · playlist "${library.playlistName}"' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(summary, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
