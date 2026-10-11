// PURPOSE: Show the songs an iReal export contains, render the selected one as a chart a musician
//          can read — in the key they choose, with the whole tune on one page or paginated, and
//          with the performance facts on one bar — and let them CHANGE a chord in it or WRITE ON it
//          with a pen.
//          It is a reader and an editor: it shows the layout the engine produced, the issue list the
//          import reported, the chord palette for the cell they selected, and the handwriting layer
//          an ink mode turns on.
// INPUTS: A reference the reader supplies, an [IRealLibraryLoader] that turns that reference into
//         an [IRealLibrary], a starting reference, whether a reference is a filesystem path at all,
//         how the platform's own file chooser is asked for one, and whether to load the starting
//         reference on the first frame. The loader is injected so a widget test can pump this screen
//         with a synthetic payload and never touch the filesystem, and so the web build can hand it
//         a browser file chooser instead of a path.
// OUTPUTS: A screen with a source bar, a chart save/open bar, an ink switch, an eraser switch, undo
//          and redo, a
//          bars-and-sections switch, a song list, a scene bar and the selected song's page or pages,
//          each drawn by `ChartPainter` at
//          the size the window gives it and covered by an `InkPainter` carrying the document's
//          strokes and a `TextCuePainter` carrying the words written on the chart. A FIT that cannot
//          reach the legible floor still shows the chart — as pages, with a strip saying why — which
//          is the one case the mode request and the mode drawn disagree about (see below). A tap on
//          a page selects the bar and cell under it, the painter highlights them,
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
//          THE SHELL HAS TWO FORMS. On a surface at least [sceneBarTabletWidth] logical pixels wide
//          it is the tablet form: the tools and the document actions stand in the app bar and the
//          song list is a permanent column (the left rail) beside the chart. On a narrower surface
//          it is the phone form (owner decision D11's "phone = bottom dock"): the song list is a
//          drawer, the four tools a musician touches while playing stand in a bottom dock, and the
//          document actions move into one app-bar overflow menu so that the title is not truncated
//          by eight controls. See [_buildScreen], [_buildBody] and [_buildPhoneDock].
// KEYWORDS: viewer, ireal, reader, editor, screen, page-view, transposition, scene-bar, page-modes,
//           chord-palette, ink-mode, eraser-mode, ink-layer, op-log, undo, redo, chart-file, save,
//           open, song-form, bars, sections, text-cue, words, widget-test-seam, platform-seam,
//           verification, phone-shell, bottom-dock, song-drawer, app-bar-overflow, d11
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
// WHAT CHANGES PER PLATFORM, AND WHAT DOES NOT. Everything below the source bar is identical
// everywhere, because nothing below it touches a file: the loader is the seam and it is the same seam
// the widget tests use. Only the source bar differs, and it differs in one of two forms rather than
// in one form per platform: a desktop gets the path field, the Load button and the chooser button,
// and a hand-held and a browser each get the chooser alone, because a text field for a path that
// addresses nothing would invite a musician to type their way to a file that cannot be reached. A
// screen that cannot name a file must not pretend to. Which form a build gets is decided by
// [IRealViewerScreen.sourceIsFilePath], and the wording of what the screen says — not just which
// control it draws — follows the same fact.
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
// WHAT IS THE SAME ON A PHONE AND WHAT IS NOT, AND WHY THE LINE IS WHERE IT IS.
//
// Owner decision D11 gives the palettes two landings: a tablet gets a top ribbon and a left rail, a
// phone gets a bottom dock. The defect D11 was meant to prevent had been sitting in this file since
// the list was written: the song list is a FIXED 260-pixel column at every width, so at 412 logical
// pixels of window the chart was left about 150 and the scene bar — a `Wrap` — laid its fields out
// in a column down the side of the screen. A musician could see one or two chords per system.
//
// The fix is the SHELL and not the page: nothing in `chart_core/lib/src/layout` changes, no sheet
// changes, and the chart is not scaled down. Below [sceneBarTabletWidth] the window gives the chart
// the whole width, the song list moves into a drawer, and the tools move to the bottom. At or above
// it, every one of those choices is the one this file already made, which is what keeps the owner's
// own tablet unchanged — the rail, the app bar and the scene bar there are byte for byte the widgets
// they were, because the branch is not taken.
//
// WHY A DRAWER AND NOT A FULL-WIDTH LIST YOU RETURN FROM. Changing song on a phone costs two
// gestures either way — one to open, one to pick — and the drawer has three things the swap-screen
// list does not: the chart is never unmounted, so the page, its scroll position and the selection
// are still there when the list closes; the list slides over the chart instead of replacing it, so
// the musician keeps their bearings; and it is the platform's own idiom, which means a left-edge
// swipe opens it without a control being found first. Two details make "not losing your place" true
// rather than hopeful: the selected song is the selected row when the drawer reopens, and the list
// keeps its own [ScrollController], so a musician twenty songs down a playlist comes back to the
// same twenty.
//
// WHAT FIT DOES WHEN IT CANNOT FIT, AND WHY AN EMPTY PAGE IS NOT AN ANSWER. The page mode is chosen
// from the pane WIDTH, and FIT's verdict also depends on the pane's HEIGHT — so a window that is wide
// enough to be engraved as a tablet but too short to hold the tune above [LayoutEngine.minLegibleScale]
// asks for a fitted page that does not exist. Reporting that on screen and drawing nothing is a
// musician opening a chart and being shown a sentence where the music should be, which is a refusal
// however honest its wording. FIT therefore FALLS BACK TO PAGES: the paginated chart is drawn, and a
// strip pinned over the top of it says why, naming the floor. The fallback is automatic (a press
// between the musician and the music is the same refusal in slower form) and an explicit FIT press is
// answered in the second person rather than silently ignored. The reasoning, the rejected alternative
// and the measurements are recorded in `docs/sdd.md` A50; the mechanism is [_buildPages],
// [_fitFallbackNotice] and the mode drawn being the one `_pageGeometry` reports.
//
// AND THE FALLBACK ONLY EARNS ITS KEEP IF THERE IS ROOM TO SEE IT. The same measurement at 915x412
// found the chart pane 65 logical pixels tall, because the scene bar's full form wrapped to two rows
// on a screen only 412 high; one system needs 98, so the pages FIT fell back to were themselves
// clipped to their barlines. The bar therefore takes its compact form on a SHORT window as well as a
// narrow one — [_isBarCompact], and `sceneBarTabletHeight` in `scene_bar.dart` — which returns about
// 85 pixels to the chart. A form decided on the window's HEIGHT does not contradict the width rule:
// the fields are not what cannot fit on a short surface, the chart is.
//
// WHY THE TOOLS GO TO THE BOTTOM RATHER THAN INTO THE MENU. D11 says a phone gets a bottom dock, and
// the four controls that answer that description are the ones a hand reaches for while reading:
// the pen, the eraser, undo and redo. They are the ones whose STATE is visible from the bar, and a
// menu cannot show state — an overflow row reading "Undo" is the same row whether there is anything
// to undo or not. The four document actions (bars and sections, words, the programme, the chart
// file) open a surface and change nothing on their own, so they live in the overflow menu, which is
// also what returns the title to the app bar: eight actions in a 412-pixel bar left a title reading
// "Cha…". The dock is drawn from the SAME widget list as the app bar's actions, so the two forms
// cannot drift apart.
//
// WHICH TRANSPOSITION THIS IS. Owner decision D14 gives transposition two meanings, and this screen
// implements BOTH. The EDITOR meaning is the one the key grid edits on the chart itself: the chart
// is shown in another key, its key badge changes, every chord is re-spelled, and a per-song interval
// remembers how far the shown chart has been moved. The SCENE meaning is an offset on one setlist
// position: the screen has a programme (`SetlistSession`, seeded from the imported playlist by
// `setlist_import.dart`), an entry's `transposeSem` is applied through `setlistSceneFor` while the
// chart's own document keeps its written key, and the key badge edits THAT entry's interval when the
// chart is reached from the programme. Which of the two is in force is decided by `_playingItemFor`:
// an entry that names the chart on screen makes the scene offset the one that is shown, and the
// editor interval remembered for that song is not applied at the same time.

import 'dart:async';
import 'dart:convert';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this screen
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'chart_document.dart';
import 'chart_file_bar.dart';
import 'chord_palette_sheet.dart';
import 'document_file_name.dart';
import 'ink_capture_surface.dart';
import 'ink_layer.dart';
import 'ink_pointer_probe.dart';
import 'ink_pointer_probe_contract.dart';
import 'ireal_library.dart';
import 'ireal_source.dart';
import 'key_grid.dart';
import 'l10n/app_localizations.dart';
import 'new_chart_dialog.dart';
import 'note_palette_sheet.dart';
import 'scene_bar.dart';
import 'setlist_import.dart';
import 'setlist_resolution.dart';
import 'setlist_sheet.dart';
import 'settings_contract.dart';
import 'settings_sheet.dart';
import 'sheet_surface.dart';
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
  /// [sourceIsFilePath] and [autoLoad] are left at their defaults on every target, so a build gets
  /// the affordance its platform can honour without the caller passing anything.
  const IRealViewerScreen({
    super.key,
    this.loader = loadIRealLibrary,
    this.initialPath = defaultIRealPath,
    this.autoLoad = true,
    this.sourceIsFilePath,
    this.chooseReference = chooseIRealReference,
    this.language = LanguageChoice.system,
    this.onLanguageChanged,
  });

  /// How a reference becomes a library.
  final IRealLibraryLoader loader;

  /// The reference the source bar starts with.
  ///
  /// A path where one exists, and the empty string everywhere else, where there is no reference to
  /// type and the bar shows the platform's chooser instead.
  final String initialPath;

  /// Whether to load [initialPath] once, after the first frame.
  ///
  /// True by default, and it does nothing unless a caller supplied a reference: the reference a
  /// platform has to be handed is one only a test or a desktop session can supply, and loading an
  /// empty one used to raise a `FileSystemException` naming `path = ""` — the red banner an empty
  /// default produced on a tablet. False in a browser and on a hand-held, where the source is a file
  /// chooser and a browser additionally refuses to open one outside a user gesture; a test that
  /// wants to decide exactly when the loader runs passes false and presses the button itself.
  final bool autoLoad;

  /// Whether [initialPath] is a filesystem path the reader may type.
  ///
  /// NULL MEANS "ASK THE PLATFORM", which is what every production build does; the field exists so
  /// that a test can force either form of the bar. Read through [_IRealViewerScreenState.sourceIsFilePath],
  /// never directly, because the two controls below have to agree about it.
  final bool? sourceIsFilePath;

  /// How a reference is obtained from the platform's own file chooser, where that is a useful
  /// thing to offer.
  ///
  /// Defaults to the platform's implementation. It answers with the path the reader chose, or null
  /// when they dismissed the dialog or when the platform has no path to hand back — on a hand-held
  /// the chooser is reached through [loader] instead, because the chosen file cannot leave it as a
  /// reference. See `chooseIRealReference`.
  final Future<String?> Function() chooseReference;

  /// The language choice in force, so the settings sheet can show which row is ticked.
  ///
  /// PASSED IN RATHER THAN READ FROM THE STORE, because this widget does not own the choice: it is
  /// decided above the [MaterialApp], which is the only place a locale can be changed for the whole
  /// tree. What this widget owns is the control that reports a new choice back up.
  final LanguageChoice language;

  /// Called with the language the musician picked in the settings sheet, or null when nothing is
  /// listening.
  ///
  /// NULL IS THE NORMAL CASE IN A WIDGET TEST, where the screen is pumped inside a bare
  /// [MaterialApp] with no application root above it. The sheet still opens and still shows the
  /// language it was given; the tap simply has nowhere to go, which is what "no owner" means.
  final ValueChanged<LanguageChoice>? onLanguageChanged;

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

  /// The width of the song list when it stands as a permanent column.
  ///
  /// One number, read in one place, because the chart's width on a tablet is the window minus this:
  /// a second literal somewhere else would silently change what the page is engraved for. It is
  /// deliberately NOT read on a phone, where the list is a drawer and the chart gets the whole
  /// window.
  static const double _songRailWidth = 260;

  late final TextEditingController _pathController;

  /// Whether this platform offers a path field, read once so the bar's two controls cannot disagree.
  ///
  /// The injected [IRealViewerScreen.sourceIsFilePath] wins when a caller supplied one, which is what
  /// lets a test force either form of the bar; every production build passes nothing and gets the
  /// platform's own answer from `ireal_source.dart`, which is the answer to "may the reader type a
  /// path and have it work?" — true on a desktop, false on Android, iOS and the web.
  bool get sourceIsFilePath => widget.sourceIsFilePath ?? iRealSourceIsFilePath;

  /// The scroll position of the song list, kept across the drawer being closed and reopened.
  ///
  /// This is the "does not lose their place" half of the phone shell: a musician twenty songs down a
  /// playlist who opens the drawer, reads, and closes it without picking comes back to the same
  /// twenty rather than to the top. It is a field rather than a local because the list is rebuilt
  /// when the drawer opens, and a scroll position that lives in the widget dies with it.
  final ScrollController _songListScroll = ScrollController();

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

  /// The programme being played, or null before a library is loaded.
  ///
  /// It is a session rather than a [Setlist] because the programme is an op-log document in its own
  /// right: the sheet edits it through its events and undoes them with its own history, exactly as
  /// the chart's [EditSession] does for a chart. It is built from the loaded library by
  /// `importedSetlist`, so the owner's playlist arrives as a setlist rather than as a list of names,
  /// and it is replaced — not edited across — when a different library is loaded, because its
  /// entries name the loaded songs by id.
  SetlistSession? _setlist;

  /// The programme entry currently being played, or null while the chart is read on its own.
  ///
  /// This is what makes the scene meaning of D14 apply: while an entry names the chart on screen, the
  /// interval shown is that entry's `transposeSem` and the scene bar reports the programme's
  /// position. Selecting another song from the list leaves the programme, which is why a manual
  /// selection clears it.
  int? _sceneIndex;

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
    // ONLY WHEN THERE IS A PATH TO LOAD. `autoLoad` says this platform opens a file by path, which is
    // true on Android and false in a browser; it does NOT say that a path was supplied. Loading an
    // empty one raises a FileSystemException naming `path = ""`, so the application could open on a red
    // error banner about a file nobody named — which is exactly what an empty default produced on a
    // tablet. The default is empty now, and this is the other half of that fix: a platform that loads
    // by path still has to be HANDED one.
    if (widget.autoLoad && widget.initialPath.isNotEmpty) {
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
    _songListScroll.dispose();
    // Cleared rather than left dangling: a reader that outlived the screen would answer an
    // inspecting tool with the last state this screen ever held, which reads as a live chart.
    inkStateReader = noInkStatePublished;
    strokeCountReader = noStrokesPublished;
    inkInputCountersReader = noInkStatePublished;
    pageGeometryReader = noInkStatePublished;
    super.dispose();
  }

  // PURPOSE: Decide whether the surface is a phone, which is the device's own fact and not the
  //          chart's.
  // INPUTS: windowWidth — the width of the whole window in logical pixels, read from the
  //         [MediaQuery] by [_buildScreen], [_buildBody] and the drawer.
  // OUTPUTS: True below [sceneBarTabletWidth], the one threshold this application uses to separate
  //          a tablet from a phone. It is the same number the page-mode default uses, and it is
  //          deliberately NOT the pane width: the pane's width is an answer about how to engrave the
  //          music, while this is an answer about where a hand goes and how much screen a rail may
  //          take. A surface is one or the other, never both.
  // KEYWORDS: shell-form, phone-vs-tablet, threshold, window-width, d11
  bool _isPhoneWidth(double windowWidth) => windowWidth < sceneBarTabletWidth;

  // PURPOSE: Decide whether the scene bar must take its COMPACT form, which is a question about the
  //          window on TWO axes rather than one.
  // INPUTS: window — the whole window's logical size, read from the [MediaQuery] by [_buildSongPane].
  // OUTPUTS: True when the window is narrower than [sceneBarTabletWidth] OR shorter than
  //          [sceneBarTabletHeight], false when it has room on both axes. The bar therefore keeps its
  //          full form on every surface the owner uses — 1200x900, 1400x900 and 824x1318 all clear
  //          both thresholds — and takes the compact form on a phone in portrait and, newly, on a
  //          phone in LANDSCAPE, where the full bar's two rows left the chart pane 65 logical pixels.
  //          One system needs `pageMargin + sectionLabelHeight + barHeight` = 98, so at 65 neither
  //          FIT nor its paginated fallback could put a chord on screen; the compact form returns the
  //          ~85 pixels that make the fallback worth having. WHY THIS IS NOT THE SHELL'S DECISION:
  //          the shell's form stays width-only, because "where does a hand go" is a question about
  //          width and a short window is a surface without room rather than a different device. See
  //          A49 for the measurement and A50 for the fallback this room serves.
  // KEYWORDS: scene-bar-form, compact, two-axes, window-height, chart-room, a49, a50
  bool _isBarCompact(Size window) =>
      window.width < sceneBarTabletWidth ||
      window.height < sceneBarTabletHeight;

  // PURPOSE: Report the song list's scroll position when the drawer opens or closes, so "the list
  //          does not lose its place" is something that was read rather than something asserted.
  // INPUTS: open — whether the drawer is now open.
  // OUTPUTS: Nothing. Prints one line AFTER the frame the drawer's animation produced, because the
  //          list is built as the drawer moves in: read inside this callback the position is
  //          always `detached` on the opening edge, which is a true statement about the frame and a
  //          useless one about the list. After the frame the number is the position the musician
  //          will actually see, so an open line and the close line before it can be compared.
  // KEYWORDS: drawer, scroll-position, evidence, structured-log, place-keeping
  void _onDrawerChanged(bool open) {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      debugPrint(
        'viewer.song.drawer ${open ? 'open' : 'closed'} '
        'songs=${_library?.songs.length ?? 0} selected=$_selectedSong '
        'scroll=${_songListScroll.hasClients ? _songListScroll.offset.toStringAsFixed(1) : 'detached'}',
      );
    });
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
      // --- THE PROGRAMME (the setlist being played) -------------------------------------------
      // Reported beside the ink for the same reason: a headless driver cannot reach the session, and
      // "the chart is shown two semitones up while its document still says the written key" is a
      // claim only the two values together can settle. Null before a library is loaded.
      'programme': _setlistState(),
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
    final Song displayed = _shownSong(library.songs[index]);
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

  // PURPOSE: Replace the shown library with the one the current reference holds, or record why it
  //          could not be read.
  // INPUTS: None; the reference comes from [_pathController], and is empty on every platform that
  //         reaches its file through the chooser rather than through a typed path.
  // OUTPUTS: Nothing. Sets [_loading] around the read and either [_library] or [_error] afterwards.
  //          A result that arrives after the screen is gone is dropped rather than calling setState
  //          on an unmounted state. A successful load clears every remembered transposition. A
  //          chooser the reader dismissed is NOT an error and leaves the screen as it was: the
  //          banner is for a failure, and changing one's mind is not one.
  // KEYWORDS: load, error-handling, cancellation, unmounted-guard, structured-log
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
        // The imported playlist BECOMES the programme: an iReal export is a list of songs under a
        // playlist name, which is exactly what a setlist is. Seeding it here rather than on first
        // use means the scene path always has a programme to resolve against, and replacing any old
        // one wholesale is what keeps entries from naming charts the new library does not hold —
        // they are keyed by the id the import gave each song.
        _setlist = SetlistSession(setlist: importedSetlist(library));
        _sceneIndex = null;
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
        'playlist_chars=${library.playlistName.length} '
        'setlist_entries=${_setlist?.items.length ?? 0}',
      );
    } on IRealFileCancelledException catch (error) {
      if (!mounted) {
        return;
      }
      // A dismissed chooser is the reader's own action, so the screen returns to exactly what it was
      // showing and no banner appears. The exception's message is the platform's description of what
      // it saw and goes to the log; the interface words its own outcomes from the catalogue.
      setState(() {
        _loading = false;
      });
      debugPrint('viewer.load.cancelled reason="${error.message}"');
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        // The catalogue was carrying `issuesTitle` and `issueLine` and this dialog printed the words
        // itself in English, so a Russian reader opening the issue list read English above a Russian
        // shell. The title goes through `_titleFor` for the same reason every other name does: an
        // empty title is the interface's `Без названия` and not the payload's blank.
        title: Text(l10n.issuesTitle(_titleFor(entry, l10n))),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final IRealParseIssue issue in entry.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l10n.issueLine(issue.offset, issue.message)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
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
        'viewer.transpose.cancelled song="${_rawTitleFor(entry)}" '
        'picked=${picked == null ? 'none' : picked.key}',
      );
      return;
    }
    setState(() => _semitonesBySong[entry.index] = picked.semitones);
    debugPrint(
      'viewer.transpose.ok song="${_rawTitleFor(entry)}" written=${entry.song.key} '
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

  // PURPOSE: Find the loaded chart one programme entry names, which is the ONE place the join
  //          between a programme and a library is decided — so the play action, the scene meaning,
  //          the row's title and the missing-chart report cannot disagree about which chart an
  //          entry is.
  // INPUTS: item — the entry, whose `chartIdentity` is the durable name and whose `documentId` is
  //         the id the chart's own log is keyed by.
  // OUTPUTS: The loaded song the entry names, or null when this library holds none. The RULE is
  //          `resolveSetlistItem` in `setlist_resolution.dart`: identity first and authoritative
  //          when the entry carries one, document id only for an entry that carries none. It lives
  //          outside this widget so a `dart run` probe can exercise the same code; what this method
  //          adds is the "no library loaded yet" guard.
  // KEYWORDS: resolution, chart-identity, document-id-fallback, missing-chart, single-join
  IRealSong? _songForItem(SetlistItem item) {
    final IRealLibrary? library = _library;
    return library == null ? null : resolveSetlistItem(library, item);
  }

  // PURPOSE: Return the programme entry being played for one song, or null when the song is being
  //          read on its own. This is the one place that decides whether the SCENE meaning of D14 is
  //          in force, so the display, the song list and the scene bar cannot disagree about it.
  // INPUTS: entry — the loaded song whose pane is being drawn.
  // OUTPUTS: The entry at [_sceneIndex] when it names [entry]'s chart, resolved through
  //          [_songForItem]; null otherwise. The resolution and not a raw id comparison, because a
  //          library replacement renumbers document ids and only the identity survives it.
  // KEYWORDS: scene-entry, document-identity-match, single-decision, d14
  SetlistItem? _playingItemFor(IRealSong entry) {
    final SetlistSession? setlist = _setlist;
    final int? index = _sceneIndex;
    if (setlist == null || index == null) {
      return null;
    }
    final SetlistItem? item = setlist.itemAt(index);
    if (item == null) {
      return null;
    }
    return _songForItem(item)?.index == entry.index ? item : null;
  }

  // PURPOSE: Report how far the chart on screen is shown from its written key, taking the scene
  //          interval of the programme entry when the song was reached from the programme and the
  //          editor interval remembered for the song otherwise.
  // INPUTS: entry — the loaded song.
  // OUTPUTS: The signed interval in semitones. In the programme it is the entry's stored interval
  //          exactly, so a `+2` entry shows a chart two semitones up; otherwise it is the interval
  //          the key grid stored for that song, or zero.
  // KEYWORDS: shown-interval, scene-vs-editor, d14, single-source
  int _shownSemitones(IRealSong entry) {
    final SetlistItem? playing = _playingItemFor(entry);
    if (playing != null) {
      return playing.transposeSem;
    }
    return _semitonesBySong[entry.index] ?? 0;
  }

  // PURPOSE: Produce the chart to draw for one song, in whichever meaning of D14 is in force.
  // INPUTS: entry — the loaded song.
  // OUTPUTS: The displayed song. When the song is being played from the programme it is
  //          `setlistSceneFor`'s result: the session's document moved by the entry's interval,
  //          labelled with a practical key, and the document itself untouched. Otherwise it is the
  //          edited chart moved by the editor interval, as before.
  // KEYWORDS: shown-song, scene-resolution, editor-transposition, document-preserved
  Song _shownSong(IRealSong entry) {
    final SetlistItem? playing = _playingItemFor(entry);
    if (playing != null) {
      return setlistSceneFor(
        entry: playing,
        written: _sessionFor(entry).song,
      ).shown;
    }
    return _displayedSong(entry, _semitonesBySong[entry.index] ?? 0);
  }

  // PURPOSE: Report the key the chart on screen is labelled with, so the song list can state the
  //          move without building the whole transposed chart for every row.
  // INPUTS: entry — the loaded song.
  // OUTPUTS: The shown key. In the programme it is the scene resolution's practical spelling;
  //          otherwise the editor interval's target from the twelve-key grid.
  // KEYWORDS: shown-key, scene-vs-editor, cheap-read, list-subtitle
  Key _shownKeyFor(IRealSong entry) {
    final SetlistItem? playing = _playingItemFor(entry);
    if (playing != null) {
      return setlistSceneFor(
        entry: playing,
        written: _sessionFor(entry).song,
      ).shownKey;
    }
    return _keyFor(
      _sessionFor(entry).song.key,
      _semitonesBySong[entry.index] ?? 0,
    );
  }

  // PURPOSE: Describe the programme and the chart it is playing for the verification handoff, so a
  //          browser-driving tool that cannot reach a Dart object can still check what the scene
  //          meaning did: which entry is playing, what interval it carries, the key the CHART
  //          DOCUMENT holds and the key the page is SHOWN in — the pair that makes "the chart keeps
  //          its written key while the stage reads two semitones up" a measurement rather than a
  //          claim.
  // INPUTS: None; reads the programme, the selected song and the scene index.
  // OUTPUTS: A map, or null before a library is loaded. `writtenKey` is read from the chart's own
  //          session document and `shownKey` from the scene resolution over that document, so the
  //          two are the same value only when the entry is not transposed. `log` is the setlist
  //          event types in order, which is what makes an undo visible as an appended inverse rather
  //          than as a removed row. `entryCharts` reports, per entry, the document id and the
  //          identity it stores and the loaded song index it RESOLVED to (or `found: false`), and
  //          `missingCharts` counts those — the pair that makes "a programme saved from one export
  //          still finds its charts after another import" a measurement rather than a claim.
  // KEYWORDS: verification-handoff, programme-state, written-vs-shown, scene-index, setlist-log,
  //           entry-resolution, missing-chart
  Map<String, Object?>? _setlistState() {
    final SetlistSession? setlist = _setlist;
    final IRealLibrary? library = _library;
    if (setlist == null || library == null || library.songs.isEmpty) {
      return null;
    }
    final int songIndex =
        _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final IRealSong entry = library.songs[songIndex];
    final SetlistItem? playing = _playingItemFor(entry);
    final Song written = _sessionFor(entry).song;
    // WHAT EACH ENTRY RESOLVES TO, reported beside the entries themselves rather than inside them:
    // a headless driver cannot reach `_songForItem`, and "the programme names music this library
    // does not hold" is a claim only this report can settle. The `items` list keeps its original
    // shape — the entry as it is STORED — so what a driver reads as the programme and what it reads
    // as the resolution are two facts rather than one restated.
    final List<Object?> entryCharts = <Object?>[];
    int missing = 0;
    for (int index = 0; index < setlist.items.length; index++) {
      final SetlistItem item = setlist.items[index];
      final IRealSong? found = _songForItem(item);
      if (found == null) {
        missing++;
      }
      entryCharts.add(<String, Object?>{
        'index': index,
        'documentId': item.documentId,
        'chartIdentity': item.chartIdentity,
        'songIndex': found?.index,
        'found': found != null,
      });
    }
    return <String, Object?>{
      'id': setlist.setlist.id,
      'title': setlist.setlist.title,
      'depth_undo': setlist.undoDepth,
      'depth_redo': setlist.redoDepth,
      'seq': setlist.seq,
      'log': <Object?>[
        for (final SetlistEvent event in setlist.log) event.type,
      ],
      'scene': _sceneIndex,
      'items': <Object?>[
        for (final SetlistItem item in setlist.items)
          <String, Object?>{
            'documentId': item.documentId,
            'transposeSem': item.transposeSem,
            'notes': item.notes,
          },
      ],
      'entryCharts': entryCharts,
      'missingCharts': missing,
      'playingDocumentId': playing?.documentId,
      'writtenSongId': written.id,
      'writtenKey': written.key.toString(),
      'shownSemitones': playing?.transposeSem,
      'shownKey': playing == null
          ? written.key.toString()
          : setlistSceneFor(
              entry: playing,
              written: written,
            ).shownKey.toString(),
    };
  }

  // PURPOSE: Leave the programme and start playing one of its entries, which is the action that
  //          gives the scene meaning of D14 a chart to apply itself to.
  // INPUTS: index — the entry to play.
  // OUTPUTS: Nothing. The chart the entry names becomes the selected song, the entry becomes the
  //          playing one, the hit selection is dropped (a section id from another song names
  //          different music) and the page mode is set to PAGES, which is D13's scene default. An
  //          entry whose chart is not in the loaded library changes nothing and says so — an index
  //          into the programme is not an index into the library, and pretending otherwise would
  //          select whatever chart happens to sit at that position. WHICH chart an entry names is
  //          decided by [_songForItem] and nowhere else.
  // KEYWORDS: play-entry, scene-mode, selection-reset, page-mode-default, library-lookup
  void _playSetlistEntry(int index) {
    final IRealLibrary? library = _library;
    final SetlistSession? setlist = _setlist;
    if (library == null || setlist == null) {
      return;
    }
    final SetlistItem? item = setlist.itemAt(index);
    if (item == null) {
      return;
    }
    final IRealSong? found = _songForItem(item);
    if (found == null) {
      debugPrint(
        'viewer.setlist.play.skipped index=$index document="${item.documentId}" '
        'identity="${item.chartIdentity}" reason=chart-not-loaded',
      );
      return;
    }
    setState(() {
      _sceneIndex = index;
      _selectedSong = found.index;
      _selection = null;
      _chosenPageMode = PageMode.pages;
    });
    debugPrint(
      'viewer.setlist.play index=$index document="${item.documentId}" '
      'identity="${item.chartIdentity}" song=${found.index} '
      'transpose=${item.transposeSem} '
      'entries=${setlist.items.length}',
    );
  }

  // PURPOSE: Open the programme sheet, which is where the setlist is named and its entries are
  //          ordered and edited.
  // INPUTS: context — where to open the sheet.
  // OUTPUTS: A future that completes when the sheet is dismissed. Does nothing before a library is
  //          loaded, because there is no programme then. Every edit rebuilds this screen, so the
  //          chart behind the sheet reflects a transposition the moment it is applied.
  // KEYWORDS: programme-sheet, setlist-edit, no-library-guard, rebuild-on-apply
  Future<void> _openSetlist(BuildContext context) async {
    final IRealLibrary? library = _library;
    final SetlistSession? setlist = _setlist;
    if (library == null || setlist == null) {
      debugPrint('viewer.setlist.open.skipped reason=no-library');
      return;
    }
    debugPrint(
      'viewer.setlist.open entries=${setlist.items.length} '
      'title_chars=${setlist.setlist.title.length}',
    );
    await showSetlistSheet(
      context,
      session: setlist,
      songs: library.songs,
      titleFor: _titleForItem,
      onPlay: _playSetlistEntry,
      onChanged: () => setState(() {}),
      initialFilePath: setlistPathBeside(widget.initialPath),
      onOpenedFile: _adoptOpenedSetlist,
    );
  }

  // PURPOSE: Give the key badge a second meaning in the programme: tapping it while a setlist entry
  //          is playing edits THAT entry's interval through the setlist log, which is D14's scene
  //          transposition at D9's two-tap budget.
  // INPUTS: entry — the loaded song on screen, whose session holds the WRITTEN chart the grid must
  //         spell from.
  // OUTPUTS: A future that completes when the grid closes. A picked key is stored on the entry as
  //          its interval, so the chart shows the new key while the document's own key is untouched;
  //          a dismissed grid, an unavailable target or a closed screen changes nothing. The grid is
  //          built from the chart's written key, not from the shown one, so the spelling is chosen
  //          the same way the editor path chooses it.
  // KEYWORDS: scene-transposition, key-grid, setlist-entry-edit, two-taps, written-key-source
  Future<void> _chooseSceneKey(IRealSong entry) async {
    final SetlistSession? setlist = _setlist;
    final int? index = _sceneIndex;
    if (setlist == null || index == null) {
      return;
    }
    final SetlistItem? item = setlist.itemAt(index);
    if (item == null || _songForItem(item)?.index != entry.index) {
      return;
    }
    final Song written = _sessionFor(entry).song;
    final Key shown = setlistSceneFor(entry: item, written: written).shownKey;
    final TranspositionTarget? picked = await showKeyGrid(
      context,
      writtenKey: written.key,
      currentPitchClass: shown.tonicPitchClass,
    );
    if (!mounted || picked == null || !picked.available) {
      debugPrint(
        'viewer.setlist.scene.transpose.cancelled index=$index '
        'picked=${picked == null ? 'none' : picked.key}',
      );
      return;
    }
    setState(() => setlist.updateItem(index, transposeSem: picked.semitones));
    debugPrint(
      'viewer.setlist.scene.transpose index=$index '
      'written=${written.key} shown=${picked.key} '
      'semitones=${picked.semitones}',
    );
  }

  // PURPOSE: Give the title to SHOW for one loaded song, which is the edited one once the song has
  //          been opened — a rename has to reach every place the name is read, or one screen says
  //          the new name and the list beside it says the old one.
  // INPUTS: entry — the song as loaded, whose index names a session if one exists.
  // OUTPUTS: The session's title when that song has a session, the loaded title otherwise, and the
  //          catalogue's own word for "no title" for an empty one — the same fallback
  //          `IRealSong.title` applies, so the two agree before anything is edited. [l10n] is
  //          passed rather than read from a context because this runs while a row is being built
  //          and the caller already has the catalogue. The session is looked up in the map and NOT
  //          created: listing a library must not open a document for every song in it just to read
  //          a name.
  // KEYWORDS: title, edited-metadata, session-source, untitled-fallback, no-eager-session
  String _titleFor(IRealSong entry, AppLocalizations l10n) {
    final String title = _sessions[entry.index]?.song.title ?? entry.song.title;
    return title.isEmpty ? l10n.untitled : title;
  }

  // PURPOSE: Resolve the same name for a DIAGNOSTIC LOG LINE rather than for a musician, which is
  //          why it is a second function and not a second argument.
  // INPUTS: entry — the song whose name to resolve.
  // OUTPUTS: The session's title, the loaded title, or the literal `Untitled` when the song has no
  //          name — in ENGLISH, always, whatever the interface is set to.
  // KEYWORDS: log-line, english-only, diagnostics, title, untitled-fallback
  //
  // WHY THIS EXISTS AND WHY IT IS ENGLISH. A LOG LINE IS NOT INTERFACE TEXT. Lines such as
  // `viewer.song.select`, `viewer.select`, `viewer.page.fit.fallback`, `setlist.item.move` and
  // `ink.contact.down` are read by tools and by the driving harness, and several are asserted by
  // tests byte for byte; translating one would break a tool for no reader's benefit, because no
  // musician sees it. So `_titleFor` above may return `Без названия` and this one may not, and the
  // two are kept apart by their names rather than by a comment asking the next person to remember.
  // The same rule holds for EVERY `debugPrint` in this application: leave those lines English. If
  // you are here to "finish the job" by translating them, this comment is the answer — do not.
  String _rawTitleFor(IRealSong entry) {
    final String title = _sessions[entry.index]?.song.title ?? entry.song.title;
    return title.isEmpty ? 'Untitled' : title;
  }

  // PURPOSE: Name the chart a programme entry refers to, so the programme sheet shows the name the
  //          editor would show — including a rename — and can say plainly when the entry names a
  //          chart this library does not hold.
  // INPUTS: item — the entry, which is resolved through [_songForItem] rather than by either of its
  //         ids directly, because which id is authoritative depends on whether the entry carries an
  //         identity.
  // OUTPUTS: The loaded (or edited) title EXACTLY AS THE DOCUMENT HOLDS IT — the empty string for a
  //          chart that has no name — or null when the entry resolves to no loaded song. NULL IS THE
  //          MISSING CASE and not an empty name: the sheet renders `(missing chart)` for null and its
  //          own localized fallback for the empty string, and the entry itself is untouched — it is
  //          still in the running order, can still be edited and deleted, and is saved again exactly
  //          as it stands. A silently dropped row would lose a tune the musician put in the
  //          programme, and a blank one would look like a chart with no name.
  // KEYWORDS: title-resolution, chart-identity, rename-aware, missing-chart, programme-sheet,
  //           empty-is-not-null, raw-title
  String? _titleForItem(SetlistItem item) {
    final IRealSong? found = _songForItem(item);
    if (found == null) {
      return null;
    }
    // NO WORD FOR AN UNNAMED CHART IS INVENTED HERE. The programme sheet draws every name this
    // application shows for a chart, so it is the side that owns the interface fallback, and it is
    // the only side that can reach a catalogue at the moment a name is drawn. Returning the raw
    // title is what lets a rename show through and a nameless chart reach the sheet as nameless
    // rather than as an English `Untitled`.
    return _sessions[found.index]?.song.title ?? found.song.title;
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

  // PURPOSE: Describe the shell — the app bar, the song list, the tools and the body — in the form
  //          the surface's width asks for.
  // INPUTS: context — the build context, whose [MediaQuery] holds the window width the shell form is
  //         decided from.
  // OUTPUTS: A [Scaffold]. On a tablet-width surface it is the shell this file has always built: the
  //          eight controls in the app bar, the song list as a permanent left column and nothing at
  //          the bottom. On a phone-width surface it is D11's phone shell: the four document actions
  //          in an app-bar overflow menu, the song list in a drawer, and the four tools a musician
  //          touches while playing in a bottom dock. Which of the two is built is decided ONCE, here,
  //          from the window width, and every branch below reads that one answer — so the rail and
  //          the drawer can never both be built, and the tools can never be in two places at once.
  // KEYWORDS: scaffold, shell, app-bar, drawer, bottom-dock, overflow-menu, phone, tablet, d11,
  //           one-decision-many-reads
  Widget _buildScreen(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? error = _error;
    final EditSession? session = _currentSession;
    final IRealLibrary? library = _library;
    final bool phone = _isPhoneWidth(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(
        // The title names the application, not the file, and on a phone it names it in one word:
        // eight actions beside a two-word title is what left the bar reading `Cha…`, and a title
        // that cannot be read is worse than a shorter one that can. The phone form is the brand
        // name alone, which is the same string in every language and so is not in the catalogue.
        title: Text(phone ? 'ChartApp' : l10n.appTitle),
        actions: phone
            ? <Widget>[_buildOverflowMenu(context, session)]
            : <Widget>[
                ..._documentTools(context, session),
                ..._sheetActions(context, session),
              ],
      ),
      // The drawer exists only when there is a library to list: an empty drawer over a screen that
      // says "load a file" offers a control that opens nothing.
      drawer: phone && library != null && library.songs.isNotEmpty
          ? _buildSongDrawer(context, library)
          : null,
      onDrawerChanged: phone ? _onDrawerChanged : null,
      bottomNavigationBar: phone ? _buildPhoneDock(context, session) : null,
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

  // PURPOSE: The four tools whose STATE the bar shows and whose press changes the document, built
  //          once for whichever surface is going to hold them.
  // INPUTS: session — the session of the song on screen, or null when nothing is loaded.
  // OUTPUTS: The pen, the eraser, undo and redo, in that order, as the widgets the app bar and the
  //          phone dock both use. They carry the keys the tests and the driving tools find them by,
  //          and the list is built in ONE place because the two surfaces must not be able to
  //          disagree about what a tool does: the dock is not a second implementation of undo.
  //          Every control is disabled rather than hidden when there is no chart, so the pair keeps
  //          its place in the bar and a musician's hand learns where it is.
  // KEYWORDS: tools, pen, eraser, undo, redo, one-definition-two-surfaces, disabled-not-hidden
  List<Widget> _documentTools(BuildContext context, EditSession? session) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return <Widget>[
      // The ink switch stands first because it changes what a pen DOES, and a musician about to
      // write needs it under their thumb before anything else in this bar. Its icon and tooltip
      // state the mode in words, because a toggle whose only signal is a colour is not discoverable.
      IconButton(
        key: const ValueKey<String>('viewer-ink-toggle'),
        icon: Icon(_inkOn ? Icons.draw : Icons.edit_outlined),
        tooltip: _inkOn
            ? l10n.tooltipInkOn
            : (_eraserOn ? l10n.tooltipInkOffEraserOn : l10n.tooltipInkOff),
        onPressed: session == null ? null : () => _toggleInk(session),
      ),
      // --- ERASER ---------------------------------------------------------------------------------
      // The eraser stands next to the pen because the two are the two things a contact on the
      // chart can do to the ink, and there is exactly one of them at a time: pressing it turns
      // the pen off, and pressing the pen turns it off. Its tooltip states the gesture in words —
      // a tap on a stroke removes that whole stroke — because a musician cannot be expected to
      // discover a mode from an icon. This button, `_toggleEraser` below `_toggleInk`, the
      // `_eraserOn` getter beside `_inkOn`, the `eraser` keys in `_inkProbeState`, and the eraser
      // branch of `_onPageTapUp` are the whole of this feature's footprint in this file.
      IconButton(
        key: const ValueKey<String>('viewer-eraser-toggle'),
        icon: const Icon(Icons.auto_fix_normal),
        tooltip: _eraserOn ? l10n.tooltipEraserOn : l10n.tooltipEraserOff,
        onPressed: session == null ? null : () => _toggleEraser(session),
      ),
      IconButton(
        key: const ValueKey<String>('viewer-undo'),
        icon: const Icon(Icons.undo),
        tooltip: l10n.tooltipUndo,
        onPressed: session != null && session.canUndo
            ? () => _undo(session)
            : null,
      ),
      IconButton(
        key: const ValueKey<String>('viewer-redo'),
        icon: const Icon(Icons.redo),
        tooltip: l10n.tooltipRedo,
        onPressed: session != null && session.canRedo
            ? () => _redo(session)
            : null,
      ),
    ];
  }

  // PURPOSE: The four actions that OPEN a surface — the form sheet, the words sheet, the programme
  //          and the chart file — built for the app bar of a tablet.
  // INPUTS: context — the build context. session — the session of the song on screen, or null.
  // OUTPUTS: The controls in the order they have always stood in this bar, plus the settings
  //          action the language switch needs. They are separated from [_documentTools] because a
  //          phone puts them somewhere else: they are in the overflow menu of the phone app bar,
  //          where [PopupMenuButton] calls the very same methods by name, so an action never has two
  //          implementations.
  // KEYWORDS: sheet-actions, form, text-cue, programme, chart-file, settings, app-bar,
  //           phone-overflow
  List<Widget> _sheetActions(BuildContext context, EditSession? session) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return <Widget>[
      // --- BARS AND SECTIONS (form editing, owner decision D17) -----------------------------------
      // An action rather than a row in the body: a body row costs the chart height, and D13's FIT
      // refuses to shrink a chart past the legible floor (the `.chart` control's move into this
      // bar, in `chart_file_bar.dart`, is that mistake measured). It is disabled until a bar is
      // selected, because every operation in its sheet acts on the selected bar's section and
      // index. This button, the `_openSongForm` method below `_redo`, and the bar-level branch of
      // `_buildSelectionLine` are the whole of this feature's footprint in this file.
      IconButton(
        key: const ValueKey<String>('viewer-form'),
        icon: const Icon(Icons.segment),
        tooltip: l10n.tooltipForm,
        onPressed: session == null || _selection == null
            ? null
            : () => _openSongForm(context, session),
      ),
      // --- WORDS ON THE CHART (text cues, `textcue.*`) --------------------------------------------
      // Placed beside the form action because both act on the bar the page's hit test named, and
      // disabled under the same condition: a cue is anchored to an address, so there is nothing to
      // write on until a bar is selected. Its icon is a speech mark rather than a pencil, because the
      // pencil is what the ink switch already means.
      IconButton(
        key: const ValueKey<String>('viewer-text-cue'),
        icon: const Icon(Icons.format_quote),
        tooltip: l10n.tooltipCues,
        onPressed: session == null || _selection == null
            ? null
            : () => _openTextCueSheet(context, session),
      ),
      // --- THE PROGRAMME (setlist, owner decision D14's scene meaning) -----------------------------
      // The programme is the setlist document the imported playlist becomes. It lives beside the
      // other document-level actions because it is a document, not a property of the bar under the
      // cursor; the sheet it opens holds the running order. Its undo and redo live INSIDE the sheet
      // rather than here, because the programme has its own log and its own history, and a second
      // pair of arrows in this bar would make a musician guess which document they reverse.
      //
      // THE WHOLE PROGRAMME FOOTPRINT IN THIS FILE, named so a later edit can find it: this button,
      // `_songForItem` (the one resolution join, delegated to `setlist_resolution.dart`),
      // `_playingItemFor` / `_shownSong` / `_shownSemitones` / `_shownKeyFor`, `_playSetlistEntry`,
      // `_openSetlist` (which hands the sheet its resolver and its file callbacks),
      // `_chooseSceneKey`, `_titleForItem`, `_adoptOpenedSetlist`, the `entryCharts`/`missingCharts`
      // report in `_setlistState`, the `chartIdentity` of a chart opened from a file in
      // `_adoptOpenedSong`, and the scene branch of the scene bar in `_buildSongPane`. Everything
      // else is in `setlist_sheet.dart` (the sheet), `setlist_file_bar.dart` (its file dialog),
      // `setlist_document.dart` (session to file and back), `setlist_import.dart` (the bridge) and
      // `setlist_resolution.dart` (which chart an entry names).
      IconButton(
        key: const ValueKey<String>('viewer-setlist'),
        icon: const Icon(Icons.queue_music),
        tooltip: l10n.tooltipSetlist,
        onPressed: _library == null
            ? null
            : () => unawaited(_openSetlist(context)),
      ),
      // The chart document itself can be named and moved, on every platform: where a path exists the
      // field holds it, and in a browser it holds the name offered to the browser's chooser and
      // download. It lives in the app bar because a control in the body takes height away from the
      // chart, and D13's FIT mode refuses to shrink a chart past a legible floor — the bar turned a
      // song that fitted on one page into one that did not.
      ChartFileAction(
        document: _documentOfSelection,
        events: session?.log ?? const <ChartEvent>[],
        initialPath: chartPathBeside(widget.initialPath),
        // The title the proposed FILE name is built from — the one on screen, not the one in the
        // snapshot. `document` above is the written snapshot, and a rename this session made lives
        // in the operations beside it, so a chart typed from scratch and then named would otherwise
        // be offered as `untitled.chart`. Measured on the owner's tablet before this argument:
        // naming the chart "Moya Pesnya" and pressing Save proposed `untitled.chart`.
        nameTitle: session?.song.title,
        onOpened: _adoptOpenedSong,
        // The third thing a musician does with a chart document, beside saving one and opening one,
        // and it lives here for the same reason the other two do: this bar is where a charter's
        // attention already is, and a fourth control beside the save/open button costs no width in
        // an app bar whose width A49 measured as the scarce resource. On a phone this dialog is
        // reached from the overflow menu, so both shells get it without a new toolbar row.
        onNew: () => unawaited(_newChart(context)),
      ),
      // --- SETTINGS, AND WHY IT IS HERE ------------------------------------------------
      // The language switch is the one SETTING this application has, and a setting belongs
      // where every other surface-opening action already is rather than behind a gesture. It
      // is a new action and it is placed LAST on purpose: the eight controls before it are the
      // ones a musician reaches for while working, and the app bar lays them out left to right,
      // so the newest and least-used control takes the far end rather than displacing the pen.
      // The cost is one more 48-pixel target in a bar whose WIDTH A49 measured as scarce; the
      // measurement of what that did to the title is in `docs/sdd.md` beside the entry for this
      // change, at 824 and at 600 logical pixels.
      IconButton(
        key: const ValueKey<String>('viewer-settings'),
        icon: const Icon(Icons.settings),
        tooltip: l10n.tooltipSettings,
        onPressed: () => unawaited(_openSettings(context)),
      ),
    ];
  }

  // PURPOSE: Give a phone the surface-opening actions in one app bar control, so that the title
  //          beside them can be read.
  // INPUTS: context — where the sheets are opened from, and the [PopupMenuButton]'s anchor.
  //         session — the session of the song on screen, or null when nothing is loaded.
  // OUTPUTS: One overflow menu holding bars-and-sections, words, the programme, the chart file and
  //          settings. The first two are DISABLED rather than absent until a bar is selected,
  //          matching the app bar's own rule and for the same reason: a musician looking for the
  //          form should find it and be told why it is not available yet rather than hunt a control
  //          that is not there. Each row calls the same method its app-bar button calls, so the
  //          phone and the tablet cannot come to mean different things by the same words.
  // KEYWORDS: overflow-menu, phone-app-bar, disabled-rows, one-implementation, settings, d11
  Widget _buildOverflowMenu(BuildContext context, EditSession? session) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const ValueKey<String>('viewer-phone-menu'),
      tooltip: l10n.tooltipOverflowMenu,
      onSelected: (String picked) {
        if (picked == 'form' && session != null) {
          _openSongForm(context, session);
        } else if (picked == 'cues' && session != null) {
          _openTextCueSheet(context, session);
        } else if (picked == 'setlist') {
          unawaited(_openSetlist(context));
        } else if (picked == 'file') {
          unawaited(
            showChartFileDialog(
              context,
              document: _documentOfSelection,
              events: session?.log ?? const <ChartEvent>[],
              initialPath: chartPathBeside(widget.initialPath),
              onOpened: _adoptOpenedSong,
              // The same title-on-screen rule the app-bar action follows; see its own comment.
              nameTitle: session?.song.title,
              // The phone's way to the same action the tablet's app-bar file dialog offers. It is
              // passed rather than made a menu row of its own so that "New chart" means one thing
              // on both shells and sits beside Save and Open wherever a musician finds either.
              onNew: () => unawaited(_newChart(context)),
            ),
          );
        } else if (picked == 'settings') {
          unawaited(_openSettings(context));
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'form',
          enabled: session != null && _selection != null,
          child: Text(l10n.menuForm),
        ),
        PopupMenuItem<String>(
          value: 'cues',
          enabled: session != null && _selection != null,
          child: Text(l10n.menuCues),
        ),
        PopupMenuItem<String>(
          value: 'setlist',
          enabled: _library != null,
          child: Text(l10n.menuSetlist),
        ),
        PopupMenuItem<String>(value: 'file', child: Text(l10n.menuChartFile)),
        // The settings row stands last, for the same reason its app-bar twin does: the rows above
        // it are the ones a musician opens a chart to reach.
        PopupMenuItem<String>(
          value: 'settings',
          child: Text(l10n.menuSettings),
        ),
      ],
    );
  }

  // PURPOSE: Raise the settings sheet and adopt the language it reports.
  // INPUTS: context — where the sheet is raised from.
  // OUTPUTS: A future that completes when the sheet closes. A tap on a language row is handed to
  //          [IRealViewerScreen.onLanguageChanged], which is the application root, because the
  //          locale belongs to the [MaterialApp] above this screen and nowhere else. With no owner
  //          listening — a widget test pumping this screen on its own — the sheet still opens and
  //          still shows which language is in force; the tap simply has nowhere to go.
  // KEYWORDS: settings, language, sheet, callback-to-root, widget-test-seam
  Future<void> _openSettings(BuildContext context) => showSettingsSheet(
    context,
    language: widget.language,
    // NOT `widget.onLanguageChanged ?? (_) {}` — the null is carried through, so a test can tell
    // "there is no owner" from "the owner did nothing" without a second flag.
    onChanged: (LanguageChoice choice) =>
        widget.onLanguageChanged?.call(choice),
    // A preference that lives in the page is a fact about where this build RUNS, not about whether
    // it offers a path field. Deriving it from the field put a tablet's language choice in the same
    // sentence as Safari's seven-day storage policy, which is a claim about a browser the tablet is
    // not. See `iRealSourceIsBrowser`.
    browserStorage: iRealSourceIsBrowser,
  );

  // PURPOSE: Put the tools under the thumb on a phone, which is D11's own landing for a phone.
  // INPUTS: context — the build context, for the surface colour. session — the session of the song
  //         on screen, or null.
  // OUTPUTS: A bottom dock holding exactly the widgets [_documentTools] builds, stretched to equal
  //          shares of the width so a hand finds each of the four in the same place every time. The
  //          dock's height does not change with what is in it, so the chart above it is laid out for
  //          one height and stays there as plays change. WHY THIS IS A `Material` OF ITS OWN AND NOT
  //          A [BottomNavigationBar]: the four controls carry state (pen on, eraser on, undo
  //          available, redo available) that already has one implementation as an [IconButton]; a
  //          navigation bar would want the state expressed a second time as a selected index.
  // KEYWORDS: bottom-dock, phone-tools, equal-shares, fixed-height, d11, state-carrying-controls
  Widget _buildPhoneDock(BuildContext context, EditSession? session) =>
      Material(
        key: const ValueKey<String>('viewer-phone-dock'),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: <Widget>[
                for (final Widget tool in _documentTools(context, session))
                  Expanded(child: Center(child: tool)),
              ],
            ),
          ),
        ),
      );

  // PURPOSE: Give the song list to a phone, which has no width to spare for a permanent column.
  // INPUTS: context — where the list is built. library — the loaded songs.
  // OUTPUTS: A drawer holding a header naming how many songs there are and the list itself, which
  //          closes when a song is picked. The header is not decoration: the drawer covers the chart
  //          and the status bar under it, so without it the reader has no idea whether they are
  //          looking at a 22-song playlist or a single chart.
  // KEYWORDS: drawer, song-list-home, header, close-on-pick, phone, d11
  Widget _buildSongDrawer(BuildContext context, IRealLibrary library) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String header = library.isPlaylist
        ? l10n.drawerSongsPlaylist(library.songs.length, library.playlistName)
        : l10n.songCount(library.songs.length);
    return Drawer(
      key: const ValueKey<String>('viewer-song-drawer'),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                header,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildSongList(context, library, closeAfterPick: true),
            ),
          ],
        ),
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
      'viewer.ink.toggle song="${_rawTitleFor(entry)}" on=$next '
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
      'viewer.eraser.toggle song="${_rawTitleFor(entry)}" on=$next '
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

  // PURPOSE: Start a chart from nothing — the one way music enters this application that does not
  //          come from an iReal export — and put it on screen through the SAME door an opened
  //          `.chart` file uses, so a made-up chart and an imported one are one kind of thing
  //          everywhere downstream.
  // INPUTS: context — where the new-chart dialog is shown from.
  // OUTPUTS: A future completing when the dialog closes. On a choice it builds the song with the
  //          chosen key and meter through `newChartSong` and hands it to [_adoptOpenedSong] as a
  //          document with an EMPTY operation tail — because a new chart has exactly that: a
  //          snapshot and no history. On a dismissal nothing is created and the screen is untouched,
  //          which is why the dismissal is logged rather than treated as a failure.
  //
  //          WHY THERE IS NO SECOND ADOPTION PATH. The rail, the programme of one, the session, the
  //          ink layer, the scene bar and the save button all read the library and the sessions this
  //          screen holds; seeding them here by hand would be a second implementation of
  //          [_adoptOpenedSong] that could disagree with the first about any of them. A new chart is
  //          a document, and a document is what that method takes.
  //
  //          WHAT IS NOT ASKED HERE, AND WHY. The title is not: it is renamed through the song-info
  //          sheet, which is the same `song.update` a rename of an imported chart goes through, so
  //          asking for it at creation would be a second naming mechanism. Tempo and style are not:
  //          both are editable afterwards and neither is required for the page to be read.
  // KEYWORDS: new-chart, from-scratch, one-adoption-path, empty-tail, d21, structured-log
  Future<void> _newChart(BuildContext context) async {
    final NewChartChoice? choice = await showNewChartDialog(context);
    if (!mounted || choice == null) {
      debugPrint('viewer.chart.new.cancelled');
      return;
    }
    final Song song = newChartSong(
      key: choice.key,
      timeSignature: choice.timeSignature,
    );
    // The identity is printed here and not only computed inside the adoption, because it is the
    // answer to a question this feature raises and nothing else can show: two charts made with the
    // same key and meter hold identical MUSIC, and an identity that names music must therefore be
    // identical too. A reader of this line can see that happen rather than have it asserted.
    debugPrint(
      'viewer.chart.new.created key=${song.key} '
      'meter=${song.sections.first.bars.first.timeSignature} '
      'bars=${song.writtenBarCount} '
      'sections=${song.sections.length} '
      'identity=${chartIdentityOf(song)}',
    );
    _adoptOpenedSong((
      document: DocumentState(song: song),
      events: const <ChartEvent>[],
    ));
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
    // One library value built once, so the session and the programme cannot be seeded from two
    // different lists that happen to have identical contents today.
    final IRealLibrary library = IRealLibrary(
      playlistName: '',
      songs: <IRealSong>[
        IRealSong(
          index: 0,
          song: opened.document.song,
          // The identity of what the file HOLDS, so a programme entry made from this chart resolves
          // by content like every other entry and does not fall back to the id the file happened to
          // store.
          chartIdentity: chartIdentityOf(opened.document.song),
        ),
      ],
    );
    setState(() {
      _library = library;
      _selectedSong = 0;
      _semitonesBySong.clear();
      // A single opened chart is a programme of one, built the same way a loaded playlist is, so the
      // scene path has no special case: its entry names the opened document by the id the file gave
      // it. The previous programme is replaced rather than kept, because its entries named charts
      // that are no longer loaded.
      _setlist = SetlistSession(setlist: importedSetlist(library));
      _sceneIndex = null;
      _sessions
        ..clear()
        ..[0] = EditSession(
          document: opened.document,
          // THE ID THE FILE ITSELF IS WRITTEN UNDER, not the song's own id, because those differ
          // for exactly one kind of document and it is the kind this screen can now make: a chart
          // typed from scratch carries no song id (`Song.id` is empty until a store assigns one),
          // and `chartFileFor` writes such a chart under `untitledDocumentId`. Passing the empty id
          // through would give the session a doc id of `''` while the file it saves declares
          // `chartapp-untitled`, and the container refuses a file whose operations name a different
          // document than its header — so the first edit would make the chart unsavable. Both
          // sides read the rule from `documentIdFor`, so they cannot answer differently.
          docId: documentIdFor(opened.document.song),
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

  // PURPOSE: Adopt the programme a `.setlist` file decoded to, so the running order on the sheet is
  //          the one the file holds and the sheet's further edits continue its log.
  // INPUTS: session — the session the sheet built from the decoded file through
  //         `setlistSessionFor`, which has already folded the file's tail into its snapshot.
  // OUTPUTS: Nothing. The programme on screen becomes that session and the scene index is cleared,
  //          because an index into the replaced programme names a different entry now.
  //
  //          THE SESSION IS BUILT BY THE SHEET AND HANDED OVER AS ONE VALUE, rather than this screen
  //          rebuilding it from the pieces: the sheet is where the `.setlist` dialog lives, and two
  //          constructions of one session would be two chances to disagree about the sequence number
  //          the continued log starts from. What this screen adds is the state change and the trace.
  //
  //          AN ENTRY THAT FINDS NOTHING IS KEPT, and its missing state is reported by
  //          [_setlistState]'s `entryCharts`/`missingCharts` and by the sheet's own sentence. The
  //          entry is never dropped and never rerouted to whatever chart sits at the position its
  //          document id names: a programme that silently dropped a chart would be worse than one
  //          that says which one it cannot find, because the musician cannot re-add what they were
  //          never told was gone.
  // KEYWORDS: open-setlist, adopt-session, scene-reset, missing-chart, keep-entry, trace
  void _adoptOpenedSetlist(SetlistSession session) {
    setState(() {
      _setlist = session;
      _sceneIndex = null;
    });
    debugPrint(
      'viewer.setlist.open.adopted id="${session.docId}" '
      'entries=${session.items.length} '
      'operations=${session.log.length}',
    );
  }

  // PURPOSE: Give the reader the control that starts a load, in the form the platform can honour.
  // INPUTS: context — the build context.
  // OUTPUTS: The bar widget. Where a typed path addresses the file — a desktop — the path field and
  //          the Load button are shown, together with a chooser button that fills the field in for
  //          the reader, because both ways in genuinely work there. Everywhere else the bar is a
  //          single button that opens the platform's own file chooser: a text field for a path that
  //          addresses nothing, which is the case on Android, on iOS and in a browser, would invite
  //          the reader to type something meaningless. Every button is disabled while a load is
  //          running, so two reads cannot race for the same state.
  // KEYWORDS: source-bar, path-field, load-button, file-picker, busy-guard, platform-affordance,
  //           chooser-button
  Widget _buildPathBar(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!sourceIsFilePath) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('viewer-open-file'),
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.openHtmlFile),
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
              key: const ValueKey<String>('viewer-path-field'),
              controller: _pathController,
              decoration: InputDecoration(
                labelText: l10n.iRealHtmlFileLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (String _) => unawaited(_load()),
            ),
          ),
          const SizedBox(width: 8),
          // A chooser beside the field rather than instead of it, and only here: a desktop is the
          // one platform where typing a path is a real way to name a file, so offering the dialog as
          // well costs nothing and saves the reader who does not want to type. It is not shown where
          // the field is not, because there the single button above IS the chooser.
          OutlinedButton.icon(
            key: const ValueKey<String>('viewer-choose-file'),
            onPressed: _loading ? null : () => unawaited(_chooseAndLoad()),
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.chooseFile),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey<String>('viewer-load-file'),
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.download),
            label: Text(l10n.load),
          ),
        ],
      ),
    );
  }

  // PURPOSE: Let a desktop reach a file through the platform's own chooser instead of making the
  //          reader type its path, which is the second way in that only a desktop has.
  // INPUTS: None; the reader's choice in the platform's own dialog.
  // OUTPUTS: Nothing. Writes the chosen path into the field — so the reader can see which file is
  //          loaded and can edit or re-use it — and then loads it through the ONE loading path,
  //          [_load]. A null answer means the reader dismissed the dialog, on a platform that has no
  //          path to hand back, or both: nothing is loaded and nothing is reported, because a
  //          cancellation is not a fault.
  // KEYWORDS: chooser, reference, desktop-only, cancellation, one-loading-path
  Future<void> _chooseAndLoad() async {
    final String? reference = await widget.chooseReference();
    if (!mounted || reference == null) {
      debugPrint('viewer.choose.cancelled');
      return;
    }
    _pathController.text = reference;
    debugPrint('viewer.choose.ok path_chars=${reference.length}');
    await _load();
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
  //          the selected song's pages — or, on a phone, the chart ALONE with the list in a drawer.
  // INPUTS: context — the build context, whose [MediaQuery] holds the window width.
  // OUTPUTS: The body widget. Before a load it explains what to do, and after an empty library it
  //          says so rather than showing an empty list. Where there is a chart, the chart is given
  //          the WHOLE width on a phone and the window minus the rail on a tablet. That difference
  //          is the whole point of the shell: at 412 logical pixels a fixed 260-pixel column left
  //          about 150 for the music, which is one chord per system, and no musician can read from
  //          that. The page geometry is untouched — the same engine engraves the same chart — so the
  //          phone gains bars per system purely by having the width to fit them in.
  // KEYWORDS: body, empty-state, split-view, phone-full-width, tablet-rail, no-list-on-phone
  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final IRealLibrary? library = _library;
    if (library == null) {
      // THREE PLATFORMS, THREE SENTENCES, and none of them instructs a reader to do something their
      // platform cannot. A desktop may type a path OR choose one; a hand-held can only choose; a
      // browser can only choose and is the one place a musician is told the file is never uploaded.
      // The browser wording is selected by WHAT THIS BUILD IS and not by "there is no path field",
      // because Android has no path field either and is not a page — the coupling that made the
      // tablet's empty state talk about a browser.
      final String prompt = sourceIsFilePath
          ? l10n.promptNativePath
          : (iRealSourceIsBrowser ? l10n.promptWeb : l10n.promptNativeChooser);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(prompt, textAlign: TextAlign.center),
              // THE ONE GESTURE. A musician who opens the application to write a tune has nothing
              // else to look at on this screen, so the action that starts a chart stands ON the
              // empty state rather than in the app bar or behind the overflow menu: those are the
              // places a musician with a chart already open looks, and this is the place a musician
              // with nothing looks. It is a button and not a sentence about a button, because the
              // empty state already carries one instruction — how to open an export — and a second
              // paragraph about writing would be read as part of the first.
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey<String>('viewer-new-chart'),
                onPressed: () => unawaited(_newChart(context)),
                icon: const Icon(Icons.add),
                label: Text(l10n.newChart),
              ),
            ],
          ),
        ),
      );
    }
    if (library.songs.isEmpty) {
      return Center(child: Text(l10n.payloadNoSongs));
    }
    final int songIndex =
        _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final bool phone = _isPhoneWidth(MediaQuery.sizeOf(context).width);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The rail is NOT built on a phone rather than built and hidden: a `SizedBox` still in the
        // tree would still be taking its width, and the list would then exist twice — once in the
        // drawer and once in a column the reader cannot see.
        if (!phone) ...<Widget>[
          SizedBox(
            width: _songRailWidth,
            child: _buildSongList(context, library),
          ),
          const VerticalDivider(width: 1),
        ],
        Expanded(child: _buildSongPane(context, library, songIndex)),
      ],
    );
  }

  // PURPOSE: List the loaded songs so one can be selected, whether as the tablet's rail or as the
  //          phone's drawer.
  // INPUTS: context — the build context. library — the loaded songs. closeAfterPick — whether
  //         picking a song must also close the surface the list is in, which is true only in the
  //         drawer: the list is covering the chart there, and leaving it open would keep the
  //         musician from the song they just chose. False in the rail, where there is nothing to
  //         close and closing the route would leave the screen.
  // OUTPUTS: A scrollable list. Each row names the song, its bar count, the key it is shown in and,
  //          when there are any, its issue count. A transposed song shows the move, so the list
  //          says which charts are no longer in their written key. A song whose session exists
  //          reports the NAME and bar count of the EDITED chart, so the row and the pane beside it
  //          cannot disagree about a chart the musician just changed — a rename that reached the
  //          page's own header and not this list would be two names for one song. A song nobody has
  //          opened reports the loaded values, and no session is created just to read them. The list
  //          is scrolled by [_songListScroll] and stored under a [PageStorageKey], so closing the
  //          drawer and opening it again lands where the musician left it, and the picked song is
  //          the selected row on the way back for the same reason.
  // KEYWORDS: song-list, selection, issue-count, shown-key, written-key, edited-title, edited-count,
  //           drawer-aware, scroll-kept, structured-log
  Widget _buildSongList(
    BuildContext context,
    IRealLibrary library, {
    bool closeAfterPick = false,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListView.builder(
      key: const PageStorageKey<String>('viewer-song-list'),
      controller: _songListScroll,
      itemCount: library.songs.length,
      itemBuilder: (BuildContext context, int index) {
        final IRealSong entry = library.songs[index];
        final int semitones = _shownSemitones(entry);
        final String writtenName = localizedKeyName(l10n, entry.song.key);
        final String keyLabel = semitones == 0
            ? writtenName
            : '$writtenName → ${localizedKeyName(l10n, _shownKeyFor(entry))}';
        final Song summarySong = _sessions[entry.index]?.song ?? entry.song;
        final String subtitle =
            '${l10n.barCount(summarySong.writtenBarCount)} · $keyLabel'
            '${entry.issues.isEmpty ? '' : ' · ${l10n.issueCount(entry.issues.length)}'}';
        return ListTile(
          dense: true,
          selected: index == _selectedSong,
          title: Text(
            _titleFor(entry, l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            setState(() {
              _selectedSong = index;
              // Choosing a song by hand LEAVES the programme: the scene offset belongs to a position
              // in the running order, and reading a chart on its own is not playing that position.
              // The editor interval remembered for the song is what applies again.
              _sceneIndex = null;
              // A selection belongs to the song it was made in; another song's bar at the same
              // address is a different bar.
              _selection = null;
            });
            if (closeAfterPick) {
              Scaffold.of(context).closeDrawer();
            }
            debugPrint(
              'viewer.song.select index=$index title="${_rawTitleFor(entry)}" '
              'from_drawer=$closeAfterPick '
              'scroll=${_songListScroll.hasClients ? _songListScroll.offset.toStringAsFixed(1) : 'detached'}',
            );
          },
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final IRealSong entry = library.songs[songIndex];
    final SetlistItem? playing = _playingItemFor(entry);
    final int semitones = _shownSemitones(entry);
    final Song displayed = _shownSong(entry);
    // In the programme the POS field reports the running order, not the library order: a setlist
    // that dropped two tunes and moved a third makes those two numbers different, and the position a
    // performer needs is the one in the programme they are playing from.
    final int position = playing == null
        ? songIndex + 1
        : (_sceneIndex ?? 0) + 1;
    final int songCount = playing == null
        ? library.songs.length
        : (_setlist?.items.length ?? library.songs.length);
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
                      message: l10n.songInfoTooltip,
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
                                _titleFor(entry, l10n),
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
                  Text(l10n.barCount(displayed.writtenBarCount)),
                  if (entry.issues.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => unawaited(_showIssues(context, entry)),
                      child: Text(l10n.issueCount(entry.issues.length)),
                    ),
                  ],
                ],
              ),
            ),
            SceneBar(
              position: position,
              songCount: songCount,
              song: displayed,
              semitones: semitones,
              pageMode: mode,
              // The bar's FORM follows the SHELL's decision about the surface, taken from the
              // WINDOW by [_isBarCompact] — not from the pane this bar is drawn in. The pane is the
              // right measure for the page mode above and the wrong one here: the owner's tablet has
              // a 564-pixel pane, so a bar that called itself narrow on that number would drop STYLE
              // and REPEATS on the owner's own device while the shell around it was still the
              // tablet's. The window is read on BOTH axes, and the height is the one that matters on
              // a phone held sideways: see [_isBarCompact] and A49.
              compact: _isBarCompact(MediaQuery.sizeOf(context)),
              // The key badge keeps its two-tap meaning in BOTH senses of D14: on a chart read on
              // its own it edits the editor interval, and while a programme entry is playing it
              // edits that entry's scene interval through the setlist log. Which one is in force is
              // the same `_playingItemFor` answer the display used, so the badge and the page can
              // never disagree about which document is being changed.
              onOpenKeyGrid: () => unawaited(
                playing == null ? _chooseKey(entry) : _chooseSceneKey(entry),
              ),
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
    // The palette edits the WRITTEN chart — `applyChordToCell` writes the picked chord unchanged —
    // and only its preview is moved, so it is handed the interval and the key the page is SHOWN in.
    // In the programme that is the entry's scene interval, which is why a chord picked while playing
    // an entry is written in the chart's own key and previewed in the key the stage reads.
    final int semitones = _shownSemitones(entry);
    final Key shownKey = _shownSong(entry).key;
    unawaited(
      showChordPalette(
        context,
        session: session,
        sectionId: hit.sectionId,
        barIndex: hit.barIndex,
        beat: hit.beat!,
        shownKey: shownKey,
        semitoneShift: semitones,
        // The page is drawn from the session, so a rebuild after each applied chord is the whole of
        // what "show the edit" means here. The selection is deliberately NOT recomputed: the
        // address did not move, and re-running the hit test would need a point the sheet never had.
        onChanged: () => setState(() {}),
      ),
    );
  }

  // PURPOSE: Open the note palette for the selected cell, which is the third tap of the melodic
  //          edit: the first named the cell, the second opened what can be written in it, and this
  //          one writes a note. It is the entry the note staff had none of — the model, the events,
  //          the codec and the engraving all existed and nothing in the application could append a
  //          `note.insert`.
  // INPUTS: context — the build context.
  // OUTPUTS: Nothing. Does nothing when no cell is selected — a note is placed on a beat, so a
  //          bar-level selection names nowhere to put one — or when nothing is loaded. Otherwise the
  //          sheet edits through the session and rebuilds this screen after each applied note.
  //
  //          WHY THE PALETTE IS HANDED THE WRITTEN KEY AND NOT THE SHOWN ONE, which is the one place
  //          this differs from the chord palette beside it. The chord palette writes a SOUNDING root
  //          and the page spells it later, so it previews in the shown key; a note's written letter
  //          and alteration ARE the value that is stored, so a palette that offered the shown key
  //          would store a pitch the musician did not choose and would quietly transpose the chart's
  //          own melody while the chart is merely being DISPLAYED in another key. The interval is
  //          therefore not passed at all: the sheet writes the document, and the document is written
  //          in its own key.
  // KEYWORDS: note-edit-entry, cell-required, written-key, session, rebuild-on-apply, melody
  void _editNoteSelection(BuildContext context) {
    final ChartHit? hit = _selection;
    final EditSession? session = _currentSession;
    if (hit == null || hit.cell == null || session == null) {
      debugPrint(
        'viewer.note.skipped hit=${hit ?? 'none'} cell=${hit?.beat ?? 'none'}',
      );
      return;
    }
    debugPrint(
      'viewer.note.open section=${hit.sectionId} bar=${hit.barIndex} '
      'beat=${hit.beat} written_key=${session.song.key}',
    );
    unawaited(
      showNotePalette(
        context,
        session: session,
        sectionId: hit.sectionId,
        barIndex: hit.barIndex,
        beat: hit.beat!,
        writtenKey: session.song.key,
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
  // OUTPUTS: The selection line as ONE TO THREE WRAPPED ROWS. With a selection it reads
  //          `selected: bar 12 cell 2`; without one it invites a tap. A bar-level selection says so
  //          instead of inventing a cell number, and it leads to the FORM sheet rather than to the
  //          chord palette, because a bar and its section are what the form operations act on and a
  //          bar-level selection names both. The hint beside the label states the affordance in
  //          words, since a label that changes what it is when touched is not discoverable on its
  //          own. Nothing here can ellipsize: when the two parts do not share a row the hint moves
  //          to the next row whole, at full size.
  // KEYWORDS: selection-label, edit-entry, falsifiable-feedback, musician-numbering, empty-state,
  //           wrap-not-ellipsis, full-instruction
  Widget _buildSelectionLine(BuildContext context, Song song) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ChartHit? hit = _selection;
    final EditSession? session = _currentSession;
    final bool editable = hit != null && hit.cell != null;
    // A bar-level selection names no cell to write a chord or a note into, but it names exactly what
    // the form sheet acts on — a section and a bar — so the line is a control in both cases instead
    // of being dead text whenever the touch landed on a bar's padding rather than on one of its
    // cells.
    final VoidCallback? onTap = hit == null
        ? null
        : (editable
              ? () => _editSelection(context)
              : (session == null
                    ? null
                    : () => _openSongForm(context, session)));
    final String hint = editable
        ? l10n.selectionHintChord
        : l10n.selectionHintForm;
    final String text = hit == null
        ? l10n.selectionPrompt
        : _selectionLabel(song, hit, l10n);
    final TextStyle? style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: hit == null ? FontWeight.normal : FontWeight.bold,
    );
    final Widget label = Wrap(
      // The two parts are separate runs on purpose: they are different facts (what is selected, and
      // what a tap will do), the second one is the ACTION, and an action cut short is the defect
      // this layout exists to remove.
      spacing: 8,
      children: <Widget>[
        // A WRAP AND NOT A ROW OF FLEXIBLES. The line was a Row of two `Flexible` texts with
        // `TextOverflow.ellipsis`, and at 412 logical pixels in Russian the hint received about half
        // the pane and printed `— коснитесь, чтобы сменить а…`: the half a musician needs to read
        // was the half removed. Neither ellipsis nor a scale-down is acceptable here — an
        // instruction has to be complete, and text shrunk to fit is not readable on a music stand —
        // so the line wraps instead. The cost is named: on a phone-width pane in Russian the hint
        // takes a second row, and the chart in the `Expanded` below gives up that row's height. That
        // is the honest price of a longer language, and it is smaller than hiding the instruction.
        Text(
          text,
          key: const ValueKey<String>('viewer-selection-label'),
          style: style,
        ),
        if (onTap != null)
          Text(
            hint,
            key: const ValueKey<String>('viewer-selection-edit-hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
    // TWO NAMED ACTIONS RATHER THAN A SECOND GESTURE. A cell can now carry a chord AND notes, so
    // "tap the line" no longer names one thing; a long press for the second surface would be a
    // gesture nothing on screen mentions, and a mode switch would make a musician discover which
    // surface is armed by making a mistake. So the line carries the two words for the two surfaces,
    // and the third tap that writes a note is spent deliberately. The measure of what that costs is
    // in the decision record: chord editing went from two taps to three on the pane, and both
    // surfaces are now reachable from one named place.
    final bool cellSelected = editable && session != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
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
          if (cellSelected)
            Row(
              children: <Widget>[
                _SelectionAction(
                  widgetKey: 'viewer-selection-chord',
                  label: l10n.viewerChord,
                  onTap: () => _editSelection(context),
                ),
                const SizedBox(width: 8),
                _SelectionAction(
                  widgetKey: 'viewer-selection-note',
                  label: l10n.viewerNote,
                  onTap: () => _editNoteSelection(context),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // PURPOSE: Render a selection the way the musician counts — bars from the top of the chart and
  //          cells from the start of the bar, both one-based — while the model keeps zero-based
  //          indices. The conversion lives here so the label and the log cannot disagree silently.
  // INPUTS: song — the chart. hit — the selection, holding the model's zero-based address. l10n —
  //         the catalogue, because the two numbers are written into a sentence and the sentence is
  //         not the same in both languages.
  // OUTPUTS: The label. A null cell means the touch landed on the bar and not on a cell, which is
  //          stated rather than rounded to the nearest cell.
  // KEYWORDS: label-format, one-based, global-bar-ordinal, model-address
  String _selectionLabel(Song song, ChartHit hit, AppLocalizations l10n) {
    final int bar = _writtenBarOrdinal(song, hit.sectionId, hit.barIndex);
    final int? beat = hit.beat;
    return beat == null
        ? l10n.selectionBar(bar)
        : l10n.selectionBarCell(bar, beat + 1);
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

  /// The background of the strip that explains a FIT fallback.
  ///
  /// A warm band rather than the page's own white: the strip is a remark ABOUT the chart and must not
  /// read as part of it.
  static const Color _fitFallbackColor = Color(0xFFFFE9A8);

  /// The colour of the words on [_fitFallbackColor].
  static const Color _fitFallbackTextColor = Color(0xFF5A4300);

  // PURPOSE: Lay the displayed song out at the size the window gives it and show it as one fitted
  //          page or as a page at a time.
  // INPUTS: entry — the selected song, for identity. displayed — the chart to draw, in its chosen
  //         key. mode — the mode the musician asked for: FIT or PAGES. layer — the ink layer of the
  //         song on screen, which decides what a contact on a page means. strokes — the committed
  //         strokes of the WRITTEN document, which are placed by address and so are unaffected by
  //         the transposition on screen. textCues — the cues of the same document, placed by
  //         address for the same reason.
  // OUTPUTS: The chart. PAGES is the layout engine's ordinary pagination in a [PageView]. FIT is one
  //          scaled page when the song fits above the legible floor, and — when it does not — the
  //          SAME pagination with [_fitFallbackNotice] pinned over the top of it, because a floor
  //          the engine refuses to cross is a reason to paginate and not a reason to show nothing.
  //          The mode DRAWN is what `_pageGeometry` reports, so a driving tool measures the pages on
  //          screen rather than asking FIT again about a page that was never drawn. A song the
  //          layout engine produces no pages for says so instead of showing an empty page, because
  //          an empty song and a blank page must not look alike.
  // KEYWORDS: pagination, fit, fit-fallback, page-scale, layout-call, page-view, empty-song,
  //           legibility-message, fallback-notice, ink-layering, cue-layering, a50
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
        final AppLocalizations l10n = AppLocalizations.of(context);
        final double pageWidth = constraints.maxWidth;
        final double pageHeight = constraints.maxHeight;
        _lastPageSurface = Size(pageWidth, pageHeight);
        _lastPageMode = mode;
        if (!pageWidth.isFinite ||
            !pageHeight.isFinite ||
            pageWidth <= 0 ||
            pageHeight <= 0 ||
            displayed.writtenBarCount == 0) {
          return Center(child: Text(l10n.noBars));
        }
        if (mode == PageMode.fit) {
          final FitOutcome outcome = _engine.fitToPage(
            displayed,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            cues: textCues,
          );
          final PageLayout? page = outcome.page;
          if (page != null) {
            _lastPageScale = page.scale;
            return _tappablePage(page, displayed, layer, strokes, textCues);
          }
          // --- THE FIT FALLBACK -----------------------------------------------------------------
          // FIT could not put the song on one page above the legible floor, so the chart is shown
          // PAGINATED rather than left blank. The decision and the reasons behind it are recorded
          // beside [_fitFallbackNotice] and in `docs/sdd.md` A50; this is where it is carried out.
          final List<PageLayout> fallback = _engine.layout(
            displayed,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            cues: textCues,
          );
          if (fallback.isEmpty) {
            return Center(child: Text(l10n.noBars));
          }
          // The mode reported to `_pageGeometry` is the one DRAWN, so a driving tool re-engraves
          // the paginated pages it is actually looking at instead of asking FIT again and getting
          // an empty answer.
          _lastPageMode = PageMode.pages;
          _lastPageScale = fallback.first.scale;
          debugPrint(
            'viewer.page.fit.fallback song="${_rawTitleFor(entry)}" '
            'pane=${pageWidth.toStringAsFixed(0)}x${pageHeight.toStringAsFixed(0)} '
            'floor=${outcome.scale} pages=${fallback.length} '
            'bar0=${fallback.first.bars.length} '
            'requested=${_chosenPageMode == PageMode.fit ? 'explicit' : 'default'}',
          );
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PageView.builder(
                key: ValueKey<int>(entry.index),
                itemCount: fallback.length,
                itemBuilder: (BuildContext context, int index) => _tappablePage(
                  fallback[index],
                  displayed,
                  layer,
                  strokes,
                  textCues,
                ),
              ),
              // IGNORED BY THE POINTER, so the band states the substitution WITHOUT taking a contact
              // away from the page under it. The page's own contract is that a touch on its white
              // space — exactly where a musician may miss a bar — is reported and clears the
              // selection; a band that swallowed the page's top strip would break that contract in
              // the one mode where the page already has the least room.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: _fitFallbackNotice(context, outcome),
                ),
              ),
            ],
          );
        }
        final List<PageLayout> pages = _engine.layout(
          displayed,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          cues: textCues,
        );
        if (pages.isEmpty) {
          return Center(child: Text(l10n.noBars));
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

  // PURPOSE: Say WHY the chart is paginated when FIT was asked for and could not deliver, without
  //          taking the music off the screen — the strip states the substitution, the pages under it
  //          are the chart.
  // INPUTS: context — the build context, for the theme. outcome — the failed fit, whose [FitOutcome.scale]
  //         is the legible floor the engine refused to go below.
  // OUTPUTS: A one-to-three-line band pinned over the top of the chart area, saying that one page is
  //          impossible at the floor and that the chart is shown as pages. It is drawn OVER the page
  //          rather than above it: the chart area is the scarce resource that made the fallback
  //          necessary in the first place, and the top of a page is its empty margin, so a band here
  //          costs the music nothing. Returns a band whatever the surface; it never returns nothing,
  //          because a silent substitution would leave the musician unable to tell a chart that was
  //          too long from one they had asked to paginate.
  // KEYWORDS: fit, legibility-floor, on-screen-message, fallback-notice, overlay, honest-substitution
  //
  // THE DECISIONS THIS BAND CARRIES, and why each is the one it is:
  //
  //   THE FALLBACK IS AUTOMATIC. A musician who opened a chart wants the music, and making them
  //   press a control to be shown it is the same "no" the missing chart already was, in a slower
  //   form. The strip explains the substitution instead of asking for permission to make it.
  //
  //   THE MESSAGE IS NEVER DROPPED. A3x's message existed so the reader would know the chart had
  //   not silently been made small; the fallback must not throw that away. The floor is named, so
  //   the reader can tell a genuinely long tune from a window that is merely short.
  //
  //   AN EXPLICIT FIT PRESS IS ANSWERED IN THE SECOND PERSON. Pressing FIT is a decision, not a
  //   default, so it must be visible that the press was read and could not be honoured: the strip
  //   then opens with "You asked for one page". The rejected alternative — honouring the press by
  //   emptying the page again — is the defect this fallback exists to remove, so a press can change
  //   the explanation but never the outcome.
  Widget _fitFallbackNotice(BuildContext context, FitOutcome outcome) {
    final int percent = (outcome.scale * 100).round();
    // Kept to one line wherever the strip has the width for it, because the strip is pinned over the
    // page and every line it wraps to covers a little more of the music's own band. That is also why
    // the two sentences are TWO catalogue entries rather than one sentence with a clause removed:
    // a translator must be free to arrange "you asked for one page" and "it does not fit" as their
    // own language does, and stitching a translated fragment onto a translated head would fix the
    // English word order in place.
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String message = _chosenPageMode == PageMode.fit
        ? l10n.fitFallbackExplicit(percent)
        : l10n.fitFallbackAuto(percent);
    return Container(
      color: _fitFallbackColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: _fitFallbackTextColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // PURPOSE: State what is loaded, so the reader can tell a 22-song playlist from a single song
  //          without counting the list.
  // INPUTS: context — the build context.
  // OUTPUTS: A one-line status bar.
  // KEYWORDS: status-bar, summary, playlist-name
  Widget _buildStatusBar(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final IRealLibrary? library = _library;
    final String summary = library == null
        ? l10n.noFileLoaded
        : (library.isPlaylist
              ? l10n.statusSongsPlaylist(
                  library.songs.length,
                  library.playlistName,
                )
              : l10n.songCount(library.songs.length));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(summary, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

/// One named action beside the selection line, sized for a thumb and worded for the surface it
/// opens.
class _SelectionAction extends StatelessWidget {
  /// Creates an action labelled [label] that runs [onTap].
  const _SelectionAction({
    required this.widgetKey,
    required this.label,
    required this.onTap,
  });

  /// The widget key a driver test looks the action up by.
  final String widgetKey;

  /// The word on the action.
  final String label;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: sheetCellColor,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: ValueKey<String>(widgetKey),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: const TextStyle(
            color: sheetOnPanelColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
