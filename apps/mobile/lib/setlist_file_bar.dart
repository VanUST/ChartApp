// PURPOSE: Give a programme two buttons — save it to a `.setlist` file the reader names, and open a
//          `.setlist` file into the app — from the Programme sheet, so a running order a musician
//          built survives the session it was built in. It is the programme's half of the same plate
//          `chart_file_bar.dart` puts on a chart, and it uses the same platform seam to move the
//          bytes.
// INPUTS: The programme's [SetlistSession] to save, the path or file name the field starts with, a
//         callback that receives the setlist a file decoded to and returns the sentence to show
//         about it, and — injected for a probe — the two functions that move bytes. The defaults are
//         the platform's own, selected by `chart_source.dart` at compile time.
// OUTPUTS: An app-bar-shaped control that opens a dialog holding a name field, Save and Open, a
//          sentence naming what a save on this platform actually does, and a one-line status. Where
//          [chartSourceIsFilePath] is false — a browser — the field holds a file NAME to offer the
//          platform's chooser rather than a path.
// KEYWORDS: setlist-file, save, open, programme, sheet, dialog, platform-seam, status-line,
//           missing-chart
//
// WHY THE CALLER — NOT THIS DIALOG — DECIDES WHAT THE STATUS SAYS ABOUT AN OPENED FILE.
//
// Whether a programme's entries find their charts is a question about the LIBRARY that is loaded,
// and the library belongs to the viewer; a dialog that answered it would need the songs, the
// resolution rule and the identity function, and would then be a second place that decides what
// "found" means. So the callback returns the sentence and this file renders it, exactly as
// `chart_file_bar.dart` renders the sentence the container's own warnings produce.
import 'dart:async';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:flutter/material.dart';

import 'chart_source.dart';
import 'document_file_name.dart';
import 'l10n/app_localizations.dart';
import 'setlist_document.dart';

/// Moves a `.setlist` container's bytes to the place the reader named.
typedef SetlistFileSaver = Future<void> Function(String path, Uint8List bytes);

/// Reads a `.setlist` container's bytes from the place the reader named.
typedef SetlistFileOpener = Future<Uint8List> Function(String path);

/// What an opened `.setlist` file gives the viewer: the document id its operation log is keyed by,
/// the programme the file stored, and the operation tail it carried beside that programme.
///
/// All three are handed over because the file holds all three and they mean different things:
/// `snapshot` is the programme BEFORE the tail, and the tail is what a session applying the two
/// together reaches, and what it must continue from rather than reissue. A caller that shows
/// `snapshot` and ignores the tail would show a running order missing every edit the file recorded;
/// a caller that reduces the two itself and then hands both over would run the history twice; and a
/// caller that re-derived the document id from the snapshot's own id would key the continued log by
/// something the events inside it do not agree with.
typedef OpenedSetlist = ({
  String docId,
  Setlist snapshot,
  List<SetlistEvent> events,
});

// PURPOSE: Open the `.setlist` save/open dialog for a programme, so the one plate is reachable from
//          wherever a programme is shown.
// INPUTS: context — where the dialog is shown. session — the programme being edited. initialPath —
//         the text the field starts with. onOpened — called with the programme and tail a file
//         decoded to; it returns the sentence the dialog shows about what was found. save and open
//         default to the platform implementations, so only a probe passes them.
// OUTPUTS: A future completing when the dialog is dismissed. The dialog stays open after an
//          operation, because the outcome is the part worth reading — the entry count, the charts
//          that could not be found, or the typed reason a damaged file was refused.
// KEYWORDS: setlist-file, dialog-entry, save, open, status-callback
/// Shows the `.setlist` save/open dialog described by the arguments.
Future<void> showSetlistFileDialog(
  BuildContext context, {
  required SetlistSession session,
  required String Function(OpenedSetlist opened) onOpened,
  String initialPath = '',
  SetlistFileSaver save = saveSetlistFile,
  SetlistFileOpener open = loadSetlistFile,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => _SetlistFileDialog(
    session: session,
    onOpened: onOpened,
    initialPath: initialPath,
    save: save,
    open: open,
  ),
);

/// The control that saves and opens a `.setlist` document.
class SetlistFileAction extends StatelessWidget {
  /// Creates the control for [session], reporting an opened programme through [onOpened].
  ///
  /// [save] and [open] default to the platform implementations from `chart_source.dart`, so the
  /// sheet passes neither and a probe can pass both without a filesystem.
  const SetlistFileAction({
    super.key,
    required this.session,
    required this.onOpened,
    this.initialPath = '',
    this.save = saveSetlistFile,
    this.open = loadSetlistFile,
  });

  /// The programme being edited.
  final SetlistSession session;

  /// Called with the programme and the operation tail a `.setlist` file decoded to; returns the
  /// sentence to show about it.
  final String Function(OpenedSetlist opened) onOpened;

  /// The text the dialog's field starts with, normally [setlistPathBeside] of the loaded export.
  final String initialPath;

  /// How the container's bytes reach the reader's disk.
  final SetlistFileSaver save;

  /// How the reader's file becomes bytes.
  final SetlistFileOpener open;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey<String>('setlist-file'),
    icon: const Icon(Icons.save_alt),
    tooltip: AppLocalizations.of(context).setlistFileTooltip,
    onPressed: () => unawaited(
      showSetlistFileDialog(
        context,
        session: session,
        onOpened: onOpened,
        initialPath: initialPath,
        save: save,
        open: open,
      ),
    ),
  );
}

/// The dialog behind [SetlistFileAction]: a name field, the two operations and their outcome.
class _SetlistFileDialog extends StatefulWidget {
  const _SetlistFileDialog({
    required this.session,
    required this.onOpened,
    required this.initialPath,
    required this.save,
    required this.open,
  });

  final SetlistSession session;
  final String Function(OpenedSetlist opened) onOpened;
  final String initialPath;
  final SetlistFileSaver save;
  final SetlistFileOpener open;

  @override
  State<_SetlistFileDialog> createState() => _SetlistFileDialogState();
}

/// The dialog's state: its text field, the save mechanism this platform actually has, the last
/// outcome, and whether an operation is running.
class _SetlistFileDialogState extends State<_SetlistFileDialog> {
  late final TextEditingController _controller;

  /// What a save will do here, read once when the dialog opens.
  ///
  /// Read once rather than per build because it cannot change while the dialog is up — it is a
  /// property of the browser, not of the programme.
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
  // INPUTS: None; [SetlistFileAction.initialPath] and the programme on screen.
  // OUTPUTS: The initial path when there is one, otherwise [setlistFileNameFor] of the programme's
  //          title, and `untitled.setlist` when it has no title either.
  // KEYWORDS: initial-value, file-name, path, title-fallback, empty-state
  String _initialFieldText() {
    final String given = widget.initialPath.trim();
    if (given.isNotEmpty) {
      return given;
    }
    return setlistFileNameFor(widget.session.setlist.title);
  }

  // PURPOSE: Write the programme on screen to the file the reader named, snapshot and operation tail
  //          together, and say afterwards which of the three saves actually happened.
  // INPUTS: None; the programme is [SetlistFileAction.session] and the destination is the field.
  // OUTPUTS: Nothing. Sets [_busy] around the write and [_status] afterwards with the byte count,
  //          the entry count, the operation count and what [ChartSaveMode] this platform has — so a
  //          reader whose file was re-written and one whose file was merely downloaded do not read
  //          the same sentence. An empty name and a dismissed chooser are reported rather than
  //          silently doing nothing.
  // KEYWORDS: save, encode, setlist-file, operation-tail, save-mode, status, error-reporting
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String path = _controller.text.trim();
    if (path.isEmpty) {
      setState(() => _status = l10n.setlistFileNameToSave);
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    debugPrint(
      'viewer.setlist.save.start mode=${_mode.name} path_chars=${path.length}',
    );
    try {
      final SetlistFile file = setlistFileFor(
        widget.session,
        modifiedAt: DateTime.now().toUtc(),
      );
      final SetlistFileEncodeResult encoded = SetlistFileCodec.encode(file);
      await widget.save(path, encoded.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = _savedStatus(encoded, path);
      });
      debugPrint(
        'viewer.setlist.save.ok mode=${_mode.name} bytes=${encoded.bytes.length} '
        'entries=${widget.session.items.length} '
        'operations=${widget.session.log.length}',
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
        'viewer.setlist.save.cancelled mode=${_mode.name} '
        'reason="${error.message}"',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileSaveFailed('$error');
      });
      debugPrint('viewer.setlist.save.error error=$error');
    }
  }

  // PURPOSE: Word the successful save so that re-writing a file and downloading a new one cannot be
  //          mistaken for each other, and so that every count is written in the reader's language.
  // INPUTS: encoded — what the codec produced, for the byte count and the D19 warnings. path — the
  //         path or file name the reader supplied. The catalogue comes from the context.
  // OUTPUTS: The status sentence: the byte count, the entry count, the operation count, any warning,
  //          and the platform's own promise about what a second save will do.
  // KEYWORDS: status, save-mode, in-place, download, honest-reporting, localized
  String _savedStatus(SetlistFileEncodeResult encoded, String path) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String bytes = l10n.byteCount(encoded.bytes.length);
    final String entries = l10n.entryCount(widget.session.items.length);
    final String operations = l10n.operationCount(widget.session.log.length);
    final String base = _mode == ChartSaveMode.namedPath
        ? l10n.setlistFileSavedTo(bytes, path, entries, operations)
        : l10n.setlistFileSavedAs(bytes, path, entries, operations);
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
  // OUTPUTS: One sentence, or the empty string where the platform replaces the named file.
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
  //          directly.
  // KEYWORDS: save-hint, file-system-access, download, up-front-disclosure, save-mode, localized
  String _saveHint() => switch (_mode) {
    ChartSaveMode.namedPath => '',
    ChartSaveMode.rewriteInPlace => AppLocalizations.of(
      context,
    ).setlistFileSaveHintRewriteInPlace,
    ChartSaveMode.download => AppLocalizations.of(
      context,
    ).setlistFileSaveHintDownload,
  };

  // PURPOSE: Read the `.setlist` file the reader named and hand its programme and operation tail to
  //          the viewer.
  // INPUTS: None; the source is the text field on a platform where that field is a path, and the
  //         browser's chooser in a browser.
  // OUTPUTS: Nothing, or a call to [SetlistFileAction.onOpened]. Sets [_busy] around the read and
  //          [_status] afterwards with the sentence the callback returned and any warning. A decode
  //          failure is shown as the typed message the container produced, which is the point of the
  //          shared failure family: a truncated file says it is truncated rather than looking like
  //          an empty programme. The programme handed over is the file's SNAPSHOT, because the
  //          session folds the tail in itself; handing over the reduction as well would apply every
  //          operation twice.
  // KEYWORDS: open, read, decode, snapshot, operation-tail, typed-failure, cancellation, status
  Future<void> _open() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String path = _controller.text.trim();
    if (chartSourceIsFilePath && path.isEmpty) {
      setState(() => _status = l10n.setlistFileNameToOpen);
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    debugPrint('viewer.setlist.open.start path_chars=${path.length}');
    try {
      final Uint8List bytes = await widget.open(path);
      final SetlistFileDecodeResult decoded = SetlistFileCodec.decode(bytes);
      final String reported = widget.onOpened((
        docId: decoded.file.metadata.docId,
        snapshot: decoded.file.snapshot,
        events: decoded.file.events,
      ));
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$reported${_warningSuffix(decoded.warnings)}';
      });
      debugPrint(
        'viewer.setlist.open.ok entries=${decoded.file.snapshot.items.length} '
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
      debugPrint('viewer.setlist.open.cancelled reason="${error.message}"');
    } on ContainerException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileOpenFailed(error.message);
      });
      debugPrint('viewer.setlist.open.refused type=${error.runtimeType}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = l10n.fileOpenFailed('$error');
      });
      debugPrint('viewer.setlist.open.error error=$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? status = _status;
    return AlertDialog(
      title: Text(l10n.setlistFileDialogTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('setlist-file-name'),
              controller: _controller,
              decoration: InputDecoration(
                // A label rather than a different widget, because the field is the same field: on a
                // filesystem its contents address the file, and in a browser they are the name the
                // chooser and the download are given.
                labelText: chartSourceIsFilePath
                    ? l10n.setlistFileLabelPath
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
          key: const ValueKey<String>('setlist-file-open'),
          onPressed: _busy ? null : () => unawaited(_open()),
          child: Text(l10n.setlistFileOpenButton),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('setlist-file-save'),
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
  String _warningSuffix(List<SetlistFileWarning> warnings) => warnings.isEmpty
      ? ''
      : ' ${AppLocalizations.of(context).warningCount(warnings.length)}: '
            '${warnings.first.message}';
}
