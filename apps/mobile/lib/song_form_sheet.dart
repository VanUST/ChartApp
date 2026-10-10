// PURPOSE: Offer the operations that decide the SHAPE of a tune — put a bar in, take it out, copy
//          it; add, rename, copy, move and remove a section — as one sheet over the chart, so a
//          musician can build a 32-bar form and a rehearsal-letter form without a menu search and
//          without a keyboard. It is the form half of the edit loop: `edit_session.dart` decides
//          which event each operation is, and this file decides where the buttons go and what a tap
//          does.
// INPUTS: The session being edited, the address of the bar the musician selected (section id and
//         zero-based index inside it), and a callback the sheet calls after every applied edit.
// OUTPUTS: A modal bottom sheet whose result is nothing: every button applies through [EditSession]
//          as it is pressed, so by the time the sheet closes the document already holds the form.
//          The sheet keeps its own cursor — the address the NEXT operation will use — because a
//          form edit moves the very address it was given: inserting a bar before the selection
//          pushes the selected bar one place later, and after a delete the old index may name the
//          bar after the one that went away.
// KEYWORDS: song-form, bars, sections, rehearsal-letter, bottom-sheet, op-log, undoable,
//           edit-session, no-keyboard
//
// WHY A SHEET AND NOT A ROW OF BUTTONS ABOVE THE CHART.
//
// A control in the body takes height away from the chart, and D13's FIT mode refuses to shrink a
// page past a legible floor — so a body row does not merely move the music, it turns a song that
// fitted on one page into "does not fit legibly". That was measured once already when the `.chart`
// control lived in the body (see `chart_file_bar.dart`), and the entry moved into the app bar. This
// sheet takes no height at all until it is opened, and it is opened from a control that is already
// in the app bar or from the selection line that already exists.
//
// WHY THE SHEET STAYS OPEN AND KEEPS A CURSOR.
//
// Building a 32-bar form is thirty-two operations, and a sheet that closed after each one would
// charge a reopen for every bar. Staying open is only useful if the next operation lands where the
// musician expects, and "where" changes with every edit, so the sheet holds the address itself and
// updates it after each applied operation. The address is reported to the caller through [onChanged]
// only as "rebuild"; the page's own selection is a hit-test result that names a laid-out bar, and it
// cannot be re-derived here, so the caller decides what to do with a selection that no longer names
// what it did.
//
// WHY THE METER TRAVELS WITH A NEW BAR AND THE SIGNS DO NOT.
//
// A meter is per bar in this model, because a real chart changes it mid-song, so a new bar that
// defaulted to 4/4 would put a wrong bar into a 3/4 tune — a musical change nobody asked for. Repeat
// signs, volta brackets and barlines are signs of a PASSAGE; copying one into a position the
// musician chose says "repeat from here" or "first ending" about music that may not repeat, which is
// an invented instruction rather than a copied one. The meter is inherited; the signs are not.
//
// WHY SOME OPERATIONS ARE REFUSED.
//
// A section is drawn through the bars it contains: with no bars it is not on the page, cannot be
// tapped, and therefore cannot be selected again. The same is true one level up for a song with no
// sections. So the last bar of a section and the last section of a song are not removable from here
// — a state reachable in one tap and impossible to leave is worse than a button that says no. These
// refusals are the one rule this sheet adds to the catalogue, and they are reported on screen rather
// than only in the log.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'sheet_surface.dart';

/// The colour of a destructive action's label.
const Color _dangerColor = Color(0xFFFF8A80);

// PURPOSE: Open the form sheet for one selected bar and resolve when the musician is finished.
// INPUTS: context — where to open the sheet. session — the document being edited. sectionId and
//         barIndex — the selected bar, in the model's own zero-based numbering. onChanged — called
//         after every applied edit so the caller can rebuild; the sheet does not know how the caller
//         draws its page, and the page's selection is the caller's to keep or drop.
// OUTPUTS: A future that completes when the sheet is dismissed, whether anything was edited or not.
//          An address that names no bar opens nothing and completes at once, because the sheet's
//          every operation is relative to that bar and an empty sheet would be a lie about what is
//          selectable.
// KEYWORDS: show, bottom-sheet, session-edit, callback, guard
/// Opens the form sheet — bars and sections — for the bar at ([sectionId], [barIndex]).
Future<void> showSongForm(
  BuildContext context, {
  required EditSession session,
  required String sectionId,
  required int barIndex,
  VoidCallback? onChanged,
}) async {
  if (session.song.barAt(sectionId, barIndex) == null) {
    debugPrint(
      'viewer.form.skipped section=$sectionId bar=$barIndex reason=no-such-bar',
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: sheetPanelColor,
    isScrollControlled: true,
    builder: (BuildContext context) => SongFormSheet(
      session: session,
      sectionId: sectionId,
      barIndex: barIndex,
      onChanged: onChanged,
    ),
  );
}

// PURPOSE: Turn what the musician typed in the rename box into a section label, so a single letter
//          stays a rehearsal letter and anything else is kept as written.
// INPUTS: text — the typed label, possibly with surrounding spaces or a lower-case letter.
// OUTPUTS: A letter label for one alphabetic character, upper-cased, otherwise a custom label
//          carrying the trimmed text. Empty input yields a custom label with no text; the dialog
//          refuses to submit that, and [SongFormSheet] refuses to apply it, because a section whose
//          label prints nothing is indistinguishable from an unlabelled one.
// KEYWORDS: section-label, rehearsal-letter, custom-label, text-normalisation, total-function
/// Returns the section label [text] describes.
SectionLabel sectionLabelFrom(String text) {
  final String trimmed = text.trim();
  if (trimmed.length == 1 && RegExp('[A-Za-z]').hasMatch(trimmed)) {
    return SectionLabel.letter(trimmed.toUpperCase());
  }
  return SectionLabel.custom(trimmed);
}

/// The form sheet itself: the bar group, the section group and the address both act on.
class SongFormSheet extends StatefulWidget {
  /// Creates a form sheet over the bar at ([sectionId], [barIndex]) of [session].
  const SongFormSheet({
    super.key,
    required this.session,
    required this.sectionId,
    required this.barIndex,
    this.onChanged,
  });

  /// The document being edited.
  final EditSession session;

  /// The section the initially selected bar belongs to.
  final String sectionId;

  /// The zero-based index of the initially selected bar inside its section.
  final int barIndex;

  /// Called after every applied edit.
  final VoidCallback? onChanged;

  @override
  State<SongFormSheet> createState() => _SongFormSheetState();
}

/// The sheet's state: the address the next operation will use, and what the last one did.
class _SongFormSheetState extends State<SongFormSheet> {
  /// The section the next operation addresses.
  late String _sectionId = widget.sectionId;

  /// The index, inside [_sectionId], of the bar the next operation addresses.
  late int _barIndex = widget.barIndex;

  /// What the last operation did, or the reason the last one was refused.
  ///
  /// Shown in the sheet because the page is behind the sheet: a musician who presses "delete" and
  /// sees the sheet cover the change has no other evidence that anything happened.
  String? _status;

  /// The song as it stands, read back from the session after every edit.
  Song get _song => widget.session.song;

  /// The section the cursor is in, or null when the cursor names a section the song does not have.
  Section? get _section => _song.sectionById(_sectionId);

  /// The bar the cursor names, or null when it names no bar.
  Bar? get _bar => _song.barAt(_sectionId, _barIndex);

  /// Where the cursor's section sits in the song, or -1 when the cursor names no section.
  int get _sectionIndex =>
      _song.sections.indexWhere((Section section) => section.id == _sectionId);

  // PURPOSE: Apply one bar or section operation and move the cursor to wherever the musician should
  //          look next, so the sheet and the document cannot disagree about what was edited.
  // INPUTS: applied — whether the session took the operation. message — what it did, in the words
  //         the musician used. refusal — what to say instead when it was refused; it stands alone,
  //         because a past-tense success message followed by a reason would open with a claim that
  //         the operation happened. sectionId and barIndex — the address the cursor should take,
  //         omitted when the operation did not move it.
  // OUTPUTS: Nothing. An applied operation moves the cursor, ticks the haptic, rebuilds the caller
  //          and writes one structured line carrying the resulting form; a refused one changes
  //          nothing but the status line and writes why.
  // KEYWORDS: apply, cursor, haptic, structured-log, refusal-reporting, single-path
  void _report(
    bool applied,
    String message, {
    String refusal = 'Nothing changed: that operation is not possible here.',
    String? sectionId,
    int? barIndex,
  }) {
    if (!applied) {
      debugPrint(
        'viewer.form.refused op="$message" section=$_sectionId bar=$_barIndex',
      );
      setState(() => _status = refusal);
      return;
    }
    setState(() {
      if (sectionId != null) {
        _sectionId = sectionId;
      }
      if (barIndex != null) {
        _barIndex = barIndex;
      }
      _status = message;
    });
    HapticFeedback.selectionClick();
    widget.onChanged?.call();
    final Song song = widget.session.song;
    debugPrint(
      'viewer.form.op "$message" section=$_sectionId bar=$_barIndex '
      'sections=${song.sections.length} bars=${song.writtenBarCount} '
      'seq=${widget.session.seq} undo_depth=${widget.session.undoDepth}',
    );
  }

  // PURPOSE: Add a blank bar on the chosen side of the cursor, which is how a form of a chosen
  //          length is built.
  // INPUTS: before — true to put the new bar in front of the cursor's bar, false behind it.
  // OUTPUTS: Nothing. The cursor follows the edit: a bar inserted BEFORE takes the cursor's index,
  //          so the cursor is left on the new bar, which is the bar a musician who asked for one is
  //          about to write into; a bar inserted AFTER lands on the next index and takes the cursor
  //          with it.
  // KEYWORDS: bar-insert, cursor-follows, before-after, form-building
  void _insertBar({required bool before}) {
    final bool applied = before
        ? widget.session.insertBarBefore(
            sectionId: _sectionId,
            barIndex: _barIndex,
          )
        : widget.session.insertBarAfter(
            sectionId: _sectionId,
            barIndex: _barIndex,
          );
    _report(
      applied,
      before ? 'Inserted a bar before.' : 'Inserted a bar after.',
      refusal: 'Nothing was inserted: the song has no such bar.',
      barIndex: before ? _barIndex : _barIndex + 1,
    );
  }

  // PURPOSE: Copy the cursor's bar into the place after it and leave the cursor on the copy, so the
  //          musician can edit what they just made.
  // INPUTS: None.
  // OUTPUTS: Nothing. The cursor moves to `barIndex + 1`.
  // KEYWORDS: bar-duplicate, cursor-on-copy, repeat-bar
  void _duplicateBar() {
    final bool applied = widget.session.duplicateBar(
      sectionId: _sectionId,
      barIndex: _barIndex,
    );
    _report(
      applied,
      'Duplicated this bar.',
      refusal: 'Nothing was copied: the song has no such bar.',
      barIndex: _barIndex + 1,
    );
  }

  // PURPOSE: Remove the cursor's bar and leave the cursor on the bar that took its place, or on the
  //          section's new last bar when the last one went.
  // INPUTS: None.
  // OUTPUTS: Nothing. The last bar of a section is refused, with the reason on screen.
  // KEYWORDS: bar-delete, cursor-clamp, last-bar-refusal
  void _deleteBar() {
    final bool applied = widget.session.deleteBar(
      sectionId: _sectionId,
      barIndex: _barIndex,
    );
    final Section? section = _song.sectionById(_sectionId);
    final int remaining = section?.bars.length ?? 0;
    final int next = remaining == 0
        ? 0
        : (_barIndex < remaining ? _barIndex : remaining - 1);
    _report(
      applied,
      'Deleted this bar.',
      refusal:
          'Nothing was deleted: a section keeps at least one bar, or it could '
          'not be shown or selected.',
      barIndex: next,
    );
  }

  // PURPOSE: Add a new one-bar section on the chosen side of the cursor's section.
  // INPUTS: before — true to put the new section in front of the cursor's, false behind it.
  // OUTPUTS: Nothing. The cursor moves into the new section's first bar, because an operation on a
  //          section the musician cannot see would leave them pressing buttons at nothing.
  // KEYWORDS: section-insert, cursor-to-new-section, rehearsal-letter, one-bar
  void _insertSection({required bool before}) {
    final String? created = before
        ? widget.session.insertSectionBefore(_sectionId)
        : widget.session.insertSectionAfter(_sectionId);
    _report(
      created != null,
      before
          ? 'Inserted a new section before.'
          : 'Inserted a new section after.',
      refusal: 'Nothing was inserted: the song has no such section.',
      sectionId: created,
      barIndex: 0,
    );
  }

  // PURPOSE: Copy the cursor's section, with everything in it, into the place after it.
  // INPUTS: None.
  // OUTPUTS: Nothing. The cursor moves into the copy's first bar. The copy carries a new identity,
  //          so an annotation anchored in the original stays anchored in the original.
  // KEYWORDS: section-duplicate, fresh-identity, cursor-to-copy
  void _duplicateSection() {
    final String? created = widget.session.duplicateSection(_sectionId);
    _report(
      created != null,
      'Duplicated this section.',
      refusal: 'Nothing was copied: the song has no such section.',
      sectionId: created,
      barIndex: 0,
    );
  }

  // PURPOSE: Move the cursor's section earlier or later in the written order.
  // INPUTS: places — how far to move it; negative is earlier.
  // OUTPUTS: Nothing. The cursor stays on the same section and bar, because the section's identity
  //          and the bar's index are the address and neither changes. A move past either end is
  //          refused with the reason on screen.
  // KEYWORDS: section-reorder, identity-stable, cursor-stays, form-repair
  void _moveSection(int places) {
    final bool applied = widget.session.moveSection(_sectionId, places);
    _report(
      applied,
      places < 0 ? 'Moved this section earlier.' : 'Moved this section later.',
      refusal: 'Nothing moved: the section is already at that end of the form.',
    );
  }

  // PURPOSE: Remove the cursor's section and everything in it, leaving the cursor in the section
  //          that takes its place.
  // INPUTS: None.
  // OUTPUTS: Nothing. The song's only section is refused, with the reason on screen.
  // KEYWORDS: section-delete, cursor-to-successor, last-section-refusal
  void _deleteSection() {
    final int index = _sectionIndex;
    final bool applied = widget.session.deleteSection(_sectionId);
    String? next;
    if (applied) {
      final List<Section> sections = _song.sections;
      next = sections[index < sections.length ? index : sections.length - 1].id;
    }
    _report(
      applied,
      'Deleted this section.',
      refusal:
          'Nothing was deleted: a song keeps at least one section, or there '
          'would be nothing left to show.',
      sectionId: next,
      barIndex: 0,
    );
  }

  // PURPOSE: Ask for a new label for the cursor's section and apply it, which is the one form
  //          operation that needs the keyboard: a rehearsal letter is a name, not a choice.
  // INPUTS: None.
  // OUTPUTS: Nothing. A dismissed dialog and an empty name change nothing; an applied rename leaves
  //          the cursor where it is, because a label is not part of an address.
  // KEYWORDS: section-rename, dialog, keyboard-allowed, empty-refusal
  Future<void> _renameSection() async {
    final Section? section = _song.sectionById(_sectionId);
    if (section == null) {
      return;
    }
    final String? typed = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _RenameSectionDialog(initialLabel: section.label.text),
    );
    if (!mounted || typed == null || typed.trim().isEmpty) {
      return;
    }
    final SectionLabel label = sectionLabelFrom(typed);
    final bool applied = widget.session.renameSection(_sectionId, label);
    _report(
      applied,
      'Renamed this section to "${label.text}".',
      refusal: 'Nothing was renamed: it already carries that name.',
    );
  }

  // PURPOSE: Number a bar the way a musician counts, across sections from the top of the chart,
  //          which is the same counting the viewer's selection line and the chord palette use.
  // INPUTS: None; reads the cursor and the song.
  // OUTPUTS: The one-based ordinal of the cursor's bar in the whole written chart, or 0 when the
  //          cursor names no bar. Zero is reported rather than a guess, and the header says so.
  // KEYWORDS: bar-ordinal, musician-numbering, one-based, total-function
  int get _barOrdinal {
    int ordinal = 0;
    for (final Section section in _song.sections) {
      if (section.id == _sectionId) {
        return ordinal + _barIndex + 1;
      }
      ordinal += section.bars.length;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final Section? section = _section;
    final Bar? bar = _bar;
    final int sectionIndex = _sectionIndex;
    final List<Section> sections = _song.sections;
    final bool hasBar = bar != null;
    final bool canDeleteBar = section != null && section.bars.length > 1;
    final bool canDeleteSection = sections.length > 1;
    final bool canMoveUp = sectionIndex > 0;
    final bool canMoveDown =
        sectionIndex >= 0 && sectionIndex < sections.length - 1;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(section, sectionIndex),
              const SizedBox(height: 10),
              _buildStatus(),
              _buildGroup('BAR', <Widget>[
                _FormButton(
                  buttonKey: 'song-form-bar-insert-before',
                  icon: Icons.add,
                  label: 'Bar before',
                  onTap: hasBar ? () => _insertBar(before: true) : null,
                ),
                _FormButton(
                  buttonKey: 'song-form-bar-insert-after',
                  icon: Icons.add,
                  label: 'Bar after',
                  onTap: hasBar ? () => _insertBar(before: false) : null,
                ),
                _FormButton(
                  buttonKey: 'song-form-bar-duplicate',
                  icon: Icons.copy_all_outlined,
                  label: 'Duplicate bar',
                  onTap: hasBar ? _duplicateBar : null,
                ),
                _FormButton(
                  buttonKey: 'song-form-bar-delete',
                  icon: Icons.delete_outline,
                  label: 'Delete bar',
                  danger: true,
                  onTap: canDeleteBar ? _deleteBar : null,
                ),
              ]),
              const SizedBox(height: 14),
              _buildGroup('SECTION', <Widget>[
                _FormButton(
                  buttonKey: 'song-form-section-insert-before',
                  icon: Icons.playlist_add,
                  label: 'Section before',
                  onTap: section == null
                      ? null
                      : () => _insertSection(before: true),
                ),
                _FormButton(
                  buttonKey: 'song-form-section-insert-after',
                  icon: Icons.playlist_add,
                  label: 'Section after',
                  onTap: section == null
                      ? null
                      : () => _insertSection(before: false),
                ),
                _FormButton(
                  buttonKey: 'song-form-section-duplicate',
                  icon: Icons.copy_all_outlined,
                  label: 'Duplicate section',
                  onTap: section == null ? null : _duplicateSection,
                ),
                _FormButton(
                  buttonKey: 'song-form-section-rename',
                  icon: Icons.edit_outlined,
                  label: 'Rename section',
                  onTap: section == null ? null : () => _renameSection(),
                ),
                _FormButton(
                  buttonKey: 'song-form-section-up',
                  icon: Icons.arrow_upward,
                  label: 'Move earlier',
                  onTap: canMoveUp ? () => _moveSection(-1) : null,
                ),
                _FormButton(
                  buttonKey: 'song-form-section-down',
                  icon: Icons.arrow_downward,
                  label: 'Move later',
                  onTap: canMoveDown ? () => _moveSection(1) : null,
                ),
                _FormButton(
                  buttonKey: 'song-form-section-delete',
                  icon: Icons.delete_outline,
                  label: 'Delete section',
                  danger: true,
                  onTap: canDeleteSection ? _deleteSection : null,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // PURPOSE: State which bar the next operation acts on, in the words the musician counts in, so a
  //          sheet that holds its own cursor says where the cursor is.
  // INPUTS: section — the cursor's section, or null when the cursor names none.
  //          sectionIndex — its position in the song, or -1.
  // OUTPUTS: The header row: the position, the section's label and place, the counts that make a
  //          reorder or a delete checkable, and the control that closes the sheet.
  // KEYWORDS: header, position-label, cursor, section-identity, done
  Widget _buildHeader(Section? section, int sectionIndex) {
    final String position = section == null
        ? 'No bar selected'
        : 'Bar $_barOrdinal · section ${section.label}';
    final String detail = section == null
        ? 'The selected bar is no longer in the song.'
        : 'bar ${_barIndex + 1} of ${section.bars.length} in this section · '
              'section ${sectionIndex + 1} of ${_song.sections.length}';
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                position,
                key: const ValueKey<String>('song-form-position'),
                style: const TextStyle(
                  color: sheetOnPanelColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                detail,
                key: const ValueKey<String>('song-form-detail'),
                style: const TextStyle(color: sheetMutedColor, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey<String>('song-form-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done', style: TextStyle(color: sheetAccentColor)),
        ),
      ],
    );
  }

  // PURPOSE: Say what the last operation did, or why it was refused, because the page the change
  //          landed on is behind the sheet.
  // INPUTS: None; reads [_status].
  // OUTPUTS: A one-line card, or an empty box before anything has been pressed, so the sheet does
  //          not open with a line about nothing.
  // KEYWORDS: status, feedback, refusal, before-anything-empty
  Widget _buildStatus() {
    final String? status = _status;
    if (status == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: sheetCellColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        key: const ValueKey<String>('song-form-status'),
        style: const TextStyle(color: sheetAccentColor, fontSize: 13),
      ),
    );
  }

  // PURPOSE: Caption one group of buttons, so the bar operations and the section operations are
  //          told apart at a glance rather than by reading every label.
  // INPUTS: caption — the group's one-word name. children — its buttons.
  // OUTPUTS: The captioned, wrapping group.
  // KEYWORDS: group, caption, wrap, layout
  Widget _buildGroup(String caption, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        caption,
        style: const TextStyle(
          color: sheetMutedColor,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: children),
    ],
  );
}

/// One operation button in the form sheet.
class _FormButton extends StatelessWidget {
  /// Creates a button labelled [label] that calls [onTap], or does nothing when [onTap] is null.
  ///
  /// [danger] colours the label as a removal, so the two destructive operations are not one slip of
  /// the thumb away from looking like the harmless ones beside them.
  const _FormButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  /// The widget key the tests and the driving tools find this button by.
  final String buttonKey;

  /// The glyph beside the label.
  final IconData icon;

  /// The words on the button, which name the operation and not the mechanism.
  final String label;

  /// What a press does, or null when the operation is not available right now.
  final VoidCallback? onTap;

  /// Whether this button removes something.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color foreground = !enabled
        ? sheetMutedColor
        : (danger ? _dangerColor : sheetOnPanelColor);
    return Material(
      color: enabled ? sheetCellColor : sheetCellColor.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey<String>(buttonKey),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dialog that asks for a section's new name.
class _RenameSectionDialog extends StatefulWidget {
  /// Creates a rename box pre-filled with [initialLabel].
  const _RenameSectionDialog({required this.initialLabel});

  /// The label the section carries now, so the musician edits a name rather than retyping one.
  final String initialLabel;

  @override
  State<_RenameSectionDialog> createState() => _RenameSectionDialogState();
}

/// The rename box's state: what is typed, and whether it can be submitted.
class _RenameSectionDialogState extends State<_RenameSectionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLabel,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // PURPOSE: Hand the typed text back to the sheet that opened this box.
  // INPUTS: None; reads the field.
  // OUTPUTS: Nothing. Popping with the text is the result: the dialog does not edit the document,
  //          so a rename that is cancelled cannot have half happened.
  // KEYWORDS: submit, result, no-side-effect, cancel-safe
  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename section'),
    content: TextField(
      key: const ValueKey<String>('song-form-rename-field'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Rehearsal letter or name',
        helperText: 'A single letter becomes a rehearsal letter.',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (String _) => setState(() {}),
      onSubmitted: (String _) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey<String>('song-form-rename-save'),
        // Disabled on an empty name: a section whose label prints nothing looks unlabelled, and the
        // sheet would then be the only place the difference could be seen.
        onPressed: _controller.text.trim().isEmpty ? null : _submit,
        child: const Text('Rename'),
      ),
    ],
  );
}
