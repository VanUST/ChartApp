// PURPOSE: Offer the operations that decide the SHAPE of a tune — put a bar in, take it out, copy
//          it; mark where it repeats and which ending each pass takes; draw the signs a bar carries
//          (segno, coda, fermata, player's stop); add, rename, copy, move and remove a section — as
//          one sheet over the chart, so a musician can build a 32-bar form, a rehearsal-letter form
//          and a repeated, signed form without a menu search and without a keyboard.
//          It is the form half of the edit loop: `edit_session.dart` decides which event each
//          operation is, and this file decides where the buttons go and what a tap does.
// INPUTS: The session being edited, the address of the bar the musician selected (section id and
//         zero-based index inside it), and a callback the sheet calls after every applied edit.
// OUTPUTS: A modal bottom sheet whose result is nothing: every button applies through [EditSession]
//          as it is pressed, so by the time the sheet closes the document already holds the form.
//          The sheet keeps its own cursor — the address the NEXT operation will use — because a
//          form edit moves the very address it was given: inserting a bar before the selection
//          pushes the selected bar one place later, and after a delete the old index may name the
//          bar after the one that went away. A repeat, an ending or a mark does NOT move an address,
//          so the cursor stays where it was for those.
// KEYWORDS: song-form, bars, sections, rehearsal-letter, repeat, ending, volta, percent-bar,
//           bar-mark, segno, coda, fermata, player-ending, bottom-sheet, op-log, undoable,
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
//
// WHY REPEATS AND ENDINGS ARE HERE, AND WHY THEY ARE NOT CHECKED HERE.
//
// Repeat barlines and alternative-ending brackets are STATE ON A BAR (A14) and they are read by
// `derivePlayOrder`, so the bar this sheet already holds a cursor on is exactly the thing they attach
// to: no second selection mechanism and no second sheet were needed, and the controls sit beside the
// operations that move a bar because both act on the same selected bar. What the sheet does NOT do
// is decide whether a repeat is well formed: a start with no end, an end with no start and a bracket
// on a bar inside no repeat are all written as asked, because the derivation already says what each
// one means and reports it (`repeatStartWithoutEnd`, `repeatEndWithoutStart`, `voltaOutsideRepeat`).
// A refusal here would be a second rule about the same music, living in the UI and disagreeing with
// the reader the musician plays from.
//
// CLEARING IS TWO DIFFERENT GESTURES, AND THAT IS THE MODEL'S SHAPE, NOT A CHOICE MADE HERE. A
// repeat barline is switched off by pressing its button again — the button is a toggle and shows
// which state the bar is in — which writes the neutral `Barline.single`. A bracket is removed
// through the ending dialog's "No bracket", which writes a null bracket, because `Volta(0)` is an
// unnumbered bracket the page DRAWS and is not the same thing as having none.
//
// WHY THE MARKS ARE A GROUP OF FOUR TOGGLES AND NOT A CYCLE. A bar's marks are a SET, not a single
// value: the painter joins every mark a bar carries into one line of glyphs, and the owner's own
// setlist carries several on one bar. A cycle through one button would therefore be a control that
// could only ever express one mark per bar — it would have to take two signs off to put a third on
// — which is a shape the model does not have and the corpus does not ask for. One toggle per sign
// matches the model: each sign is independently present or absent, the button's `active` state
// shows which signs the bar carries right now, and a bar with two keeps both while a third is
// toggled on. The group is deliberately ordered as the model declares `BarMark` (segno, coda,
// fermata, player ending) so the buttons are in one fixed order rather than in the order the
// musician happened to press them. The ORDER of the glyphs on the page is not decided here: the
// painter draws the bar's set in its own iteration order, and toggling a sign on never reorders the
// signs already there.
//
// MARKS ARE NOT CHECKED HERE EITHER, AND FOR A DIFFERENT REASON THAN REPEATS. `derivePlayOrder`
// does not read a segno, a coda, a fermata or a player's stop — nothing in the model interprets
// them as navigation yet — so there is no reader whose verdict this sheet could disagree with. The
// control writes exactly the sign the musician asked for and says so on the status line.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'sheet_button.dart';
import 'sheet_surface.dart';

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

// PURPOSE: Word the repeat-previous symbol of a bar, so the sheet's control and the text a
//          verification quotes name the state the same way.
// INPUTS: previous — the symbol the bar carries, or null when no bar is selected. l10n — the
//         message catalogue, which carries the three words.
// OUTPUTS: The catalogue's word for "no symbol", "the previous bar" or "the previous two bars", and
//          the word for none for null: a bar nobody selected carries no symbol as far as this label
//          is concerned, and inventing a fourth word for "no bar" would make the label describe the
//          selection rather than the sign.
//          WHY THE CATALOGUE IS A PARAMETER AND NOT A DEFAULT: a default would have to be an
//          English catalogue living beside the real one, which is a second source of English text.
//          Every caller in the application has a context to read it from.
// KEYWORDS: repeat-previous, percent-bar, label, total-function, shared-wording, localized
/// Returns the words that name [previous] on the sheet's button.
String repeatPreviousText(RepeatPrevious? previous, AppLocalizations l10n) =>
    switch (previous) {
      null || RepeatPrevious.none => l10n.formRepeatPreviousOff,
      RepeatPrevious.oneBar => l10n.formRepeatPreviousOneBar,
      RepeatPrevious.twoBars => l10n.formRepeatPreviousTwoBars,
    };

// PURPOSE: Word an alternative-ending bracket the way it is drawn on the page, so the button and
//          the engraved `[1.` cannot be read as two different things.
// INPUTS: volta — the bracket, or null when the bar carries none. l10n — the message catalogue,
//         which carries the two words.
// OUTPUTS: The catalogue's word for "no bracket", its word for the unnumbered bracket, or the
//          figure with a leading dot as in `1.` / `2.`. Null and the unnumbered bracket are given
//          different words because they are different states: the first draws nothing and the
//          second draws an empty bracket. The FIGURE is not a word and is not translated: it is the
//          number the page engraves.
// KEYWORDS: volta, ending, bracket, label, unnumbered-is-not-none, localized
/// Returns the words that name [volta] on the sheet's button.
String voltaText(Volta? volta, AppLocalizations l10n) {
  if (volta == null) {
    return l10n.formVoltaNone;
  }
  return volta.number == 0 ? l10n.formVoltaUnnumbered : '${volta.number}.';
}

// PURPOSE: Word one of the signs a bar can carry, so the sheet's button and the text a verification
//          quotes name the same sign the same way — and so the four signs are labelled in one place
//          rather than in a switch at each call site.
// INPUTS: mark — the sign, one of [BarMark]'s four values. l10n — the message catalogue, which
//         carries the four names.
// OUTPUTS: The catalogue's name for that sign. Total over the enum: there is no null case, because
//          a bar-level control only ever names a sign it can set, and "the bar does not carry it" is
//          what the button's `active` state says.
//          WHY THE FOUR NAMES ARE TRANSLATED RATHER THAN LEFT AS NOTATION: these are the words on
//          OUR buttons. The glyph the painter draws on the page is the notation, and it is drawn the
//          same in every locale; the label a musician reads to find the button is interface text.
// KEYWORDS: bar-mark, segno, coda, fermata, player-ending, label, shared-wording, localized
/// Returns the words that name [mark] on the sheet's button.
String barMarkText(BarMark mark, AppLocalizations l10n) => switch (mark) {
  BarMark.segno => l10n.markSegno,
  BarMark.coda => l10n.markCoda,
  BarMark.fermata => l10n.markFermata,
  BarMark.playerEnding => l10n.markPlayerEnding,
};

// The glyph beside each mark button, in one switch rather than four literals at the call site, so
// a sign and its icon cannot drift apart. The choices are stand-ins for shapes the app has no font
// for: a target for the segno's crossed circle, a centre focus for the coda's, a pause disc for the
// fermata's held note, and a stop disc for the player's stop.
IconData _markIcon(BarMark mark) => switch (mark) {
  BarMark.segno => Icons.gps_fixed,
  BarMark.coda => Icons.filter_center_focus,
  BarMark.fermata => Icons.pause_circle_outline,
  BarMark.playerEnding => Icons.stop_circle_outlined,
};

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
  //         the operation happened. Null asks the catalogue for the generic refusal, which is what a
  //         caller that has nothing more specific to say passes. sectionId and barIndex — the
  //         address the cursor should take, omitted when the operation did not move it.
  // OUTPUTS: Nothing. An applied operation moves the cursor, ticks the haptic, rebuilds the caller
  //          and writes one structured line carrying the resulting form; a refused one changes
  //          nothing but the status line and writes why.
  // KEYWORDS: apply, cursor, haptic, structured-log, refusal-reporting, single-path, localized
  void _report(
    bool applied,
    String message, {
    String? refusal,
    String? sectionId,
    int? barIndex,
  }) {
    if (!applied) {
      debugPrint(
        'viewer.form.refused op="$message" section=$_sectionId bar=$_barIndex',
      );
      setState(
        () => _status =
            refusal ?? AppLocalizations.of(context).formRefusedDefault,
      );
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
      before ? l10n.formBarInsertedBefore : l10n.formBarInsertedAfter,
      refusal: l10n.formNoSuchBarInsert,
      barIndex: before ? _barIndex : _barIndex + 1,
    );
  }

  // PURPOSE: Copy the cursor's bar into the place after it and leave the cursor on the copy, so the
  //          musician can edit what they just made.
  // INPUTS: None.
  // OUTPUTS: Nothing. The cursor moves to `barIndex + 1`.
  // KEYWORDS: bar-duplicate, cursor-on-copy, repeat-bar
  void _duplicateBar() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool applied = widget.session.duplicateBar(
      sectionId: _sectionId,
      barIndex: _barIndex,
    );
    _report(
      applied,
      l10n.formBarDuplicated,
      refusal: l10n.formNoSuchBarCopy,
      barIndex: _barIndex + 1,
    );
  }

  // PURPOSE: Remove the cursor's bar and leave the cursor on the bar that took its place, or on the
  //          section's new last bar when the last one went.
  // INPUTS: None.
  // OUTPUTS: Nothing. The last bar of a section is refused, with the reason on screen.
  // KEYWORDS: bar-delete, cursor-clamp, last-bar-refusal
  void _deleteBar() {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
      l10n.formBarDeleted,
      refusal: l10n.formLastBarRefused,
      barIndex: next,
    );
  }

  // PURPOSE: Switch the repeat-start barline on the cursor's bar on or off, which is one half of
  //          marking the passage a musician repeats: this bar starts the passage, and the bar the
  //          passage comes back to carries the repeat end.
  // INPUTS: None; reads the cursor's bar to decide which way the toggle goes.
  // OUTPUTS: Nothing. The button is a toggle rather than two buttons because a sign that is either
  //          present or absent has two states, and showing which one the bar is in is the whole of
  //          what "set or clear" needs. A repeat start with no end is written as asked: the
  //          derivation reads it as a passage played once and reports it, and the status line says
  //          so rather than the sheet refusing it.
  // KEYWORDS: repeat-start, toggle, unmatched-start-note, op-log, rebuild-on-apply
  void _toggleRepeatStart() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Bar? bar = _bar;
    if (bar == null) {
      return;
    }
    final bool starts = bar.openingBarline != Barline.repeatStart;
    final bool applied = widget.session.setRepeatStart(
      sectionId: _sectionId,
      barIndex: _barIndex,
      starts: starts,
    );
    _report(
      applied,
      starts ? l10n.formRepeatStartSet : l10n.formRepeatStartCleared,
      refusal: l10n.formBarlineSame,
    );
  }

  // PURPOSE: Switch the repeat-end barline on the cursor's bar on or off, which closes the passage
  //          the repeat start opened.
  // INPUTS: None; reads the cursor's bar to decide which way the toggle goes.
  // OUTPUTS: Nothing. As with the start, a lone repeat end is written as asked and reported by the
  //          derivation instead of being refused here.
  // KEYWORDS: repeat-end, toggle, unmatched-end-note, op-log, rebuild-on-apply
  void _toggleRepeatEnd() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Bar? bar = _bar;
    if (bar == null) {
      return;
    }
    final bool ends = bar.closingBarline != Barline.repeatEnd;
    final bool applied = widget.session.setRepeatEnd(
      sectionId: _sectionId,
      barIndex: _barIndex,
      ends: ends,
    );
    _report(
      applied,
      ends ? l10n.formRepeatEndSet : l10n.formRepeatEndCleared,
      refusal: l10n.formBarlineSame,
    );
  }

  // PURPOSE: Step the cursor's bar through the three states of the repeat-previous symbol — no
  //          symbol, the previous bar, the previous two bars — which is how a `%` bar is written,
  //          and how it is taken away again.
  // INPUTS: None; reads the symbol the cursor's bar carries now.
  // OUTPUTS: Nothing. The cycle is ordered off → one bar → two bars → off so that every state is
  //          reachable from every other by pressing the same button, which is what makes this one
  //          control instead of three and keeps it inside D2's two-tap budget. The button's own
  //          label carries the state, because a musician who cannot see what the symbol currently
  //          is cannot tell what the next press will do.
  // KEYWORDS: repeat-previous, percent-bar, cycle, three-states, op-log, rebuild-on-apply
  void _cycleRepeatPrevious() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Bar? bar = _bar;
    if (bar == null) {
      return;
    }
    final RepeatPrevious next = switch (bar.repeatPrevious) {
      RepeatPrevious.none => RepeatPrevious.oneBar,
      RepeatPrevious.oneBar => RepeatPrevious.twoBars,
      RepeatPrevious.twoBars => RepeatPrevious.none,
    };
    final bool applied = widget.session.setRepeatPrevious(
      sectionId: _sectionId,
      barIndex: _barIndex,
      previous: next,
    );
    _report(
      applied,
      l10n.formRepeatPreviousStatus(repeatPreviousText(next, l10n)),
      refusal: l10n.formSymbolSame,
    );
  }

  // PURPOSE: Ask which alternative ending the cursor's bar carries and apply the answer, because a
  //          bracket's figure is a small set of choices rather than text and asking through a
  //          keyboard would charge a musician for a number the sheet can offer as a button.
  // INPUTS: None; reads the bracket the cursor's bar carries now, so the dialog can show it.
  // OUTPUTS: Nothing. A dismissed dialog and a choice equal to what the bar already carries change
  //          nothing. "No bracket" is a real choice and removes the bracket; it is not the same as
  //          the unnumbered bracket, which the page draws and the musician asked for.
  // KEYWORDS: volta, ending, bracket, dialog, no-keyboard, clear-by-null, op-log
  Future<void> _chooseVolta() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Bar? bar = _bar;
    if (bar == null) {
      return;
    }
    final _VoltaChoice? choice = await showDialog<_VoltaChoice>(
      context: context,
      builder: (BuildContext context) => _VoltaDialog(current: bar.volta),
    );
    if (!mounted || choice == null || !choice.chosen) {
      return;
    }
    final bool applied = widget.session.setVolta(
      sectionId: _sectionId,
      barIndex: _barIndex,
      volta: choice.volta,
    );
    _report(
      applied,
      // No full stop after the figure: `voltaText` names a bracket the way it is drawn, and the
      // figure already carries the dot that belongs to it, so a sentence ending here would print
      // `[1..` — two dots where the page has one. The Russian wording ends on the figure for the
      // same reason, which is why the message itself carries no full stop either.
      choice.volta == null
          ? l10n.formEndingRemoved
          : l10n.formEndingSetTo(voltaText(choice.volta!, l10n)),
      refusal: l10n.formBracketSame,
    );
  }

  // PURPOSE: Switch one of the four signs the painter draws on a bar — the segno, the coda, the
  //          fermata or the player's stop — on or off on the cursor's bar, which is the whole of the
  //          control for a mark.
  // INPUTS: mark — which sign the pressed button stands for; the sheet builds one button per
  //         [BarMark] value.
  // OUTPUTS: Nothing. The button is a TOGGLE rather than a pair of buttons because a sign is either
  //          present or absent, and the button's `active` state is what shows which state the bar
  //          is in. A bar that already carries two signs keeps both; pressing a third's button adds
  //          the third and leaves the other two exactly where they were, which is the model's own
  //          set semantics and the reason the controls are four toggles and not a cycle. The status
  //          line names the sign and what happened to it, because the page is behind the sheet.
  // KEYWORDS: bar-mark, segno, coda, fermata, player-ending, toggle, set-semantics, op-log,
  //           rebuild-on-apply, no-keyboard
  void _toggleMark(BarMark mark) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Bar? bar = _bar;
    if (bar == null) {
      return;
    }
    final bool present = !bar.marks.contains(mark);
    final bool applied = widget.session.setBarMark(
      sectionId: _sectionId,
      barIndex: _barIndex,
      mark: mark,
      present: present,
    );
    _report(
      applied,
      present
          ? l10n.formMarkSet(barMarkText(mark, l10n))
          : l10n.formMarkCleared(barMarkText(mark, l10n)),
      refusal: present ? l10n.formSignPresent : l10n.formSignAbsent,
    );
  }

  // PURPOSE: Add a new one-bar section on the chosen side of the cursor's section.
  // INPUTS: before — true to put the new section in front of the cursor's, false behind it.
  // OUTPUTS: Nothing. The cursor moves into the new section's first bar, because an operation on a
  //          section the musician cannot see would leave them pressing buttons at nothing.
  // KEYWORDS: section-insert, cursor-to-new-section, rehearsal-letter, one-bar
  void _insertSection({required bool before}) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? created = before
        ? widget.session.insertSectionBefore(_sectionId)
        : widget.session.insertSectionAfter(_sectionId);
    _report(
      created != null,
      before ? l10n.formSectionInsertedBefore : l10n.formSectionInsertedAfter,
      refusal: l10n.formNoSuchSectionInsert,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? created = widget.session.duplicateSection(_sectionId);
    _report(
      created != null,
      l10n.formSectionDuplicated,
      refusal: l10n.formNoSuchSectionCopy,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool applied = widget.session.moveSection(_sectionId, places);
    _report(
      applied,
      places < 0 ? l10n.formSectionMovedEarlier : l10n.formSectionMovedLater,
      refusal: l10n.formSectionAtEnd,
    );
  }

  // PURPOSE: Remove the cursor's section and everything in it, leaving the cursor in the section
  //          that takes its place.
  // INPUTS: None.
  // OUTPUTS: Nothing. The song's only section is refused, with the reason on screen.
  // KEYWORDS: section-delete, cursor-to-successor, last-section-refusal
  void _deleteSection() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int index = _sectionIndex;
    final bool applied = widget.session.deleteSection(_sectionId);
    String? next;
    if (applied) {
      final List<Section> sections = _song.sections;
      next = sections[index < sections.length ? index : sections.length - 1].id;
    }
    _report(
      applied,
      l10n.formSectionDeleted,
      refusal: l10n.formLastSectionRefused,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
      l10n.formSectionRenamed(label.text),
      refusal: l10n.formNameSame,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
              _buildGroup(l10n.formGroupBar, <Widget>[
                SheetButton(
                  buttonKey: 'song-form-bar-insert-before',
                  icon: Icons.add,
                  label: l10n.formBarBefore,
                  onTap: hasBar ? () => _insertBar(before: true) : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-bar-insert-after',
                  icon: Icons.add,
                  label: l10n.formBarAfter,
                  onTap: hasBar ? () => _insertBar(before: false) : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-bar-duplicate',
                  icon: Icons.copy_all_outlined,
                  label: l10n.formDuplicateBar,
                  onTap: hasBar ? _duplicateBar : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-bar-delete',
                  icon: Icons.delete_outline,
                  label: l10n.formDeleteBar,
                  danger: true,
                  onTap: canDeleteBar ? _deleteBar : null,
                ),
              ]),
              const SizedBox(height: 14),
              // Where the tune repeats and which pass takes which ending. The buttons carry the
              // state of the cursor's bar as well as the action, because a sign that is present or
              // absent is something a musician reads before deciding what to press; a row of
              // identical buttons would say what CAN be done and not what IS.
              _buildGroup(l10n.formGroupRepeat, <Widget>[
                SheetButton(
                  buttonKey: 'song-form-repeat-start',
                  icon: Icons.first_page,
                  label: l10n.formRepeatStart,
                  active: bar?.openingBarline == Barline.repeatStart,
                  onTap: hasBar ? _toggleRepeatStart : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-repeat-end',
                  icon: Icons.last_page,
                  label: l10n.formRepeatEnd,
                  active: bar?.closingBarline == Barline.repeatEnd,
                  onTap: hasBar ? _toggleRepeatEnd : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-repeat-previous',
                  icon: Icons.repeat,
                  label: l10n.formPreviousLabel(
                    repeatPreviousText(bar?.repeatPrevious, l10n),
                  ),
                  active:
                      bar != null && bar.repeatPrevious != RepeatPrevious.none,
                  onTap: hasBar ? _cycleRepeatPrevious : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-volta',
                  icon: Icons.bookmark_border,
                  label: l10n.formEndingLabel(voltaText(bar?.volta, l10n)),
                  active: bar?.volta != null,
                  onTap: hasBar ? () => _chooseVolta() : null,
                ),
              ]),
              const SizedBox(height: 14),
              // The signs drawn ON the bar rather than around it: the segno, the coda, the fermata
              // and the player's stop. Every one is an independent toggle over the bar's own set of
              // marks, so the buttons show what the bar carries now and a bar may carry several at
              // once — see the header note on why this is a group and not a cycle.
              _buildGroup(l10n.formGroupMarks, <Widget>[
                for (final BarMark mark in BarMark.values)
                  SheetButton(
                    buttonKey: 'song-form-mark-${mark.name}',
                    icon: _markIcon(mark),
                    label: barMarkText(mark, l10n),
                    active: bar?.marks.contains(mark) ?? false,
                    onTap: hasBar ? () => _toggleMark(mark) : null,
                  ),
              ]),
              const SizedBox(height: 14),
              _buildGroup(l10n.formGroupSection, <Widget>[
                SheetButton(
                  buttonKey: 'song-form-section-insert-before',
                  icon: Icons.playlist_add,
                  label: l10n.formSectionBefore,
                  onTap: section == null
                      ? null
                      : () => _insertSection(before: true),
                ),
                SheetButton(
                  buttonKey: 'song-form-section-insert-after',
                  icon: Icons.playlist_add,
                  label: l10n.formSectionAfter,
                  onTap: section == null
                      ? null
                      : () => _insertSection(before: false),
                ),
                SheetButton(
                  buttonKey: 'song-form-section-duplicate',
                  icon: Icons.copy_all_outlined,
                  label: l10n.formDuplicateSection,
                  onTap: section == null ? null : _duplicateSection,
                ),
                SheetButton(
                  buttonKey: 'song-form-section-rename',
                  icon: Icons.edit_outlined,
                  label: l10n.formRenameSection,
                  onTap: section == null ? null : () => _renameSection(),
                ),
                SheetButton(
                  buttonKey: 'song-form-section-up',
                  icon: Icons.arrow_upward,
                  label: l10n.moveEarlier,
                  onTap: canMoveUp ? () => _moveSection(-1) : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-section-down',
                  icon: Icons.arrow_downward,
                  label: l10n.moveLater,
                  onTap: canMoveDown ? () => _moveSection(1) : null,
                ),
                SheetButton(
                  buttonKey: 'song-form-section-delete',
                  icon: Icons.delete_outline,
                  label: l10n.formDeleteSection,
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
  // KEYWORDS: header, position-label, cursor, section-identity, done, localized
  Widget _buildHeader(Section? section, int sectionIndex) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String position = section == null
        ? l10n.formNoBarSelected
        : l10n.formPosition(_barOrdinal, '${section.label}');
    final String detail = section == null
        ? l10n.formBarGone
        : l10n.formDetail(
            _barIndex + 1,
            section.bars.length,
            sectionIndex + 1,
            _song.sections.length,
          );
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
          child: Text(
            l10n.done,
            style: const TextStyle(color: sheetAccentColor),
          ),
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
///
/// The button itself lives in `sheet_button.dart`, shared with the text-cue sheet: the two sheets
/// are one surface to a musician, and a copy of this widget in each would be two looks for one
/// gesture. Everything below decides WHERE the buttons go and WHAT a tap does.

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
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.formRenameSection),
      content: TextField(
        key: const ValueKey<String>('song-form-rename-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.formRenameLabel,
          helperText: l10n.formRenameHelper,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (String _) => setState(() {}),
        onSubmitted: (String _) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('song-form-rename-save'),
          // Disabled on an empty name: a section whose label prints nothing looks unlabelled, and the
          // sheet would then be the only place the difference could be seen.
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: Text(l10n.formRenameButton),
        ),
      ],
    );
  }
}

/// What the ending dialog gave back: whether the musician chose anything at all, and the bracket
/// they chose — a null bracket being a real choice ("no bracket"), not an absence of one.
///
/// A record rather than a nullable [Volta] because the two states a caller must tell apart would
/// otherwise share a value: a dismissed dialog and "remove the bracket" would both arrive as null.
typedef _VoltaChoice = ({bool chosen, Volta? volta});

/// The brackets the ending dialog offers, in the order they are shown.
///
/// `0` is the unnumbered bracket — the one iReal writes `N0` and the page draws as a bare `[` — and
/// it is offered beside "No bracket" because they are different states of the bar. The figures stop
/// at 4: a chart that needs a fifth ending is expressible in the model, but none appeared in the
/// corpus this project checked against, and a row of every figure to twenty-six would be a wall of
/// buttons to solve a case nobody has.
const List<_VoltaChoice> _voltaChoices = <_VoltaChoice>[
  (chosen: true, volta: null),
  (chosen: true, volta: Volta(0)),
  (chosen: true, volta: Volta(1)),
  (chosen: true, volta: Volta(2)),
  (chosen: true, volta: Volta(3)),
  (chosen: true, volta: Volta(4)),
];

// PURPOSE: Ask which alternative-ending bracket a bar carries, as buttons rather than as a number
//          to type, because a phone's keyboard covers half the screen and a bracket figure is one
//          of a handful of choices.
// INPUTS: current — the bracket the bar carries now, so the dialog can mark it and a musician can
//         see what they are changing from.
// OUTPUTS: A [_VoltaChoice] when an option is pressed, or null when the dialog is dismissed. The
//          dialog never edits the document itself: it hands the choice back, so a dismissed dialog
//          cannot have half-changed anything.
// KEYWORDS: volta, ending, dialog, choices, no-keyboard, dismiss-safe, cancel-is-null
class _VoltaDialog extends StatelessWidget {
  /// Creates the ending chooser showing [current] as the chosen figure.
  const _VoltaDialog({required this.current});

  /// The bracket the bar carries, or null when it carries none.
  final Volta? current;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.formEndingTitle),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final _VoltaChoice choice in _voltaChoices)
            SheetButton(
              buttonKey: 'song-form-volta-${_voltaChoiceKey(choice.volta)}',
              icon: choice.volta == null ? Icons.block : Icons.bookmark_border,
              label: choice.volta == null
                  ? l10n.formNoBracket
                  : (choice.volta!.number == 0
                        ? l10n.formUnnumberedBracket
                        : '[${choice.volta!.number}.'),
              active: current == choice.volta,
              onTap: () => Navigator.of(context).pop(choice),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('song-form-volta-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// The key fragment naming one ending choice, so a test and a driving tool can address each option
/// without depending on the order the buttons happen to be built in.
String _voltaChoiceKey(Volta? volta) =>
    volta == null ? 'none' : 'n${volta.number}';
