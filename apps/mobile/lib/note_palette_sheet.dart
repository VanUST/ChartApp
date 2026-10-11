// PURPOSE: Offer the notes a musician can write on the beat they have selected, and make the one
//          they choose the edit. It is the surface half of the melodic writer: `EditSession` decides
//          what an edit means and this file decides where the buttons go and what a tap does.
// INPUTS: The session being edited, the bar and beat to edit, the key the chart is WRITTEN in — the
//         palette writes the written document, so it spells pitches in the written key — and a
//         callback the sheet calls after every applied edit.
// OUTPUTS: A modal bottom sheet that leaves the sheet open across edits, so a phrase is a run of
//          taps rather than a run of reopenings, and a `onChanged` callback per edit so the page
//          behind it is rebuilt. Nothing here mutates a `Song`: the only way a choice reaches the
//          document is `EditSession.insertNote` / `updateNote` / `setNoteTie` / `deleteNoteAt`.
// KEYWORDS: note-palette, melody, bottom-sheet, degree-grid, accidental, duration, tie, stacked,
//           one-hand, d16, d23, editing
//
// WHY THIS IS A PALETTE OF SCALE DEGREES AND NOT A PIANO KEYBOARD.
//
// A piano is the right picture of pitch and the wrong instrument here. The owner's requirement is
// notation, and notation names a note by its LETTER AND ALTERATION, not by a key on a keyboard: an
// E-flat and a D-sharp are one key and two notes, and a chromatic keyboard would have to guess which
// the musician meant — a guess that lands in the saved file and in the transposition, not only on
// the screen. A full keyboard is also 30-odd targets per octave, which does not fit the width of a
// phone or of a tablet held in one hand.
//
// The palette therefore offers what a melody is actually made of: SEVEN DEGREES of the written key,
// named with the key's own spelling (so in E-flat major the third button of the row reads "G" and
// the seventh reads "D", and neither reads "Eb" or "D#"), one octave at a time, plus one row of
// ALTERATIONS for the chromatic notes. That is twelve wide targets per octave rather than thirty,
// every one of them a note a musician would say out loud, and the spelling is a fact about the
// button rather than a choice the app makes for them.
//
// WHY THE DURATION AND THE ALTERATION ARE STICKY AND THE SHEET STAYS OPEN.
//
// D2 asks for sticky parameters, and the same argument the chord palette makes applies with more
// force to a melody: a musician writing an eighth-note line picks "Eighth" once and then taps
// seven pitches, and a sheet that closed after each would charge a reopen per note.
//
// HOW SEVERAL NOTES ON ONE BEAT AND HOW THE TIE ARE REACHED.
//
// The beat's notes are listed as rows above the grid, and the row that an edit will change is the
// SELECTED one; there is exactly one selected row, so one pitch tap always means one note. Tapping
// a row selects it and the grid then EDITS that note instead of inserting another — which is how a
// wrong pitch on the second voice of a chord is corrected without deleting it first. The row that
// adds a third note is the "New note" button, which clears the selection and makes the next pitch
// tap an INSERTION; the reducer puts the new note at the front of the cell and pushes the others
// up, so nothing a musician already wrote moves out from under them. The tie is a single action on
// the selected note (`BeatNote.tiedToNext` lives on the earlier note alone), and it is offered as
// the word for the state that a tap produces rather than as a toggle, because a tie's direction is
// the one thing about it a musician cannot see from the button.
//
// WHAT A MUSICIAN CANNOT DO WITH THIS SURFACE, stated rather than left to be discovered: there is no
// drag to move a note to another beat (which is a delete and an insert, not a move), no dotted or
// tuplet value, no rest, no cross-bar tie, and no way to reach a second voice of the same pitch by
// pointing at the staff itself — the second note of a beat is reached here, in the list, because two
// noteheads at one address are one point on the page.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'note_value_label.dart';
import 'sheet_surface.dart';

// PURPOSE: Open the note palette for one beat and resolve when the musician is finished. Like the
//          chord palette, the sheet appends its edits as choices are made, so its result is not the
//          note but nothing: by the time it closes the document has already changed.
// INPUTS: context — where to open the sheet. session — the document being edited. sectionId,
//         barIndex and beat — the address of the beat, in the model's own zero-based numbering.
//         writtenKey — the key the document is WRITTEN in, which is the key a note's pitch is
//         spelled in. onChanged — called after every applied edit so the caller can rebuild.
// OUTPUTS: A future that completes when the sheet is dismissed, whether anything was edited or not.
//          An address that names no bar — a form edit made after the tap — opens nothing and
//          completes at once, because there is nothing to edit and an empty sheet would be a lie
//          about what is selectable.
// KEYWORDS: show, bottom-sheet, session-edit, written-key, callback, guard
/// Opens the note palette for one beat.
Future<void> showNotePalette(
  BuildContext context, {
  required EditSession session,
  required String sectionId,
  required int barIndex,
  required int beat,
  required Key writtenKey,
  VoidCallback? onChanged,
}) async {
  if (session.song.barAt(sectionId, barIndex) == null) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: sheetPanelColor,
    isScrollControlled: true,
    builder: (BuildContext context) => NotePaletteSheet(
      session: session,
      sectionId: sectionId,
      barIndex: barIndex,
      beat: beat,
      writtenKey: writtenKey,
      onChanged: onChanged,
    ),
  );
}

/// The palette itself: a duration row, an octave row, a degree grid, an alteration row and the list
/// of notes the beat already carries.
class NotePaletteSheet extends StatefulWidget {
  /// Creates a note palette over one beat of [session].
  const NotePaletteSheet({
    super.key,
    required this.session,
    required this.sectionId,
    required this.barIndex,
    required this.beat,
    required this.writtenKey,
    this.onChanged,
  });

  /// The document being edited.
  final EditSession session;

  /// The section the edited bar belongs to.
  final String sectionId;

  /// The bar's index inside its section.
  final int barIndex;

  /// The beat's index inside its bar.
  final int beat;

  /// The key the document is written in, which the degree grid is spelled in.
  final Key writtenKey;

  /// Called after every applied edit.
  final VoidCallback? onChanged;

  @override
  State<NotePaletteSheet> createState() => _NotePaletteSheetState();
}

/// The sheet's state: the sticky duration and alteration, the octave being shown, and which note of
/// the beat is being edited.
class _NotePaletteSheetState extends State<NotePaletteSheet> {
  /// The duration this musician used last, remembered ACROSS the sheets a bar is written with.
  ///
  /// Owner decision D28 names choosing a duration per note as the cost. A duration that is sticky
  /// only while one sheet is open makes the musician re-choose it at the next beat; one that is
  /// sticky across openings is chosen once for a RUN of notes, which is how a line is actually
  /// written. It lives on the State's class rather than on the widget because the widget is built
  /// fresh for every opening — that is the point — and it survives a save and a reopen only as far
  /// as the running application goes, which is the right lifetime for a habit and not for data.
  static NoteBase _lastBase = NoteBase.quarter;

  /// The duration every insertion currently uses.
  ///
  /// A quarter, because it is the value a melody is most often written in and the value the bar's
  /// own cell division already assumes; after the first choice the musician's own last value is used
  /// instead.
  NoteBase _base = _lastBase;

  /// The alteration every pitch tap applies, in semitones. Zero is the key's own spelling.
  int _alter = 0;

  /// The octave the degree grid is showing.
  ///
  /// Seeded from the notes already on the beat when there are any, so a second voice of a chord is
  /// offered in the register the first one is written in, and four otherwise.
  late int _octave = _seedOctave();

  /// The `(beat, step)` of the note an edit acts on, or null when the next pitch tap inserts a new
  /// one. Deliberately an ADDRESS and not a copy of the note: the value is read back from the
  /// session on every build, so an undo made while the sheet is open is reflected rather than
  /// showing the note as it was when the row was tapped.
  int? _editingStep;

  @override
  void initState() {
    super.initState();
    // The last note of the beat is the one a musician just wrote, so it is the one they are most
    // likely to be looking at; the first is the fallback when the address cannot be reread.
    final List<BeatNote> existing = _notesHere();
    if (existing.isNotEmpty) {
      _editingStep = existing.last.step;
      _base = existing.last.value.base;
    }
  }

  // PURPOSE: Read the beat's notes back from the session, which is what makes every control in this
  //          sheet show the document as it stands rather than as it stood when the sheet opened.
  // INPUTS: None.
  // OUTPUTS: The notes at this beat, ascending by step. Empty when the beat holds none.
  // KEYWORDS: read-back, live-state, undo-aware, session-query
  List<BeatNote> _notesHere() => widget.session.existingNotesAt(
    sectionId: widget.sectionId,
    barIndex: widget.barIndex,
    beat: widget.beat,
  );

  // PURPOSE: Choose the octave the grid opens in, from the bar rather than from a constant, so that
  //          writing a second voice does not start an octave away from the first.
  // INPUTS: None; reads the bar.
  // OUTPUTS: The octave of the bar's lowest note, the last note of this beat, or four when there is
  //          nothing to go by. Four is middle C's octave and sits in the middle of a treble staff,
  //          which is where a melody is written.
  // KEYWORDS: default-octave, register, seed, empty-bar-fallback
  int _seedOctave() {
    final Bar? bar = widget.session.song.barAt(
      widget.sectionId,
      widget.barIndex,
    );
    final List<BeatNote> onBeat = _notesHere();
    if (onBeat.isNotEmpty) {
      return onBeat.last.pitch.octave;
    }
    if (bar == null || bar.melody.isEmpty) {
      return 4;
    }
    int lowest = bar.melody.first.pitch.octave;
    for (final BeatNote note in bar.melody) {
      if (note.pitch.octave < lowest) {
        lowest = note.pitch.octave;
      }
    }
    return lowest;
  }

  /// The note an edit currently acts on, or null when the next pitch tap inserts one.
  BeatNote? get _selected {
    final int? step = _editingStep;
    if (step == null) {
      return null;
    }
    return widget.session.existingNoteAt(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
      step: step,
    );
  }

  // PURPOSE: Apply one pitch as an edit of the selected note, or as an insertion when nothing is
  //          selected — the sheet's only way of changing the document, and the one place the two
  //          catalogue operations are chosen between.
  // INPUTS: note — the written pitch the tap means, after the sticky alteration has been applied to
  //         the tapped degree.
  // OUTPUTS: Nothing. Inserts when no note is selected, updates when one is, and selects the note
  //          it just wrote so a following tap corrects the same note rather than adding a third.
  //          A refused edit — the address vanished, the duration no longer fits — changes nothing
  //          and reports itself in the header, which is what `_status` is for.
  // KEYWORDS: apply, insert-vs-update, sticky-alteration, sticky-duration, haptic, stay-open
  void _applyPitch(PitchedNote note) {
    final BeatNote? selected = _selected;
    if (selected == null) {
      final bool inserted = widget.session.insertNote(
        sectionId: widget.sectionId,
        barIndex: widget.barIndex,
        beat: widget.beat,
        pitch: note,
        value: NoteValue.plain(_base),
      );
      if (!inserted) {
        _reportRefusal();
        return;
      }
      HapticFeedback.selectionClick();
      final List<BeatNote> after = _notesHere();
      setState(() => _editingStep = after.isEmpty ? null : after.first.step);
      widget.onChanged?.call();
      return;
    }
    final bool updated = widget.session.updateNote(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
      step: selected.step,
      pitch: note,
    );
    if (!updated) {
      HapticFeedback.selectionClick();
    }
    setState(() {});
    widget.onChanged?.call();
  }

  // PURPOSE: Change the duration of the selected note, or of the next insertion when nothing is
  //          selected, which is why the duration row is a sticky parameter rather than an edit.
  // INPUTS: base — the value to use.
  // OUTPUTS: Nothing. The sticky value moves either way; the selected note is updated only when
  //          there is one, so tapping a duration with no note selected sets up the next tap instead
  //          of writing an edit nobody asked for.
  // KEYWORDS: duration, sticky, update-selected, undoable
  void _chooseBase(NoteBase base) {
    final BeatNote? selected = _selected;
    if (selected == null) {
      _lastBase = base;
      setState(() => _base = base);
      return;
    }
    final bool updated = widget.session.updateNote(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
      step: selected.step,
      value: NoteValue.plain(base),
    );
    if (!updated) {
      _reportRefusal();
      return;
    }
    HapticFeedback.selectionClick();
    _lastBase = base;
    setState(() => _base = base);
    widget.onChanged?.call();
  }

  // PURPOSE: Set or clear the tie on the selected note, which is the whole of how a sound is written
  //          across a beat.
  // INPUTS: None; the target state is the opposite of what the note carries.
  // OUTPUTS: Nothing. Does nothing when no note is selected, because a tie is a fact about a note
  //          and there is none to tie yet.
  // KEYWORDS: tie, toggle, selected-only, undoable
  void _toggleTie() {
    final BeatNote? selected = _selected;
    if (selected == null) {
      return;
    }
    final bool changed = widget.session.setNoteTie(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
      step: selected.step,
      tied: !selected.tiedToNext,
    );
    if (!changed) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {});
    widget.onChanged?.call();
  }

  // PURPOSE: Take the selected note off the staff, which is the catalogue's `note.delete` reached
  //          from the same sheet rather than from a mode.
  // INPUTS: None.
  // OUTPUTS: Nothing. Removes the selected note and clears the selection, so the next pitch tap
  //          inserts rather than editing a note that is no longer there.
  // KEYWORDS: delete, note-remove, same-sheet, no-mode-switch
  void _remove() {
    final BeatNote? selected = _selected;
    if (selected == null) {
      return;
    }
    final bool removed = widget.session.deleteNoteAt(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
      step: selected.step,
    );
    if (!removed) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _editingStep = null);
    widget.onChanged?.call();
  }

  // PURPOSE: Say why an edit was refused, so a tap that wrote nothing is explained rather than
  //          silently ignored — the outcome the note writer's own documentation calls the one thing
  //          an event log must make impossible.
  // INPUTS: None; the reason is read from the bar's own length against the value being written.
  // OUTPUTS: Nothing but a rebuild; the message is computed in `_statusText`.
  // KEYWORDS: refusal, feedback, duration-guard, bar-length
  void _reportRefusal() {
    setState(() => _refused = true);
  }

  /// Whether the last edit was refused, which makes the header say why.
  bool _refused = false;

  // PURPOSE: Tell the musician what state the beat is in, which is the one thing the grid cannot
  //          show: whether a tap will write a new note or change the selected one, and why a tap
  //          did nothing.
  // INPUTS: l10n — the message catalogue.
  // OUTPUTS: A sentence. The order of the three answers is deliberate: a refusal is reported before
  //          anything else, because it explains a tap the musician just made; a beat with no notes
  //          says so, because that is why tapping a pitch will INSERT; and a beat with notes reports
  //          whether one is selected.
  // KEYWORDS: status, refusal, insert-vs-edit, empty-beat, localized
  String _statusText(AppLocalizations l10n) {
    if (_refused) {
      return l10n.melodyValueTooLong;
    }
    final List<BeatNote> notes = _notesHere();
    if (notes.isEmpty) {
      return l10n.melodyBeatEmpty;
    }
    final BeatNote? selected = _selected;
    if (selected == null) {
      return l10n.melodyBeatEmpty;
    }
    return l10n.melodyNoteLine(
      selected.step + 1,
      '${selected.pitch}',
      noteBaseNotation(selected.value.base),
    );
  }

  // PURPOSE: Number the edited bar the way a musician counts, across the whole written chart, so the
  //          header names a bar the musician can find on the page and not an index that restarts at
  //          every section. The same rule the selection line and the chord palette follow.
  // INPUTS: None.
  // OUTPUTS: The bar's one-based ordinal in the written chart.
  // KEYWORDS: label, one-based, bar-ordinal, musician-numbering
  int _barOrdinal() {
    int ordinal = 0;
    for (final Section section in widget.session.song.sections) {
      if (section.id == widget.sectionId) {
        return ordinal + widget.barIndex + 1;
      }
      ordinal += section.bars.length;
    }
    return ordinal + widget.barIndex + 1;
  }

  // PURPOSE: Report whether the bar's existing notes already last longer than its meter, so the
  //          sheet can say the bar contradicts its own meter rather than letting a musician discover
  //          it by playing. The sum is exact — the model's durations are rationals precisely so that
  //          a triplet fill is not reported short by rounding.
  // INPUTS: None; reads the bar.
  // OUTPUTS: True when the sum of every note's written duration exceeds the bar's own length. False
  //          for a bar with no notes, and false for a bar that is exactly full.
  // KEYWORDS: bar-length, over-full, exact-arithmetic, meter-disagreement
  bool _barOverflows() {
    final Bar? bar = widget.session.song.barAt(
      widget.sectionId,
      widget.barIndex,
    );
    if (bar == null || bar.melody.isEmpty) {
      return false;
    }
    int numerator = 0;
    int denominator = 1;
    for (final BeatNote note in bar.melody) {
      numerator =
          numerator * note.value.wholeDenominator +
          note.value.wholeNumerator * denominator;
      denominator = denominator * note.value.wholeDenominator;
    }
    return numerator * bar.timeSignature.denominator >
        bar.timeSignature.numerator * denominator;
  }

  // PURPOSE: Build the written pitch a degree button means, by applying the sticky alteration to the
  //          key's own spelling of that degree.
  // INPUTS: degree — the scale degree's own written note, as the key spells it. octave — the octave
  //         the grid is showing.
  // OUTPUTS: A [PitchedNote] whose letter is the key's letter for the degree and whose alteration is
  //          the key's plus the sticky one, so tapping a degree in E-flat major and then "Sharp"
  //          writes the raised seventh rather than respelling the key's own note. The letter is
  //          deliberately kept: an alteration moves the sounding pitch and leaves the letter, which
  //          is what makes the sharp of a degree a degree raised rather than a different degree.
  // KEYWORDS: pitch-construction, degree-plus-alteration, letter-kept, key-spelling
  PitchedNote _pitchFor(WrittenNote degree, int octave) => PitchedNote(
    note: WrittenNote(degree.letter, degree.alter + _alter),
    octave: octave,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<BeatNote> notes = _notesHere();
    final bool overflow = _barOverflows();
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(l10n),
              const SizedBox(height: 6),
              Text(
                _statusText(l10n),
                key: const ValueKey<String>('note-palette-status'),
                style: const TextStyle(color: sheetMutedColor, fontSize: 13),
              ),
              if (overflow)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.melodyValueOverflow,
                    key: const ValueKey<String>('note-palette-overflow'),
                    style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              _buildNoteList(l10n, notes),
              const SizedBox(height: 10),
              _buildDurationRow(l10n),
              const SizedBox(height: 8),
              _buildOctaveRow(l10n),
              const SizedBox(height: 8),
              _buildDegreeGrid(l10n),
              const SizedBox(height: 8),
              _buildAlterRow(l10n),
              const SizedBox(height: 8),
              _buildActions(l10n),
              const SizedBox(height: 4),
              Text(
                l10n.melodyTapStaffHint,
                style: const TextStyle(color: sheetMutedColor, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // PURPOSE: Draw the sheet's header: the position, the key the buttons are spelled in, and the
  //          control that closes the sheet.
  // INPUTS: l10n — the catalogue.
  // OUTPUTS: The header row.
  // KEYWORDS: header, position-label, written-key, done, localized
  Widget _buildHeader(AppLocalizations l10n) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              // The chord palette's own sentence, reused rather than duplicated: it names a bar and a
              // cell the way a musician counts, and it already says so in both languages. A second
              // string for the same two numbers would be a second place for them to disagree.
              l10n.palettePosition(_barOrdinal(), widget.beat + 1),
              key: const ValueKey<String>('note-palette-position'),
              style: const TextStyle(
                color: sheetOnPanelColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            // The written key is named because it is a fact about what a tap will WRITE: the chart on
            // screen may be shown in another key, and a note is written into the document. The
            // catalogue supplies the SENTENCE and the name inside it is NOTATION — `C major`, never
            // `C мажор`, which is owner decision A53 — so the key is rendered by `keyNotation` rather
            // than by the viewer's `localizedKeyName`. A key name inside a translated sentence is
            // still a key name.
            Text(
              l10n.paletteChordsIn(keyNotation(widget.writtenKey)),
              style: const TextStyle(color: sheetMutedColor, fontSize: 12),
            ),
          ],
        ),
      ),
      TextButton(
        key: const ValueKey<String>('note-palette-done'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.done, style: const TextStyle(color: sheetAccentColor)),
      ),
    ],
  );

  // PURPOSE: List the notes the beat carries and offer the row that adds another, which is how
  //          several notes on one beat are reached and how the one an edit acts on is chosen.
  // INPUTS: l10n — the catalogue. notes — the beat's notes, ascending by step.
  // OUTPUTS: One row per note plus a "New note" row. The selected row is filled with the accent, so
  //          "this is the note the grid will change" is visible without reading a label, and the
  //          rows exist even when the beat is empty — an empty list would leave a musician with no
  //          way to say "insert rather than edit".
  // KEYWORDS: note-list, selection, stacked-notes, new-note, one-based-step, localized
  Widget _buildNoteList(AppLocalizations l10n, List<BeatNote> notes) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _sectionCaption(l10n.melodyGroup),
      const SizedBox(height: 4),
      for (final BeatNote note in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: note.step == _editingStep
                ? sheetSelectedCellColor
                : sheetCellColor,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey<String>('note-palette-note-${note.step}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _refused = false;
                _editingStep = note.step;
                _base = note.value.base;
                _lastBase = note.value.base;
                _octave = note.pitch.octave;
                _alter = note.pitch.note.alter;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.melodyNoteLine(
                          note.step + 1,
                          '${note.pitch}',
                          noteBaseNotation(note.value.base),
                        ),
                        style: const TextStyle(
                          color: sheetOnPanelColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      note.tiedToNext ? l10n.melodyTie : '',
                      style: const TextStyle(
                        color: sheetAccentColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      Material(
        color: _editingStep == null ? sheetSelectedCellColor : sheetCellColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const ValueKey<String>('note-palette-new'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _refused = false;
            _editingStep = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              l10n.melodyNewNote,
              style: TextStyle(
                color: _editingStep == null
                    ? sheetOnPanelColor
                    : sheetAccentColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  // PURPOSE: Draw the sticky duration row, one chip per value the palette offers.
  // INPUTS: l10n — the catalogue.
  // OUTPUTS: A wrapping row of chips whose chosen member is filled with the accent. Each chip is
  //          labelled with the fraction of a bar the value is worth and the notation's own name for
  //          it (`1/4 · Quarter`), which is what lets a duration be read at a glance instead of
  //          translated from a word before it can be chosen — see `noteBaseChipLabel`.
  // KEYWORDS: duration-row, chips, sticky-state, accent, localized, fraction-and-name
  Widget _buildDurationRow(AppLocalizations l10n) {
    const List<NoteBase> offered = <NoteBase>[
      NoteBase.whole,
      NoteBase.half,
      NoteBase.quarter,
      NoteBase.eighth,
      NoteBase.sixteenth,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _sectionCaption(l10n.melodyDuration),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final NoteBase base in offered)
              _PaletteChip(
                widgetKey: 'note-palette-base-${base.name}',
                label: noteBaseChipLabel(base),
                selected: base == _base,
                onTap: () => _chooseBase(base),
              ),
          ],
        ),
      ],
    );
  }

  // PURPOSE: Draw the octave row: the register the degree grid is spelled in, with one control in
  //          each direction.
  // INPUTS: l10n — the catalogue, for the two tooltips.
  // OUTPUTS: A row holding the octave's own notation between two buttons. The range is capped at the
  //          two octaves either side of four because the engraved staff clamps a note beyond five
  //          ledger lines to the last position it can write, and offering a register the engraver
  //          will silently move a note out of would be offering a button whose result is not on it.
  //          The label is NOTATION and stays Latin: `Octave 4` is how a scientific pitch notation is
  //          read in every language, which is owner decision A53's rule applied to a register.
  // KEYWORDS: octave, register, stepper, engraving-limit, notation-latin
  Widget _buildOctaveRow(AppLocalizations l10n) => Row(
    children: <Widget>[
      Text(
        'Octave $_octave',
        key: const ValueKey<String>('note-palette-octave'),
        style: const TextStyle(color: sheetOnPanelColor, fontSize: 15),
      ),
      const Spacer(),
      IconButton(
        key: const ValueKey<String>('note-palette-octave-down'),
        tooltip: l10n.melodyOctaveLower,
        icon: const Icon(Icons.keyboard_arrow_down),
        color: sheetOnPanelColor,
        onPressed: _octave <= 2 ? null : () => setState(() => _octave--),
      ),
      IconButton(
        key: const ValueKey<String>('note-palette-octave-up'),
        tooltip: l10n.melodyOctaveHigher,
        icon: const Icon(Icons.keyboard_arrow_up),
        color: sheetOnPanelColor,
        onPressed: _octave >= 6 ? null : () => setState(() => _octave++),
      ),
    ],
  );

  // PURPOSE: Draw the seven degrees of the written key, each labelled with the pitch it writes, so a
  //          diatonic melody is one tap per note and no button ever means an enharmonic pitch the
  //          key would not write that way.
  // INPUTS: l10n — the catalogue, for the accidental names the buttons' own labels would need.
  // OUTPUTS: A seven-column grid. Seven columns is the width of the scale and keeps a target wider
  //          than the 48 logical pixels a thumb needs on a phone-width sheet, so the whole row is
  //          reachable one-handed.
  // KEYWORDS: degree-grid, seven-columns, key-spelling, touch-target, one-tap-per-note
  Widget _buildDegreeGrid(AppLocalizations l10n) {
    const SpellingTable table = SpellingTable();
    final List<WrittenNote> degrees = table.scaleOf(widget.writtenKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _sectionCaption(l10n.melodyPitch),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            for (final WrittenNote degree in degrees)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _DegreeButton(
                    widgetKey: 'note-palette-degree-${degree.letter.name}',
                    label: '${_pitchFor(degree, _octave)}',
                    selected: _selected?.pitch == _pitchFor(degree, _octave),
                    onTap: () => _applyPitch(_pitchFor(degree, _octave)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // PURPOSE: Draw the alteration row: the five ways a pitch outside the key is written, as a mode
  //          that the next pitch tap applies.
  // INPUTS: l10n — the catalogue, for the section caption only.
  // OUTPUTS: A wrapping row of chips, the chosen one filled with the accent. The chips carry the
  //          MARKS a musician reads — `♮ ♯ ♭ ♯♯ ♭♭` — and not their names, which is the same decision
  //          the pitch buttons follow: this surface exists to show what will be WRITTEN, and the mark
  //          is what gets written. The names are not translated either, so a catalogue entry for them
  //          would be one whose two values must be identical; they are not translated here at all.
  // KEYWORDS: alteration-row, chromatic, sticky-mode, accidental-mark, notation-latin
  Widget _buildAlterRow(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _sectionCaption(l10n.melodyAlteration),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final int alteration in <int>[-2, -1, 0, 1, 2])
            _PaletteChip(
              widgetKey: 'note-palette-alter-$alteration',
              label: accidentMark(alteration),
              selected: _alter == alteration,
              onTap: () => setState(() => _alter = alteration),
            ),
        ],
      ),
    ],
  );

  // PURPOSE: Offer the two operations that act on the selected note and have no button on the grid:
  //          tying it forward, and removing it.
  // INPUTS: l10n — the catalogue.
  // OUTPUTS: A row with the tie action and the destructive removal, both disabled while no note is
  //          selected. The tie's label names the state a tap produces — "Tie" for an untied note,
  //          "Untie" for a tied one — because a musician cannot see from the button which way a tie
  //          points.
  // KEYWORDS: tie-action, remove, destructive, disabled-when-unselected, localized
  Widget _buildActions(AppLocalizations l10n) {
    final BeatNote? selected = _selected;
    return Row(
      children: <Widget>[
        Expanded(
          child: TextButton.icon(
            key: const ValueKey<String>('note-palette-tie'),
            onPressed: selected == null ? null : _toggleTie,
            icon: Icon(
              (selected?.tiedToNext ?? false) ? Icons.link_off : Icons.link,
              size: 18,
            ),
            label: Text(
              (selected?.tiedToNext ?? false)
                  ? l10n.melodyUntie
                  : l10n.melodyTie,
            ),
            style: TextButton.styleFrom(
              foregroundColor: sheetAccentColor,
              disabledForegroundColor: sheetMutedColor,
            ),
          ),
        ),
        TextButton.icon(
          key: const ValueKey<String>('note-palette-remove'),
          onPressed: selected == null ? null : _remove,
          icon: const Icon(Icons.backspace_outlined, size: 18),
          label: Text(l10n.melodyRemove),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF8A80),
            disabledForegroundColor: sheetMutedColor,
          ),
        ),
      ],
    );
  }

  // PURPOSE: Label a group of controls, so the sheet reads as named sections rather than as a pile
  //          of buttons.
  // INPUTS: text — the caption, from the catalogue.
  // OUTPUTS: A small uppercase-style caption.
  // KEYWORDS: section-caption, grouping, sheet-style
  Widget _sectionCaption(String text) => Text(
    text,
    style: const TextStyle(
      color: sheetMutedColor,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );
}

/// One chip in a sticky row.
class _PaletteChip extends StatelessWidget {
  /// Creates a chip with the given [label] and [widgetKey], marked [selected].
  const _PaletteChip({
    required this.widgetKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// The widget key a driver test looks the chip up by.
  final String widgetKey;

  /// The chip's text.
  final String label;

  /// Whether this chip is the sticky choice.
  final bool selected;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? sheetAccentColor : sheetCellColor,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: ValueKey<String>(widgetKey),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? sheetPanelColor : sheetOnPanelColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// One pitch button of the degree grid.
class _DegreeButton extends StatelessWidget {
  /// Creates a button writing [label], marked [selected].
  const _DegreeButton({
    required this.widgetKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// The widget key a driver test looks the button up by.
  final String widgetKey;

  /// The pitch this button writes, as it will be engraved.
  final String label;

  /// Whether the selected note already carries exactly this pitch.
  final bool selected;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? sheetSelectedCellColor : sheetCellColor,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      key: ValueKey<String>(widgetKey),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          label,
          style: const TextStyle(
            color: sheetOnPanelColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
