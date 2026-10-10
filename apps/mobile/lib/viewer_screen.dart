// PURPOSE: Show the songs an iReal export contains and render the selected one as a chart a
//          musician can read: in the key they choose, with the whole tune on one page or paginated,
//          and with the performance facts — position, tempo, style, key and repeats — on one bar.
//          It is a reader first: it shows the layout the engine produced and the issue list the
//          import reported.
// INPUTS: A reference the reader supplies, an [IRealLibraryLoader] that turns that reference into
//         an [IRealLibrary], a starting reference, whether a reference is a filesystem path at all,
//         and whether to load the starting reference on the first frame. The loader is injected so
//         a widget test can pump this screen with a synthetic payload and never touch the
//         filesystem, and so the web build can hand it a browser file chooser instead of a path.
// OUTPUTS: A screen with a source bar, a song list, a scene bar and the selected song's page or
//          pages, each drawn by `ChartPainter` at the size the window gives it.
// KEYWORDS: viewer, ireal, reader, screen, page-view, transposition, scene-bar, page-modes,
//           widget-test-seam, platform-seam, verification
//
// WHAT CHANGES ON THE WEB, AND WHAT DOES NOT. Everything below the source bar is identical on
// every platform, because nothing below it touches a file: the loader is the seam and it is the
// same seam the widget tests use. Only the source bar differs — a path field where a path exists
// and a file-picker button where the browser can only offer a choice — which is what
// [sourceIsFilePath] selects. A screen that cannot name a file must not pretend to.
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

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this screen
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'ireal_library.dart';
import 'ireal_source.dart';
import 'key_grid.dart';
import 'scene_bar.dart';

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

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath);
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
    super.dispose();
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
        'viewer.transpose.cancelled song="${entry.title}" '
        'picked=${picked == null ? 'none' : picked.key}',
      );
      return;
    }
    setState(() => _semitonesBySong[entry.index] = picked.semitones);
    debugPrint(
      'viewer.transpose.ok song="${entry.title}" written=${entry.song.key} '
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

  // PURPOSE: Produce the chart to show for one song, which is the written chart moved by the
  //          interval the musician chose, or the written chart itself when they chose nothing.
  // INPUTS: entry — the song. semitones — the stored interval.
  // OUTPUTS: The displayed song. At zero the written song is returned unchanged, so the common
  //          case does no work and the drawn result is identical to the loaded one.
  // KEYWORDS: display-song, transposition, identity-fast-path
  Song _displayedSong(IRealSong entry, int semitones) => semitones == 0
      ? entry.song
      : transposeSong(
          entry.song,
          semitones,
          toKey: _keyFor(entry.song.key, semitones),
        );

  @override
  Widget build(BuildContext context) {
    final String? error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('ChartApp — iReal reader')),
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
  //          says which charts are no longer in their written key.
  // KEYWORDS: song-list, selection, issue-count, shown-key, written-key
  Widget _buildSongList(BuildContext context, IRealLibrary library) {
    return ListView.builder(
      itemCount: library.songs.length,
      itemBuilder: (BuildContext context, int index) {
        final IRealSong entry = library.songs[index];
        final int semitones = _semitonesBySong[entry.index] ?? 0;
        final String keyLabel = semitones == 0
            ? '${entry.song.key}'
            : '${entry.song.key} → ${_keyFor(entry.song.key, semitones)}';
        final String subtitle =
            '${entry.song.writtenBarCount} bar(s) · $keyLabel'
            '${entry.issues.isEmpty ? '' : ' · ${entry.issues.length} issue(s)'}';
        return ListTile(
          dense: true,
          selected: index == _selectedSong,
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => setState(() => _selectedSong = index),
        );
      },
    );
  }

  // PURPOSE: Show one song: its identity, the scene bar with everything a performer reads, and the
  //          chart in the chosen key and page mode.
  // INPUTS: context — the build context. library — the loaded songs. songIndex — which one.
  // OUTPUTS: A column widget. The title stays visible above the scene bar because the song's name
  //          is the one thing the scene bar does not repeat.
  // KEYWORDS: song-pane, title, scene-bar, issue-button, pages
  Widget _buildSongPane(
    BuildContext context,
    IRealLibrary library,
    int songIndex,
  ) {
    final IRealSong entry = library.songs[songIndex];
    final int semitones = _semitonesBySong[entry.index] ?? 0;
    final Song displayed = _displayedSong(entry, semitones);
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
                  Expanded(
                    child: Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('${entry.song.writtenBarCount} bar(s)'),
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
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildPages(entry, displayed, mode)),
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

  // PURPOSE: Lay the displayed song out at the size the window gives it and show it as one fitted
  //          page or as a page at a time.
  // INPUTS: entry — the selected song, for identity. displayed — the chart to draw, in its chosen
  //         key. mode — FIT or PAGES.
  // OUTPUTS: The chart. PAGES is the layout engine's ordinary pagination in a [PageView]. FIT is
  //          one scaled page, or a message saying the song would have to be shrunk below the
  //          legible floor, which is reported on screen rather than delivered as an unreadable
  //          page. A song the layout engine produces no pages for says so instead of showing an
  //          empty page, because an empty song and a blank page must not look alike.
  // KEYWORDS: pagination, fit, page-scale, layout-call, page-view, empty-song, legibility-message
  Widget _buildPages(IRealSong entry, Song displayed, PageMode mode) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double pageWidth = constraints.maxWidth;
        final double pageHeight = constraints.maxHeight;
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
          );
          final PageLayout? page = outcome.page;
          if (page == null) {
            return _buildNoFit(context, outcome);
          }
          return CustomPaint(
            painter: ChartPainter(
              song: displayed,
              page: page,
              metrics: _metrics,
            ),
            child: const SizedBox.expand(),
          );
        }
        final List<PageLayout> pages = _engine.layout(
          displayed,
          pageWidth: pageWidth,
          pageHeight: pageHeight,
        );
        if (pages.isEmpty) {
          return const Center(child: Text('This song has no bars.'));
        }
        return PageView.builder(
          key: ValueKey<int>(entry.index),
          itemCount: pages.length,
          itemBuilder: (BuildContext context, int index) => CustomPaint(
            painter: ChartPainter(
              song: displayed,
              page: pages[index],
              metrics: _metrics,
            ),
            child: const SizedBox.expand(),
          ),
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
