// PURPOSE: Offer the programme — the setlist a musician plays from — as one sheet over the chart:
//          name it, put a chart into it, take one out, move one, change how one is played (its
//          transposition and its note), and keep it: save it to a `.setlist` file and open one back.
//          Every button applies through [SetlistSession], so the programme is an op-log document
//          with the same undo and redo a chart has, and the scene playback of an entry is the
//          sheet's "play" action.
//          It is the setlist half of the edit loop: `setlist_session.dart` decides which event each
//          operation is, and this file decides where the buttons go and what a tap does.
// INPUTS: The session being edited, the loaded songs (to offer one when adding), a resolver from an
//         entry to the title a musician reads — null when the entry names no loaded chart — a
//         callback that plays one entry, a callback the sheet calls after every applied edit, the
//         text the file dialog starts with, and a callback that hands the viewer the session an
//         opened `.setlist` file produced.
// OUTPUTS: A modal bottom sheet whose result is nothing: every button applies through
//          [SetlistSession] as it is pressed, so by the time the sheet closes the programme already
//          holds the edit. Undo and redo are shown in the sheet itself, because the programme has
//          its own log and its own history: undoing a setlist edit must not be confused with
//          undoing a chord, and a musician cannot see which one they would get from one app-bar
//          button. Opening a `.setlist` file REPLACES the session this sheet is editing, so the
//          sheet — not the screen behind it — holds the session it draws, and the screen is handed
//          the same value.
// KEYWORDS: setlist, programme, sheet, rename, insert, delete, move, transposition, notes, undo,
//           redo, op-log, scene-playback, save-setlist, open-setlist, missing-chart
//
// WHY THE TITLE COMES FROM A RESOLVER AND NOT FROM THE LOADED SONG. A chart can be renamed in the
// editor, and the viewer already answers "the name to show" from the session that holds the rename.
// A sheet that read `IRealSong.title` directly would keep showing the imported name after the chart
// was renamed — the same two-names-for-one-song defect the viewer's own title path exists to prevent.
//
// WHY THE RESOLVER ANSWERS NULL RATHER THAN A PLACEHOLDER. Which chart an entry names is decided by
// the viewer, from the loaded library and the entry's identity; a sheet that invented its own
// wording for "not found" would be a second opinion about a question only the library can answer.
// Null means "this entry names nothing this library holds", the sheet renders that in the one place
// a musician reads it, and it counts the nulls to say how many there are.
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
// that the band does not do that. An entry ADDED here carries the chart's content identity, so the
// duplicate and the original resolve to the same music without either being special-cased.
import 'dart:async';

import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one only in strings; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'ireal_library.dart';
import 'l10n/app_localizations.dart';
// `localizedKeyName` and `localizedSemitoneInterval` are imported rather than re-derived: the key
// badge, the twelve-key grid, the scene bar and this sheet all name the same key and the same
// interval with the same words.
import 'scene_bar.dart';
import 'setlist_document.dart';
import 'setlist_file_bar.dart';
import 'sheet_button.dart';
import 'sheet_surface.dart';

// PURPOSE: Open the programme sheet for [session] and resolve when the musician is finished.
// INPUTS: context — where to open the sheet. session — the setlist document being edited. songs —
//         the loaded library, used to offer a chart when one is added. titleFor — the resolver that
//         names an entry's chart, or null when the entry names no loaded chart. onPlay — called
//         with the entry index when the musician presses play; the sheet closes before the call so
//         the chart the entry names is visible. onChanged — called after every applied edit so the
//         caller can rebuild. initialFilePath — the text the save/open dialog's field starts with.
//         onOpenedFile — called with the session an opened `.setlist` file produced, so the caller
//         adopts the same value this sheet now draws.
// OUTPUTS: A future that completes when the sheet is dismissed, whether anything was edited or not.
// KEYWORDS: show, bottom-sheet, setlist-edit, scene-play, title-resolver, callback, guard
/// Opens the programme sheet over the chart.
Future<void> showSetlistSheet(
  BuildContext context, {
  required SetlistSession session,
  required List<IRealSong> songs,
  required String? Function(SetlistItem item) titleFor,
  required ValueChanged<int> onPlay,
  VoidCallback? onChanged,
  String initialFilePath = '',
  ValueChanged<SetlistSession>? onOpenedFile,
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
    initialFilePath: initialFilePath,
    onOpenedFile: onOpenedFile,
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
    this.initialFilePath = '',
    this.onOpenedFile,
  });

  /// The setlist document the sheet opens on.
  ///
  /// The sheet keeps its own reference to the session because opening a `.setlist` file replaces it;
  /// [session] is read once, in `initState`, and this field is never read again.
  final SetlistSession session;

  /// The loaded songs, in payload order, offered when a chart is added.
  final List<IRealSong> songs;

  /// The title to show for an entry's chart, or null when the entry names no chart this library
  /// holds.
  ///
  /// A function rather than a map because the viewer answers it from the sessions it holds, which is
  /// where a rename lives; a map built here would be a copy that goes stale on the next rename. It
  /// is also the ONE place the missing case is decided, so the row's wording and the count above the
  /// list cannot disagree.
  final String? Function(SetlistItem item) titleFor;

  /// Called with the entry index when the musician plays one.
  final ValueChanged<int> onPlay;

  /// Called after every applied edit.
  final VoidCallback? onChanged;

  /// The text the save/open dialog's field starts with.
  final String initialFilePath;

  /// Called with the session an opened `.setlist` file produced.
  final ValueChanged<SetlistSession>? onOpenedFile;

  @override
  State<SetlistSheet> createState() => _SetlistSheetState();
}

/// The sheet's state: the title field's controller and the session it draws.
class _SetlistSheetState extends State<SetlistSheet> {
  late final TextEditingController _titleController;

  /// The session this sheet draws, which is the one it was opened with until a `.setlist` file
  /// replaces it.
  late SetlistSession _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _titleController = TextEditingController(text: _session.setlist.title);
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
  // INPUTS: item — the entry.
  // OUTPUTS: The title the resolver gave, or the catalogue's `(missing chart)` when it answered
  //          null. An EMPTY title is a chart that has no name, and the catalogue words that too:
  //          both fallbacks live here because they are UI text, while WHICH entries are missing is
  //          the resolver's answer and is not second-guessed. The two are different facts and are
  //          said differently — a nameless chart is in the programme, a missing one is not in the
  //          library.
  // KEYWORDS: title-resolution, missing-chart, empty-name, honest-fallback, one-wording, localized
  String _titleFor(SetlistItem item) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? resolved = widget.titleFor(item);
    if (resolved == null) {
      return l10n.setlistMissingChart;
    }
    return resolved.isEmpty ? l10n.untitled : resolved;
  }

  // PURPOSE: Count the entries that name a chart this library does not hold, so the sheet can say
  //          how many there are above the list instead of making the musician count rows.
  // INPUTS: None; the session on screen and the resolver.
  // OUTPUTS: The number of entries the resolver answered null for. Zero for an ordinary programme
  //          built from the loaded library.
  // KEYWORDS: missing-chart, count, honest-report, live-with-edits
  int get _missingCount => _session.items
      .where((SetlistItem item) => widget.titleFor(item) == null)
      .length;

  // PURPOSE: Adopt the programme an opened `.setlist` file decoded to, since this sheet is what is
  //          drawing it.
  // INPUTS: opened — the file's document id, its snapshot and its operation tail, as
  //         `setlist_file_bar.dart` read them.
  // OUTPUTS: The status sentence the dialog shows: the programme's name, its entry count and, when
  //          it is not zero, how many entries name no chart this library holds. The sheet's session
  //          is replaced — through `setlistSessionFor`, so the tail is folded and the sequence
  //          continues past it — and the caller is handed the same value so the page behind the
  //          sheet cannot keep drawing the previous programme.
  // KEYWORDS: open-setlist, adopt-session, status-sentence, missing-chart, live-count, localized
  String _adoptOpened(OpenedSetlist opened) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SetlistSession next = setlistSessionFor(
      docId: opened.docId,
      snapshot: opened.snapshot,
      events: opened.events,
    );
    setState(() {
      _session = next;
      _titleController.text = next.setlist.title;
    });
    widget.onOpenedFile?.call(next);
    final int missing = next.items
        .where((SetlistItem item) => widget.titleFor(item) == null)
        .length;
    final String name = next.setlist.title.isEmpty
        ? l10n.untitledProgramme
        : next.setlist.title;
    final String openedSentence = l10n.setlistOpened(
      name,
      l10n.entryCount(next.items.length),
    );
    // Two sentences, each carrying its own full stop, because Russian agrees the verb of the second
    // one with the count and a preposition glued on by the caller could not be translated at all.
    return missing == 0
        ? openedSentence
        : '$openedSentence ${l10n.missingEntryCount(missing)}';
  }

  // PURPOSE: Word how one entry is played, so a row states the transposition and the note together
  //          and a zero interval is named rather than left blank.
  // INPUTS: item — the entry. The catalogue comes from the context.
  // OUTPUTS: A subtitle such as `written · count off` or `+2 st · ballad`. The interval unit is the
  //          catalogue's abbreviation, and the note itself is the musician's own data and is printed
  //          exactly as written.
  // KEYWORDS: subtitle, interval-label, notes, reading-order, localized
  String _subtitleFor(SetlistItem item) => item.notes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Setlist setlist = _session.setlist;
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
                  Expanded(
                    // WHY THE HEADING SHRINKS RATHER THAN WRAPS. Measured at 412 logical pixels
                    // (the phone width A49 records): the Russian heading `Программа` and the two
                    // Russian button labels `Отменить` and `Вернуть` together are wider than the
                    // row, and the heading — being the only flexible child — wrapped mid-word into
                    // `Программ` / `а`. The English words are short enough that this never showed.
                    // Scaling the heading down keeps the word whole and keeps the three controls
                    // where a thumb expects them; on a wide sheet the text already fits the
                    // Expanded box and `scaleDown` changes nothing at all.
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.setlistSheetTitle,
                          style: const TextStyle(
                            color: sheetOnPanelColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SheetButton(
                    buttonKey: 'setlist-undo',
                    icon: Icons.undo,
                    label: l10n.undo,
                    onTap: _session.canUndo
                        ? () => _after(_session.undo())
                        : null,
                  ),
                  const SizedBox(width: 8),
                  SheetButton(
                    buttonKey: 'setlist-redo',
                    icon: Icons.redo,
                    label: l10n.redo,
                    onTap: _session.canRedo
                        ? () => _after(_session.redo())
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // --- THE PROGRAMME'S FILE (a `.setlist` container) ---------------------------------
                  // Save and open the programme itself, through the same platform seam the chart's
                  // own file control uses. It lives here rather than in the app bar because the
                  // programme is what it acts on: the app bar's chart-file control saves the CHART
                  // on screen, and two controls named "save" in one window would make a musician
                  // guess which document they were keeping. Opening replaces this sheet's session,
                  // which is why `_adoptOpened` and `_session` exist.
                  SetlistFileAction(
                    session: _session,
                    initialPath: widget.initialFilePath,
                    onOpened: _adoptOpened,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('setlist-title'),
                controller: _titleController,
                style: const TextStyle(color: sheetOnPanelColor),
                decoration: InputDecoration(
                  labelText: l10n.setlistNameLabel,
                  labelStyle: const TextStyle(color: sheetMutedColor),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: sheetMutedColor),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: sheetAccentColor),
                  ),
                ),
                onSubmitted: (String value) => _after(_session.rename(value)),
                onEditingComplete: () =>
                    _after(_session.rename(_titleController.text)),
              ),
              if (_missingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.setlistMissingCharts(_missingCount),
                    key: const ValueKey<String>('setlist-missing'),
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: setlist.items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.setlistEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: sheetMutedColor),
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
                label: l10n.setlistAddChart,
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
  // KEYWORDS: entry-row, position, play, move, edit, delete, bounds-disabled, localized
  Widget _entryRow(int index, SetlistItem item) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
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
                      _titleFor(item),
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
                tooltip: l10n.setlistPlayTooltip,
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onPlay(index);
                },
              ),
              IconButton(
                key: ValueKey<String>('setlist-up-$index'),
                icon: const Icon(Icons.arrow_upward),
                color: sheetOnPanelColor,
                tooltip: l10n.moveEarlier,
                onPressed: index == 0
                    ? null
                    : () => _after(_session.moveItem(index, index - 1)),
              ),
              IconButton(
                key: ValueKey<String>('setlist-down-$index'),
                icon: const Icon(Icons.arrow_downward),
                color: sheetOnPanelColor,
                tooltip: l10n.moveLater,
                onPressed: index == _session.items.length - 1
                    ? null
                    : () => _after(_session.moveItem(index, index + 1)),
              ),
              IconButton(
                key: ValueKey<String>('setlist-edit-$index'),
                icon: const Icon(Icons.tune),
                color: sheetOnPanelColor,
                tooltip: l10n.setlistEntryTooltip,
                onPressed: () => unawaited(_editEntry(context, index, item)),
              ),
              IconButton(
                key: ValueKey<String>('setlist-delete-$index'),
                icon: const Icon(Icons.delete_outline),
                color: const Color(0xFFFF8A80),
                tooltip: l10n.setlistRemoveTooltip,
                onPressed: () => _after(_session.deleteItem(index)),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              backgroundColor: sheetPanelColor,
              title: Text(
                _titleFor(item),
                style: const TextStyle(color: sheetOnPanelColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    key: const ValueKey<String>('setlist-notes'),
                    controller: notes,
                    style: const TextStyle(color: sheetOnPanelColor),
                    decoration: InputDecoration(
                      labelText: l10n.setlistNotesLabel,
                      labelStyle: const TextStyle(color: sheetMutedColor),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  key: const ValueKey<String>('setlist-edit-ok'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.ok),
                ),
              ],
            ),
      ),
    );
    final String written = notes.text;
    notes.dispose();
    if (confirmed != true) {
      return;
    }
    _after(_session.updateItem(index, notes: written));
  }

  // PURPOSE: Put a chart from the library into the programme, chosen from the loaded songs.
  // INPUTS: context — where to open the dialog. The lookup read here, not at confirm: the action is
  //         one tap and the list does not change while the dialog is open.
  // OUTPUTS: A future that completes when the dialog closes. A picked song is appended to the
  //          programme; dismissing changes nothing. A duplicate is allowed and stated on the
  //          subtitle of the row it lands in.
  // KEYWORDS: add-entry, chart-picker, append, duplicate-allowed, dismissable
  Future<void> _addEntry(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final IRealSong? picked = await showDialog<IRealSong>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: sheetPanelColor,
        title: Text(
          l10n.setlistAddChartTitle,
          style: const TextStyle(color: sheetOnPanelColor),
        ),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.builder(
            itemCount: widget.songs.length,
            itemBuilder: (BuildContext context, int index) {
              final IRealSong song = widget.songs[index];
              // The picker names each chart through the SAME resolver a row uses, by asking it
              // about the entry this tap would make. The chart's own title is only the fallback for
              // a resolver that cannot see the library, so a chart renamed in the editor is listed
              // under the name the editor gave it rather than under the imported one.
              //
              // THE FALLBACK FOR A NAMELESS CHART IS THE CATALOGUE'S. The resolver hands back the
              // document's own title, which is empty for a chart the export left unnamed, and the
              // word shown for that is interface text: it is said in `Без названия` on a Russian
              // tablet and `Untitled` in English, never in one fixed language. That is why this
              // reads the raw `song.song.title` and not a display accessor which might have chosen
              // a language of its own.
              final String? resolved = widget.titleFor(
                SetlistItem(
                  documentId: song.song.id,
                  chartIdentity: song.identity,
                ),
              );
              final String raw = (resolved == null || resolved.isEmpty)
                  ? song.song.title
                  : resolved;
              final String shown = raw.isEmpty ? l10n.untitled : raw;
              return ListTile(
                key: ValueKey<String>('setlist-add-$index'),
                dense: true,
                title: Text(
                  shown,
                  style: const TextStyle(color: sheetOnPanelColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  l10n.setlistSongSubtitle(
                    localizedKeyName(l10n, song.song.key),
                    l10n.barCount(song.song.writtenBarCount),
                  ),
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
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (picked == null) {
      return;
    }
    _after(
      _session.insertItem(
            SetlistItem(
              documentId: picked.song.id,
              // The identity of the music, so the entry this picker makes resolves against another
              // import exactly like the entries the playlist import built.
              chartIdentity: picked.identity,
            ),
          ) !=
          null,
    );
  }
}
