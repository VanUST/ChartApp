// PURPOSE: Give a `.chart` document a name and two buttons — save the document on screen to a file
//          the reader names, and open a `.chart` file into the app — from the viewer's app bar, so
//          the chart area keeps every pixel it had. It is a widget of its own so that the viewer
//          gains one line rather than a second state machine, and so the whole save/open path reads
//          in one place.
// INPUTS: The document to save, written form only, together with the operation tail that produced
//         it; a callback that receives the document and the tail read back from a file; and,
//         injected for a test, the two functions that move bytes. The defaults are the platform's
//         own, selected by `chart_source.dart` at compile time.
// OUTPUTS: An app-bar button that opens a dialog holding a text field, Save and Open, a sentence
//          naming what a save on this platform actually does, and a one-line status. Where
//          [chartSourceIsFilePath] is false — a browser — the field holds a file NAME to offer the
//          platform's chooser rather than a path, and the sentence says whether a save re-writes the
//          chosen file or downloads a new copy, because those are two different promises and the
//          reader is told which one is in force. The control is shown on every platform now that
//          both functions work on both.
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
import 'document_file_name.dart';
import 'l10n/app_localizations.dart';

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
//          The rule itself lives in [extensionPathBeside], shared with the `.setlist` dialog, so the
//          two cannot come to derive a file name in two different ways.
// KEYWORDS: path, default, extension, beside, empty-input, shared-rule
/// Returns [sourcePath] with its extension replaced by `.chart`.
String chartPathBeside(String sourcePath) =>
    extensionPathBeside(sourcePath, chartFileExtension);

// PURPOSE: Derive the `.chart` file name to offer when there is no source path to sit beside, which
//          is the browser's ordinary case: the iReal export was chosen through a chooser and left no
//          path behind, so the dialog would otherwise open with an empty field and a reader with
//          nothing to accept.
// INPUTS: title — the song's own title, which may be empty, may contain characters a filesystem
//         refuses, and may already end in `.chart`.
// OUTPUTS: The title with every character illegal in a file name replaced by `_` and `.chart`
//          appended, or `untitled.chart` when nothing usable is left — an ASCII token in every
//          language, because a file name travels and a label does not (see [documentFileNameFor]).
//          The sanitizing rule itself lives in [documentFileNameFor], shared with the `.setlist`
//          dialog.
// KEYWORDS: file-name, download, suggested-name, sanitize, empty-title, shared-rule
/// Returns a usable `.chart` file name for a song called [title].
String chartFileNameFor(String title) =>
    documentFileNameFor(title, chartFileExtension);

// PURPOSE: Open the `.chart` save/open dialog for a document, so the ONE dialog is reachable from
//          both places that offer it.
// INPUTS: context — where the dialog is shown. document — the written document to save, or null when
//         nothing is loaded. events — the operation tail that produced it. initialPath — the text the
//         field starts with. onOpened — called with the document and tail a file decoded to. save and
//         open default to the platform implementations, so only a test passes them.
// OUTPUTS: A future completing when the dialog is dismissed. The dialog itself is unchanged and
//          behaves identically whichever caller opened it, which is the point of the function: the
//          tablet's app-bar button and the phone's overflow menu call this same function, so the two
//          shells cannot come to mean different things by "Save or open a .chart file".
// KEYWORDS: chart-file, dialog-entry, one-dialog-two-callers, phone-overflow, tablet-app-bar
/// Shows the `.chart` save/open dialog described by the arguments.
Future<void> showChartFileDialog(
  BuildContext context, {
  required DocumentState? document,
  required ValueChanged<OpenedChart> onOpened,
  List<ChartEvent> events = const <ChartEvent>[],
  String initialPath = '',
  ChartFileSaver save = saveChartFile,
  ChartFileOpener open = loadChartFile,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => _ChartFileDialog(
    document: document,
    events: events,
    onOpened: onOpened,
    initialPath: initialPath,
    save: save,
    open: open,
  ),
);

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

  /// The text the dialog's field starts with, normally [chartPathBeside] of the loaded export.
  ///
  /// On a platform with a filesystem that is a path; in a browser it is empty, because the iReal
  /// export was chosen rather than named, and the dialog then offers [chartFileNameFor] of the
  /// song's title instead — a name the reader can accept, edit or clear before saving.
  final String initialPath;

  /// How the container's bytes reach the reader's disk.
  final ChartFileSaver save;

  /// How the reader's file becomes bytes.
  final ChartFileOpener open;

  // PURPOSE: The app-bar button's tooltip, which the catalogue words because the phone's overflow
  //          menu row that opens the same dialog already reads those words.
  // INPUTS: None; the wording comes from the context this builder was given.
  // OUTPUTS: The tooltip string.
  // KEYWORDS: tooltip, chart-file, one-wording
  String _tooltip(BuildContext context) =>
      AppLocalizations.of(context).menuChartFile;

  @override
  Widget build(BuildContext context) {
    // Shown on every platform. It used to render nothing in a browser, while the two functions
    // behind the dialog threw; now that they work there, hiding the control would hide a feature
    // that exists. What differs per platform is the field's MEANING — a path or a file name — and
    // the sentence describing what a save does, and the dialog is the only place that has to know.
    return IconButton(
      icon: const Icon(Icons.description_outlined),
      tooltip: _tooltip(context),
      onPressed: () => unawaited(
        showChartFileDialog(
          context,
          document: document,
          events: events,
          onOpened: onOpened,
          initialPath: initialPath,
          save: save,
          open: open,
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

/// The dialog's state: its text field, the save mechanism this platform actually has, the last
/// outcome, and whether an operation is running.
class _ChartFileDialogState extends State<_ChartFileDialog> {
  late final TextEditingController _controller;

  /// What a save will do here, read once when the dialog opens.
  ///
  /// Read once rather than per build because it cannot change while the dialog is up — it is a
  /// property of the browser, not of the document — and reading it in `build` would put a platform
  /// probe in the middle of the widget tree.
  late final ChartSaveMode _mode;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mode = chartSourceSaveMode();
    _controller = TextEditingController(text: _initialFieldText());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // PURPOSE: Decide what the field starts with, which is a path where the platform has one and a
  //          proposed file name where it does not.
  // INPUTS: None; [ChartFileAction.initialPath] and the document on screen.
  // OUTPUTS: The initial path when there is one, otherwise [chartFileNameFor] of the song's title,
  //          and the empty string when there is neither a path nor a document to name. An empty
  //          result is honest: there is nothing to propose, so the reader is asked to type one.
  // KEYWORDS: initial-value, file-name, path, title-fallback, empty-state
  String _initialFieldText() {
    final String given = widget.initialPath.trim();
    if (given.isNotEmpty) {
      return given;
    }
    final DocumentState? document = widget.document;
    if (document == null) {
      return '';
    }
    return chartFileNameFor(document.song.title);
  }

  // PURPOSE: Write the document on screen to the file the reader named, snapshot and operation tail
  //          together, and say afterwards which of the three saves actually happened.
  // INPUTS: None; the document is [ChartFileAction.document] and the destination is the text field.
  // OUTPUTS: Nothing. Sets [_busy] around the write and [_status] afterwards with the operation
  //          count, the byte count, any D19 warning and what [ChartSaveMode] this platform has — so
  //          a reader whose file was re-written and one whose file was merely downloaded do not read
  //          the same sentence. A missing document, an empty name and a dismissed chooser are
  //          reported in the status line rather than silently doing nothing.
  // KEYWORDS: save, encode, chart-file, operation-tail, d19, save-mode, status, error-reporting
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DocumentState? document = widget.document;
    if (document == null) {
      setState(() => _status = l10n.chartFileNoDocument);
      return;
    }
    final String path = _controller.text.trim();
    if (path.isEmpty) {
      setState(() => _status = l10n.chartFileNameToSave);
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    debugPrint(
      'viewer.chart.save.start mode=${_mode.name} path_chars=${path.length}',
    );
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
        _status = _savedStatus(encoded, path);
      });
      debugPrint(
        'viewer.chart.save.ok mode=${_mode.name} bytes=${encoded.bytes.length} '
        'operations=${widget.events.length} '
        'warnings=${encoded.warnings.length}',
      );
    } on ChartFileCancelledException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        // The outcome is worded by the catalogue rather than by the exception: the exception
        // carries the platform's own description of what happened, while "you changed your mind"
        // is interface text, and a dialog is the only side that can reach a message catalogue.
        _status = l10n.fileChooserCancelled;
      });
      debugPrint(
        'viewer.chart.save.cancelled mode=${_mode.name} reason="${error.message}"',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileSaveFailed('$error');
      });
      debugPrint('viewer.chart.save.error error=$error');
    }
  }

  // PURPOSE: Word the successful save so that re-writing a file and downloading a new one cannot be
  //          mistaken for each other, which is the whole reason the save mode is carried this far.
  // INPUTS: encoded — what the codec produced, for the byte count and the D19 warnings. path — the
  //         path or file name the reader supplied.
  // OUTPUTS: The status sentence: the byte count, the operation count, any warning, and the
  //          platform's own promise about what a second save will do.
  // KEYWORDS: status, save-mode, in-place, download, honest-reporting
  String _savedStatus(ChartFileEncodeResult encoded, String path) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String bytes = l10n.byteCount(encoded.bytes.length);
    final String operations = l10n.operationCount(widget.events.length);
    // `to` and `as` are two different promises — replacing a path, or being handed a file — and the
    // catalogue carries one sentence for each rather than a preposition the locale would have to
    // place itself.
    final String base = _mode == ChartSaveMode.namedPath
        ? l10n.chartFileSavedTo(bytes, path, operations)
        : l10n.chartFileSavedAs(bytes, path, operations);
    return _withSuffix(
      _withSuffix(base, _warningSuffix(encoded.warnings)),
      _saveModeSuffix(),
    );
  }

  // PURPOSE: Join a status sentence with a trailing clause that may be absent, so a sentence and a
  //          clause that is sometimes empty cannot run together with no space or keep a leading one.
  // INPUTS: base — the sentence. suffix — the clause, or the empty string when there is none.
  // OUTPUTS: The sentence alone, or the two joined by one space. Both empty inputs give the empty
  //          string.
  // KEYWORDS: text-join, optional-clause, spacing, empty-safe
  String _withSuffix(String base, String suffix) =>
      suffix.isEmpty ? base : '$base $suffix';

  // PURPOSE: Say, in the status line, what this platform's save did to the file that was already
  //          there — which is not the same answer on Chrome, on Safari and on a desktop.
  // INPUTS: None; [_mode] and the catalogue.
  // OUTPUTS: One sentence, or the empty string where the platform replaces the named file and there
  //          is nothing surprising to say.
  // KEYWORDS: save-mode, status-suffix, in-place, download, named-path, localized
  String _saveModeSuffix() => switch (_mode) {
    ChartSaveMode.namedPath => '',
    ChartSaveMode.rewriteInPlace => AppLocalizations.of(
      context,
    ).saveModeRewriteInPlace,
    ChartSaveMode.download => AppLocalizations.of(context).saveModeDownload,
  };

  // PURPOSE: Tell the reader, before they press Save, what this platform will do to a file that
  //          already exists — the difference between replacing their file and handing them another.
  // INPUTS: None; [_mode] and the catalogue.
  // OUTPUTS: One sentence in a browser, and the empty string where a path addresses the file
  //          directly, because there the promise is already what the field and the button say.
  // KEYWORDS: save-hint, file-system-access, download, up-front-disclosure, save-mode, localized
  String _saveHint() => switch (_mode) {
    ChartSaveMode.namedPath => '',
    ChartSaveMode.rewriteInPlace => AppLocalizations.of(
      context,
    ).chartFileSaveHintRewriteInPlace,
    ChartSaveMode.download => AppLocalizations.of(
      context,
    ).chartFileSaveHintDownload,
  };

  // PURPOSE: Read the `.chart` file the reader named and hand its document and operation tail to the
  //          viewer.
  // INPUTS: None; the source is the text field on a platform where that field is a path, and the
  //         browser's chooser in a browser, where the field holds only a name to propose.
  // OUTPUTS: Nothing, or a call to [ChartFileAction.onOpened]. Sets [_busy] around the read and
  //          [_status] afterwards with the title and any warning. A decode failure is shown as the
  //          typed message the container produced, which is the point of the container's failure
  //          types: a truncated file says it is truncated rather than looking like an empty chart.
  //          The document handed over is the file's SNAPSHOT — the state before its operation tail —
  //          because the session folds the tail in itself; handing over the reduction as well would
  //          apply every operation twice. The tail travels beside it so a session can continue the
  //          log rather than restart its numbering. A chooser the reader dismisses is reported with
  //          the catalogue's own sentence for a cancelled chooser, because changing one's mind is not
  //          a failure; the exception's own message is the platform's description of the dismissal
  //          and is written to the log beside the outcome, not onto the screen.
  // KEYWORDS: open, read, decode, snapshot, operation-tail, typed-failure, cancellation, status
  Future<void> _open() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String path = _controller.text.trim();
    if (chartSourceIsFilePath && path.isEmpty) {
      setState(() => _status = l10n.chartFileNameToOpen);
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
      // should read the name they are about to see on the page. The status line names the tune's
      // TITLE and not the song value: interpolating the `Song` printed its `toString()` — the whole
      // shape of the object, `Song(...)` — into a sentence a musician reads, which named neither
      // the tune nor anything else they asked for.
      final Song shown = decoded.file.reducedDocument.song;
      if (!mounted) {
        return;
      }
      widget.onOpened((document: document, events: decoded.file.events));
      setState(() {
        _busy = false;
        _status = _withSuffix(
          l10n.chartFileOpened(
            // The catalogue's own fallback for a nameless tune. The library hands back the
            // document's title exactly as it stands — empty when the export carried none — because
            // a word for "no name" is interface text and belongs to the same catalogue as
            // everything else this dialog prints, not to a data type.
            shown.title.isEmpty ? l10n.untitled : shown.title,
            l10n.operationCount(decoded.file.events.length),
          ),
          _warningSuffix(decoded.warnings),
        );
      });
      debugPrint(
        'viewer.chart.open.ok bars=${shown.writtenBarCount} '
        'operations=${decoded.file.events.length} '
        'warnings=${decoded.warnings.length}',
      );
    } on ChartFileCancelledException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileChooserCancelled;
      });
      debugPrint('viewer.chart.open.cancelled reason="${error.message}"');
    } on ChartFileException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileOpenFailed(error.message);
      });
      debugPrint('viewer.chart.open.refused type=${error.runtimeType}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileOpenFailed('$error');
      });
      debugPrint('viewer.chart.open.error error=$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? status = _status;
    return AlertDialog(
      title: Text(l10n.chartFileDialogTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                // A label rather than a different widget, because the field is the same field: on a
                // filesystem its contents address the file, and in a browser they are the name the
                // chooser and the download are given. A reader who typed a path into a browser field
                // labelled "path" would be told nothing and misled by the label.
                labelText: chartSourceIsFilePath
                    ? l10n.chartFileLabelPath
                    : l10n.fileNameLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (String _) => unawaited(_open()),
            ),
            if (_saveHint().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _saveHint(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
          child: Text(l10n.chartFileOpenButton),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(_save()),
          icon: const Icon(Icons.save_alt),
          label: Text(l10n.save),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }

  /// The part of a status line that reports what was left out, or nothing when nothing was.
  String _warningSuffix(List<ChartFileWarning> warnings) => warnings.isEmpty
      ? ''
      : ' ${AppLocalizations.of(context).warningCount(warnings.length)}: '
            '${warnings.first.message}';
}
