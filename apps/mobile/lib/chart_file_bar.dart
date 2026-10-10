// PURPOSE: Give a `.chart` document a name and two buttons — save the document on screen to a file
//          the reader names, and open a `.chart` file into the app — from the viewer's app bar, so
//          the chart area keeps every pixel it had. It is a widget of its own so that the viewer
//          gains one line rather than a second state machine, and so the whole save/open path reads
//          in one place.
// INPUTS: The document to save, written form only, together with the operation tail that produced
//         it; a callback that receives the document and the tail read back from a file; and,
//         injected for a test, the two functions that move bytes. The defaults are the platform's
//         own, selected by `chart_source.dart` at compile time.
// OUTPUTS: An app-bar button that opens a dialog holding the path field, Save and Open, and a
//          one-line status. Where [chartSourceIsFilePath] is false — a browser — it renders nothing
//          at all, because there is no path to name and the functions behind the buttons are not
//          implemented there.
// KEYWORDS: chart-file, save, open, viewer, app-bar, dialog, d20, d19, platform-seam, status-line
//
// WHY THIS IS A DIALOG AND NOT A BAR ABOVE THE CHART.
//
// It was a bar above the chart first, and that was wrong for a reason worth recording: the viewer
// lays the chart out in whatever height the window has left, and a `.chart` bar takes about seventy
// logical pixels of it. Owner decision D13 makes a tablet open in FIT, and FIT already refuses to
// shrink a chart past a legible floor — so the bar did not merely move the page, it turned a
// 200-bar song that fitted on one page into "does not fit on one page legibly". Measured, not
// guessed: two page-mode tests and two selection tests failed with exactly that. A control that
// changes what the musician can read is not a control, so the entry moved into the app bar, whose
// height the actions do not change.
//
// WHY THE SAVED SONG IS THE WRITTEN ONE. A musician can transpose what is on screen (D14, the
// editor meaning). What belongs in the file is the written chart: transposition is a view, and
// saving the displayed key would bake a temporary choice into the document. The caller passes the
// written song and this widget does not know a transposition exists.
//
// WHY THE PROJECT IS SAVED AS A SNAPSHOT PLUS ITS OPERATION TAIL, AND WHY BOTH ARE HANDED OVER
// UNTOUCHED. The document on screen was produced by applying operations through the log, and the
// container stores a snapshot plus the operations after it. The snapshot is what makes the file
// readable by a build that does not understand every operation in it; the tail is what makes it an
// editing record rather than a picture, and it is what a restored session replays from. Folding the
// tail into the snapshot before saving would throw away the only copy of how the chart got to where
// it is, so neither half is derived from the other here.
import 'dart:async';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:flutter/material.dart';

import 'chart_document.dart';
import 'chart_source.dart';

/// Moves a container's bytes to the place the reader named.
typedef ChartFileSaver = Future<void> Function(String path, Uint8List bytes);

/// Reads a container's bytes from the place the reader named.
typedef ChartFileOpener = Future<Uint8List> Function(String path);

/// What an opened `.chart` file gives the viewer: the state the file stored and the operation tail
/// it carried beside that state.
///
/// Both are handed over because the file holds both and they mean different things: [document] is
/// the SNAPSHOT — the state BEFORE the tail — and the tail is what a session applying the two
/// together reaches, and what it must continue from rather than reissue. A caller that shows
/// [document] and ignores the tail would show a chart missing every edit the file recorded; a
/// caller that reduces the two itself and then hands both over would run the history twice. A
/// record rather than a small class because it is a pair of values passed straight through.
typedef OpenedChart = ({DocumentState document, List<ChartEvent> events});

// PURPOSE: Derive the `.chart` path that sits beside a source path, so the dialog's path field
//          starts with something sensible instead of empty.
// INPUTS: sourcePath — the iReal export's path, which may be empty in a browser or a label such as
//         a test's synthetic reference.
// OUTPUTS: The same path with its extension replaced by `.chart`, or with `.chart` appended when it
//          had none. An empty input gives an empty output, because there is nothing to sit beside.
//          A dot in a directory name is not treated as an extension: the search starts after the
//          last separator.
// KEYWORDS: path, default, extension, beside, empty-input
/// Returns [sourcePath] with its extension replaced by `.chart`.
String chartPathBeside(String sourcePath) {
  if (sourcePath.isEmpty) {
    return '';
  }
  final int separator = sourcePath.lastIndexOf(RegExp(r'[\\/]'));
  final int dot = sourcePath.lastIndexOf('.');
  if (dot > separator) {
    return '${sourcePath.substring(0, dot)}$chartFileExtension';
  }
  return '$sourcePath$chartFileExtension';
}

/// The app-bar control that saves and opens a `.chart` document.
class ChartFileAction extends StatelessWidget {
  /// Creates the control for [document], reporting an opened document through [onOpened].
  ///
  /// [save] and [open] default to the platform implementations from `chart_source.dart`, so the
  /// viewer passes neither and a test can pass both without a filesystem. [events] is the operation
  /// tail that produced [document] and is written beside the snapshot unchanged.
  const ChartFileAction({
    super.key,
    required this.document,
    required this.onOpened,
    this.events = const <ChartEvent>[],
    this.initialPath = '',
    this.save = saveChartFile,
    this.open = loadChartFile,
  });

  /// The written document to save, or null when nothing is loaded.
  ///
  /// A document and not a song, because a `.chart` file is a snapshot plus a log and both halves
  /// live on this value; a song alone would force the save path to invent an empty tail.
  final DocumentState? document;

  /// The operations applied since that document's snapshot, in log order.
  final List<ChartEvent> events;

  /// Called with the document and the operation tail a `.chart` file decoded to.
  final ValueChanged<OpenedChart> onOpened;

  /// The path the dialog's field starts with, normally [chartPathBeside] of the loaded export.
  final String initialPath;

  /// How the container's bytes reach the reader's disk.
  final ChartFileSaver save;

  /// How the reader's file becomes bytes.
  final ChartFileOpener open;

  @override
  Widget build(BuildContext context) {
    if (!chartSourceIsFilePath) {
      // A browser has no path to name and the functions behind the dialog are not implemented
      // there; showing the control would offer the reader something that cannot work.
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.description_outlined),
      tooltip: 'Save or open a .chart file',
      onPressed: () => unawaited(
        showDialog<void>(
          context: context,
          builder: (BuildContext context) => _ChartFileDialog(
            document: document,
            events: events,
            onOpened: onOpened,
            initialPath: initialPath,
            save: save,
            open: open,
          ),
        ),
      ),
    );
  }
}

/// The dialog behind [ChartFileAction]: a path field, the two operations and their outcome.
///
/// It stays open after an operation rather than closing on success, because the outcome is the part
/// worth reading — a D19 sidecar warning, the byte count, or the typed reason a damaged file was
/// refused — and closing would throw that away. The reader closes it when they have read it.
class _ChartFileDialog extends StatefulWidget {
  const _ChartFileDialog({
    required this.document,
    required this.events,
    required this.onOpened,
    required this.initialPath,
    required this.save,
    required this.open,
  });

  final DocumentState? document;
  final List<ChartEvent> events;
  final ValueChanged<OpenedChart> onOpened;
  final String initialPath;
  final ChartFileSaver save;
  final ChartFileOpener open;

  @override
  State<_ChartFileDialog> createState() => _ChartFileDialogState();
}

/// The dialog's state: its path field, the last outcome, and whether an operation is running.
class _ChartFileDialogState extends State<_ChartFileDialog> {
  late final TextEditingController _controller;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPath);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // PURPOSE: Write the document on screen to the file the reader named, snapshot and operation tail
  //          together.
  // INPUTS: None; the document is [ChartFileAction.document] and the destination is the path field.
  // OUTPUTS: Nothing. Sets [_busy] around the write and [_status] afterwards with the operation
  //          count, the byte count and any D19 warning, or the failure. A missing document and an
  //          empty path are reported in the status line rather than silently doing nothing.
  // KEYWORDS: save, encode, chart-file, operation-tail, d19, status, error-reporting
  Future<void> _save() async {
    final DocumentState? document = widget.document;
    if (document == null) {
      setState(() => _status = 'Load or import a song before saving it.');
      return;
    }
    final String path = _controller.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Name a .chart file to save to.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    debugPrint('viewer.chart.save.start path_chars=${path.length}');
    try {
      final ChartFile file = chartFileFor(
        document,
        events: widget.events,
        modifiedAt: DateTime.now().toUtc(),
      );
      final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
      await widget.save(path, encoded.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status =
            'Saved ${encoded.bytes.length} bytes to $path'
            ' · ${widget.events.length} operation(s).'
            '${_warningSuffix(encoded.warnings)}';
      });
      debugPrint(
        'viewer.chart.save.ok bytes=${encoded.bytes.length} '
        'operations=${widget.events.length} '
        'warnings=${encoded.warnings.length}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'Could not save: $error';
      });
      debugPrint('viewer.chart.save.error error=$error');
    }
  }

  // PURPOSE: Read the `.chart` file the reader named and hand its document and operation tail to the
  //          viewer.
  // INPUTS: None; the source is the path field.
  // OUTPUTS: Nothing, or a call to [ChartFileAction.onOpened]. Sets [_busy] around the read and
  //          [_status] afterwards with the title and any warning. A decode failure is shown as the
  //          typed message the container produced, which is the point of the container's failure
  //          types: a truncated file says it is truncated rather than looking like an empty chart.
  //          The document handed over is the file's REDUCED document — its snapshot with its
  //          operation tail folded in — because that is the chart the writer saw; the tail travels
  //          beside it so a session can continue the log rather than restart its numbering.
  // KEYWORDS: open, read, decode, reduced-document, operation-tail, typed-failure, status
  Future<void> _open() async {
    final String path = _controller.text.trim();
    if (path.isEmpty) {
      setState(() => _status = 'Name a .chart file to open.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    debugPrint('viewer.chart.open.start path_chars=${path.length}');
    try {
      final Uint8List bytes = await widget.open(path);
      final ChartFileDecodeResult decoded = ChartFileCodec.decode(bytes);
      // THE SNAPSHOT, NOT THE REDUCED DOCUMENT. The container's document is the snapshot PLUS the
      // operations, so a caller that hands over the reduction and the operations together is asking
      // the session to apply every operation twice: a bar insert doubles, a bar delete takes a
      // neighbouring bar, and a re-applied stroke is refused because a stroke with that id is
      // already there. The session folds the tail in itself, which is what makes the chart on
      // screen the chart the writer saw.
      final DocumentState document = decoded.file.snapshot;
      // The song a session opened from this file will reach, used for the status line only. It is
      // the reduction, because a `song.update` in the tail may have renamed the tune and the reader
      // should read the name they are about to see on the page.
      final Song shown = decoded.file.reducedDocument.song;
      if (!mounted) {
        return;
      }
      widget.onOpened((document: document, events: decoded.file.events));
      setState(() {
        _busy = false;
        _status =
            'Opened "$shown" · ${decoded.file.events.length} operation(s).'
            '${_warningSuffix(decoded.warnings)}';
      });
      debugPrint(
        'viewer.chart.open.ok bars=${shown.writtenBarCount} '
        'operations=${decoded.file.events.length} '
        'warnings=${decoded.warnings.length}',
      );
    } on ChartFileException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'Could not open: ${error.message}';
      });
      debugPrint('viewer.chart.open.refused type=${error.runtimeType}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'Could not open: $error';
      });
      debugPrint('viewer.chart.open.error error=$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? status = _status;
    return AlertDialog(
      title: const Text('Chart file'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '.chart file',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (String _) => unawaited(_open()),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => unawaited(_open()),
          child: const Text('Open .chart'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(_save()),
          icon: const Icon(Icons.save_alt),
          label: const Text('Save'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  /// The part of a status line that reports what was left out, or nothing when nothing was.
  static String _warningSuffix(List<ChartFileWarning> warnings) =>
      warnings.isEmpty
      ? ''
      : ' ${warnings.length} warning(s): ${warnings.first.message}';
}
