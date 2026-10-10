// PURPOSE: Let a musician WRITE WORDS on the chart — `To Coda`, `D.C. al Fine`, `Solo`, `Vamp`,
//          `4×` — beside a bar or one of its cells, and change, move or remove them afterwards. The
//          catalogue has carried `textcue.insert`, `textcue.edit`, `textcue.move` and
//          `textcue.delete` since it was written and nothing wrote one; this sheet is where they are
//          written, and `EditSession` decides which event each press is.
// INPUTS: The session being edited, the address the musician selected (section id, zero-based bar
//         index, and the cell when the touch named one), and a callback the sheet calls after every
//         applied edit so the page can be rebuilt.
// OUTPUTS: A modal bottom sheet whose result is nothing: every press applies through [EditSession]
//          as it is pressed, so by the time it closes the document already holds the cue. It keeps
//          its own address cursor — the bar the NEXT cue is added to — because reaching another bar
//          is an act of this sheet rather than a second selection in the page, and it deletes
//          through the log any cue it leaves with no words (see below), so closing it can never
//          leave a remark nothing on the page can draw or select.
// KEYWORDS: text-cue, staff-text, bottom-sheet, op-log, undoable, edit-session, no-keyboard-needed,
//           address-cursor, empty-cue-cleanup
//
// WHY A SHEET AND NOT A CONTROL ABOVE THE CHART.
//
// The lesson is already measured twice in this application (A34, A38, A41): a row in the body takes
// height away from the chart, and FIT refuses to shrink a page past the legible floor, so a control
// in the body turns a song that fitted on one page into one that does not. This sheet takes no
// height until it is opened, and it is opened from an app-bar action, whose height the actions do
// not change.
//
// WHY ITS OWN SHEET AND NOT A GROUP IN THE FORM SHEET.
//
// The form sheet is about the SHAPE of the tune — where the bars and sections are — and its controls
// are all one press with one answer. This one needs a text field, a list of the remarks already on
// the bar, and a per-remark set of moves, which would triple the form sheet's surface and put a
// keyboard in the middle of building a 32-bar form. What is deliberately NOT duplicated is the
// SELECTION: this sheet is opened from the address the page's own hit test already produced, by an
// app-bar action beside the form one, so there is still exactly one thing in the application that
// decides which bar the musician means, and it is the page.
//
// WHY IT CANNOT LEAVE AN EMPTY CUE BEHIND, AND WHY THE MODEL ALLOWS ONE.
//
// `TextCue.text` documents empty as "inserted and not yet typed into", and that is the state the
// FIRST press of "Add here" produces: a cue has to exist before there is a cursor to type into, and
// the words arrive in a second event. So the insert is empty on purpose and the log records it. The
// document, however, must not KEEP one: a cue with no words draws nothing, so nothing on the page
// can be tapped to select it and only the log could reach it again. The rule this sheet implements
// is therefore: EMPTY IS AN INTERMEDIATE STATE AND NOT AN ENDPOINT. Every cue this sheet touched and
// leaves empty when it closes is deleted through `textcue.delete`, which is itself an event the
// musician can undo — so clearing the words and removing the remark are the same gesture, and the
// log still shows both halves in the order they happened.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'sheet_button.dart';
import 'sheet_surface.dart';

/// How far one press of a nudge moves a cue down or up, in surface logical pixels.
///
/// One line of the cue's own type plus a little air, so two remarks on one bar stack into two
/// readable lines rather than one smudged pair. It is a distance on the SURFACE and not an
/// anchor-local one, but the offsets a cue stores are anchor-local logical pixels and the painter
/// multiplies the anchor's position — not the offset — by the page scale, so a nudge is the same
/// distance on a fitted page as on an ordinary one. That is the one place this sheet's arithmetic
/// has to agree with the painter's, and it does by both being in surface pixels.
const double textCueNudge = 20;

// PURPOSE: Open the text-cue sheet for one selected bar and resolve when the musician is finished.
// INPUTS: context — where to open the sheet. session — the document being edited. sectionId and
//         barIndex — the selected bar, in the model's own zero-based numbering. beat — the cell the
//         touch named, or null when it named the bar as a whole; a cue added here inherits that
//         choice, so a remark about a beat is anchored to the beat and a remark about the bar is
//         anchored to the bar. onChanged — called after every applied edit so the caller can
//         rebuild; the sheet does not know how the caller draws its page.
// OUTPUTS: A future that completes when the sheet is dismissed, whether anything was edited or not.
//          An address that names no bar opens nothing and completes at once, because every control
//          in the sheet acts on that address relative to the song.
// KEYWORDS: show, bottom-sheet, session-edit, callback, guard, address-entry
/// Opens the text-cue sheet for the bar at ([sectionId], [barIndex]).
Future<void> showTextCueSheet(
  BuildContext context, {
  required EditSession session,
  required String sectionId,
  required int barIndex,
  int? beat,
  VoidCallback? onChanged,
}) async {
  if (session.song.barAt(sectionId, barIndex) == null) {
    debugPrint(
      'viewer.textcue.skipped section=$sectionId bar=$barIndex '
      'reason=no-such-bar',
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: sheetPanelColor,
    isScrollControlled: true,
    builder: (BuildContext context) => TextCueSheet(
      session: session,
      sectionId: sectionId,
      barIndex: barIndex,
      beat: beat,
      onChanged: onChanged,
    ),
  );
}

/// The text-cue sheet itself: the address the next cue is added to, the remark being edited, and
/// the words typed into it.
class TextCueSheet extends StatefulWidget {
  /// Creates a cue sheet over the bar at ([sectionId], [barIndex]) of [session].
  const TextCueSheet({
    super.key,
    required this.session,
    required this.sectionId,
    required this.barIndex,
    this.beat,
    this.onChanged,
  });

  /// The document being edited.
  final EditSession session;

  /// The section the initially selected bar belongs to.
  final String sectionId;

  /// The zero-based index of the initially selected bar inside its section.
  final int barIndex;

  /// The cell the initial selection named, or null when it named the whole bar.
  final int? beat;

  /// Called after every applied edit.
  final VoidCallback? onChanged;

  @override
  State<TextCueSheet> createState() => _TextCueSheetState();
}

/// The sheet's state: the address cursor, the cue being edited, the words in the field, and what
/// the last press did.
class _TextCueSheetState extends State<TextCueSheet> {
  /// The section the next added cue goes into.
  late String _sectionId = widget.sectionId;

  /// The index, inside [_sectionId], of the bar the next added cue goes into.
  late int _barIndex = widget.barIndex;

  /// The identity of the cue being edited, or null when none is selected.
  String? _selectedId;

  /// The words in the editing field, which are NOT the document until Save is pressed.
  ///
  /// Held in a controller rather than applied on every keystroke for the same reason the form
  /// sheet's cursor is held here: one gesture should be one event. A `textcue.edit` per character
  /// would be a log of a hundred events for one word and a hundred presses of undo to take it back.
  final TextEditingController _words = TextEditingController();

  /// The focus of the words field, moved there EXPLICITLY whenever a cue is picked or added.
  ///
  /// `TextField.autofocus` is not enough and the measurement says why: the field is built once,
  /// disabled, and only becomes enabled when a cue is selected or added — and `autofocus` fires on
  /// the FIRST mount of the field, not on the frame that enables it. Driving the built web app
  /// showed that plainly: pressing "Write words here" inserted the cue, left the cursor nowhere, and
  /// the typed words went to the browser instead of the field (`viewer.textcue.refused op="Saved the
  /// words."` with the cue still empty). Requesting the focus in a post-frame callback, after the
  /// rebuild that enables the field, is what puts the cursor where the musician is looking.
  final FocusNode _wordsFocus = FocusNode();

  /// The identities this sheet has created or edited, and therefore may delete when it closes.
  ///
  /// A set and not a flag on each cue, because the rule is about this sheet's own work: a cue it
  /// never touched is left exactly as it was, whether or not its words are empty.
  final Set<String> _touched = <String>{};

  /// What the last press did, or the reason the last one was refused.
  String? _status;

  /// The song as it stands, read back from the session after every edit.
  Song get _song => widget.session.song;

  /// The bar the cursor names, or null when it names no bar.
  Bar? get _bar => _song.barAt(_sectionId, _barIndex);

  /// The cue being edited, or null when none is selected or it has been removed.
  TextCue? get _selected {
    final String? id = _selectedId;
    return id == null ? null : widget.session.textCueById(id);
  }

  /// The cues anchored to the cursor's bar, in the document's render order.
  ///
  /// Both the bar-level ones and the cell-level ones inside that bar are listed, because a musician
  /// editing "this bar's remarks" means every remark they can see on it, and the cell each one sits
  /// on is printed beside its words.
  List<TextCue> get _cuesHere => <TextCue>[
    for (final TextCue cue in widget.session.document.textCues)
      if (cue.place.anchor.sectionId == _sectionId &&
          cue.place.anchor.bar == _barIndex)
        cue,
  ];

  /// Where the cursor's bar sits in the whole written chart, or -1 when it names no bar.
  int get _cursorOrdinal {
    int ordinal = 0;
    for (final Section section in _song.sections) {
      if (section.id == _sectionId) {
        return _barIndex >= 0 && _barIndex < section.bars.length
            ? ordinal + _barIndex
            : -1;
      }
      ordinal += section.bars.length;
    }
    return -1;
  }

  @override
  void dispose() {
    _words.dispose();
    _wordsFocus.dispose();
    super.dispose();
  }

  // PURPOSE: Put the cursor in the words field once the frame that enabled it has been built, so a
  //          musician who has just added a cue or picked one can type without aiming at the field.
  // INPUTS: None.
  // OUTPUTS: Nothing. Deferred to after the frame because the field is disabled until the rebuild
  //          that follows the selection lands, and a disabled field refuses the focus. Guarded on
  //          [mounted] because the sheet can be closed inside that frame.
  // KEYWORDS: focus, post-frame, enabled-after-rebuild, mounted-guard, keyboard-first
  void _focusWords() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _wordsFocus.requestFocus();
      }
    });
  }

  // PURPOSE: Turn an ordinal in the written chart into the address the model uses, so "the next bar"
  //          means the next bar in the song rather than the next bar in this section — a cue moved
  //          off the end of a section should land in the next part, not be refused.
  // INPUTS: ordinal — the zero-based position in the whole chart.
  // OUTPUTS: The (section id, bar index) pair at that position, or null when the position is before
  //          the first bar or past the last one. Null rather than a clamped value, because a caller
  //          that asked to move past the end has to be told the move is impossible, not silently
  //          given the last bar.
  // KEYWORDS: address-walk, ordinal-to-address, section-crossing, null-when-out-of-range
  ({String sectionId, int barIndex})? _barForOrdinal(int ordinal) {
    if (ordinal < 0) {
      return null;
    }
    int remaining = ordinal;
    for (final Section section in _song.sections) {
      if (remaining < section.bars.length) {
        return (sectionId: section.id, barIndex: remaining);
      }
      remaining -= section.bars.length;
    }
    return null;
  }

  // PURPOSE: Say what a press did, or why it was refused, because the page the change landed on is
  //          behind the sheet.
  // INPUTS: applied — whether the session took the operation. message — what it did, in the
  //         musician's words. refusal — what to say instead when it was refused.
  // OUTPUTS: Nothing. An applied operation ticks the haptic, rebuilds the caller and writes one
  //          structured line carrying the cue count and the document's own counters; a refused one
  //          changes nothing but the status line and writes why.
  // KEYWORDS: report, status, haptic, structured-log, refusal, single-path
  void _report(
    bool applied,
    String message, {
    String refusal = 'Nothing changed: that is not possible here.',
  }) {
    if (!applied) {
      debugPrint(
        'viewer.textcue.refused op="$message" section=$_sectionId '
        'bar=$_barIndex selected=${_selectedId ?? 'none'}',
      );
      setState(() => _status = refusal);
      return;
    }
    setState(() => _status = message);
    HapticFeedback.selectionClick();
    widget.onChanged?.call();
    debugPrint(
      'viewer.textcue.op "$message" section=$_sectionId bar=$_barIndex '
      'cues=${widget.session.document.textCues.length} '
      'seq=${widget.session.seq} undo_depth=${widget.session.undoDepth}',
    );
  }

  // PURPOSE: Put a new cue on the cursor's bar and select it for typing, which is the whole of
  //          "write words on the chart": one press to make a place for them, then the words.
  // INPUTS: None; reads the cursor and the cell the page selection named.
  // OUTPUTS: Nothing. The cue is inserted with NO words, because the words are a second event and
  //          the model documents that state; the editor opens on it with the cursor in the field.
  //          A refusal is said on screen rather than ignored — it means the cursor names no bar,
  //          which only a form edit made elsewhere could have produced.
  // KEYWORDS: insert, empty-until-typed, select-for-editing, cursor-into-field, op-log
  void _addCue() {
    final String? id = widget.session.insertTextCue(
      sectionId: _sectionId,
      barIndex: _barIndex,
      beat: widget.beat,
      offsetX: _defaultOffsetX,
      offsetY: _defaultOffsetY,
    );
    if (id == null) {
      _report(
        false,
        'Added a cue.',
        refusal: 'Nothing was added: the song has no such bar.',
      );
      return;
    }
    _touched.add(id);
    setState(() {
      _selectedId = id;
      _words.text = '';
    });
    _focusWords();
    debugPrint(
      'viewer.textcue.add id=$id section=$_sectionId bar=$_barIndex '
      'beat=${widget.beat ?? 'bar'}',
    );
    _report(true, 'Added a cue — type the words.');
  }

  // PURPOSE: Put a cue's current words into the field, so the musician edits what the cue says
  //          rather than retyping it.
  // INPUTS: cue — the cue to edit.
  // OUTPUTS: Nothing. The field is populated and focused; nothing is written to the document until
  //          Save is pressed, so selecting a cue can never change one.
  // KEYWORDS: select-cue, populate-field, no-document-write, cancel-safe
  void _select(TextCue cue) {
    setState(() {
      _selectedId = cue.id;
      _words.text = cue.text;
      _status = null;
    });
    _focusWords();
  }

  // PURPOSE: Apply the words in the field to the selected cue.
  // INPUTS: None; reads the field and the selection.
  // OUTPUTS: Nothing. A press with no cue selected, or with the words the cue already carries, does
  //          nothing and says so rather than appending a log row that changed nothing (the rule
  //          `EditSession.editTextCue` documents). The cue's identity is kept, so its place in the
  //          render order and its anchor are untouched by a change of words.
  // KEYWORDS: edit-words, before-after-event, no-op-refusal, identity-kept
  void _saveWords() {
    final TextCue? cue = _selected;
    if (cue == null) {
      _report(
        false,
        'Nothing happened.',
        refusal: 'Nothing was saved: no cue is selected.',
      );
      return;
    }
    final bool applied = widget.session.editTextCue(cue.id, _words.text);
    _touched.add(cue.id);
    _report(
      applied,
      'Saved the words.',
      refusal: 'Nothing changed: the cue already says that.',
    );
  }

  // PURPOSE: Take the selected cue off the chart.
  // INPUTS: None; reads the selection.
  // OUTPUTS: Nothing. The cue's identity stops naming anything, so the selection and the field are
  //          cleared; the deletion carries the cue in full and its position, so an undo restores
  //          both its words and its place in the render order.
  // KEYWORDS: delete, whole-value-event, clear-selection, undoable
  void _deleteCue() {
    final TextCue? cue = _selected;
    if (cue == null) {
      _report(
        false,
        'Nothing happened.',
        refusal: 'Nothing was removed: no cue is selected.',
      );
      return;
    }
    final bool applied = widget.session.deleteTextCue(cue.id);
    if (applied) {
      _touched.remove(cue.id);
      setState(() {
        _selectedId = null;
        _words.text = '';
      });
    }
    _report(
      applied,
      'Removed the cue.',
      refusal: 'Nothing was removed: the cue is already gone.',
    );
  }

  // PURPOSE: Move the selected cue by whole bars, in the written order, which is how a remark
  //          written on the wrong bar is put right and how two remarks that landed on top of each
  //          other are pulled apart.
  // INPUTS: delta — how many bars to move it by; negative is earlier.
  // OUTPUTS: Nothing. The cue keeps its words, its cell and its offset, and its identity, so the
  //          document's other cues are untouched. A move past either end of the song is refused and
  //          said on screen. The move may cross a section boundary: an address is (section id, bar
  //          index), and the model's own address rule has no notion of a cue belonging to a
  //          section.
  // KEYWORDS: move, re-anchor, bar-shift, section-crossing, bounds-refusal, words-kept
  void _moveCue(int delta) {
    final TextCue? cue = _selected;
    if (cue == null) {
      _report(
        false,
        'Nothing happened.',
        refusal: 'Nothing moved: no cue is selected.',
      );
      return;
    }
    final int ordinal = _ordinalOf(cue.place.anchor);
    final ({String sectionId, int barIndex})? target = _barForOrdinal(
      ordinal + delta,
    );
    if (target == null) {
      _report(
        false,
        'Nothing happened.',
        refusal: 'Nothing moved: that is the end of the song.',
      );
      return;
    }
    final bool applied = widget.session.moveTextCue(
      cue.id,
      sectionId: target.sectionId,
      barIndex: target.barIndex,
      beat: cue.place.anchor.beat,
      offsetX: cue.place.offsetX,
      offsetY: cue.place.offsetY,
    );
    _report(
      applied,
      delta < 0 ? 'Moved the cue a bar earlier.' : 'Moved the cue a bar later.',
      refusal: 'Nothing moved: the cue is already there.',
    );
  }

  // PURPOSE: Move the selected cue up or down inside the place it already holds, which is how two
  //          remarks on one bar are stacked into two readable lines without moving either off the
  //          bar it belongs to.
  // INPUTS: dy — how far to move it, in surface logical pixels; positive is down the page.
  // OUTPUTS: Nothing. Only the cue's own offset changes, so its anchor — and therefore the bar and
  //          the cell it is attached to — is untouched and it still follows that bar when the page
  //          is fitted or transposed.
  // KEYWORDS: move, offset-only, stacking, anchor-kept, reflow-survival
  void _nudgeCue(double dy) {
    final TextCue? cue = _selected;
    if (cue == null) {
      _report(
        false,
        'Nothing happened.',
        refusal: 'Nothing moved: no cue is selected.',
      );
      return;
    }
    final AnchoredPlace place = cue.place;
    final bool applied = widget.session.moveTextCue(
      cue.id,
      sectionId: place.anchor.sectionId,
      barIndex: place.anchor.bar,
      beat: place.anchor.beat,
      offsetX: place.offsetX,
      offsetY: place.offsetY + dy,
    );
    _report(
      applied,
      dy < 0 ? 'Nudged the cue up.' : 'Nudged the cue down.',
      refusal: 'Nothing moved.',
    );
  }

  // PURPOSE: Walk the cursor to another bar, so a musician can add or inspect remarks on bars other
  //          than the one they happened to select, without leaving the sheet.
  // INPUTS: delta — how many bars to walk; negative is earlier.
  // OUTPUTS: Nothing. The cursor moves and the cue list follows it; the selected cue is DROPPED,
  //          because the selection is a remark on the bar being left and the sheet's editor would
  //          otherwise show words that are no longer on screen. A walk past either end is refused.
  // KEYWORDS: cursor, bar-walk, selection-dropped, bounds-refusal, no-page-selection-needed
  void _shiftCursor(int delta) {
    final ({String sectionId, int barIndex})? target = _barForOrdinal(
      _cursorOrdinal + delta,
    );
    if (target == null) {
      _report(
        false,
        'Nothing happened.',
        refusal: 'Nothing moved: that is the end of the song.',
      );
      return;
    }
    setState(() {
      _sectionId = target.sectionId;
      _barIndex = target.barIndex;
      _selectedId = null;
      _words.text = '';
      _status = 'Now on bar ${_cursorOrdinal + 1}.';
    });
  }

  // PURPOSE: Remove, through the log, every cue this sheet left with no words, so closing it cannot
  //          leave an invisible remark behind. See the file header for why the model allows an empty
  //          cue and the application must not keep one.
  // INPUTS: None; reads [_touched] and the document.
  // OUTPUTS: True when at least one cue was deleted. Each deletion is one `textcue.delete`, appended
  //          where the cue sits, so the empty state remains in the log between the insert and the
  //          delete and an undo of the delete brings the empty cue back exactly as it was left.
  //          IDEMPOTENT: a second call finds nothing left to remove, because the deletion removes the
  //          cue from [_touched]'s target set by the only means that matters — the cue is gone.
  //
  //          IT IS CALLED FROM TWO PLACES ON PURPOSE, and that is a defect this sheet had and the
  //          browser run found: a modal sheet can be dismissed by its Done button, by the barrier
  //          behind it, by the system back gesture or by Escape, and only the first of those ran the
  //          first version of this code, which lived inside `_close`. Driving the built web app
  //          proved it — a cue added and never typed into survived a barrier dismissal as an empty
  //          cue that nothing on the page could select (`viewer.textcue.add` with no matching
  //          `viewer.textcue.close`). The Done button still cleans before it pops, and [PopScope]
  //          below cleans on every other route out; both reach this method, and running it twice is
  //          the same as running it once.
  // KEYWORDS: cleanup, empty-cue-deletion, log-visible, undoable, no-ghost, every-dismissal-path
  bool _cleanupEmptyCues() {
    int removed = 0;
    for (final String id in _touched) {
      final TextCue? cue = widget.session.textCueById(id);
      if (cue == null || cue.text.isNotEmpty) {
        continue;
      }
      if (widget.session.deleteTextCue(id)) {
        removed++;
      }
    }
    if (removed > 0) {
      widget.onChanged?.call();
      debugPrint(
        'viewer.textcue.close removed_empty=$removed '
        'cues=${widget.session.document.textCues.length} '
        'seq=${widget.session.seq}',
      );
    }
    return removed > 0;
  }

  // PURPOSE: Close the sheet from its own Done button, taking the empty cues with it.
  // INPUTS: None.
  // OUTPUTS: Nothing. The cleanup runs BEFORE the pop, so the page behind the sheet is already
  //          rebuilt without the cue by the time the sheet is gone and the musician never sees a
  //          remark flash back for one frame. The pop then reaches [PopScope], whose own cleanup call
  //          finds nothing to do.
  // KEYWORDS: close, done-button, cleanup-first, idempotent-cleanup
  void _close() {
    _cleanupEmptyCues();
    Navigator.of(context).pop();
  }

  // PURPOSE: Number a bar the way a musician counts, across sections from the top, so the sheet's
  //          header names the bar the same way the viewer's selection line does.
  // INPUTS: None; reads the cursor and the song.
  // OUTPUTS: The one-based ordinal of the cursor's bar in the whole written chart, or 0 when the
  //          cursor names no bar — reported rather than guessed, and the header says so.
  // KEYWORDS: bar-ordinal, musician-numbering, one-based, total-function
  int get _barOrdinal => _cursorOrdinal + 1;

  /// Where a newly added cue's words start, from its anchor's top-left corner.
  ///
  /// Two logical pixels in and none down: an anchor is either a cell — whose rectangle spans the
  /// bar's full stave height — or the bar itself, and in both cases the top-left is where a remark
  /// written above the chords begins. The vertical offset is what the nudge changes; the horizontal
  /// one is this small inset, so the words do not touch the barline they are drawn beside.
  static const double _defaultOffsetX = 2;

  /// See [_defaultOffsetX].
  static const double _defaultOffsetY = 0;

  // PURPOSE: Find where a cue's anchor sits in the whole written chart, which is the number the
  //          moves walk from.
  // INPUTS: anchor — the address a cue is captured against.
  // OUTPUTS: The zero-based ordinal of that bar, or -1 when the song has no such bar — which a cue
  //          left over from a removed section can genuinely be. -1 makes every walk from it fall
  //          outside the song, so such a cue is refused every move rather than being moved to the
  //          first bar by accident.
  // KEYWORDS: address-to-ordinal, dangling-anchor, sentinel, defensive
  int _ordinalOf(EventAnchor anchor) {
    int ordinal = 0;
    for (final Section section in _song.sections) {
      if (section.id == anchor.sectionId) {
        return anchor.bar >= 0 && anchor.bar < section.bars.length
            ? ordinal + anchor.bar
            : -1;
      }
      ordinal += section.bars.length;
    }
    return -1;
  }

  // PURPOSE: Word the cell a cue is anchored to, so the list on the sheet says WHERE on the bar a
  //          remark sits and not only that it exists.
  // INPUTS: cue — the cue whose cell to name.
  // OUTPUTS: `whole bar` for a bar-level anchor, otherwise `cell N` counted as a musician counts.
  // KEYWORDS: cell-label, one-based, bar-level, total-function
  String _cellLabel(TextCue cue) {
    final int? beat = cue.place.anchor.beat;
    return beat == null ? 'whole bar' : 'cell ${beat + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final TextCue? selected = _selected;
    // PopScope rather than a `dispose` hook, because the cleanup writes EVENTS and calls back into an
    // ancestor: doing that while this state is being unmounted would be a write during teardown.
    // `onPopInvokedWithResult` runs while the sheet is still mounted, so the deletion and the
    // caller's rebuild both land before the route is gone. See [_cleanupEmptyCues] for the defect
    // this exists to close: only the Done button used to clean up, so a sheet dismissed by its
    // barrier left an empty cue that nothing on the page could select.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _cleanupEmptyCues();
        }
      },
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(),
                const SizedBox(height: 10),
                _buildStatus(),
                _buildGroup('THIS BAR', <Widget>[
                  SheetButton(
                    buttonKey: 'text-cue-add',
                    icon: Icons.note_add_outlined,
                    label: 'Write words here',
                    onTap: _bar == null ? null : _addCue,
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-bar-before',
                    icon: Icons.arrow_back,
                    label: 'Previous bar',
                    onTap: () => _shiftCursor(-1),
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-bar-after',
                    icon: Icons.arrow_forward,
                    label: 'Next bar',
                    onTap: () => _shiftCursor(1),
                  ),
                ]),
                const SizedBox(height: 10),
                _buildCueList(),
                const SizedBox(height: 14),
                _buildGroup('THE CUE', <Widget>[
                  SheetButton(
                    buttonKey: 'text-cue-save',
                    icon: Icons.check,
                    label: 'Save words',
                    onTap: selected == null ? null : _saveWords,
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-earlier',
                    icon: Icons.keyboard_arrow_left,
                    label: 'A bar earlier',
                    onTap: selected == null ? null : () => _moveCue(-1),
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-later',
                    icon: Icons.keyboard_arrow_right,
                    label: 'A bar later',
                    onTap: selected == null ? null : () => _moveCue(1),
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-up',
                    icon: Icons.keyboard_arrow_up,
                    label: 'Up a line',
                    onTap: selected == null
                        ? null
                        : () => _nudgeCue(-textCueNudge),
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-down',
                    icon: Icons.keyboard_arrow_down,
                    label: 'Down a line',
                    onTap: selected == null
                        ? null
                        : () => _nudgeCue(textCueNudge),
                  ),
                  SheetButton(
                    buttonKey: 'text-cue-delete',
                    icon: Icons.delete_outline,
                    label: 'Remove the cue',
                    danger: true,
                    onTap: selected == null ? null : _deleteCue,
                  ),
                ]),
                const SizedBox(height: 12),
                _buildWordsField(selected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // PURPOSE: State which bar the next cue goes on, in the words the musician counts in, so a sheet
  //          that holds its own cursor says where the cursor is.
  // INPUTS: None; reads the cursor and the song.
  // OUTPUTS: The header row: the bar ordinal, the section's label, the counts that make a walk
  //          checkable, and the control that closes the sheet.
  // KEYWORDS: header, position-label, cursor, section-identity, done
  Widget _buildHeader() {
    final Section? section = _song.sectionById(_sectionId);
    final int? beat = widget.beat;
    final String detail = section == null
        ? 'The selected bar is no longer in the song.'
        : 'bar ${_barIndex + 1} of ${section.bars.length} in this section · '
              '${beat == null ? 'the whole bar' : 'cell ${beat + 1}'} · '
              '${_cuesHere.length} cue(s) here';
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                section == null
                    ? 'No bar selected'
                    : 'Words · bar $_barOrdinal',
                key: const ValueKey<String>('text-cue-position'),
                style: const TextStyle(
                  color: sheetOnPanelColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                detail,
                key: const ValueKey<String>('text-cue-detail'),
                style: const TextStyle(color: sheetMutedColor, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey<String>('text-cue-done'),
          onPressed: _close,
          child: const Text('Done', style: TextStyle(color: sheetAccentColor)),
        ),
      ],
    );
  }

  // PURPOSE: Say what the last press did, or why it was refused, because the page the words landed
  //          on is behind the sheet.
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
        key: const ValueKey<String>('text-cue-status'),
        style: const TextStyle(color: sheetAccentColor, fontSize: 13),
      ),
    );
  }

  // PURPOSE: List the cues on the cursor's bar so a musician can pick the one to change, and so a
  //          bar with several remarks says so rather than showing only the last one written.
  // INPUTS: None; reads [_cuesHere].
  // OUTPUTS: One tappable row per cue, or a line saying the bar has none. The row carries the words
  //          and the cell, and is marked when it is the cue being edited; an empty cue is named as
  //          such rather than shown as a blank row.
  // KEYWORDS: cue-list, per-bar, selection-mark, empty-words-named, tap-to-edit
  Widget _buildCueList() {
    final List<TextCue> cues = _cuesHere;
    if (cues.isEmpty) {
      return const Text(
        'No words on this bar yet.',
        key: ValueKey<String>('text-cue-empty'),
        style: TextStyle(color: sheetMutedColor, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final TextCue cue in cues)
          Material(
            color: cue.id == _selectedId
                ? sheetSelectedCellColor
                : sheetCellColor,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey<String>('text-cue-row-${cue.id}'),
              onTap: () => _select(cue),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        cue.text.isEmpty ? '(no words yet)' : cue.text,
                        style: TextStyle(
                          color: cue.text.isEmpty
                              ? sheetMutedColor
                              : sheetOnPanelColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _cellLabel(cue),
                      style: const TextStyle(
                        color: sheetMutedColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // PURPOSE: Give the words a field, which is the one form operation in this application that needs
  //          a keyboard: a remark is text, not a choice.
  // INPUTS: selected — the cue being edited, or null.
  // OUTPUTS: A disabled, empty field when no cue is selected, so the surface does not change shape
  //          as cues are picked; otherwise the field holding that cue's words. Editing does not
  //          touch the document: Save is what writes the event. Focus is NOT taken here —
  //          `autofocus` fires on the field's first mount and this field is mounted disabled, so the
  //          cursor is placed by [_focusWords] after the frame that enables it.
  // KEYWORDS: words-field, keyboard-allowed, no-write-until-save, disabled-state, focus-by-hand
  Widget _buildWordsField(TextCue? selected) {
    return TextField(
      key: const ValueKey<String>('text-cue-field'),
      controller: _words,
      focusNode: _wordsFocus,
      enabled: selected != null,
      textInputAction: TextInputAction.done,
      onSubmitted: (String _) => _saveWords(),
      style: const TextStyle(color: sheetOnPanelColor),
      decoration: const InputDecoration(
        labelText: 'The words',
        helperText: 'For example: To Coda · D.C. al Fine · Solo · Vamp · 4×',
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  // PURPOSE: Caption one group of controls, so adding words and changing an existing cue are told
  //          apart at a glance rather than by reading every label.
  // INPUTS: caption — the group's short name. children — its buttons.
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
