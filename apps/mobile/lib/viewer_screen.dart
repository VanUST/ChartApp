// PURPOSE: Show the songs an iReal export contains and render the selected one a page at a time,
//          so the importer can be checked against the application the file came from. This is a
//          reader for verification, not an editor: it shows the layout the engine produced, and
//          the issue list the import reported, without changing either.
// INPUTS: A path typed by the reader, an [IRealLibraryLoader] that turns a path into an
//         [IRealLibrary], a starting path, and whether to load that path on the first frame. The
//         loader is injected so a widget test can pump this screen with a synthetic payload and
//         never touch the filesystem.
// OUTPUTS: A screen with a path bar, a song list, and the selected song's pages, each drawn by
//          `ChartPainter` at the size the window gives it.
// KEYWORDS: viewer, ireal, reader, screen, page-view, widget-test-seam, verification

import 'dart:async';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/material.dart';

import 'ireal_library.dart';

/// Turns a path into the library it holds.
typedef IRealLibraryLoader = Future<IRealLibrary> Function(String path);

/// The screen that loads an iReal export and renders its songs.
class IRealViewerScreen extends StatefulWidget {
  /// Creates the viewer.
  const IRealViewerScreen({
    super.key,
    this.loader = loadIRealLibraryFromFile,
    this.initialPath = defaultIRealPath,
    this.autoLoad = true,
  });

  /// How a path becomes a library.
  final IRealLibraryLoader loader;

  /// The path the text field starts with.
  final String initialPath;

  /// Whether to load [initialPath] once, after the first frame.
  ///
  /// True in the application, so a launch shows a chart without a click. A test that wants to
  /// decide exactly when the loader runs passes false and presses Load itself.
  final bool autoLoad;

  @override
  State<IRealViewerScreen> createState() => _IRealViewerScreenState();
}

/// The viewer's state: the loaded library, which song is selected, and the last load error.
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

  late final TextEditingController _pathController;
  IRealLibrary? _library;
  int _selectedSong = 0;
  String? _error;
  bool _loading = false;

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
  //          on an unmounted state.
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

  // PURPOSE: Give the reader the path field and the button that starts a load.
  // INPUTS: context — the build context.
  // OUTPUTS: The bar widget. The button is disabled while a load is running, so two reads cannot
  //          race for the same state.
  // KEYWORDS: path-field, load-button, busy-guard
  Widget _buildPathBar(BuildContext context) {
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Load an iReal .html file to see its songs.\n'
            'Default: $defaultIRealPath',
            textAlign: TextAlign.center,
          ),
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
        Expanded(child: _buildSongPane(context, library.songs[songIndex])),
      ],
    );
  }

  // PURPOSE: List the loaded songs so one can be selected.
  // INPUTS: context — the build context. library — the loaded songs.
  // OUTPUTS: A scrollable list. Each row names the song, its bar count, its written key and, when
  //          there are any, its issue count.
  // KEYWORDS: song-list, selection, issue-count, written-key
  Widget _buildSongList(BuildContext context, IRealLibrary library) {
    return ListView.builder(
      itemCount: library.songs.length,
      itemBuilder: (BuildContext context, int index) {
        final IRealSong entry = library.songs[index];
        final String subtitle =
            '${entry.song.writtenBarCount} bar(s) · ${entry.song.key}'
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

  // PURPOSE: Show one song: its identity, its issue count, and its pages.
  // INPUTS: context — the build context. entry — the selected song.
  // OUTPUTS: A column widget. The header is outside the page area so the drawn page keeps the full
  //          remaining height for the layout engine to paginate into.
  // KEYWORDS: song-pane, header, issue-button, pages
  Widget _buildSongPane(BuildContext context, IRealSong entry) {
    final String style = entry.song.style.isEmpty
        ? 'no style'
        : entry.song.style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${entry.title} — $style',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${entry.song.key} · ${entry.song.writtenBarCount} bar(s)'),
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
        const Divider(height: 1),
        Expanded(child: _buildPages(entry)),
      ],
    );
  }

  // PURPOSE: Lay the song out at the size the window gives it and show one page at a time.
  // INPUTS: entry — the selected song.
  // OUTPUTS: A [PageView] over the layout's pages, one page on screen. A song the layout engine
  //          produces no pages for says so instead of showing an empty page, because an empty song
  //          and a blank page must not look alike.
  // KEYWORDS: pagination, layout-call, page-view, window-sized, empty-song
  Widget _buildPages(IRealSong entry) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double pageWidth = constraints.maxWidth;
        final double pageHeight = constraints.maxHeight;
        if (!pageWidth.isFinite ||
            !pageHeight.isFinite ||
            pageWidth <= 0 ||
            pageHeight <= 0) {
          return const SizedBox.shrink();
        }
        final List<PageLayout> pages = _engine.layout(
          entry.song,
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
              song: entry.song,
              page: pages[index],
              metrics: _metrics,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

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
