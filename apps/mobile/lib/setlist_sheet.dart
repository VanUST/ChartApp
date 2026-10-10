// PURPOSE: Offer the programme — the setlist a musician plays from — as one sheet over the chart:
//          name it, put a chart into it, take one out, move one, and change how one is played (its
//          transposition and its note). Every button applies through [SetlistSession], so the
//          programme is an op-log document with the same undo and redo a chart has, and the scene
//          playback of an entry is the sheet's "play" action.
//          It is the setlist half of the edit loop: `setlist_session.dart` decides which event each
//          operation is, and this file decides where the buttons go and what a tap does.
// INPUTS: The session being edited, the loaded songs (to offer one when adding), a resolver from an
//         entry's `documentId` to the title a musician reads, a callback that plays one entry, and a
//         callback the sheet calls after every applied edit.
// OUTPUTS: A modal bottom sheet whose result is nothing: every button applies through
//          [SetlistSession] as it is pressed, so by the time the sheet closes the programme already
//          holds the edit. Undo and redo are shown in the sheet itself, because the programme has
//          its own log and its own history: undoing a setlist edit must not be confused with
//          undoing a chord, and a musician cannot see which one they would get from one app-bar
//          button.
// KEYWORDS: setlist, programme, sheet, rename, insert, delete, move, transposition, notes, undo,
//           redo, op-log, scene-playback
//
// WHY THE TITLE COMES FROM A RESOLVER AND NOT FROM THE LOADED SONG. A chart can be renamed in the
// editor, and the viewer already answers "the name to show" from the session that holds the rename.
// A sheet that read `IRealSong.title` directly would keep showing the imported name after the chart
// was renamed — the same two-names-for-one-song defect the viewer's own title path exists to prevent.
//
// WHY THE ENTRY EDIT IS A DIALOG AND NOT A STEPPER IN THE ROW. Two facts belong to an entry — the
// interval it is played at and the note the performer reads — and a row that changed the interval on
// a stray tap would edit the running order by accident, on a surface a musician holds one-handed. The
// dialog states both on one plate and commits them together, so an entry is either as it was or as
// the dialog said.
//
// WHY A CHART MAY APPEAR TWICE. `SetlistItem` has no identity of its own — two entries can play the
// same chart — and `insertItem` does not refuse a duplicate. A programme that plays an encore twice
// is a real programme, and a sheet that silently dropped the second entry would be the app deciding
// that the band does not do that.
import 'dart:async';

import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one only in strings; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'ireal_library.dart';
import 'sheet_button.dart';
import 'sheet_surface.dart';

// PURPOSE: Open the programme sheet for [session] and resolve when the musician is finished.
// INPUTS: context — where to open the sheet. session — the setlist document being edited. songs —
//         the loaded library, used to offer a chart when one is added. titleFor — the resolver that
//         names an entry's chart, so a rename made in the editor is reflected here. onPlay — called
//         with the entry index when the musician presses play; the sheet closes before the call so
//         the chart the entry names is visible. onChanged — called after every applied edit so the
//         caller can rebuild.
// OUTPUTS: A future that completes when the sheet is dismissed, whether anything was edited or not.
// KEYWORDS: show, bottom-sheet, setlist-edit, scene-play, title-resolver, callback, guard
/// Opens the programme sheet over the chart.
Future<void> showSetlistSheet(
  BuildContext context, {
  required SetlistSession session,
  required List<IRealSong> songs,
  required String Function(String documentId) titleFor,
  required ValueChanged<int> onPlay,
  VoidCallback? onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: sheetPanelColor,
  isScrollControlled: true,
  builder: (BuildContext context) => SetlistSheet(
    session: session,
    songs: songs,
    titleFor: titleFor,
    onPlay: onPlay,
    onChanged: onChanged,
  ),
);

/// The programme sheet itself: the title, the ordered entries and the two histories.
class SetlistSheet extends StatefulWidget {
  /// Creates a programme sheet over [session], resolving entries against [songs].
  const SetlistSheet({
    super.key,
    required this.session,
    required this.songs,
    required this.titleFor,
    required this.onPlay,
    this.onChanged,
  });

  /// The setlist document being edited.
  final SetlistSession session;

  /// The loaded songs, in payload order, offered when a chart is added.
  final List<IRealSong> songs;

  /// Names the chart an entry's [SetlistItem.documentId] refers to.
  ///
  /// A function rather than a map because the viewer answers it from the sessions it holds, which is
  /// where a rename lives; a map built here would be a copy that goes stale on the next rename.
  final String Function(String documentId) titleFor;

  /// Called with the entry index when the musician plays one.
  final ValueChanged<int> onPlay;

  /// Called after every applied edit.
  final VoidCallback? onChanged;

  @override
  State<SetlistSheet> createState() => _SetlistSheetState();
}

/// The sheet's state: the title field's controller.
class _SetlistSheetState extends State<SetlistSheet> {
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.session.setlist.title,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // PURPOSE: Rebuild the sheet after an applied edit and tell the caller, so the page behind the
  //          sheet — which may be drawn from the same programme — is not left showing the old
  //          running order.
  // INPUTS: changed — whether the last press actually changed the document.
  // OUTPUTS: Nothing.
  // KEYWORDS: rebuild, change-propagation, guard
  void _after(bool changed) {
    setState(() {});
    if (changed) {
      widget.onChanged?.call();
    }
  }

  // PURPOSE: Name the chart an entry plays, so a row shows the title a musician knows rather than
  //          the importer's positional id.
  // INPUTS: documentId — the entry's chart id.
  // OUTPUTS: The chart's display title, or `(missing chart)` when no loaded song carries that id —
  //          which is a real state after a library that did not contain the entry is loaded, and is
  //          stated rather than shown as an empty string.
  // KEYWORDS: title-resolution, document-id, missing-chart, honest-fallback
  String _titleFor(String documentId) => widget.titleFor(documentId);

  // PURPOSE: Word how one entry is played, so a row states the transposition and the note together
  //          and a zero interval is named rather than left blank.
  // INPUTS: item — the entry.
  // OUTPUTS: A subtitle such as `written · count off` or `+2 st · ballad`.
  // KEYWORDS: subtitle, interval-label, notes, reading-order
  String _subtitleFor(SetlistItem item) {
    final String interval = item.transposeSem == 0
        ? 'written'
        : '${item.transposeSem > 0 ? '+' : ''}${item.transposeSem} st';
    return item.notes.isEmpty ? interval : '$interval · ${item.notes}';
  }

  @override
  Widget build(BuildContext context) {
    final Setlist setlist = widget.session.setlist;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Programme',
                      style: TextStyle(
                        color: sheetOnPanelColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SheetButton(
                    buttonKey: 'setlist-undo',
                    icon: Icons.undo,
                    label: 'Undo',
                    onTap: widget.session.canUndo
                        ? () => _after(widget.session.undo())
                        : null,
                  ),
                  const SizedBox(width: 8),
                  SheetButton(
                    buttonKey: 'setlist-redo',
                    icon: Icons.redo,
                    label: 'Redo',
                    onTap: widget.session.canRedo
                        ? () => _after(widget.session.redo())
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('setlist-title'),
                controller: _titleController,
                style: const TextStyle(color: sheetOnPanelColor),
                decoration: const InputDecoration(
                  labelText: 'Programme name',
                  labelStyle: TextStyle(color: sheetMutedColor),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: sheetMutedColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: sheetAccentColor),
                  ),
                ),
                onSubmitted: (String value) =>
                    _after(widget.session.rename(value)),
                onEditingComplete: () =>
                    _after(widget.session.rename(_titleController.text)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: setlist.items.isEmpty
                    ? const Center(
                        child: Text(
                          'The programme is empty.\nAdd a chart from the library.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: sheetMutedColor),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey<String>('setlist-items'),
                        itemCount: setlist.items.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _entryRow(index, setlist.items[index]),
                      ),
              ),
              const SizedBox(height: 8),
              SheetButton(
                buttonKey: 'setlist-insert',
                icon: Icons.playlist_add,
                label: 'Add a chart to the programme',
                onTap: () => unawaited(_addEntry(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // PURPOSE: Draw one entry as a row of the running order, with the play action and the operations
  //          that change the order.
  // INPUTS: index — the entry's position. item — the entry.
  // OUTPUTS: A row widget. Up is disabled on the first entry, down on the last, and delete is
  //          always available: removing the only entry is legal and leaves the empty programme the
  //          model allows.
  // KEYWORDS: entry-row, position, play, move, edit, delete, bounds-disabled
  Widget _entryRow(int index, SetlistItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: sheetCellColor,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: sheetAccentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _titleFor(item.documentId),
                    key: ValueKey<String>('setlist-entry-title-$index'),
                    style: const TextStyle(
                      color: sheetOnPanelColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _subtitleFor(item),
                    key: ValueKey<String>('setlist-entry-subtitle-$index'),
                    style: const TextStyle(
                      color: sheetMutedColor,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey<String>('setlist-play-$index'),
              icon: const Icon(Icons.play_arrow),
              color: sheetAccentColor,
              tooltip: 'Play this chart from the programme',
              onPressed: () {
                Navigator.of(context).pop();
                widget.onPlay(index);
              },
            ),
            IconButton(
              key: ValueKey<String>('setlist-up-$index'),
              icon: const Icon(Icons.arrow_upward),
              color: sheetOnPanelColor,
              tooltip: 'Move earlier',
              onPressed: index == 0
                  ? null
                  : () => _after(widget.session.moveItem(index, index - 1)),
            ),
            IconButton(
              key: ValueKey<String>('setlist-down-$index'),
              icon: const Icon(Icons.arrow_downward),
              color: sheetOnPanelColor,
              tooltip: 'Move later',
              onPressed: index == widget.session.items.length - 1
                  ? null
                  : () => _after(widget.session.moveItem(index, index + 1)),
            ),
            IconButton(
              key: ValueKey<String>('setlist-edit-$index'),
              icon: const Icon(Icons.tune),
              color: sheetOnPanelColor,
              tooltip: 'How this entry is played',
              onPressed: () => unawaited(_editEntry(context, index, item)),
            ),
            IconButton(
              key: ValueKey<String>('setlist-delete-$index'),
              icon: const Icon(Icons.delete_outline),
              color: const Color(0xFFFF8A80),
              tooltip: 'Remove from the programme',
              onPressed: () => _after(widget.session.deleteItem(index)),
            ),
          ],
        ),
      ),
    ),
  );

  // PURPOSE: Change how one entry is played, on one plate: the interval it is transposed by and the
  //          note the performer reads.
  // INPUTS: context — where to open the dialog. index — the entry. item — its current value, which
  //         is the dialog's starting point.
  // OUTPUTS: A future that completes when the dialog closes. The session is edited only when the
  //          musician confirms, and only when the confirmed value differs; a cancel changes nothing.
  // KEYWORDS: entry-edit, transposition-stepper, notes, confirm-or-cancel, no-op-refusal
  Future<void> _editEntry(
    BuildContext context,
    int index,
    SetlistItem item,
  ) async {
    final TextEditingController notes = TextEditingController(text: item.notes);
    int semitones = item.transposeSem;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              backgroundColor: sheetPanelColor,
              title: Text(
                _titleFor(item.documentId),
                style: const TextStyle(color: sheetOnPanelColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Transposition for this entry (the chart keeps its written key)',
                    style: TextStyle(color: sheetMutedColor, fontSize: 12),
                  ),
                  Row(
                    children: <Widget>[
                      IconButton(
                        key: const ValueKey<String>('setlist-transpose-down'),
                        icon: const Icon(Icons.remove),
                        color: sheetOnPanelColor,
                        onPressed: () => setDialogState(() => semitones -= 1),
                      ),
                      Text(
                        '${semitones > 0 ? '+' : ''}$semitones st',
                        key: const ValueKey<String>('setlist-transpose-value'),
                        style: const TextStyle(
                          color: sheetAccentColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey<String>('setlist-transpose-up'),
                        icon: const Icon(Icons.add),
                        color: sheetOnPanelColor,
                        onPressed: () => setDialogState(() => semitones += 1),
                      ),
                    ],
                  ),
                  TextField(
                    key: const ValueKey<String>('setlist-notes'),
                    controller: notes,
                    style: const TextStyle(color: sheetOnPanelColor),
                    decoration: const InputDecoration(
                      labelText: 'Note for the performer',
                      labelStyle: TextStyle(color: sheetMutedColor),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const ValueKey<String>('setlist-edit-ok'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('OK'),
                ),
              ],
            ),
      ),
    );
    final int chosen = semitones;
    final String written = notes.text;
    notes.dispose();
    if (confirmed != true) {
      return;
    }
    _after(
      widget.session.updateItem(index, transposeSem: chosen, notes: written),
    );
  }

  // PURPOSE: Put a chart from the library into the programme, chosen from the loaded songs.
  // INPUTS: context — where to open the dialog. The lookup read here, not at confirm: the action is
  //         one tap and the list does not change while the dialog is open.
  // OUTPUTS: A future that completes when the dialog closes. A picked song is appended to the
  //          programme; dismissing changes nothing. A duplicate is allowed and stated on the
  //          subtitle of the row it lands in.
  // KEYWORDS: add-entry, chart-picker, append, duplicate-allowed, dismissable
  Future<void> _addEntry(BuildContext context) async {
    final IRealSong? picked = await showDialog<IRealSong>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: sheetPanelColor,
        title: const Text(
          'Add a chart',
          style: TextStyle(color: sheetOnPanelColor),
        ),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.builder(
            itemCount: widget.songs.length,
            itemBuilder: (BuildContext context, int index) {
              final IRealSong song = widget.songs[index];
              return ListTile(
                key: ValueKey<String>('setlist-add-$index'),
                dense: true,
                title: Text(
                  widget.titleFor(song.song.id),
                  style: const TextStyle(color: sheetOnPanelColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${song.song.key} · ${song.song.writtenBarCount} bar(s)',
                  style: const TextStyle(color: sheetMutedColor, fontSize: 12),
                ),
                onTap: () => Navigator.of(context).pop(song),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null) {
      return;
    }
    _after(
      widget.session.insertItem(SetlistItem(documentId: picked.song.id)) !=
          null,
    );
  }
}
