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
import 'package:flutter/gestures.dart';
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
import 'pan_gesture.dart';
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
import 'two_finger_view_gesture.dart';
import 'ui_kit.dart';

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
  static const double _songRailWidth = UiKit.railWidth;

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

  /// Whether the library rail and the top block are hidden, giving their room to the document.
  ///
  /// OWNER DECISION: the rail and the top block hide TOGETHER, and one small always-visible button
  /// brings them back. Hiding them separately was rejected, as was hiding only the top block, and a
  /// GESTURE was rejected with them — which is why this is a button and not a swipe. D34 gives the
  /// page's own gestures to the pen (always writes) and to two fingers (pan and pinch), so a third
  /// gesture over the same glass would be a third thing competing for the same contacts, and the
  /// owner picked the control that needs none.
  ///
  /// It is NOT persisted: the chart is what is being read, and a surface that opened with the list
  /// gone and no obvious way to get it back would be a state the musician did not set on this run.
  bool _chromeHidden = false;

  /// Whether the musician has FIXED the view — the owner's «кнопка фиксирования масштаба».
  ///
  /// WHAT IT LOCKS, AND WHY THAT SET. The owner's own description of what he wants is
  /// «чтобы масштаб не уплывал» — the chart must stop changing size under his hand, at a music
  /// stand, while he is playing from it. Four things can change how big a chord is on this glass,
  /// measured on the tree rather than guessed: the two-finger pinch, the three `МАСШТАБ` controls,
  /// a change of page mode, and a change of the pane — a window resize, a rotation, or hiding the
  /// chrome. The lock covers ALL FOUR, and it does it by holding the NUMBER rather than by
  /// disabling the controls one at a time:
  ///
  ///   * the pinch and the drag are REFUSED — both of them, because the gesture that pinches also
  ///     pans, and a page that stops changing size but slides under the hand is half a lock;
  ///   * the three `МАСШТАБ` controls are DISABLED and say so, so a press cannot be mistaken for a
  ///     refused one;
  ///   * a page-mode change and a pane change are ALLOWED — refusing them would be refusing the
  ///     window — but they cannot change the size, because the DRAWN scale is held and the zoom is
  ///     re-derived from whatever the new engraving produced: `zoom = locked / scale`, clamped.
  ///
  /// The one thing the lock cannot do is make the chart SMALLER than the page mode's own smallest
  /// page: `PageLayout.withView` refuses a zoom below 1, because at 1 the page already fills the pane
  /// exactly, so a pane that grows while the lock is on can only grow the music. That is named where
  /// it happens — `viewer.view.lock.clamped` — rather than left to be discovered.
  bool _viewLocked = false;

  /// The drawn scale the lock is holding, in SURFACE pixels per page pixel, or null when unlocked.
  ///
  /// The DRAWN scale and not the zoom, because the zoom is relative to a page whose own scale changes
  /// with the pane and the page mode: locking a relative number would let every re-engrave move the
  /// music, which is the thing being locked. Null and [_viewLocked] are two facts rather than one
  /// because the lock can be on before a page has ever been drawn (a chart that is still loading).
  double? _lockedDrawnScale;

  /// The pan the lock is holding, in surface logical pixels, or zero when unlocked.
  LayoutOffset _lockedPan = LayoutOffset.zero;

  /// Whether the contact currently down on the page belonged to a two-finger gesture that the lock
  /// refused, so the refusal is logged once per gesture rather than once per move event.
  bool _viewGestureRefused = false;

  /// The pane size the last `viewer.page.pane` line reported, so it is logged on a CHANGE and not on
  /// every layout pass.
  ///
  /// The pane's height is the number hiding the chrome is FOR, and a number nobody can read off the
  /// running application is a claim rather than a measurement — see `_buildPages`.
  double _loggedPaneWidth = -1;
  double _loggedPaneHeight = -1;

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

  /// The OTHER end of the selection when the musician selected a RUN, or null for a single hit.
  ///
  /// A selection is an ADDRESS in the interface, not an entity of the document (D36), so it lives
  /// here and nowhere else: it is not stored in the `.chart` file, it is not an entry in the log and
  /// it cannot be undone. Two hits — an anchor and a focus — are the whole of it, and the run is
  /// DERIVED from them by [_selectionRange], so there is no second value that could disagree with the
  /// first about what is selected. Cleared with [_selection], for the same reason: a section id and a
  /// bar index name different music once a different song is shown.
  ChartHit? _selectionEnd;

  /// Whether the next tap finishes a run rather than starting a new selection.
  ///
  /// This is the state of the "until here" action in the selection line, and it is the only reason
  /// the second tap of a run means something different from the first: a musician presses the word,
  /// the line says what the next tap will do, and the tap names the other end. It is not a mode that
  /// survives the tap that uses it.
  bool _extendPending = false;

  /// What the copy action took, or null before anything was copied.
  ///
  /// Interface state, like the selection: copying writes no event, so this is not in the document and
  /// not in the log. It is what the paste action reads. It is deliberately NOT cleared when a
  /// different song or library is shown: a clipboard is not part of the document, and pasting bars
  /// copied from one chart into another is a legal edit on ordinary [Bar] values — the paste names
  /// its own section, and the ink it carries is re-anchored to the bars it lands on.
  ChartClip? _clip;

  /// The result of the last action on the selection, as words, for the line beside the chart.
  ///
  /// One sentence, built from the catalogue when the action ran, so it can name what happened
  /// ("pasted after bar 20", "moved up a semitone: 4 of 16 bars") instead of leaving the musician to
  /// work it out from the picture. Cleared whenever the selection changes, because a message about a
  /// selection that no longer exists is a lie.
  String? _selectionStatus;

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

  /// The musician's own magnification of the chart, at or above 1 and at most `PageLayout.maxZoom`.
  ///
  /// Owner decision D34 gives the view gesture to two fingers and a pinch; D33 also asks for a way
  /// to zoom from the interface, so the scene bar carries three controls that write here. The zoom
  /// is a VIEW and not an engraving: the page is laid out once for the pane and this is how it is
  /// drawn, so the same value applies to whichever page of a paginated chart is on screen.
  double _viewZoom = 1;

  /// The musician's own pan of the chart, in chart-pane logical pixels.
  ///
  /// It is the same space a pointer event's `localPosition` arrives in, which is what makes the
  /// pan gesture's arithmetic and `PageLayout.pagePointOf`'s inverse one pair rather than two. It
  /// is CLAMPED by `PageLayout.withView` on every build, so the page can never be dragged off the
  /// pane: the musician cannot lose the music.
  LayoutOffset _viewPan = LayoutOffset.zero;

  /// A sample of the two-finger gesture in progress, or null when none is.
  ///
  /// The start of a gesture is the reference the whole gesture is measured from: the zoom it began
  /// at, the pan it began at, and the focal point the page must stay under. Keeping them in one
  /// place means the update arithmetic is a function of the gesture and not of the frames in
  /// between, which is what stops a slow drag accumulating a drift.
  _ViewGestureAnchor? _viewGesture;

  /// Whether the two-finger gesture is currently in force, as told to the ink layer.
  ///
  /// It is kept here as well as on the layer because '_onPageTapUp' has to know whether a contact
  /// belongs to the gesture before it decides to select, and asking the layer for its own flag would
  /// be the same fact read from two objects. The layer is told once per transition.
  bool _viewGestureActive = false;

  /// The pan the one-contact pan gesture began at, in pane pixels, or null when none is running.
  ///
  /// The START value rather than the previous frame's, because every update is then a function of
  /// the whole gesture: a moved page whose pan the clamp has already eaten cannot make the next
  /// update drift, and the log can state the total travel of the gesture rather than a sum of
  /// per-frame numbers that nobody can check.
  LayoutOffset? _panFrom;

  /// How far the admitted pan has travelled in total, and how many samples it took.
  ///
  /// Reported once at the end of the gesture, because a line per move would be the flood A64's palm
  /// rule was written to avoid and because the number a report needs is the total, not the samples.
  LayoutOffset _panTravel = LayoutOffset.zero;
  int _panMoves = 0;

  /// The engraving the last build produced, and the inputs it was produced from.
  ///
  /// WHY A CACHE IS NOW NEEDED, IN A30's OWN WORDS. A30 recorded the cost and predicted this: the
  /// FIT search is up to 24 layout passes and nothing was cached because nothing rebuilt the page
  /// per frame. A two-finger pan DOES rebuild per frame, and a rebuild that re-engraved would pay
  /// the whole of that search for a move that changes only where the page is drawn. The key holds
  /// every input the engraving depends on — the mode, the pane, the song and the cues — so a miss
  /// is a real change and a hit is exactly the same page.
  _EngravingKey? _engravedKey;

  /// The pages the last engraving produced, shared by every frame of a pan.
  _Engraving? _engraved;

  /// The page the last frame actually drew, with the view applied.
  ///
  /// It is what the gesture arithmetic clamps against, because clamping needs the page's own size
  /// and scale and those are properties of the engraving, not of the view. It is assigned during
  /// build and read from a pointer handler, exactly as [_lastPageScale] and [_lastPageSurface] are
  /// and for the same reason: the layout that produced it is out of scope by then.
  PageLayout? _lastDrawnPage;

  /// What the view belongs to: the song on screen and the page mode it is being read in.
  ///
  /// Read during build, and a change resets the zoom and the pan. Doing it here rather than at each
  /// of the several places a song can change — the list, the drawer, the programme, an opened file —
  /// is what keeps the two from drifting: the question "is this a different chart?" has one answer
  /// and it is the identity of what is being drawn.
  Object? _viewOwner;

  /// The last probe state published, so a rebuild that changes nothing writes nothing.
  String? _publishedInkState;

  /// What the pen path has cost during the stroke in progress.
  ///
  /// The page is re-laid-out whenever this screen rebuilds, and this screen used to rebuild on every
  /// pointer sample: `fitToPage`/`layout` then ran once per sample, over the whole song, with the
  /// melody band making each system taller. That is a claim about a cost, so it is MEASURED here and
  /// written to the log as a number rather than left to be inferred from the code — the whole reason
  /// this field exists. See [_PenPathCost] for what each number means.
  final _PenPathCost _penCost = _PenPathCost();

  /// Whether the previous move sample was one the ink layer was drawing, so the cost counters are
  /// reset at the first sample of a stroke and not in the middle of one.
  bool _penWasDrawing = false;

  /// How many times the ink layer had written to the operation log the last time this screen showed
  /// the result, so a lift can tell whether the page it drew is out of date.
  ///
  /// IT IS NEEDED BECAUSE A GESTURE THAT MOVED IS NOT A TAP. The tap handler is where this screen
  /// used to learn that the document had changed, and it is not called for a stroke that travelled
  /// or for an eraser drag — which are exactly the gestures the ink layer produces now. The layer
  /// counts what it wrote and this compares the count at the lift, once per contact, so the undo
  /// control and the selection line follow an erasure that no double-tap recogniser saw.
  int _shownDocumentEdits = 0;

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

  // PURPOSE: Report whether the SELECT tool is in force — the mode in which a contact neither writes
  //          nor erases but NAMES something, and in which a drag may therefore move the sheet.
  // INPUTS: None; reads the two tool modes of the layer of the selected song.
  // OUTPUTS: True when neither the pen nor the eraser is on. A build with no layer answers true,
  //          which is harmless: nothing can be panned before a page exists, and [_refusePan] says so
  //          by name rather than by a silent false.
  //
  //          WHY THIS IS A TOOL AND NOT AN ABSENCE. The ink layer's third mode is called `off` in the
  //          model because in the model it is the absence of a writing tool; to a musician it is the
  //          tool that SELECTS, and the mode is reached by a named button and named in the selection
  //          line. [refusePan] hangs the one-contact pan on exactly this mode, because with the pen
  //          on a single contact is a stroke (A61) and a drag cannot mean two things at once.
  // KEYWORDS: select-tool, ink-mode-off, pan-owner, one-tool-at-a-time, d34-compatible
  bool get _selectTool => !_inkOn && !_eraserOn;

  /// Whether recognition is switched on for the chart on screen.
  ///
  /// OFF UNTIL THIS SESSION TURNS IT ON, which is the owner's rule 1 for recognition (D37): a
  /// musician whose recognition works badly turns it off and keeps working, and every musician
  /// starts there. It is deliberately NOT persisted: a preference nobody asked to keep would make
  /// "the switch is off after a restart" impossible, and the rule that matters is that the app never
  /// reads a chart it was not asked to read. See [IRealViewerScreen._toggleRecognition].
  bool _recognitionOn = false;

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
            // The address is the bar and the position inside it is the offset: there is no beat to
            // report, because a cue is a coordinate now and `dx` is that coordinate.
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
    final PageLayout page = pages.first.withView(
      zoom: _viewZoom,
      pan: _viewPan,
    );
    final double drawn = page.drawnScale;
    return <String, Object?>{
      'page': page.index,
      'mode': mode.name,
      // THE PAGE MODE'S SCALE AND THE MUSICIAN'S VIEW ARE REPORTED SEPARATELY, and the product is
      // reported too, so a verification can tell "the chart was fitted" from "the musician zoomed"
      // without re-deriving either. A surface position is `cell * drawn_scale + pan`, which is what
      // the cell centres below are.
      'scale': page.scale,
      'zoom': page.zoom,
      'pan': <double>[page.pan.x, page.pan.y],
      'drawn_scale': drawn,
      'surface': <double>[page.size.width * drawn, page.size.height * drawn],
      'cells': <Object?>[
        for (final PlacedBar bar in page.bars)
          for (final PlacedCell cell in bar.cells)
            <String, Object?>{
              'sec': bar.sectionId,
              'bar': bar.barIndex,
              'beat': cell.beat,
              // WHERE THE CELL LANDED ON THE SURFACE, through the page's own forward transform —
              // the same function [PageLayout.pagePointOf] inverts, so a driver that aims at these
              // numbers is aiming through the pen's own arithmetic rather than through a second
              // copy of it.
              'x': page
                  .surfacePointOf(
                    LayoutOffset(
                      cell.bounds.left + cell.bounds.size.width / 2,
                      cell.bounds.top + cell.bounds.size.height / 2,
                    ),
                  )
                  .x,
              'y': page
                  .surfacePointOf(
                    LayoutOffset(
                      cell.bounds.left + cell.bounds.size.width / 2,
                      cell.bounds.top + cell.bounds.size.height / 2,
                    ),
                  )
                  .y,
              // The cell's rectangle in the page's engraved coordinates, so a driver can also ask
              // what the hit test should answer for a point rather than only where to put a finger.
              'page_rect': <double>[
                cell.bounds.left,
                cell.bounds.top,
                cell.bounds.size.width,
                cell.bounds.size.height,
              ],
            },
      ],
    };
  }

  // PURPOSE: Put the musician's view on the page being drawn, so the whole screen — the chart, the
  //          words, the ink and the two-finger gesture — agrees about one transform.
  // INPUTS: raw — the page as the layout engine produced it, with an identity view.
  // OUTPUTS: The same page with the view applied and both clamped, so the drawn page always covers
  //          the pane. The clamp is not repeated here: it is `PageLayout`'s, and the gesture
  //          arithmetic reads its result back from [_lastDrawnPage].
  //
  //          WHILE THE VIEW IS LOCKED THE ZOOM IS NOT READ FROM THE STATE AT ALL — it is DERIVED, as
  //          the ratio between the scale the lock captured and the scale this engraving produced.
  //          That is what makes the lock survive the two changes it cannot refuse: a different page
  //          mode and a different pane both re-engrave the chart at a new `raw.scale`, and a stored
  //          zoom would then draw the music at a new size. Deriving it means there is no second place
  //          a size could come from, and the clamp is still the page's — so a pane that grows while
  //          the lock is on cannot shrink the music below the mode's own page, and the fact is logged
  //          rather than left to surprise a musician at the stand.
  // KEYWORDS: view-application, single-transform, clamps, d34, view-lock, derived-zoom
  /// Returns [raw] with the current view applied.
  PageLayout _viewed(PageLayout raw) {
    final double? locked = _lockedDrawnScale;
    final PageLayout viewed;
    if (locked == null) {
      viewed = raw.withView(zoom: _viewZoom, pan: _viewPan);
    } else {
      final double wanted = raw.scale > 0 ? locked / raw.scale : 1;
      final double zoom = _clampZoom(wanted);
      if ((zoom - wanted).abs() > 0.0005) {
        _lockedClampedReason = 'zoom below 1: the page would not fill the pane';
      } else {
        _lockedClampedReason = null;
      }
      viewed = raw.withView(zoom: zoom, pan: _lockedPan);
    }
    _lastDrawnPage = viewed;
    return viewed;
  }

  /// Why the lock could not hold the scale on the frame that was just drawn, or null when it did.
  ///
  /// It is a field rather than a log line printed from [_viewed] because that method runs inside a
  /// build and this project has already paid once for putting an instrument on a path that runs every
  /// frame; the reason is reported by `_buildPages`'s own size-change line, which runs once per change.
  String? _lockedClampedReason;

  // PURPOSE: Fix the scale the chart is drawn at, or release it, and leave the chart where it is
  //          either way.
  // INPUTS: None.
  // OUTPUTS: Nothing. Locking captures the drawn scale and the pan of the page currently on screen;
  //          releasing hands those back to the view state, so the chart does not move when the lock is
  //          turned off — a lock whose release jumps the page would be a control a musician learns not
  //          to touch, and this one is meant to be turned on and off at the stand.
  //
  //          THE LOCK IS NOT PERSISTED, for the reason the hidden chrome is not: it is a decision made
  //          about the page in front of him, and an application that opened with the scale fixed would
  //          be one whose zoom controls do not answer on the first press.
  // KEYWORDS: view-lock, capture, release-without-jump, not-persisted, owner-request, scale-fixed
  void _toggleViewLock() {
    final PageLayout? drawn = _lastDrawnPage;
    // A CHART WITH NO PAGE YET IS STILL LOCKABLE: the scale it will be drawn at is the page mode's own
    // (`_lastPageScale`), and a musician who pressed the lock on the frame a chart appeared meant it.
    // The fallback is the identity, which is what the page will be drawn at first.
    final double scaleNow =
        drawn?.drawnScale ?? (_lastPageScale > 0 ? _lastPageScale : 1);
    final LayoutOffset panNow = drawn?.pan ?? _viewPan;
    setState(() {
      if (_viewLocked) {
        if (drawn != null) {
          // The stored view becomes the view that is on the glass, so releasing the lock is not a
          // change of magnification in either direction.
          _viewZoom = drawn.zoom;
          _viewPan = drawn.pan;
        }
        _viewLocked = false;
        _lockedDrawnScale = null;
        _lockedPan = LayoutOffset.zero;
      } else {
        _viewLocked = true;
        _lockedDrawnScale = scaleNow;
        _lockedPan = panNow;
      }
    });
    debugPrint(
      'viewer.view.lock locked=$_viewLocked '
      'scale=${_lockedDrawnScale?.toStringAsFixed(4) ?? 'released'} '
      'zoom=${(_lastDrawnPage?.zoom ?? _viewZoom).toStringAsFixed(4)} '
      'pan=(${(_lastDrawnPage?.pan ?? _viewPan).x.toStringAsFixed(1)},'
      '${(_lastDrawnPage?.pan ?? _viewPan).y.toStringAsFixed(1)}) '
      'mode=${_lastPageMode?.name ?? 'none'}',
    );
  }

  /// The magnification the chart is actually drawn at, which is what the scene bar reports.
  ///
  /// The locked view derives its zoom from the engraving, so the stored `_viewZoom` can differ from
  /// what is on the glass; a reading that showed the stored number would tell a musician the chart is
  /// at 1.0 while it is drawn at 1.4.
  double get _effectiveZoom => _lastDrawnPage?.zoom ?? _viewZoom;

  // PURPOSE: The one control that fixes the scale, drawn in every shell form and in both chrome
  //          states — so a lock can never be ON in a state where nothing says so.
  // INPUTS: context — the build context.
  // OUTPUTS: An [IconButton] showing a closed lock while the view is fixed and an open one while it is
  //          free. It is disabled while no chart is on screen: there is no page to fix, and a control
  //          that can be pressed into a state with no meaning is a control that teaches nothing.
  // KEYWORDS: view-lock, always-visible, two-states, disabled-without-chart, one-definition
  Widget _viewLockToggle(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey<String>('viewer-view-lock'),
      icon: Icon(_viewLocked ? Icons.lock : Icons.lock_open),
      isSelected: _viewLocked,
      tooltip: _viewLocked ? l10n.tooltipViewLockOn : l10n.tooltipViewLockOff,
      onPressed: _currentSession == null ? null : _toggleViewLock,
    );
  }

  // PURPOSE: Hold a requested magnification inside the range the view allows, so that arithmetic
  //          which depends on the zoom agrees with the page that is finally stored.
  // INPUTS: zoom — a requested magnification, possibly below 1, above the cap, or non-finite.
  // OUTPUTS: A value in `[1, PageLayout.maxZoom]`. A non-finite request becomes the identity rather
  //          than being propagated, because a page drawn at NaN is invisible rather than
  //          wrong-looking.
  //
  //          WHY THIS EXISTS RATHER THAN LETTING `PageLayout.withView` CLAMP AT THE END. The zoom is
  //          clamped there too, but a caller that had already computed a PAN from the unclamped
  //          number would keep a pan belonging to a magnification the view never took, so the chart
  //          jumps sideways on the step that crosses the cap. That was measured: a sequence of
  //          zoom-in steps past four moved the page's centre from the middle of the pane to (74, 68)
  //          of it, and the widget test in `view_transform_test.dart` now aims at the page's centre
  //          precisely so that such a jump cannot hide.
  // KEYWORDS: zoom-clamp, single-source, pan-depends-on-zoom, no-jump, d34
  static double _clampZoom(double zoom) {
    if (!zoom.isFinite || zoom <= 1) {
      return 1;
    }
    return zoom > PageLayout.maxZoom ? PageLayout.maxZoom : zoom;
  }

  // PURPOSE: Move the view to a zoom and pan, keeping the pan legal, and rebuild.
  // INPUTS: zoom — the requested magnification. pan — the requested offset in pane pixels.
  // OUTPUTS: Nothing. Both are clamped through the page that is on screen, so the stored view is
  //          the view that is DRAWN: a gesture that started from a stored-but-clamped value would
  //          accumulate a difference between what the musician sees and what the next gesture
  //          measures from. When no page has been drawn yet the values are stored unclamped and the
  //          first build clamps them.
  // KEYWORDS: view-state, zoom, pan, clamp-through-page, rebuild, d34
  void _setView({required double zoom, required LayoutOffset pan}) {
    final PageLayout? reference = _lastDrawnPage;
    if (reference == null) {
      setState(() {
        _viewZoom = zoom;
        _viewPan = pan;
      });
      return;
    }
    final PageLayout clamped = reference.withView(zoom: zoom, pan: pan);
    setState(() {
      _viewZoom = clamped.zoom;
      _viewPan = clamped.pan;
    });
  }

  // PURPOSE: Return the chart to the view its page mode gives it, which is how the musician gets
  //          back to a known place after panning and zooming.
  // INPUTS: None.
  // OUTPUTS: Nothing. Zoom becomes 1 and the pan becomes zero, and the page is clamped by the next
  //          build rather than here, because at zoom 1 the only legal pan is zero anyway.
  //
  //          WHY THIS IS THE "FIT" OF THE VIEW AND NOT A PAGE MODE. The page mode says how the
  //          chart is ENGRAVED and the view says where the musician is looking at it; a reset that
  //          changed the mode would answer a question the musician did not ask. At zoom 1 the drawn
  //          page is exactly the pane again, which is the state the mode chose for it.
  // KEYWORDS: view-reset, fit-the-view, known-view, get-back, d33, d34
  void _resetView() {
    if (_viewLocked) {
      debugPrint('viewer.view.lock.refuse source=reset_button');
      return;
    }
    if (_viewZoom == 1 && _viewPan == LayoutOffset.zero) {
      // Said out loud rather than silently ignored: a press that does nothing must be
      // distinguishable in the log from a press that was never delivered.
      debugPrint('viewer.view.reset already_at_identity');
      return;
    }
    debugPrint(
      'viewer.view.reset from_zoom=${_viewZoom.toStringAsFixed(3)} '
      'from_pan=(${_viewPan.x.toStringAsFixed(1)},${_viewPan.y.toStringAsFixed(1)})',
    );
    _setView(zoom: 1, pan: LayoutOffset.zero);
  }

  // PURPOSE: Step the magnification by one factor about the middle of what is on screen, or about a
  //          named point, so the scene bar's two buttons are a usable interface path to the zoom
  //          that D33 asks for beside the pinch.
  // INPUTS: factor — the multiplier, above 1 to zoom in and below 1 to zoom out. about — the point
  //         in pane pixels to keep still, or null for the pane's own centre.
  // OUTPUTS: Nothing. A step that would leave the range is clamped rather than refused, so a button
  //          held down stops at the end of the range instead of fighting the hand — and the CLAMP
  //          HAPPENS BEFORE THE PAN IS COMPUTED FROM IT, so the step that reaches the cap keeps the
  //          point it was zooming about exactly where it was.
  // KEYWORDS: zoom-button, interface-path, zoom-about-point, clamped-step, d33
  void _zoomBy(double factor, {Offset? about}) {
    final Size pane = _lastPageSurface;
    if (pane.isEmpty) {
      return;
    }
    // THE LOCK IS CHECKED HERE AS WELL AS IN THE DISABLED BUTTON, because a control's enabled state
    // is a property of the frame it was built in: a press that arrives in the frame after the lock
    // was set would otherwise change the scale through a button that was drawn enabled. The buttons
    // are the interface; this is the rule.
    if (_viewLocked) {
      debugPrint(
        'viewer.view.lock.refuse source=zoom_button factor=$factor '
        'locked_scale=${_lockedDrawnScale?.toStringAsFixed(4) ?? 'none'}',
      );
      return;
    }
    final Offset centre = about ?? Offset(pane.width / 2, pane.height / 2);
    final double base = _lastPageScale <= 0 ? 1 : _lastPageScale;
    final double fromDrawn = base * _viewZoom;
    final double zoom = _clampZoom(_viewZoom * factor);
    final double toDrawn = base * zoom;
    // The page point under the button's target stays under it, so a zoom is a change of scale and
    // not a jump to another part of the tune.
    final LayoutOffset pageUnderPoint = LayoutOffset(
      (centre.dx - _viewPan.x) / fromDrawn,
      (centre.dy - _viewPan.y) / fromDrawn,
    );
    debugPrint(
      'viewer.view.zoom from=${_viewZoom.toStringAsFixed(3)} '
      'to=${zoom.toStringAsFixed(3)} about=(${centre.dx.toStringAsFixed(1)},'
      '${centre.dy.toStringAsFixed(1)})',
    );
    _setView(
      zoom: zoom,
      pan: LayoutOffset(
        centre.dx - pageUnderPoint.x * toDrawn,
        centre.dy - pageUnderPoint.y * toDrawn,
      ),
    );
  }

  // PURPOSE: Begin the two-finger view gesture, recording the reference every later sample is
  //          measured from.
  // INPUTS: sample — the focal point and span of the two touches that started it.
  // OUTPUTS: Nothing. The ink layer is told that the gesture owns the contacts, which is what stops
  //          the first of the two fingers from becoming a stroke; the reference is kept so that an
  //          update is a function of the gesture rather than of the frames in between.
  // KEYWORDS: view-gesture-start, gesture-anchor, ink-suppression, d34
  void _onViewGestureStart(TwoFingerViewSample sample) {
    // A GESTURE THAT CANNOT MOVE ANYTHING DOES NOT START. Refusing it at the START rather than at
    // every sample is what keeps the refusal off the contact path: a pinch is ~60 move events, and a
    // log line per event on the gesture that fires while a musician writes is the flood A64's palm
    // rule was written to avoid. The contacts are still marked as the gesture's, so the first of the
    // two fingers cannot become a stroke either.
    if (_viewLocked) {
      if (!_viewGestureRefused) {
        _viewGestureRefused = true;
        debugPrint(
          'viewer.view.lock.refuse source=two_finger pointers=${sample.pointerCount} '
          'locked_scale=${_lockedDrawnScale?.toStringAsFixed(4) ?? 'none'}',
        );
      }
      _viewGestureActive = true;
      _activeInkLayer?.setViewGestureActive(true);
      return;
    }
    _viewGesture = _ViewGestureAnchor(
      zoom: _viewZoom,
      pan: _viewPan,
      focal: sample.focal,
      span: sample.span,
      pageScale: _lastPageScale <= 0 ? 1 : _lastPageScale,
    );
    if (_viewGestureActive) {
      return;
    }
    _viewGestureActive = true;
    _activeInkLayer?.setViewGestureActive(true);
    debugPrint(
      'viewer.view.gesture start zoom=${_viewZoom.toStringAsFixed(3)} '
      'span=${sample.span.toStringAsFixed(1)} '
      'focal=(${sample.focal.dx.toStringAsFixed(1)},'
      '${sample.focal.dy.toStringAsFixed(1)}) pointers=${sample.pointerCount}',
    );
  }

  // PURPOSE: Apply one sample of the two-finger gesture: a translation of the focal point pans, a
  //          change of span zooms, and the page point that was under the fingers at the start stays
  //          under them throughout.
  // INPUTS: sample — the current focal point and span.
  // OUTPUTS: Nothing. A sample with fewer than two touches is ignored, because one finger is not
  //          this gesture; a sample whose start span was degenerate (two touches exactly on top of
  //          each other) pans without zooming rather than dividing by zero.
  // KEYWORDS: pan-zoom-update, focal-hold, span-ratio, degenerate-span, d34
  void _onViewGestureUpdate(TwoFingerViewSample sample) {
    final _ViewGestureAnchor? anchor = _viewGesture;
    if (anchor == null || sample.pointerCount < 2) {
      return;
    }
    final double factor = anchor.span > 0 ? sample.span / anchor.span : 1;
    // A degenerate span (two touches exactly on top of one another) or a non-finite ratio must not
    // reach the page: a page drawn at NaN is invisible rather than wrong-looking, which is the
    // failure hardest to attribute to a gesture. The CLAMP COMES BEFORE THE PAN IS DERIVED FROM THE
    // ZOOM, so a pinch that runs past the cap does not carry a pan belonging to a scale the view
    // never took — see [_clampZoom].
    final double zoom = _clampZoom(anchor.zoom * factor);
    final double fromDrawn = anchor.pageScale * anchor.zoom;
    final LayoutOffset pageUnderFocal = LayoutOffset(
      (anchor.focal.dx - anchor.pan.x) / fromDrawn,
      (anchor.focal.dy - anchor.pan.y) / fromDrawn,
    );
    final double toDrawn = anchor.pageScale * zoom;
    _setView(
      zoom: zoom,
      pan: LayoutOffset(
        sample.focal.dx - pageUnderFocal.x * toDrawn,
        sample.focal.dy - pageUnderFocal.y * toDrawn,
      ),
    );
  }

  // PURPOSE: End the two-finger view gesture and hand the contacts back to the tools.
  // INPUTS: None.
  // OUTPUTS: Nothing. The reference is dropped and the ink layer is told that a contact may draw
  //          again, which happens on the lift of the last finger — not on the lift of the first,
  //          because the remaining finger is still part of the gesture and must not begin a stroke.
  // KEYWORDS: view-gesture-end, ink-handback, last-finger, d34
  void _onViewGestureEnd() {
    _viewGesture = null;
    if (!_viewGestureActive) {
      return;
    }
    final bool wasRefused = _viewGestureRefused;
    _viewGestureRefused = false;
    _viewGestureActive = false;
    _activeInkLayer?.setViewGestureActive(false);
    debugPrint(
      'viewer.view.gesture end zoom=${_viewZoom.toStringAsFixed(3)} '
      'pan=(${_viewPan.x.toStringAsFixed(1)},${_viewPan.y.toStringAsFixed(1)})'
      '${wasRefused ? ' refused=view_locked' : ''}',
    );
  }

  // PURPOSE: Answer whether ONE contact may pan the sheet right now, and name the reason when it may
  //          not — so that "the document did not move" is attributable in the log instead of being a
  //          silence the reader has to interpret.
  // INPUTS: None; reads the tool in force, the view lock, the magnification drawn and the pane.
  // OUTPUTS: Null when a pan may start, otherwise one of three stable tokens:
  //          `tool-writes` (the pen or the eraser is on, so a drag is a stroke or an erasure),
  //          `view-locked` (the musician fixed the scale and asked nothing to move it), or
  //          `nothing-to-pan` (the drawn page already fills the pane, so every pan would be clamped
  //          to zero — and the drag is left to the pager, which is what keeps page turning alive).
  //
  //          `nothing-to-pan` IS A REAL ANSWER AND NOT A FAILURE. `PageLayout.withView` clamps the
  //          pan to `[viewport - content, 0]`, which is zero at zoom 1: a pan admitted here would
  //          move nothing while taking the gesture away from the page turn. Owner decision D33 gives
  //          the musician a zoom for exactly this reason, and the two zoom controls stand in the
  //          scene bar beside the number this method reads.
  // KEYWORDS: pan-admission, refusal-token, tool-gate, view-lock, nothing-to-pan, page-turn-kept
  String? _refusePan() {
    if (!_selectTool) {
      return 'tool-writes';
    }
    if (_viewLocked) {
      return 'view-locked';
    }
    final PageLayout? drawn = _lastDrawnPage;
    if (drawn == null) {
      return 'nothing-to-pan';
    }
    // The page is drawn at `scale * zoom`, and the surface it was engraved for is `size * scale`.
    // Anything at zoom 1 therefore has no slack on either axis.
    if (drawn.zoom <= 1) {
      return 'nothing-to-pan';
    }
    return null;
  }

  // PURPOSE: Begin a one-contact pan, recording the view it started from so every update is measured
  //          from the same place.
  // INPUTS: None.
  // OUTPUTS: Nothing. The reference is kept and the start is logged with the view it began at.
  // KEYWORDS: pan-start, gesture-anchor, view-state, d34-compatible
  void _onPagePanStart() {
    _panFrom = _viewPan;
    _panTravel = LayoutOffset.zero;
    _panMoves = 0;
    debugPrint(
      'viewer.pan.start tool=select zoom=${_viewZoom.toStringAsFixed(3)} '
      'pan=(${_viewPan.x.toStringAsFixed(1)},${_viewPan.y.toStringAsFixed(1)}) '
      'pane=(${_lastPageSurface.width.toStringAsFixed(1)},'
      '${_lastPageSurface.height.toStringAsFixed(1)})',
    );
  }

  // PURPOSE: Move the sheet by one sample of the admitted pan.
  // INPUTS: delta — how far the contact travelled since the previous sample, in pane pixels.
  // OUTPUTS: Nothing; the view is set from the pan the gesture STARTED at plus the travel so far, so
  //          the arithmetic cannot drift and the clamp cannot accumulate an error. A paused or
  //          clamped page simply stops; the gesture keeps its reference.
  // KEYWORDS: pan-update, clamp-safe, no-drift, view-set, measured-travel
  void _onPagePanUpdate(Offset delta) {
    final LayoutOffset from = _panFrom ?? _viewPan;
    _panMoves++;
    _panTravel = LayoutOffset(_panTravel.x + delta.dx, _panTravel.y + delta.dy);
    _setView(
      zoom: _viewZoom,
      pan: LayoutOffset(from.x + _panTravel.x, from.y + _panTravel.y),
    );
  }

  // PURPOSE: End the one-contact pan and report what it did, so the sheet's movement is a number in
  //          the log rather than an impression from a screenshot.
  // INPUTS: None.
  // OUTPUTS: Nothing. The start reference is dropped; the end is logged with the pan it began at, the
  //          pan it ended at, the total travel and the number of samples, which is what makes "the
  //          document moves" checkable by anyone reading the log.
  // KEYWORDS: pan-end, measured-travel, structured-log, view-state
  void _onPagePanEnd() {
    final LayoutOffset? from = _panFrom;
    _panFrom = null;
    debugPrint(
      'viewer.pan.end moves=$_panMoves '
      'dx=${_panTravel.x.toStringAsFixed(1)} dy=${_panTravel.y.toStringAsFixed(1)} '
      'from=(${from?.x.toStringAsFixed(1) ?? '0.0'},'
      '${from?.y.toStringAsFixed(1) ?? '0.0'}) '
      'to=(${_viewPan.x.toStringAsFixed(1)},${_viewPan.y.toStringAsFixed(1)})',
    );
  }

  // PURPOSE: Report a drag that was refused a pan, once per contact, so that a musician's drag which
  //          produced neither ink nor movement has a line saying which rule stopped it.
  // INPUTS: reason — the stable token [_refusePan] returned.
  // OUTPUTS: Nothing. One line per declined drag, never per move: a declined drag continues to send
  //          moves, and only the first decision is reported.
  // KEYWORDS: pan-refused, instrumented-decision, cheap-once, attributable-inaction
  void _onPagePanRefused(String reason) {
    debugPrint(
      'viewer.pan.refused reason=$reason tool=$_toolToken '
      'zoom=${_viewZoom.toStringAsFixed(3)} locked=$_viewLocked',
    );
  }

  /// The tool in force, as one stable token for a log line.
  ///
  /// Written from the same three getters the buttons read, so the log cannot disagree with the bar
  /// about which tool a press of the pen or the eraser left in force.
  String get _toolToken {
    if (_inkOn) {
      return 'pen';
    }
    if (_eraserOn) {
      return 'eraser';
    }
    return 'select';
  }

  /// Whether the verification state was changed while the pen was down and is owed a publication.
  ///
  /// A flag rather than a direct write, because the write is the thing this class stopped doing on
  /// the pen path: the state is published by the next frame that is built with no contact drawing,
  /// and this is what tells that frame the work is there to do.
  bool _inkPublishOwed = false;

  // PURPOSE: Publish the verification state, but only from a frame in which no contact is drawing,
  //          so that a cost proportional to the ink on the page is never paid on the thread that
  //          reads the pen.
  //
  //          THE WORK IS MOVED AND NOT DROPPED, AND THIS METHOD IS THE WHOLE OF THAT CLAIM. The
  //          publication is a one-way convenience for a tool inspecting the page; nothing in the
  //          application reads it back, so no behaviour depends on when it happens — but a tool that
  //          reads it after a stroke must still see the committed stroke, and it does: the lift
  //          resumes the build that carries it, and the build calls this. What was removed from the
  //          pen path is only the O(ink) serialisation that used to run inside a stroke, and the
  //          interval that bounded it is gone with it.
  // INPUTS: None. The owed flag is set by [_onPagePointerMove] while a contact is drawing, and the
  //         ink layer is asked whether a contact still is.
  // OUTPUTS: Nothing. Returns without publishing when no change is owed or a contact is still down,
  //          which is what makes the call safe from every frame; otherwise publishes through
  //          [_publishInkState] and charges the time to [_PenPathCost]. Note that the charge lands on
  //          whichever stroke's report is open when the publication finally runs, so `publish_ms`
  //          reads zero throughout a stroke by construction.
  // KEYWORDS: verification-handoff, publish-when-idle, pen-starvation, latency, deferred-work
  void publishInkStateWhenIdle() {
    if (!_inkPublishOwed || (_activeInkLayer?.isDrawingInk ?? false)) {
      return;
    }
    _inkPublishOwed = false;
    final Stopwatch publishing = Stopwatch()..start();
    _publishInkState();
    _penCost.notePublish(publishing.elapsedMicroseconds);
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
        _selectionEnd = null;
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
      _selectionEnd = null;
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
    // The call is a no-op on every target without a browser, a no-op here when no change is owed, and
    // — since the pen path no longer publishes — a no-op while a contact is still drawing, which is
    // what keeps an O(ink) serialisation off the thread that reads the pen.
    publishInkStateWhenIdle();
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
    final bool chrome = !_chromeHidden;
    // THE CHART'S OWN NAME IS THE BAR'S TITLE, WHICH IS WHY THERE IS NO SECOND TITLE ROW. The bar
    // used to carry the application's name — a fact the musician already knows, since he opened it —
    // and the chart's name sat in a row of its own below, so the top of the screen began with two
    // titles, one of which said nothing, and 36 logical pixels of chart height went with it.
    final int songIndex = library == null || library.songs.isEmpty
        ? -1
        : (_selectedSong >= 0 && _selectedSong < library.songs.length
              ? _selectedSong
              : 0);
    final IRealSong? entry = songIndex < 0 ? null : library!.songs[songIndex];
    final Widget? issue = _buildIssueAction(context, entry);
    return Scaffold(
      // THE APP BAR IS THE TOP BLOCK'S FIRST HALF, and hiding the chrome replaces it rather than
      // removing it: the document tools live here on a tablet, and a hidden state that took the pen
      // and the eraser away would be a state a musician writing cannot get out of without leaving
      // the page. What goes is everything that does not change what is already on the page.
      appBar: chrome
          ? AppBar(
              title: entry == null
                  ? Text(l10n.appTitle)
                  : Row(
                      mainAxisSize: MainAxisSize.max,
                      children: <Widget>[_buildSongTitle(context, entry)],
                    ),
              // ONE 48-PIXEL TARGET INSTEAD OF A 64-PIXEL ROW. Opening a chart file is the first
              // thing a musician does and the last thing he does again: on a platform where the
              // source is a chooser rather than a path field, that row was 64 logical pixels of the
              // chart's own height spent on a button pressed once per session. It is an action now,
              // carrying the SAME `viewer-open-file` key the row's button carried, so anything that
              // drove the old control still finds it. A DESKTOP KEEPS THE ROW: there the row is a
              // path FIELD plus a chooser plus a load button, which is a form and cannot become a
              // button without losing the field.
              actions: phone
                  ? <Widget>[
                      ?issue,
                      _viewLockToggle(context),
                      _chromeToggle(context),
                      _buildOverflowMenu(context, session),
                    ]
                  : <Widget>[
                      ..._documentTools(context, session),
                      ..._sheetActions(context, session),
                      ?issue,
                      if (!sourceIsFilePath) _buildOpenFileAction(context),
                      _viewLockToggle(context),
                      _chromeToggle(context),
                    ],
            )
          : _buildDocumentBar(context),
      // The drawer exists only when there is a library to list: an empty drawer over a screen that
      // says "load a file" offers a control that opens nothing.
      drawer: phone && library != null && library.songs.isNotEmpty
          ? _buildSongDrawer(context, library)
          : null,
      onDrawerChanged: phone ? _onDrawerChanged : null,
      bottomNavigationBar: phone ? _buildPhoneDock(context, session) : null,
      body: Column(
        children: <Widget>[
          // The path bar is a FORM where a platform lets a path be typed, and nothing else: see the
          // app bar's action above for where the chooser went and why.
          if (chrome && sourceIsFilePath) _buildPathBar(context),
          if (error != null) _buildError(context, error),
          Expanded(child: _buildBody(context)),
          if (chrome) _buildStatusBar(context),
        ],
      ),
    );
  }

  // PURPOSE: Build the one bar the document keeps while the rest of the chrome is hidden, holding
  //          the control that brings everything back and — on a tablet, where there is no dock — the
  //          four tools that change what is already written.
  // INPUTS: context — the build context. session — the session of the song on screen, or null.
  // OUTPUTS: A bar [UiKit.toolBarHeight] tall. On a phone it holds the toggle alone, because the
  //          dock below the chart already carries the four tools and a second copy of them in a
  //          second place is how two surfaces come to disagree about which mode is on.
  // KEYWORDS: document-bar, chrome-hidden, always-visible-toggle, tools-stay-reachable, no-duplicate
  PreferredSizeWidget _buildDocumentBar(BuildContext context) {
    final EditSession? session = _currentSession;
    final bool phone = _isPhoneWidth(MediaQuery.sizeOf(context).width);
    return AppBar(
      toolbarHeight: UiKit.toolBarHeight,
      titleSpacing: UiKit.spaceM,
      title: phone ? null : Row(children: _documentTools(context, session)),
      actions: <Widget>[
        // The view lock travels with the toggle rather than with the scene bar, because the scene
        // bar is what the chrome hides: a lock whose state is only visible while everything else is
        // visible is exactly the lock this change exists to make trustworthy.
        _viewLockToggle(context),
        _chromeToggle(context),
      ],
    );
  }

  // PURPOSE: Say which chart is on the screen, where the screen begins, and be the handle that opens
  //          the sheet where its own facts are edited.
  // INPUTS: context — where the song-info sheet is opened from. entry — the song on screen.
  // OUTPUTS: The chart's title with a pencil beside it, then its bar count and, when the importer
  //          reported any, its issue count as a control. The count is the EDITED one, read from the
  //          chart the page is drawn from, so a bar inserted on the page changes the number beside
  //          the title.
  //
  //          WHY THIS MOVED OUT OF THE PANE AND INTO THE BAR. It is the same widget tree it was; what
  //          changed is the row it stands on. The pane's header row cost 36 logical pixels of chart
  //          height on every surface to say the chart's name directly under a bar that was already
  //          saying the application's name, and the owner's report of the result is that the top has
  //          too much empty space and does not read as one composition. Two title rows are exactly
  //          that: a composition reads as one when the first thing the eye meets is the thing the
  //          screen is about.
  // KEYWORDS: song-title, app-bar-title, bar-count, issues, song-info-entry, one-title-row,
  //           composition
  Widget _buildSongTitle(BuildContext context, IRealSong entry) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EditSession session = _sessionFor(entry);
    final Song displayed = _shownSong(entry);
    // ONE STRING AND ONE CONTROL, SO THERE IS NOTHING LEFT TO OVERFLOW. The first version of this row
    // put the title, the bar count and the issue button side by side, with the count as a plain
    // `Text` beside a `Flexible` title: in a narrow app bar the flexible half shrank to nothing and
    // the count, which cannot shrink, then overflowed the bar by its own width. `ink_mode_test` found
    // it on its own 140-pixel title box — the test failed with `RenderFlex OVERFLOWING` before it
    // ever reached its assertion. A title that ellipsizes is a title; a bar that overflows is a
    // defect. So the count is part of the title's own string (both are facts about the same chart and
    // are read as one line), and the issue count is a control in the bar's actions.
    final String label =
        '${_titleFor(entry, l10n)} · '
        '${l10n.barCount(displayed.writtenBarCount)}';
    return Flexible(
      child: Tooltip(
        message: l10n.songInfoTooltip,
        child: InkWell(
          key: const ValueKey<String>('viewer-song-info'),
          onTap: () => _openSongInfo(context, session, SongMetadataField.title),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: UiKit.spaceXs),
              const Icon(
                Icons.edit_outlined,
                size: 14,
                color: Color(0xFF486581),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // PURPOSE: Say that the importer reported problems with this chart, and open the list.
  // INPUTS: context — where the list is opened from. entry — the song on screen, or null.
  // OUTPUTS: A warning icon carrying the count in its tooltip, or null when there is nothing to say.
  //          An ACTION rather than part of the title: an app bar can afford a target whose width it
  //          controls, and cannot afford a label in the box the title has to share.
  // KEYWORDS: issues, warning, app-bar-action, no-title-overflow
  Widget? _buildIssueAction(BuildContext context, IRealSong? entry) {
    if (entry == null || entry.issues.isEmpty) {
      return null;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey<String>('viewer-issues'),
      icon: const Icon(Icons.report_problem_outlined),
      tooltip: l10n.issueCount(entry.issues.length),
      onPressed: () => unawaited(_showIssues(context, entry)),
    );
  }

  // PURPOSE: The one action that opens a chart file on a platform whose source is a chooser, so the
  //          entry point a musician uses first is in the bar with every other action instead of on a
  //          row of its own.
  // INPUTS: context — the build context.
  // OUTPUTS: An [IconButton] carrying the `viewer-open-file` key the row's button carried, disabled
  //          while a load is in flight so a second press cannot start a second one.
  // KEYWORDS: open-file, chooser, app-bar-action, one-entry-point, disabled-while-loading
  Widget _buildOpenFileAction(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey<String>('viewer-open-file'),
      icon: const Icon(Icons.folder_open),
      tooltip: l10n.openHtmlFile,
      onPressed: _loading ? null : () => unawaited(_load()),
    );
  }

  // PURPOSE: Build the ONE always-visible control that hides the library rail and the top block, and
  //          brings them back — the owner's own answer to "make the top block open and close", chosen
  //          over a gesture precisely because a button needs no gesture of its own.
  // INPUTS: context — the build context.
  // OUTPUTS: An [IconButton] that is present in every shell form and in both chrome states, so the
  //          control never moves and never disappears: a control that vanishes with the thing it
  //          controls is a state the musician can enter and not leave.
  // KEYWORDS: chrome-toggle, always-visible, hide-rail-and-top, button-not-gesture, d34-safe
  Widget _chromeToggle(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return IconButton(
      key: const ValueKey<String>('viewer-chrome-toggle'),
      icon: Icon(_chromeHidden ? Icons.fullscreen_exit : Icons.fullscreen),
      tooltip: _chromeHidden ? l10n.tooltipChromeShow : l10n.tooltipChromeHide,
      onPressed: _toggleChrome,
    );
  }

  // PURPOSE: Turn the library rail and the top block on or off together, and report the pane the
  //          decision left behind.
  // INPUTS: None.
  // OUTPUTS: Nothing. Rebuilds the shell. The two surfaces are ONE decision and not two, because
  //          that is what the owner chose: a rail hidden over a visible scene bar would be a screen
  //          that is neither reading nor editing.
  //
  //          THE LINE REPORTS THE WINDOW AND NOT THE PANE, and that is deliberate: the window is
  //          known here, while the pane is only known after the frame this call causes. The pane's
  //          own number is printed by `_buildPages`, once per size change, which is where it is
  //          actually known.
  // KEYWORDS: chrome-toggle, one-decision, rebuild, structured-log, measurable
  void _toggleChrome() {
    final Size window = MediaQuery.sizeOf(context);
    setState(() => _chromeHidden = !_chromeHidden);
    debugPrint(
      'viewer.chrome.toggle hidden=$_chromeHidden '
      'window=${window.width.toStringAsFixed(0)}x${window.height.toStringAsFixed(0)}',
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
        // THE GLYPH IS THE MODE, AND THE OFF STATE USED TO LOOK LIKE THE ON ONE. It was a pencil
        // outline when the pen was off and a pencil when it was on: two nearly identical pictures for
        // the two states of the one control that decides whether a contact writes, about which the
        // owner reported "I never understood how to select — it only draws". A selection frame reads
        // as "choose something" in every application that has ever had one, and it cannot be mistaken
        // for the pen beside it.
        icon: Icon(_inkOn ? Icons.draw : Icons.highlight_alt),
        isSelected: _inkOn,
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
      //
      // WHY THE GLYPH IS DRAWN RATHER THAN TAKEN FROM THE FONT. It was `Icons.auto_fix_normal`,
      // which is a wand with sparkles and reads as a feature that does something FOR the musician
      // rather than as the tool that removes what he wrote; the owner's report is that the eraser is
      // missing outright, and a wand is a candidate explanation for that. The bundled Material Icons
      // font of this Flutter version carries NO eraser glyph at all, and the nearest substitute
      // (`Icons.highlight_remove`) was built, looked at on the tablet and rejected for reading as a
      // circle with a cross — that is "cancel", not "rub". `_EraserGlyph` draws the picture everyone
      // already knows, and `_buildSelectionLine` states the mode in WORDS as well, because a glyph
      // nobody can name is how this tool went missing in the first place.
      IconButton(
        key: const ValueKey<String>('viewer-eraser-toggle'),
        // The colour is read from the button's OWN `IconTheme`, which `IconButton` sets from its
        // enabled and selected state: a drawn glyph that picked its own colour would stay dark when
        // the button is disabled and would not light up when the eraser is on.
        icon: Builder(
          builder: (BuildContext context) => _EraserGlyph(
            color:
                IconTheme.of(context).color ??
                Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        isSelected: _eraserOn,
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
      // --- RECOGNITION OF BAR DIVISIONS (owner decision D37) ------------------------
      // THE SWITCH THE OWNER ASKED FOR, and the reason it is a switch rather than a feature that is
      // simply on: a musician whose recognition works badly turns it off and keeps working, and
      // that is what makes a wrong recognition survivable. It therefore starts OFF, its icon states
      // the state in force (a dashed line reads as "a division the application drew", a pencil-line
      // reads as "your own hand"), and its tooltip says what is drawn in words rather than leaving
      // the glyph to be guessed — the same rule the pen and the eraser follow here.
      IconButton(
        key: const ValueKey<String>('viewer-recognition-toggle'),
        // THE GLYPH NO LONGER NAMES A BARLINE, AND THAT IS THE POINT. It was `border_vertical` when
        // the switch was on and `linear_scale` when it was off — a barline and three dashes — while
        // the switch now governs RECOGNITION of the page as a whole. A picture narrower than its
        // meaning is how a control teaches the wrong thing, and the owner's own vocabulary for this
        // one is «Распознавание: ВКЛ/ВЫКЛ»: the scanner is that word in a picture, and the state is
        // carried by `isSelected` and by the tooltip's sentence rather than by a second glyph.
        icon: const Icon(Icons.document_scanner),
        isSelected: _recognitionOn,
        tooltip: _recognitionOn
            ? l10n.tooltipRecognitionOn
            : l10n.tooltipRecognitionOff,
        onPressed: session == null ? null : _toggleRecognition,
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
        } else if (picked == 'recognition') {
          _toggleRecognition();
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
        // The recognition row STATES the state in force rather than naming the action, because a
        // feature that is off is invisible otherwise: a musician looking for the barline recognition
        // he was told about finds "OFF" and knows it exists and that he can have it.
        PopupMenuItem<String>(
          value: 'recognition',
          enabled: session != null,
          child: Text(
            _recognitionOn ? l10n.menuRecognitionOn : l10n.menuRecognitionOff,
          ),
        ),
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

  // PURPOSE: Turn RECOGNITION of bar divisions on or off in the top menu, which is the one organ
  //          the owner's decision D37 requires: a musician whose recognition works badly turns it off
  //          and keeps working, and nothing else in the application changes.
  //
  //          WHAT TURNING IT ON DOES, IN ONE SENTENCE, because a switch that changes what is on the
  //          page without saying so would be the secret action D37 forbids: the application reads
  //          the ink already on the page, records every vertical division it finds as structure, and
  //          draws those as ideal lines INSTEAD of the handwriting they came from. Turning it off
  //          draws the handwriting again and leaves every division in the document untouched — so
  //          nothing the switch does can lose a mark, and the switch itself is the undo for a
  //          recognition the musician does not want.
  //
  //          THE SWITCH IS NAMED FOR RECOGNITION AS A WHOLE AND READS ONE READER FOR NOW. The glyph
  //          is a scanner and the row says «Распознавание: ВКЛ/ВЫКЛ», not "bar lines", because the
  //          control governs recognition as a whole and the note reader hangs off it the moment the
  //          shape of a recognised note is decided (see `_recogniseWholePage`). A control renamed to
  //          mean less than it will mean is how a musician turns on the wrong thing.
  // INPUTS: None; reads the library, the selected song and its layer.
  // OUTPUTS: Nothing. The layer's own flag and a screen rebuild; the document changes only by the
  //          `division.set` events the pass appends, each of which undo reverses like any other.
  // KEYWORDS: recognition-switch, top-menu, default-off, whole-pass, d37-rule-1, undoable
  void _toggleRecognition() {
    final IRealLibrary? library = _library;
    if (library == null || library.songs.isEmpty) {
      return;
    }
    final int index = _selectedSong >= 0 && _selectedSong < library.songs.length
        ? _selectedSong
        : 0;
    final IRealSong entry = library.songs[index];
    final InkCaptureLayer layer = _inkFor(entry);
    final bool next = !_recognitionOn;
    setState(() {
      _recognitionOn = next;
      layer.recognitionEnabled = next;
    });
    final int found = next ? _recogniseWholePage(layer, entry) : 0;
    _publishInkState();
    debugPrint(
      'viewer.recognition.toggle song="${_rawTitleFor(entry)}" on=$next '
      'found_now=$found divisions=${layer.documentDivisions.length} '
      'strokes=${layer.strokeCount}',
    );
  }

  // PURPOSE: Read the ink ALREADY on the page the moment recognition is switched on, so that the
  //          musician sees his chart recognised rather than having to write everything again.
  // INPUTS: layer — the layer of the song on screen. entry — that song, for the page it is drawn on.
  // OUTPUTS: How many divisions the document held after the pass. The pass is the layer's own
  //          whole-page recognition, run against the page the screen is currently showing; with no
  //          page drawn yet there is nothing to read and the number is what the document already had.
  //
  //          THE NOTE PASS IS NOT PART OF THIS PASS YET, AND THAT IS A DECISION. `recogniseMelodyNotes`
  //          exists and is measured, but it writes `(beat, step, pitch)` — the representation the
  //          owner removed as a class — so running it here would write the shape he rejected into
  //          his file while its replacement is being decided. See `ink_layer.dart`'s `endStroke`,
  //          where the same decision is recorded at the call site that will be the one to come back.
  // KEYWORDS: whole-page-pass, on-enable, idempotent, no-crash-without-a-page, note-pass-deferred
  int _recogniseWholePage(InkCaptureLayer layer, IRealSong entry) {
    final List<PageLayout> pages = _engraved?.pages ?? const <PageLayout>[];
    if (pages.isEmpty) {
      return layer.documentDivisions.length;
    }
    // EVERY PAGE, not just the first: a chart the musician has paged through may hold ink on any of
    // them, and recognising only the page in front of him would leave the rest of his chart
    // unstructured with no way to ask for it.
    for (final PageLayout page in pages) {
      layer.recogniseBarDivisions(page);
    }
    return layer.documentDivisions.length;
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
      _selectionEnd = null;
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
        padding: UiKit.barPadding,
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
      padding: UiKit.barPadding,
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
        // drawer and once in a column the reader cannot see. The same rule holds when the chrome is
        // hidden, for the same reason: this is the owner's "hide the library" and a rail that kept
        // its 260 pixels while drawing nothing would be hiding in name only.
        if (!phone && !_chromeHidden) ...<Widget>[
          SizedBox(
            width: _songRailWidth,
            child: _buildSongList(context, library),
          ),
          const VerticalDivider(width: UiKit.hairline),
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
              _selectionEnd = null;
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
        // THE TOP BLOCK, IN ONE PIECE. Everything from the chart's title to the selection line is
        // one `if`: the owner chose that the rail and the top block hide TOGETHER, and a half-hidden
        // state — a title over a hidden scene bar — is exactly the "does not look like one whole"
        // complaint this arrangement exists to answer.
        //
        // THE CHART'S TITLE IS NOT HERE ANY MORE. It is the app bar's title; see `_buildSongTitle`
        // for why the top of the screen says one name and not two, and for the 36 logical pixels of
        // chart height that row was costing on every surface.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!_chromeHidden) ...<Widget>[
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
                // THE VIEW THE MUSICIAN HAS ON THE CHART, shown and driven where he reads. D33 asks
                // for a zoom reachable from the interface beside the touch gesture, and D34 gives the
                // GESTURE to two fingers; these three controls are the interface half, and the middle
                // one is how he gets back to a known view after a pan he cannot see the edges of.
                //
                // The number reported is the magnification that is ON THE GLASS, not the stored one:
                // while the view is locked the zoom is derived from the engraving (see [_viewed]),
                // and a reading that showed the stored value would say ×1.0 over a chart drawn at
                // ×1.4. The fourth control fixes that number, and it stands HERE — with the scale it
                // fixes — as well as in the always-visible bars, because this is where a musician
                // reads the scale and therefore where he looks for the control that pins it.
                zoom: _effectiveZoom,
                zoomLocked: _viewLocked,
                onZoomIn: () => _zoomBy(1.25),
                onZoomOut: () => _zoomBy(0.8),
                onZoomReset: _resetView,
                // The tempo and the style are edited where they are shown. The sheet is one surface
                // for all four facts and opens with the tapped field focused, so the tempo a musician
                // pressed is the tempo the cursor is in.
                onEditTempo: () =>
                    _openSongInfo(context, session, SongMetadataField.tempo),
                onEditStyle: () =>
                    _openSongInfo(context, session, SongMetadataField.style),
              ),
              _buildSelectionLine(context, displayed),
            ],
            // THE DOCUMENT IS FRAMED BY THE SHELL AND NOT BY ITSELF. One rounded field behind the
            // music, drawn from the same corner radius as every other framed surface, is what makes
            // the pane read as the page rather than as the leftover part of the screen — and it is a
            // background and an outline and NOT a padding, because a frame that consumed pixels would
            // be paying for looks with exactly the room this change exists to return.
            Expanded(
              child: DecoratedBox(
                key: const ValueKey<String>('viewer-document-frame'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(UiKit.radius),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: UiKit.hairline,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(UiKit.radius),
                  child: _buildPages(
                    entry,
                    displayed,
                    mode,
                    layer,
                    strokes,
                    textCues,
                  ),
                ),
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
  //
  //          AND THE SAME DISPATCH ORDER IS WHY THERE IS A THIRD, OUTERMOST LISTENER FOR THE LIFT.
  //          A gesture that MOVED is never a tap, so for a pen stroke that travelled and for an
  //          eraser drag the tap handler above is not called at all; the lift listener is placed
  //          ABOVE the ink capture precisely so that it runs after the layer has written to the log,
  //          which is what lets "the document changed" reach the screen at all. See
  //          [_onPagePointerUp].
  // KEYWORDS: page-widget, pointer-listener, dispatch-order, ink-overlay, tap-vs-stroke,
  //           selection-entry, commit-before-select
  Widget _tappablePage(
    PageLayout page,
    Song song,
    InkCaptureLayer layer,
    List<TextCue> textCues,
  ) => Listener(
    // THE LIFT IS TAKEN HERE, ABOVE THE INK CAPTURE, AND THE ORDER IS THE WHOLE POINT. Hit testing
    // runs from the deepest target outwards, so a listener ABOVE `RawPointerCapture` is called after
    // the layer's own lift handler — that is, after `endStroke` or `endErase` has written to the
    // operation log. A listener BELOW it asks "did the document change during this contact" one
    // event too early and gets the previous contact's answer, which was measured on the tablet
    // before this was moved: the erase's own four deletions were reported with the edit count from
    // before them.
    //
    // `deferToChild` because the page below is opaque and this listener adds nothing to the hit test
    // of its own: it is here to observe the lift, not to make the page touchable.
    behavior: HitTestBehavior.deferToChild,
    onPointerUp: (PointerUpEvent event) => _onPagePointerUp(),
    child: RawPointerCapture(
      layer: layer,
      page: page,
      child: Listener(
        // This listener does NOT repaint. The ink layer repaints itself through its own tick, and
        // the only jobs left here are the pen path's cost accounting and marking the verification
        // state as owed — see [_onPagePointerMove]. A move the layer did not take — a finger, or a
        // pen with the mode off — therefore costs one comparison and nothing else.
        onPointerMove: (PointerMoveEvent event) => _onPagePointerMove(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails details) => _onPageTapDown(layer, details),
          onTapUp: (TapUpDetails details) => _onPageTapUp(page, layer, details),
          onTapCancel: _onPageTapCancel,
          child: _layeredPage(page, song, layer, textCues),
        ),
      ),
    ),
  );

  // PURPOSE: Account for what the pen path costs, and mark the verification state as owed, so that
  //          the change is published by an idle frame instead of by the pen's own thread.
  //
  //          IT NO LONGER REBUILDS ANYTHING, AND THAT IS THE WHOLE OF THE LATENCY FIX. The live line
  //          is repainted by the ink layer's own tick (see [_layeredPage]); this listener is left
  //          with the two jobs that are not a repaint. Both of them were measured on the owner's
  //          tablet and both were expensive, in this order: publishing the verification state cost
  //          1 738 ms of a 2 882 ms stroke — sixty per cent of the pen path, because the published
  //          document carries every stroke's canonical form and is re-serialised and re-parsed whole
  //          each time — and the rebuild that carried it re-engraved the chart on 105 of the stroke's
  //          246 samples.
  //
  //          WHY THE PUBLICATION LEFT THIS METHOD ALTOGETHER RATHER THAN BEING MADE RARER. Throttling
  //          it to four a second was this project's previous answer, and it was not enough: the cost
  //          of one publication is proportional to the ink already on the page, so a rarer O(ink) job
  //          is still an O(ink) job, and by the eighteenth stroke of a four-second-per-stroke run it
  //          was 7 783 ms — 45 % of the run — spent inside a diagnostic on the thread that reads the
  //          pen. A rate cannot bound a cost that grows with the document; only taking the work off
  //          the path can.
  // INPUTS: None; the ink layer is asked whether a contact is drawing.
  // OUTPUTS: Nothing that a frame depends on. The cost counters are reset at the first sample of a
  //          stroke and reported, throttled, for as long as it lasts.
  //
  //          THE VERIFICATION STATE IS NOT PUBLISHED FROM HERE, AND THAT IS THE FIX FOR THE DEFECT
  //          THIS METHOD USED TO CAUSE. Every publication serialises every stroke the document holds
  //          in its canonical form and then parses that line back to validate it, so its cost is
  //          proportional to the ink ALREADY ON THE PAGE — measured on the owner's tablet as 0.7 ms
  //          for the first stroke of a session rising to 7 783 ms of `publish_ms` by the eighteenth,
  //          which is 45 % of a 17 s run spent inside a diagnostic. It ran on the thread that reads
  //          the pen, the platform's input pipeline backed up behind it, and the same fixed 0.4 s
  //          gesture that carried 532 samples on a fresh page carried 4 by the time the page was
  //          full. The instrument is `viewer.pen.cost` before and after, and the sample count in
  //          `ink.stroke.commit`.
  //
  //          WHAT REPLACED IT. While a contact is drawing, this method only marks the publication as
  //          owed and returns; the frame that follows the lift publishes it, because the lift
  //          resumes the build that carries the committed stroke. A tool that reads the state after
  //          a stroke therefore still sees the stroke, and it no longer reads it at the pen's
  //          expense. See [publishInkStateWhenIdle] for why the work is moved and not dropped.
  // KEYWORDS: verification-handoff, publish-when-idle, cost-measurement, no-rebuild, latency,
  //           pen-starvation
  void _onPagePointerMove() {
    final InkCaptureLayer? layer = _activeInkLayer;
    if (!(layer?.isDrawingInk ?? false)) {
      _penWasDrawing = false;
      return;
    }
    if (!_penWasDrawing) {
      _penWasDrawing = true;
      _penCost.beginStroke();
    }
    _penCost.noteSample();
    _inkPublishOwed = true;
    final String? report = _penCost.reportIfDue();
    if (report != null) {
      debugPrint(report);
    }
  }

  // PURPOSE: Show what a contact that has just lifted did to the document, when it wrote something
  //          the tap handler will never be told about. It is the lift half of a gesture that moved:
  //          a pen stroke that travelled and an eraser drag both finish here and neither is a tap.
  //
  //          WHY IT IS ONE COMPARISON AND NOT A LISTENER. A rebuild per sample is the cost this
  //          screen already paid to remove (see [_onPagePointerMove]); what is needed is "did the
  //          document change during this contact", asked once, and a counter on the layer answers it
  //          for both the stroke that was committed and the strokes that were erased — including the
  //          case of an eraser drag that crossed twelve of them. With nothing written the method
  //          costs a field read, which is why it is safe on the pen's own lift.
  // INPUTS: None. The active song's ink layer is asked how many edits it has appended.
  // OUTPUTS: Nothing. Rebuilds when the count moved since the last lift, so the undo control becomes
  //          live and the chart stops showing ink the document no longer holds, and offers the
  //          verification state for publication by the frame that follows.
  // KEYWORDS: pointer-up, commit-then-show, drag-not-a-tap, edit-counter, undo-liveness, d34
  void _onPagePointerUp() {
    final InkCaptureLayer? layer = _activeInkLayer;
    if (layer == null || layer.documentEdits == _shownDocumentEdits) {
      return;
    }
    _shownDocumentEdits = layer.documentEdits;
    setState(() {});
    _inkPublishOwed = true;
    publishInkStateWhenIdle();
    debugPrint(
      'viewer.page.edit.shown edits=${layer.documentEdits} '
      'strokes=${layer.strokeCount} undo_depth=${_currentSession?.undoDepth ?? 0}',
    );
  }

  // PURPOSE: Run one chart engraving and record what it cost, so that "the page was re-laid-out on
  //          every pen sample" is a number in the log rather than an inference from the code.
  // INPUTS: engrave — the call, which is either `fitToPage` or `layout` at one of the three places
  //         this screen engraves a page.
  // OUTPUTS: Whatever [engrave] returns, unchanged. The cost is a side effect on [_penCost], which
  //          publishes it at most a few times a second.
  // KEYWORDS: layout-cost, stopwatch, single-wrap, measurement-not-assertion
  T _meteredLayout<T>(T Function() engrave) {
    final Stopwatch watch = Stopwatch()..start();
    final T result = engrave();
    _penCost.noteLayout(watch.elapsedMicroseconds);
    return result;
  }

  // PURPOSE: Stack the chart, the words written on it and the ink, with all three positioned by the
  //          same page transform.
  // INPUTS: page, song, layer and textCues, as in [_tappablePage].
  // OUTPUTS: The page widget. The cue layer is drawn AFTER the chart, so a remark lies over the
  //          music it annotates, and BEFORE the ink, so the ink stays the topmost layer and the
  //          ordering this file already documents for it (see [_tappablePage] and A37) is left
  //          exactly as it was. Each layer is given the page's own scale, which is what keeps them
  //          in one coordinate system rather than three that agree until the page is fitted.
  //
  //          THE INK LAYER REPAINTS ITSELF, AND THE OTHER TWO DO NOT. Everything below this widget —
  //          the chart, the cues, the app bar, the song list — is built from values that change when
  //          the DOCUMENT changes, not when a pen moves. The ink is the one layer whose content
  //          changes sixty to a hundred and twenty times a second, so it is the one layer wrapped in
  //          a listener: a sample raises the layer's own tick and only this `CustomPaint` is marked
  //          for painting, while the surrounding widget tree — and with it the chart's engraving — is
  //          left alone. Before this, a sample called `setState` on the whole screen, which
  //          re-engraved the page (measured: 105 layout passes for one 246-sample stroke) and
  //          re-serialised the verification state (measured: 1 738 ms of that stroke's 2 882 ms).
  //
  //          WHY THE STROKES ARE READ INSIDE THE BUILDER AND NOT CAPTURED OUTSIDE IT. A captured
  //          list is the document as it was when the page was built, so a stroke committed while no
  //          rebuild happens would be invisible — and a long drag does not always resolve as a tap,
  //          which is the rebuild that would otherwise have carried it. Reading them through the
  //          layer inside the builder is what makes a committed stroke appear the instant it is
  //          committed, whatever the gesture arena decided about the contact.
  // KEYWORDS: painter-stack, cues-over-chart, ink-stays-on-top, shared-scale, one-coordinate-system,
  //           self-repainting-ink, listenable-builder, latency
  Widget _layeredPage(
    PageLayout page,
    Song song,
    InkCaptureLayer layer,
    List<TextCue> textCues,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(
          painter: ChartPainter(
            song: song,
            page: page,
            metrics: _metrics,
            selection: _selection,
            // The RUN the musician selected, so sixteen bars look like sixteen bars. It is the same
            // address the copy, paste and transpose actions read, so what is highlighted and what an
            // operation acts on cannot come apart.
            selectionRange: _selectionRange,
          ),
          child: const SizedBox.expand(),
        ),
        CustomPaint(
          painter: TextCuePainter(
            cues: _resolveCues(page, textCues),
            pageScale: page.scale,
            pageZoom: page.zoom,
            pagePan: page.pan,
          ),
          child: const SizedBox.expand(),
        ),
        ListenableBuilder(
          listenable: layer.liveRevision,
          builder: (BuildContext context, Widget? child) => CustomPaint(
            painter: InkPainter(
              strokes: _inkStrokes(page, layer),
              pageScale: page.scale,
              pageZoom: page.zoom,
              pagePan: page.pan,
            ),
            child: child,
          ),
          child: const SizedBox.expand(),
        ),
        // --- RECOGNISED DIVISIONS, DRAWN AS STRUCTURE (owner decision D37) ---------------
        // THE LAYER THAT MAKES "recognised" VISIBLE, and it is drawn ABOVE the ink and BELOW
        // nothing, because while recognition is on the ink it came from is not drawn at all: see
        // [_inkStrokes]. It is added to the stack only when recognition is on, so with the switch
        // off this widget is not built and the page is composed exactly as it was before this
        // feature existed — the property the owner's rule 1 requires of everything that worked
        // before there was any recognition.
        if (_recognitionOn)
          CustomPaint(
            painter: BarlinePainter(
              divisions: _resolveDivisions(page, layer.documentDivisions),
              pageScale: page.scale,
              pageZoom: page.zoom,
              pagePan: page.pan,
            ),
            child: const SizedBox.expand(),
          ),
      ],
    );
  }

  // PURPOSE: Collect every stroke the ink layer draws on [page]: the document's committed strokes
  //          plus the ones still under the pen, both resolved against the page on screen.
  //
  //          WHAT THE ERASER HAS ALREADY TAKEN COMES OUT HERE, WHICH IS WHY A DRAG LOOKS LIKE A
  //          RUBBER RATHER THAN LIKE A GESTURE THAT DOES NOTHING UNTIL THE HAND LIFTS. The layer
  //          collects what a dragged erase contact crosses and writes the deletions only at the
  //          lift (so a gesture the two-finger pan takes over deletes nothing); the strokes it has
  //          collected are hidden by this filter, on the layer's own repaint tick, so the musician
  //          sees the ink go away under the eraser while he is still moving it. A stroke in that
  //          set is still IN the document — that is what makes the preview revocable — and it
  //          reappears if the gesture is cancelled.
  //
  //          THE ANCHOR IS RESOLVED HERE, ONCE PER REPAINT, AGAINST THE PAGE ON SCREEN, and that is
  //          the whole reason a stroke stays where the musician put it. The stored coordinates are
  //          measured from the anchor's own corner, so adding the corner's position on THIS page
  //          moves the ink with the music: a transposition re-engraves the bars, the anchor resolves
  //          to the bar's new rectangle, and the stroke's own geometry is untouched. A stroke whose
  //          address is on another page of a paginated document is simply not drawn here. The
  //          strokes come from the layer's session — the WRITTEN document — so the transposition on
  //          screen changes where a stroke is placed and never what it says.
  // INPUTS: page — the page being drawn. layer — the ink layer of the song on screen, which is the
  //         live source of both halves.
  // OUTPUTS: The strokes that resolved, in render order: the document's order first, so a later
  //          stroke lies over an earlier one, and the live preview last, because it is the newest
  //          mark and the one the musician is watching. Strokes the armed eraser has crossed are
  //          left out, and no other stroke is affected: with nothing armed the filter is empty.
  //
  //          THE ONE OTHER THING THAT COMES OUT IS THE INK OF A RECOGNISED DIVISION, and only while
  //          recognition is on. D37 rule 2 says that with recognition on the RECOGNISED variant is
  //          what is drawn, so the hand-drawn line is replaced by the ideal one rather than covered
  //          by it — a line drawn on top of his would be a line hiding his, which is the failure
  //          that rule exists to prevent. The stroke is NOT deleted from the document: turn the
  //          switch off and it is right here, because this filter is the whole of the hiding and it
  //          is a decision made once per frame rather than a change to what is stored.
  // KEYWORDS: anchor-resolution, page-filter, render-order, transposition-survival, fit-survival,
  //           live-source, no-cached-document, erase-preview, recognised-ink-hidden, d37
  List<ResolvedInkStroke> _inkStrokes(PageLayout page, InkCaptureLayer layer) {
    final Set<String> erasedPreview = layer.pendingEraseIds;
    // THE INK OF EVERYTHING RECOGNITION HAS TAKEN OVER, from ONE source: the divisions the document
    // holds, and the note-reader's own record of which strokes became heads. Both are read only while
    // the switch is on, and both are decisions made once per frame rather than changes to the
    // document — so turning the switch off puts every stroke back with nothing to undo, which is the
    // property D37 rule 1 rests on.
    final Set<String> recognised = _recognitionOn
        ? <String>{
            for (final BarDivision division in layer.documentDivisions)
              if (division.sourceStrokeId.isNotEmpty) division.sourceStrokeId,
            ...layer.recognisedNoteStrokeIds,
          }
        : const <String>{};
    return <ResolvedInkStroke>[
      ..._resolveStrokes(page, layer.documentStrokes).where(
        (ResolvedInkStroke resolved) =>
            !erasedPreview.contains(resolved.stroke.id) &&
            !recognised.contains(resolved.stroke.id),
      ),
      ...layer.liveStrokes.where(
        (ResolvedInkStroke resolved) => _isOnPage(page, resolved),
      ),
    ];
  }

  // PURPOSE: Turn every division of the document into the pair the barline painter needs, skipping
  //          the ones this page cannot place.
  // INPUTS: page — the page being drawn. divisions — the document's divisions, in render order.
  // OUTPUTS: The divisions whose anchor this page resolves, with the anchor's origin. A division on
  //          another page of a paginated document is simply not drawn here, which is the same rule
  //          the ink follows and the same call (`resolveEventAnchor`) that resolves it.
  // KEYWORDS: division-placement, anchor-resolution, page-filter, one-resolver
  List<ResolvedDivision> _resolveDivisions(
    PageLayout page,
    List<BarDivision> divisions,
  ) {
    final List<ResolvedDivision> resolved = <ResolvedDivision>[];
    for (final BarDivision division in divisions) {
      final InkPlacement? placement = resolveEventAnchor(page, division.anchor);
      if (placement == null) {
        continue;
      }
      resolved.add(
        ResolvedDivision(division: division, origin: placement.origin),
      );
    }
    return resolved;
  }

  // PURPOSE: Turn every committed stroke into the pair a painter needs, skipping the ones this page
  //          cannot place.
  // INPUTS: page — the page being drawn. strokes — the document's strokes, in render order.
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
  //
  //          AND A CONTACT THAT BELONGED TO THE TWO-FINGER VIEW GESTURE SELECTS NOTHING EITHER. A
  //          pan is not a tap, but a two-finger touch that never moved can still reach a tap
  //          recogniser — and the musician who put two fingers down to move the chart did not ask
  //          for the bar under his hand to be selected. The layer's flag is read because it is the
  //          one object that knows the gesture owned those contacts (owner decision D34).
  // INPUTS: page — the page the tap landed on. layer — the ink layer of the song on screen, whose
  //         mode is the only thing that can consume a tap without a stroke being drawn. details —
  //         the tap, whose local position is in the page's surface.
  // OUTPUTS: Nothing. It rebuilds when the contact was consumed, so a new stroke is painted, a
  //          deletion shows, and the undo control becomes live; it selects otherwise, and clears the
  //          selection on a miss.
  // KEYWORDS: tap-up, commit-then-repaint, eraser-suppresses-selection, selection, fit-scale,
  //           view-gesture-suppresses-selection, d34
  void _onPageTapUp(
    PageLayout page,
    InkCaptureLayer layer,
    TapUpDetails details,
  ) {
    final bool drew = _tapWasInk;
    final bool erasing = layer.eraserMode;
    final bool panning = layer.viewGestureActive;
    _tapWasInk = false;
    if (panning) {
      return;
    }
    if (drew || erasing) {
      // The contact was the ink layer's: the document may have changed under this frame, so the page
      // and the app bar are both out of date. No selection is made — the bar under a stroke is not
      // what the musician asked for, and under the eraser not even a miss is a selection.
      setState(() {});
      // The state changed under this contact, and the contact has now lifted, so this is the first
      // moment at which publishing it cannot starve the pen. See [_onPagePointerMove].
      publishInkStateWhenIdle();
      return;
    }
    _select(page, details.localPosition);
  }

  // PURPOSE: Turn a completed tap on a page into a selection, converting the surface point into the
  //          page's own coordinates first, so a fitted page is hit where it is DRAWN rather than
  //          where it was engraved.
  //
  //          THE STAFF IS TESTED FIRST, AND THAT IS THE WHOLE OF "TOUCH A BEAT OF THE STAFF TO WRITE
  //          ITS NOTE". A bar's staff lies BELOW its chord-line rectangle, so the two surfaces never
  //          overlap and the order between them cannot change what a chord-line tap means: a point
  //          on the chord line is answered by [hitTestPage] exactly as it was, and a point on the
  //          five lines is answered by [hitTestMelodyStaff]. A touch that lands on a staff column
  //          opens the note palette for that beat immediately, which is the shortest path owner
  //          decision D28 asks for: the beat is named by the column the musician touched — and the
  //          beat captions under the staff say which number it is — rather than by a tap on the bar
  //          and then a tap on a word in the selection line.
  //
  //          WHY IT DOES NOT WAIT FOR A SECOND TAP. The staff has no other meaning: nothing on it is
  //          selectable for its own sake, so a single tap cannot be ambiguous, and a double tap
  //          would add a gesture nothing on screen mentions. The chord line keeps its own single tap
  //          for selection and its own two named actions.
  // INPUTS: page — the page the tap landed on. localPosition — the point in the page widget's own
  //         coordinate space, which is the surface the painter scaled into.
  // OUTPUTS: Nothing. Sets [_selection] to the hit, or to null when the tap missed every bar; a miss
  //          clears the selection rather than leaving a stale one, because a highlight that survives
  //          the tap meant to dismiss it is a lie about what is selected. A tap on a staff column
  //          additionally opens the note palette, with the cell already selected so that a refused
  //          edit still has somewhere to be reported. The surface point, the converted page point
  //          and the answer are logged as key-value pairs, so the arithmetic can be checked against
  //          what is on screen.
  // KEYWORDS: tap-handling, coordinate-transform, page-point, hit-test, staff-first, note-entry,
  //           selection-state, structured-log
  void _select(PageLayout page, Offset localPosition) {
    final LayoutOffset surface = LayoutOffset(
      localPosition.dx,
      localPosition.dy,
    );
    // THE ONE-ACTION REPAIR FOR RECOGNITION, AND IT IS TRIED BEFORE ANYTHING ELSE. With recognition
    // on and the pen off, a tap that lands ON INK changes the application's mind about that ink:
    // a stroke that is a division is rejected (and the handwriting comes back into view), and a
    // stroke that is not one becomes a division. Both errors are repaired exactly here, by one tap
    // on the mark itself, which is the price the owner's rule puts on a wrong recognition.
    //
    // It costs nothing when the tap misses the ink — the layer answers null and the tap goes on to
    // select the bar under it — and it cannot fire at all with recognition off, so the tap that
    // selects a cell is the tap it always was.
    if (_recognitionOn) {
      final InkCaptureLayer? layer = _selectedInkLayer;
      final String? repaired = layer?.toggleDivisionAt(
        page: page,
        surfacePoint: surface,
      );
      if (repaired != null) {
        setState(() {});
        publishInkStateWhenIdle();
        debugPrint(
          'viewer.select.repaired page=${page.index} what=$repaired '
          'divisions=${layer?.documentDivisions.length}',
        );
        return;
      }
      // AND THE SAME GESTURE FOR A NOTE, because the reader is the second thing this switch turns
      // on and a wrong recognition has to cost one or two actions whichever reader made it. A tap
      // that lands on the ink of a recognised head deletes that note and gives the handwriting back;
      // a tap that lands on nothing recognised falls through to the selection below, so the tap that
      // names a bar or a beat is the tap it always was.
      final String? note = layer?.rejectRecognisedNoteAt(
        page: page,
        surfacePoint: surface,
      );
      if (note != null) {
        setState(() {});
        publishInkStateWhenIdle();
        debugPrint(
          'viewer.select.repaired page=${page.index} what=$note '
          'notes_ink=${layer?.recognisedNoteStrokeIds.length}',
        );
        return;
      }
    }
    final LayoutOffset pagePoint = page.pagePointOf(surface);
    final ChartHit? staffHit = hitTestMelodyStaff(page, pagePoint);
    // THE SECOND TAP OF A RUN IS NOT ANOTHER SELECTION, AND IT OPENS NOTHING. While the "until here"
    // action is armed, the next touch names the OTHER END of the run: it must not open the note
    // palette, because the musician is pointing at a bar and not at a beat to write into, and it must
    // not replace the anchor, because that is the end he already named.
    if (_extendPending) {
      _extendTo(page, staffHit ?? hitTestPage(page, pagePoint));
      return;
    }
    if (staffHit != null) {
      setState(() {
        _selection = staffHit;
        _selectionEnd = null;
        _selectionStatus = null;
      });
      debugPrint(
        'viewer.select staff page=${page.index} scale=${page.scale} '
        'surface=(${surface.x.toStringAsFixed(1)},${surface.y.toStringAsFixed(1)}) '
        'page_point=(${pagePoint.x.toStringAsFixed(1)},'
        '${pagePoint.y.toStringAsFixed(1)}) '
        'hit=${staffHit.sectionId}#${staffHit.barIndex} beat=${staffHit.beat}',
      );
      _editNoteSelection(context);
      return;
    }
    final ChartHit? hit = hitTestPage(page, pagePoint);
    setState(() {
      _selection = hit;
      _selectionEnd = null;
      _selectionStatus = null;
    });
    debugPrint(
      'viewer.select page=${page.index} scale=${page.scale} '
      'surface=(${surface.x.toStringAsFixed(1)},${surface.y.toStringAsFixed(1)}) '
      'page_point=(${pagePoint.x.toStringAsFixed(1)},'
      '${pagePoint.y.toStringAsFixed(1)}) '
      'hit=${hit == null ? 'none' : '${hit.sectionId}#${hit.barIndex} '
                'beat=${hit.beat}'}',
    );
  }

  // PURPOSE: Name the RUN the musician has selected — from the bar (or cell) he touched to the one he
  //          pointed at — so copy, paste and transpose all act on the same fragment the highlight
  //          shows.
  // INPUTS: None; reads [_selection] and [_selectionEnd].
  // OUTPUTS: A [ChartSelection], or null when nothing is selected. A single hit gives a run of one,
  //          at the hit's own depth: a cell gives a one-beat window and a bar gives a whole bar, which
  //          is what makes the same two taps mean "this bar" and "these bars" without a mode.
  //          The run is DERIVED and never stored: there is one value here and no second copy of the
  //          selection that could disagree with it.
  //
  //          WHY THE DEPTH IS THE HIT'S AND NOT A SEPARATE CHOICE. A musician who touched a cell has
  //          already said "this beat"; one who touched the bar's padding said "this bar". Reading the
  //          depth from the touch is what keeps the interface from asking a question the gesture
  //          already answered (D36's whole point: a selection can be finer than a bar).
  // KEYWORDS: selection-range, derived-address, depth-from-touch, ui-state-not-document-state, d35,
  //           d36
  ChartSelection? get _selectionRange {
    final ChartHit? anchor = _selection;
    if (anchor == null) {
      return null;
    }
    final ChartHit? focus = _selectionEnd;
    if (focus == null) {
      final int? beat = anchor.beat;
      return beat == null
          ? ChartSelection.bars(
              sectionId: anchor.sectionId,
              firstBar: anchor.barIndex,
              lastBar: anchor.barIndex,
            )
          : ChartSelection.beats(
              sectionId: anchor.sectionId,
              barIndex: anchor.barIndex,
              firstBeat: beat,
              lastBeat: beat,
            );
    }
    return ChartSelection.span(
      sectionId: anchor.sectionId,
      firstBar: anchor.barIndex,
      firstBeat: anchor.beat,
      lastBar: focus.barIndex,
      lastBeat: focus.beat,
    );
  }

  // PURPOSE: Finish a run with the bar the musician just pointed at, and say what was selected, so the
  //          highlight he sees is the address the next operation will act on.
  // INPUTS: page — the page the touch landed on, for the log. hit — the bar and cell it named, or null
  //         for a touch that hit nothing.
  // OUTPUTS: Nothing. Sets [_selectionEnd] and clears [_extendPending], or — on a miss, or on a bar of
  //          another section — clears the pending state and says why in the log rather than building a
  //          run that spans two sections. A run inside one section is the only run this model has: an
  //          address is `(section, bar)` and bars of two sections are not a contiguous run of anything.
  // KEYWORDS: selection-extend, range-finish, one-section, miss-refusal, structured-log
  void _extendTo(PageLayout page, ChartHit? hit) {
    final ChartHit? anchor = _selection;
    if (hit == null || anchor == null) {
      setState(() => _extendPending = false);
      debugPrint(
        'viewer.selection.extend.skipped reason=${hit == null ? 'miss' : 'no-anchor'} '
        'page=${page.index}',
      );
      return;
    }
    if (hit.sectionId != anchor.sectionId) {
      setState(() => _extendPending = false);
      debugPrint(
        'viewer.selection.extend.skipped reason=other-section '
        'anchor=${anchor.sectionId}#${anchor.barIndex} '
        'hit=${hit.sectionId}#${hit.barIndex}',
      );
      return;
    }
    setState(() {
      _selectionEnd = hit;
      _extendPending = false;
      _selectionStatus = null;
    });
    final ChartSelection? range = _selectionRange;
    debugPrint(
      'viewer.selection.extend page=${page.index} '
      'anchor=${anchor.sectionId}#${anchor.barIndex} beat=${anchor.beat} '
      'focus=${hit.sectionId}#${hit.barIndex} beat=${hit.beat} '
      'range=${range?.toString() ?? 'none'} bars=${range?.barCount ?? 0} '
      'beats=${range?.beatCount ?? 0}',
    );
  }

  // PURPOSE: Arm the "until here" action, so the next tap names the other end of the run rather than
  //          starting a new selection.
  // INPUTS: context — for the catalogue, which states what the next tap will do.
  // OUTPUTS: Nothing. Only meaningful with a selection; with none there is no anchor to extend from
  //          and the action is disabled.
  // KEYWORDS: selection-extend, arm, next-tap, discoverable-state
  void _armExtend(BuildContext context) {
    setState(() {
      _extendPending = true;
      _selectionStatus = null;
    });
    debugPrint(
      'viewer.selection.extend.armed '
      'search=${_selection == null ? 'none' : '${_selection!.sectionId}'
                '#${_selection!.barIndex}'}',
    );
  }

  // PURPOSE: Take a copy of what is selected, so the musician can paste it at another address —
  //          including when nothing on it was ever recognised as music.
  // INPUTS: context — for the catalogue.
  // OUTPUTS: Nothing. The clip is held in [_clip] and NOTHING is written to the log, because copying
  //          changes no document (D36: only the result of an operation reaches the op-log). The line
  //          beside the chart says what was taken, with the numbers that make it checkable: how many
  //          bars, how many of them carried structure, and how many strokes came with them.
  // KEYWORDS: copy, clipboard, no-event, ink-carried, numbers-stated, d35
  void _copySelection(BuildContext context) {
    final EditSession? session = _currentSession;
    final ChartSelection? range = _selectionRange;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (session == null || range == null) {
      debugPrint('viewer.selection.copy.skipped reason=no-selection');
      return;
    }
    final ChartClip? clip = session.copySelection(range);
    final SelectionReport report = selectionReportOf(
      song: session.song,
      strokes: session.document.strokes,
      selection: range,
    );
    if (clip == null) {
      setState(() => _selectionStatus = l10n.selectionCopyNothing);
      debugPrint('viewer.selection.copy.skipped reason=no-bars range=$range');
      return;
    }
    setState(() {
      _clip = clip;
      _selectionStatus = l10n.selectionCopied(
        range.barCount,
        // The MUSICIAN's number, counted across the sections from the top of the chart, exactly as
        // the selection label counts it: the log may keep the model's zero-based index, but a
        // sentence a musician reads must not.
        _writtenBarOrdinal(session.song, range.sectionId, range.firstBar),
      );
    });
    debugPrint(
      'viewer.selection.copy range=$range depth=${range.depth.name} '
      'bars=${clip.barCount} beats=${clip.beatCount} '
      'strokes=${clip.strokes.length} '
      'structured=${report.structuredBars} minimal=${report.minimalBars} '
      'ink_area=${report.inkArea.toStringAsFixed(1)}',
    );
  }

  // PURPOSE: Put the copied fragment after the selected bar (or into the selected cell), as ONE edit.
  // INPUTS: context — for the catalogue.
  // OUTPUTS: Nothing. Appends at most one event, rebuilds the page, and states the outcome in words —
  //          including every refusal, because a paste that silently did nothing is the defect the
  //          outcome value exists to prevent.
  // KEYWORDS: paste, one-undo, outcome-stated, refusal-logged, d35, d36
  void _pasteSelection(BuildContext context) {
    final EditSession? session = _currentSession;
    final ChartSelection? range = _selectionRange;
    final ChartClip? clip = _clip;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (session == null || range == null || clip == null) {
      debugPrint(
        'viewer.selection.paste.skipped '
        'session=${session == null ? 'none' : 'ok'} '
        'range=${range == null ? 'none' : 'ok'} '
        'clip=${clip == null ? 'none' : 'ok'}',
      );
      return;
    }
    // THE COUNT AND THE ORDINALS ARE READ BEFORE THE PASTE, because after it the questions have
    // different answers: a log line that printed the same number twice would be a line nobody could
    // check. The insertion moves nothing before its own address, so the ordinals read here are still
    // the ones the sentence means.
    final int before =
        session.document.song.sectionById(range.sectionId)?.bars.length ?? 0;
    final ClipPasteOutcome outcome = session.pasteClip(at: range, clip: clip);
    // The numbers the sentence needs, in the musician's own counting.
    final int targetOrdinal = _writtenBarOrdinal(
      session.song,
      range.sectionId,
      range.lastBar,
    );
    final int cellBarOrdinal = _writtenBarOrdinal(
      session.song,
      range.sectionId,
      range.firstBar,
    );
    setState(() {
      _selectionStatus = switch (outcome) {
        ClipPasteOutcome.pasted =>
          clip.depth == SelectionDepth.bars
              ? l10n.selectionPastedAfter(targetOrdinal, clip.barCount)
              : l10n.selectionPastedInto(
                  cellBarOrdinal,
                  (range.firstBeat ?? 0) + 1,
                ),
        ClipPasteOutcome.needsCell => l10n.selectionPasteNeedsCell,
        ClipPasteOutcome.windowDoesNotFit => l10n.selectionPasteDoesNotFit,
        ClipPasteOutcome.noSuchSection ||
        ClipPasteOutcome.noSuchBar ||
        ClipPasteOutcome.noSuchRun => l10n.selectionPasteNoBar,
      };
      // A PASTED RUN OF BARS MOVES THE ADDRESS THE SELECTION NAMES — the bar the musician was on is
      // still the bar he was on, and the run landed after it — so the pending range is dropped rather
      // than left to name bars that have shifted under it.
      //
      // AND THE CONSEQUENCE IS NAMED HERE BECAUSE IT COSTS THE MUSICIAN TAPS. The owner's workflow
      // ends with "транспонировать вставленное", and after this paste the selection is a single bar
      // again, so the pasted run has to be re-named with two taps and the "До сюда" action before the
      // transposition can act on it. The alternative — leaving the pasted run selected — was tried and
      // reverted: a selection here is a `ChartHit`, which holds a `PlacedBar` from the page that is on
      // screen, and the pasted bars exist only in the engraving the NEXT build produces. Selecting
      // them would mean a second, address-shaped copy of the selection kept beside this one until that
      // build ran, which is exactly the duplicated selection D36 forbids.
      if (outcome == ClipPasteOutcome.pasted &&
          clip.depth == SelectionDepth.bars) {
        _selectionEnd = null;
      }
    });
    debugPrint(
      'viewer.selection.paste outcome=${outcome.name} at=$range '
      'depth=${clip.depth.name} bars=${clip.barCount} '
      'strokes=${clip.strokes.length} '
      'undo=${session.undoDepth} bars_before=$before '
      'bars_after=${session.document.song.sectionById(range.sectionId)?.bars.length ?? 0}',
    );
  }

  // PURPOSE: Move the chords and the melody of the selected bars up a semitone, as ONE edit, leaving
  //          the chart's key and every bar outside the selection alone — and saying out loud what
  //          happened to the handwriting, which cannot move.
  // INPUTS: context — for the catalogue.
  // OUTPUTS: Nothing. Appends at most one event and states the counts: how many of the selected bars
  //          changed, and how many strokes the selection carries that stay exactly where they were
  //          drawn. A selection with nothing structured says so instead of writing an empty event.
  // KEYWORDS: transpose-selection, one-undo, key-unchanged, ink-not-transposed, counts-stated, d35
  void _transposeSelection(BuildContext context) {
    final EditSession? session = _currentSession;
    final ChartSelection? range = _selectionRange;
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (session == null || range == null) {
      debugPrint('viewer.selection.transpose.skipped reason=no-selection');
      return;
    }
    final SelectionTransposition report = session.transposeSelection(
      selection: range,
      semitones: 1,
    );
    setState(() {
      _selectionStatus = switch (report.outcome) {
        SelectionTransposeOutcome.applied => l10n.selectionTransposed(
          report.barsChanged,
          report.barsTotal,
        ),
        SelectionTransposeOutcome.nothingToTranspose =>
          l10n.selectionTransposeNothing,
        SelectionTransposeOutcome.beatsOnly => l10n.selectionTransposeBeats,
        SelectionTransposeOutcome.noSuchSection => l10n.selectionTransposeNoBar,
      };
    });
    debugPrint(
      'viewer.selection.transpose outcome=${report.outcome.name} '
      'range=$range bars_changed=${report.barsChanged} '
      'bars_total=${report.barsTotal} strokes_kept=${report.strokesKept} '
      'semitones=${report.semitones} key=${session.song.key} '
      'undo=${session.undoDepth}',
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
        onChanged: () => setState(() {
          _selection = null;
          _selectionEnd = null;
        }),
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
    // THE TOOL'S OWN WORDS WHILE A TOOL IS IN FORCE, AND THE PEN'S WERE THE ONES MISSING. Its icon is
    // a pencil and its tooltip needs a long press on a tablet, so the one place a mode can say what it
    // does in words is this line: with nothing selected the line has nothing else to say, and a
    // musician who has just pressed a tool is exactly the person who needs to be told what a touch
    // will do. The eraser has had its sentence since A64; **the pen never had one, and the owner's own
    // report is what that costs** — he wrote that the interface "only draws, with the stylus and with
    // the finger" and could not find selection at all, while the line under the chart said "tap a bar
    // to select it" the whole time. A sentence that describes a gesture the current tool has taken
    // away is worse than no sentence: it is a promise the next touch breaks.
    // AND THE LOCK'S OWN WORDS, WHILE THE SCALE IS FIXED. Its button is a padlock and its state is a
    // colour, and A64 established that a glyph plus a colour is how a mode goes unnoticed. The order
    // is deliberate: a selection is what the musician just touched and outranks everything; a fixed
    // scale comes next, because it changes what the whole screen will do; the tool's hint is last,
    // because it only changes what one touch will do.
    final String text = hit == null
        ? (_viewLocked
              ? l10n.viewLockActiveHint
              : (_inkOn
                    ? l10n.penActiveHint
                    : (_eraserOn
                          ? l10n.eraserActiveHint
                          : l10n.selectionPrompt)))
        : _runLabel(song, hit, l10n);
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
    //
    // THE TWO ACTIONS BELONG TO THE SAME WRAP AS THE TWO TEXTS, AND THAT IS A FIX RATHER THAN A
    // TIDY-UP. They used to sit in a `Row` under the label inside a `Column`, so a selected cell
    // always cost a SECOND row: on the owner's tablet that was 24 logical pixels of chart height —
    // measured on the device, the page's top edge sat 24 logical pixels lower with a cell selected
    // than without one — spent on a row that had 1 300 logical pixels of empty width beside it. A
    // `Wrap` holding all four runs keeps them on one line wherever one line fits and falls back to
    // two only where the pane really cannot hold them, which is the same rule the label and the hint
    // already follow. `WrapCrossAlignment.center` keeps the two texts on the buttons' centre line
    // rather than at their top, which is what makes one row read as one row.
    final bool cellSelected = editable && session != null;
    // THE RUN, AND WHAT IT IS MADE OF. `range` is the same address the copy, paste and transpose
    // actions act on, and `report` is what makes the two levels of quality sayable: a musician has to
    // be able to tell a fragment that will transpose from one that will only travel (D37 point 4),
    // and "12 bars selected" says neither. Both are computed from the document, not from a cached
    // copy of it, so an edit that changes a bar changes the sentence.
    final ChartSelection? range = _selectionRange;
    final SelectionReport? report = session == null || range == null
        ? null
        : selectionReportOf(
            song: session.song,
            strokes: session.document.strokes,
            selection: range,
          );
    final String? quality = report == null
        ? null
        : l10n.selectionQuality(
            report.barCount,
            report.structuredBars,
            report.inkOnlyBars,
            report.emptyBars,
          );
    final String? inkNote = report == null || report.strokeCount == 0
        ? null
        : l10n.selectionInkKept(report.strokeCount);
    return Padding(
      padding: UiKit.paneRowPadding,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (onTap == null)
            label
          else
            InkWell(
              key: const ValueKey<String>('viewer-selection-edit'),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: label,
              ),
            ),
          // THE TWO LEVELS OF QUALITY, BESIDE THE RANGE AND NOT BEHIND A TAP. A fragment that looks
          // the same but behaves differently is the lie this project spent a day removing, so the
          // sentence stands in the same line as the selection, every time: how many bars carry
          // structure (and will therefore transpose), how many carry only handwriting (and will
          // therefore only travel), and — when there is ink in the selection — that the ink cannot be
          // transposed and will stay exactly where it was drawn.
          if (quality != null)
            Text(
              quality,
              key: const ValueKey<String>('viewer-selection-quality'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (inkNote != null)
            Text(
              inkNote,
              key: const ValueKey<String>('viewer-selection-ink'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (_selectionStatus != null)
            Text(
              _selectionStatus!,
              key: const ValueKey<String>('viewer-selection-status'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          if (cellSelected) ...<Widget>[
            _SelectionAction(
              widgetKey: 'viewer-selection-chord',
              label: l10n.viewerChord,
              onTap: () => _editSelection(context),
            ),
            _SelectionAction(
              widgetKey: 'viewer-selection-note',
              label: l10n.viewerNote,
              onTap: () => _editNoteSelection(context),
            ),
          ],
          // THE FOUR ACTIONS OF THE OWNER'S WORKFLOW, in the order he says it in: select, copy,
          // paste, transpose (D35). They live in this line rather than in the app bar because the app
          // bar's width is the scarce resource A49 measured, and because every one of them acts on
          // exactly what this line names — putting them anywhere else would separate the words from
          // the address they apply to.
          if (range != null && session != null) ...<Widget>[
            _SelectionAction(
              widgetKey: 'viewer-selection-extend',
              label: l10n.selectionActionExtend,
              onTap: () => _armExtend(context),
            ),
            _SelectionAction(
              widgetKey: 'viewer-selection-copy',
              label: l10n.selectionActionCopy,
              onTap: () => _copySelection(context),
            ),
            if (_clip != null)
              _SelectionAction(
                widgetKey: 'viewer-selection-paste',
                label: l10n.selectionActionPaste,
                onTap: () => _pasteSelection(context),
              ),
            _SelectionAction(
              widgetKey: 'viewer-selection-transpose',
              label: l10n.selectionActionTransposeUp,
              onTap: () => _transposeSelection(context),
            ),
          ],
          // WHAT THE NEXT TAP WILL DO, while "until here" is armed. It replaces the edit hint rather
          // than standing beside it: the hint says what a tap on the LINE does, and while a run is
          // being completed the question a musician has is what a tap on the PAGE will do.
          if (_extendPending)
            Text(
              l10n.selectionExtendPrompt,
              key: const ValueKey<String>('viewer-selection-extend-prompt'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  // PURPOSE: Say what is selected when a RUN is selected rather than a single bar, so the words beside
  //          the chart name the same fragment the highlight covers.
  // INPUTS: song — the chart on screen, for the musician's bar numbering. hit — the anchor of the run.
  //         l10n — the catalogue.
  // OUTPUTS: The run sentence for a run, and the single-hit sentence otherwise (through
  //          [_selectionLabel]), which keeps the one-bar case worded exactly as it was: nothing about
  //          selecting one bar changed, so nothing about how it is described should.
  // KEYWORDS: selection-label, run, beat-window, one-based, single-hit-unchanged
  String _runLabel(Song song, ChartHit hit, AppLocalizations l10n) {
    final ChartSelection? range = _selectionRange;
    if (_selectionEnd == null || range == null) {
      return _selectionLabel(song, hit, l10n);
    }
    if (range.isBeatWindow) {
      return l10n.selectionRunWindow(
        _writtenBarOrdinal(song, range.sectionId, range.firstBar),
        range.firstBeat! + 1,
        range.lastBeat! + 1,
      );
    }
    return l10n.selectionRunRange(
      _writtenBarOrdinal(song, range.sectionId, range.firstBar),
      _writtenBarOrdinal(song, range.sectionId, range.lastBar),
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
  //          page or as a page at a time, under the musician's own zoom and pan.
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
  //
  //          EVERY BRANCH IS WRAPPED IN THE TWO-FINGER GESTURE, and that is the one place in this
  //          file where owner decision D34 is turned into a recogniser. It is wrapped here rather
  //          than around the page because the gesture has to be an ANCESTOR of the pager: a
  //          recogniser only competes for a pointer that hits it or a descendant, and the whole
  //          reason `TwoFingerViewGestureRecognizer` accepts on the second touch is so that it wins
  //          the arena before the pager's horizontal drag does.
  //
  //          THE ENGRAVING IS CACHED AND THE VIEW IS NOT. A pan rebuilds this subtree on every
  //          frame, and re-engraving there would pay the FIT search — up to 24 layout passes — for a
  //          move that only changes where the same page is drawn. [_engraveFor] holds the pages
  //          against the inputs that determine them, so a frame during a gesture reuses them and
  //          only wraps them in a new view.
  // KEYWORDS: pagination, fit, fit-fallback, page-scale, layout-call, page-view, empty-song,
  //           legibility-message, fallback-notice, ink-layering, cue-layering, a50, two-finger,
  //           view-zoom, view-pan, engraving-cache, d34
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
        // THE PANE'S OWN SIZE, PRINTED WHEN IT CHANGES AND NOWHERE ELSE. This is the number the
        // hideable chrome is FOR — `FIT` engraves from the pane's width AND its verdict depends on
        // the pane's height — and a claim about it that nobody can read off the running application
        // is exactly the kind of number this project has three times caught being asserted rather
        // than measured. Logging on a CHANGE rather than per frame is what keeps it off the pen's
        // path: a pan rebuilds this subtree every frame, and a line per frame would be a flood.
        if (_loggedPaneWidth != pageWidth || _loggedPaneHeight != pageHeight) {
          _loggedPaneWidth = pageWidth;
          _loggedPaneHeight = pageHeight;
          debugPrint(
            'viewer.page.pane width=${pageWidth.toStringAsFixed(1)} '
            'height=${pageHeight.toStringAsFixed(1)} '
            'area=${(pageWidth * pageHeight).toStringAsFixed(0)} '
            'chrome_hidden=$_chromeHidden mode=${mode.name} '
            'view_locked=$_viewLocked '
            'locked_clamped=${_lockedClampedReason ?? 'no'} '
            'song="${_rawTitleFor(entry)}"',
          );
        }
        _lastPageMode = mode;
        // The view belongs to the chart and the page mode it is being read in — not to the app. A
        // fresh chart opens at the identity, and switching how the chart is engraved starts the
        // view over, because every rectangle the old pan pointed at is a different one now.
        //
        // UNLESS THE VIEW IS LOCKED. A locked view is the musician saying "do not move this"; a reset
        // he did not ask for is the same class of surprise as a palm moving the page, which is what
        // the lock exists to remove. The lock re-derives its own zoom from the new engraving, so a
        // mode change while locked keeps the SIZE and only changes how the chart is laid out.
        final Object viewOwner = (entry.index, mode);
        if (_viewOwner != viewOwner) {
          _viewOwner = viewOwner;
          if (!_viewLocked) {
            _viewZoom = 1;
            _viewPan = LayoutOffset.zero;
          }
          _lastDrawnPage = null;
        }
        if (!pageWidth.isFinite ||
            !pageHeight.isFinite ||
            pageWidth <= 0 ||
            pageHeight <= 0 ||
            displayed.writtenBarCount == 0) {
          return Center(child: Text(l10n.noBars));
        }
        final _Engraving engraving = _engraveFor(
          entry,
          displayed,
          mode,
          pageWidth,
          pageHeight,
          textCues,
        );
        final List<PageLayout> pages = engraving.pages;
        if (pages.isEmpty) {
          return Center(child: Text(l10n.noBars));
        }
        // The mode reported to `_pageGeometry` is the one DRAWN, so a driving tool re-engraves the
        // paginated pages it is actually looking at instead of asking FIT again and getting an
        // empty answer. The scale is the PAGE MODE's; the view is reported separately.
        _lastPageMode = engraving.drawnMode;
        _lastPageScale = pages.first.scale;
        final Widget chart;
        if (engraving.fit?.page != null) {
          chart = _tappablePage(
            _viewed(pages.first),
            displayed,
            layer,
            textCues,
          );
        } else {
          final Widget pager = PageView.builder(
            key: ValueKey<int>(entry.index),
            itemCount: pages.length,
            itemBuilder: (BuildContext context, int index) => _tappablePage(
              _viewed(pages[index]),
              displayed,
              layer,
              textCues,
            ),
          );
          final FitOutcome? outcome = engraving.fit;
          chart = outcome == null
              ? pager
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    pager,
                    // IGNORED BY THE POINTER, so the band states the substitution WITHOUT taking a
                    // contact away from the page under it. The page's own contract is that a touch
                    // on its white space — exactly where a musician may miss a bar — is reported
                    // and clears the selection; a band that swallowed the page's top strip would
                    // break that contract in the one mode where the page already has the least room.
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
        return _chartGestures(chart);
      },
    );
  }

  // PURPOSE: Put the chart's two view gestures in front of the chart — the TWO-finger pan and pinch
  //          of owner decision D34, and the ONE-contact pan that the Select tool owns — so that
  //          neither is handed to the pager underneath and a single contact in a writing tool is
  //          never taken from it.
  // INPUTS: child — the chart, already carrying the current view.
  // OUTPUTS: The chart with both recognisers in front of it. The callbacks are re-bound on every
  //          build, and each recogniser itself is REUSED by `RawGestureDetector` for as long as the
  //          widget is in the same place, which is what lets a gesture survive the rebuild its own
  //          first frame caused: a recogniser replaced mid-gesture would lose the pointers it is
  //          measuring and the gesture would end at the first frame it moved.
  //
  //          WHY BOTH LIVE IN ONE DETECTOR. They answer two different questions about the same
  //          contacts — "are there two of them?" and "has this one travelled far enough to be a
  //          drag?" — and putting them in one detector is what makes the arena resolve between them
  //          once, deepest first, instead of two detectors racing at different depths. The
  //          two-finger recogniser needs no help to win: it resolves on the second contact. The
  //          one-contact pan resolves at `kTouchSlop` because the pager does, and being the deeper
  //          of the two it is asked first.
  //
  //          THE GATE IS BOUND TO THE INK LAYER AND NOT TO A RULE OF ITS OWN. [refuseTouch] asks
  //          `InkCaptureLayer.refuseViewGestureTouch`, so the question "may this contact move the
  //          page?" is answered by the one object that also answers "may this contact write?" — the
  //          palm rule, the width arbitration and the pen's open contact all live there, and a copy
  //          here is exactly how the two answers would come to disagree. See the ink layer for why
  //          a palm-like contact and a pen that is on the glass are both refusals, and for why the
  //          pen's one-second proximity window is no longer one of them.
  // KEYWORDS: gesture-detector, recogniser-factory, stable-across-rebuild, d34, palm-refusal,
  //           single-rule-binding, one-finger-pan, select-tool
  Widget _chartGestures(Widget child) => RawGestureDetector(
    // OPAQUE, so a touch on the page's own white space still reaches the recognisers: that is where
    // the musician's fingers most often land, and a deferring detector would let exactly those
    // touches fall through to nothing.
    behavior: HitTestBehavior.opaque,
    gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
      TwoFingerViewGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TwoFingerViewGestureRecognizer>(
            () => TwoFingerViewGestureRecognizer(),
            (TwoFingerViewGestureRecognizer recognizer) {
              recognizer.callbacks = TwoFingerViewCallbacks(
                onStart: _onViewGestureStart,
                onUpdate: _onViewGestureUpdate,
                onEnd: _onViewGestureEnd,
              );
              recognizer.refuseTouch = _refuseViewGestureTouch;
              recognizer.onTouchRefused = _onViewGestureTouchRefused;
            },
          ),
      PagePanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<PagePanGestureRecognizer>(
            () => PagePanGestureRecognizer(),
            (PagePanGestureRecognizer recognizer) {
              recognizer.refusePan = _refusePan;
              recognizer.onPanStart = _onPagePanStart;
              recognizer.onPanUpdate = _onPagePanUpdate;
              recognizer.onPanEnd = _onPagePanEnd;
              recognizer.onPanRefused = _onPagePanRefused;
            },
          ),
    },
    child: child,
  );

  // PURPOSE: Answer whether one touch may become part of the two-finger view gesture, which is the
  //          ruling that keeps a resting palm from panning the page under a writing hand.
  // INPUTS: event — the engine's pointer-down, whose kind, radius and timestamp are the three
  //         numbers the ink layer's rule reads.
  // OUTPUTS: Null when the touch is admitted, otherwise the ink layer's own reason token. A null
  //          layer — a build in which the pane has not made one yet — admits, because a gesture
  //          refused by an absence would be a control that works only sometimes.
  // KEYWORDS: view-gesture-gate, palm-rule-delegation, null-admits, no-second-copy
  String? _refuseViewGestureTouch(PointerDownEvent event) {
    final InkCaptureLayer? layer = _activeInkLayer;
    if (layer == null) {
      return null;
    }
    return layer.refuseViewGestureTouch(
      kind: event.kind,
      width: InkInputMapper.contactWidthOf(event),
      time: InkInputMapper.millisOf(event),
    );
  }

  // PURPOSE: Report a touch the view gesture refused, so the owner's defect has a log line that
  //          names which half of the rule fired rather than a silently missing pan.
  // INPUTS: event — the refused pointer-down. reason — the ink layer's stable reason token.
  // OUTPUTS: Nothing. One line per refused contact: a CONTACT, not a move, so this cannot flood a
  //          log the way a per-sample probe would, and cannot cost anything on the pen's path.
  // KEYWORDS: view-gesture-refusal, instrumented-decision, palm-like-width, pen-in-play, cheap-once
  void _onViewGestureTouchRefused(PointerDownEvent event, String reason) {
    debugPrint(
      'viewer.view.gesture.refuse pointer=${event.pointer} reason=$reason '
      'kind=${event.kind.name} width=${InkInputMapper.contactWidthOf(event).toStringAsFixed(1)} '
      'at=(${event.localPosition.dx.toStringAsFixed(1)},'
      '${event.localPosition.dy.toStringAsFixed(1)})',
    );
  }

  // PURPOSE: Produce the pages of one chart for one pane, once, and hand back the same pages while
  //          the inputs that determine them are unchanged.
  // INPUTS: entry — the song, for the fallback log line and for identity in the key. displayed —
  //         the chart to engrave. mode — the mode asked for. width and height — the pane. cues — the
  //         document's remarks, whose reserved rows change where the bars sit.
  // OUTPUTS: An [_Engraving] holding the pages, the mode they are really drawn in — FIT falls back
  //          to PAGES below the legible floor, see A50 — and the FIT verdict when FIT was asked, so
  //          the notice above the pages can still name the floor it refused to cross. A cache hit
  //          returns the value the last identical input produced, without re-running the search.
  // KEYWORDS: engraving-cache, cache-key, fit-fallback, layout-call, per-frame-cost, d34
  _Engraving _engraveFor(
    IRealSong entry,
    Song displayed,
    PageMode mode,
    double width,
    double height,
    List<TextCue> cues,
  ) {
    final _EngravingKey key = _EngravingKey(
      mode: mode,
      width: width,
      height: height,
      song: displayed,
      cues: cues,
    );
    final _Engraving? cached = _engraved;
    if (cached != null && _engravedKey == key) {
      return cached;
    }
    final _Engraving fresh;
    if (mode == PageMode.fit) {
      final FitOutcome outcome = _meteredLayout(
        () => _engine.fitToPage(
          displayed,
          pageWidth: width,
          pageHeight: height,
          cues: cues,
        ),
      );
      final PageLayout? page = outcome.page;
      if (page != null) {
        fresh = _Engraving(
          pages: <PageLayout>[page],
          drawnMode: PageMode.fit,
          fit: outcome,
        );
      } else {
        // --- THE FIT FALLBACK -------------------------------------------------------------
        // FIT could not put the song on one page above the legible floor, so the chart is shown
        // PAGINATED rather than left blank. The decision and the reasons behind it are recorded
        // beside [_fitFallbackNotice] and in `docs/sdd.md` A50; this is where it is carried out.
        final List<PageLayout> fallback = _meteredLayout(
          () => _engine.layout(
            displayed,
            pageWidth: width,
            pageHeight: height,
            cues: cues,
          ),
        );
        fresh = _Engraving(
          pages: fallback,
          drawnMode: PageMode.pages,
          fit: outcome,
        );
        if (fallback.isNotEmpty) {
          debugPrint(
            'viewer.page.fit.fallback song="${_rawTitleFor(entry)}" '
            'pane=${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)} '
            'floor=${outcome.scale} pages=${fallback.length} '
            'bar0=${fallback.first.bars.length} '
            'requested=${_chosenPageMode == PageMode.fit ? 'explicit' : 'default'}',
          );
        }
      }
    } else {
      fresh = _Engraving(
        pages: _meteredLayout(
          () => _engine.layout(
            displayed,
            pageWidth: width,
            pageHeight: height,
            cues: cues,
          ),
        ),
        drawnMode: PageMode.pages,
      );
    }
    _engravedKey = key;
    _engraved = fresh;
    return fresh;
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
  //
  //          THE HONEST BOUND OF NOTE RECOGNITION USED TO BE A SECOND LINE HERE — «Распознавание
  //          читает только высоту: длительность и знак не читаются.» — and it is gone for a reason
  //          rather than for space: the note reader is not wired to the switch yet (see
  //          `_recogniseWholePage`), so while only divisions are recognised that sentence would be
  //          describing a reader that is not running. It comes back WITH the call site, in the same
  //          change, because a recognised note is drawn as a quarter and nothing on the page can say
  //          that its rhythm was not read.
  // KEYWORDS: status-bar, summary, playlist-name, honest-bound-deferred
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
      padding: UiKit.statusPadding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(summary, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

// PURPOSE: Draw the one glyph this application could not take from the icon font: an eraser.
//          The bundled Material Icons of this Flutter version carry NO eraser at all — their nearest
//          relatives are the `auto_fix_*` wands, and `Icons.highlight_remove` renders as a circle
//          with a cross, which reads as "cancel" and was rejected after looking at it on the tablet.
//          A wand is worse still: the owner's report is that the eraser is missing outright, and a
//          glyph that suggests a feature does something FOR him is a candidate explanation for that.
//          So the tool gets the picture everyone already knows, drawn from two rectangles.
// INPUTS: color — the ink the glyph is stroked and tipped with, taken from the button's own icon
//         theme so a disabled or selected button tints it the way Material does.
// OUTPUTS: A [CustomPaint] of exactly 24 logical pixels square, which is the icon slot every
//          [IconButton] in this bar reserves. Nothing throws; every coordinate is a constant.
// KEYWORDS: eraser-glyph, custom-paint, no-font-glyph, discoverability, tool-icon, self-contained
class _EraserGlyph extends StatelessWidget {
  /// Creates the eraser glyph in [color].
  const _EraserGlyph({required this.color});

  /// The colour the outline and the eraser's tip are drawn in.
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: CustomPaint(painter: _EraserGlyphPainter(color)),
  );
}

/// Paints the eraser: a block tilted the way a hand holds one, with the working tip filled in.
class _EraserGlyphPainter extends CustomPainter {
  /// Creates a painter in [color].
  const _EraserGlyphPainter(this.color);

  /// The colour of the outline and of the tip.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double unit = size.shortestSide / 24;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // A hand holds an eraser tilted; the tilt is what makes the block read as an eraser rather than
    // as a card. About 32 degrees, which is the angle the two corners still clear the square at.
    canvas.rotate(-0.56);
    final RRect body = RRect.fromRectAndRadius(
      Rect.fromLTRB(-8 * unit, -5 * unit, 8 * unit, 5 * unit),
      Radius.circular(1.6 * unit),
    );
    canvas.drawRRect(body, Paint()..color = color.withValues(alpha: 0.18));
    // THE TIP IS THE PART THAT DOES THE WORK, so it is the only part drawn solid: a reader who sees
    // only two shapes still sees "a block with a working end", which is what an eraser is.
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(
      Rect.fromLTRB(1.5 * unit, -6 * unit, 9 * unit, 6 * unit),
      Paint()..color = color,
    );
    canvas.restore();
    canvas.drawRRect(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * unit,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EraserGlyphPainter old) => old.color != color;
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

// PURPOSE: Measure what the pen path costs, so a latency claim about handwriting is a number in the
//          log rather than an adjective. The two numbers that matter are the pair the defect is
//          made of: how many SAMPLES arrived, and how many full chart ENGRAVINGS those samples paid
//          for. A sample that triggers an engraving is a sample that re-measured every bar of the
//          song, re-packed its systems and re-paginated them, and the cost of that grows with the
//          melody band, with the number of systems and — in FIT mode — with a bisection over the
//          whole song. Alongside them the time spent serialising the verification probe state is
//          counted, because that publication scales with every stroke the document has accumulated
//          and is therefore the other thing that can make a later stroke slower than the first.
//
//          WHY A REPORT AND NOT AN ASSERTION. Nothing here fails: it writes a line. A measurement
//          that a passing test suite could not see is exactly what this project needed when a
//          latency regression arrived in the owner's hand with every gate green.
// INPUTS: Nothing; the numbers are about one screen's pen path.
// OUTPUTS: A `viewer.pen.cost` line, at most once per [_reportIntervalMs] while a stroke is being
//          drawn, carrying the elapsed time, the sample count, the layout pass count and the two
//          accumulated millisecond totals. A stroke that ends contributes no final line, so the
//          last report of a stroke is partial: the sample count at its end is in the stroke's own
//          `ink.stroke.commit` line, which is the number to compare across builds.
//
//          WHAT `publish_ms` MEANS NOW, AND WHY A READER MUST NOT MISREAD IT AS A REGRESSION. It
//          accumulates the cost of publications that a stroke OWED, and those publications now run
//          after the pen has left the glass, so this number is zero for as long as the contact
//          lasts and the publication is charged to the report of whichever stroke is open when it
//          finally runs. Zero here therefore means "nothing on the pen path serialised anything",
//          which is the property the number was introduced to establish; the total is still worth
//          reading, because a total that grows with the document is still an O(ink) job, and the
//          question of whether it can be made cheaper is left open rather than hidden.
// KEYWORDS: pen-latency, cost-measurement, layout-passes, structured-log, no-flood, ldd,
//           publish-when-idle
class _PenPathCost {
  int _samples = 0;
  int _layoutPasses = 0;
  int _layoutMicros = 0;
  int _publishMicros = 0;
  DateTime _strokeStart = DateTime.now();
  int _lastReportMicros = 0;

  /// How often a report may be written while a stroke lasts.
  ///
  /// Four hundred milliseconds is a fifth of a slow stroke and several reports for a long one, which
  /// is enough to see the cost GROW as the stroke lengthens without turning the log itself into a
  /// cost: a line per sample would be a hundred lines a second at the sample rate a working pen
  /// delivers, and reading the log would then perturb what it measures.
  static const int _reportIntervalMs = 400;

  /// Starts counting for a new stroke, dropping whatever the previous one accumulated.
  void beginStroke() {
    _samples = 0;
    _layoutPasses = 0;
    _layoutMicros = 0;
    _publishMicros = 0;
    _strokeStart = DateTime.now();
    _lastReportMicros = 0;
  }

  /// Records that one more pointer sample arrived.
  void noteSample() => _samples++;

  /// Records one chart engraving and how long it took.
  void noteLayout(int micros) {
    _layoutPasses++;
    _layoutMicros += micros;
  }

  /// Records the time one probe publication took.
  void notePublish(int micros) => _publishMicros += micros;

  /// Returns the report line when one is due, or null when the interval has not elapsed.
  ///
  /// The line is written even when nothing is wrong, because the point is the ratio the reader
  /// compares across two builds: `layout_passes` equal to `samples` means the page was re-engraved
  /// once per pen sample, and `layout_passes` zero means it never was.
  String? reportIfDue() {
    final int elapsedMicros = DateTime.now()
        .difference(_strokeStart)
        .inMicroseconds;
    if (_lastReportMicros != 0 &&
        elapsedMicros - _lastReportMicros < _reportIntervalMs * 1000) {
      return null;
    }
    _lastReportMicros = elapsedMicros;
    if (_samples == 0) {
      return null;
    }
    final double perSample = _layoutMicros / 1000 / _samples;
    return 'viewer.pen.cost elapsed_ms=${(elapsedMicros / 1000).round()} '
        'samples=$_samples layout_passes=$_layoutPasses '
        'layout_ms=${(_layoutMicros / 1000).toStringAsFixed(1)} '
        'layout_per_sample_ms=${perSample.toStringAsFixed(2)} '
        'publish_ms=${(_publishMicros / 1000).toStringAsFixed(1)}';
  }
}

/// The reference a two-finger gesture is measured from, fixed at the moment it started.
///
/// WHY THE REFERENCE AND NOT THE PREVIOUS FRAME. A gesture that measured from the last update would
/// integrate every rounding of every frame, and a slow drag would drift away from the fingers; and a
/// zoom about the focal point has to keep the page point that was under the fingers AT THE START
/// under them at the end, which is a statement about two moments and not about two frames.
class _ViewGestureAnchor {
  /// Creates the reference for a gesture that began at [focal] with [span].
  const _ViewGestureAnchor({
    required this.zoom,
    required this.pan,
    required this.focal,
    required this.span,
    required this.pageScale,
  });

  /// The magnification in force when the gesture began.
  final double zoom;

  /// The pan in force when the gesture began, in pane pixels.
  final LayoutOffset pan;

  /// Where the two fingers' middle was when the gesture began, in pane pixels.
  final Offset focal;

  /// How far apart the fingers were when the gesture began, as a mean radius in pixels.
  final double span;

  /// The page mode's own scale, so the arithmetic can work in surface pixels without consulting the
  /// page on every frame — it cannot change while a gesture is in progress.
  final double pageScale;
}

/// Every input an engraving depends on, so a cache hit is exactly the same page.
///
/// A value type rather than a string key on purpose: a string would have to render the song, which
/// is the work the cache exists to avoid, and an equality over the values the engine actually reads
/// cannot collide. `Song`, `TextCue` and `Section` all carry value equality, which is what makes
/// this a comparison and not an identity test.
class _EngravingKey {
  /// Creates a key for [song] engraved at [mode] on a [width] x [height] pane with [cues].
  const _EngravingKey({
    required this.mode,
    required this.width,
    required this.height,
    required this.song,
    required this.cues,
  });

  /// The page mode the engraving was asked for.
  final PageMode mode;

  /// The pane width in logical pixels.
  final double width;

  /// The pane height in logical pixels.
  final double height;

  /// The chart that was engraved, in the key it is displayed in.
  final Song song;

  /// The document's text cues, whose reserved rows change where the bars sit.
  final List<TextCue> cues;

  @override
  bool operator ==(Object other) {
    if (other is! _EngravingKey ||
        other.mode != mode ||
        other.width != width ||
        other.height != height ||
        other.song != song ||
        other.cues.length != cues.length) {
      return false;
    }
    for (int index = 0; index < cues.length; index++) {
      if (other.cues[index] != cues[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(mode, width, height, song, Object.hashAll(cues));
}

/// What one engraving of a chart produced: the pages and the mode they were drawn in.
///
/// The mode travels with the pages because FIT can fall back to PAGES (A50), and a caller that
/// re-derived the mode would report the mode it ASKED for rather than the one on screen.
class _Engraving {
  /// Creates an engraving of [pages] drawn in [drawnMode], with the FIT outcome when there was one.
  const _Engraving({required this.pages, required this.drawnMode, this.fit});

  /// The pages, in reading order.
  final List<PageLayout> pages;

  /// The mode the pages are actually drawn in.
  final PageMode drawnMode;

  /// The FIT verdict, or null when FIT was never asked.
  final FitOutcome? fit;
}
