// PURPOSE: Make the song's own facts — its title, its composer, the style it is played in and its
//          tempo — editable through the operation log, from the places a musician already reads
//          them: the title above the chart and the TEMPO and STYLE fields of the scene bar. It is
//          the surface the catalogue's `song.update` event exists for; before it, those facts were
//          text a musician could read and not change.
// INPUTS: The session being edited, which field the reader tapped (so the sheet opens with that one
//         focused), and a callback the sheet calls after an applied edit.
// OUTPUTS: A modal sheet holding all four fields, which applies ONE `song.update` carrying the
//          whole metadata on both sides. Closing without saving changes nothing, and saving when
//          nothing changed appends nothing.
// KEYWORDS: song-info, metadata, title, composer, style, tempo, scene-bar, op-log, song-update,
//           one-event-per-visit, keyboard
//
// WHY ALL FOUR FIELDS IN ONE SHEET, INCLUDING WHEN THE READER TAPPED ONLY THE TEMPO.
//
// The event that records this edit carries all four values on both sides, because its inverse has
// to name the values it restores and a partial payload could not. So the sheet collects all four
// from the document and writes them back together, which also means a musician who fixes the tempo
// and notices the title is misspelled fixes both in one visit and gets one undo for it. Opening
// with the tapped field focused is what makes "editable at the point where it is shown" true: the
// reader taps BPM and the cursor is in the tempo.
//
// WHY THE TEMPO HAS BUTTONS AND NOT ONLY A FIELD.
//
// D2 budgets a musician's taps and a phone's keyboard covers half the screen. Ten beats per minute
// either way is the interval a metronome is nudged by, so the common adjustment is one tap on a
// button that is already under the thumb, and the field is there for a real number.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'sheet_surface.dart';

/// The colour of a destructive action's label, matching the form sheet.
const Color _dangerColor = Color(0xFFFF8A80);

/// Which of the song's four fields a reader tapped, so the sheet can open with it focused.
enum SongMetadataField {
  /// The tune's name.
  title,

  /// Who wrote it.
  composer,

  /// The style or feel it is played in.
  style,

  /// The tempo in beats per minute.
  tempo,
}

// PURPOSE: Open the song-info sheet for one song and resolve when the musician is finished.
// INPUTS: context — where to open the sheet. session — the document being edited. focus — the field
//         the reader tapped, which the sheet opens with the cursor in. onChanged — called after an
//         applied edit so the caller can rebuild; the sheet does not know how the caller draws its
//         page.
// OUTPUTS: A future that completes when the sheet is dismissed. Nothing else: the edit is applied
//          as it is saved, through [EditSession.updateSong], so a caller that wanted the values
//          would be asking a second time for what the session already holds.
// KEYWORDS: show, bottom-sheet, session-edit, callback, focus, guard
/// Opens the sheet that edits the song's title, composer, style and tempo.
Future<void> showSongInfo(
  BuildContext context, {
  required EditSession session,
  SongMetadataField focus = SongMetadataField.title,
  VoidCallback? onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: sheetPanelColor,
  isScrollControlled: true,
  builder: (BuildContext context) =>
      SongInfoSheet(session: session, focus: focus, onChanged: onChanged),
);

/// The sheet itself: four fields, a tempo stepper and one Save.
class SongInfoSheet extends StatefulWidget {
  /// Creates a sheet over [session], opening with [focus] focused.
  const SongInfoSheet({
    super.key,
    required this.session,
    this.focus = SongMetadataField.title,
    this.onChanged,
  });

  /// The document being edited.
  final EditSession session;

  /// The field the cursor starts in.
  final SongMetadataField focus;

  /// Called after an applied edit.
  final VoidCallback? onChanged;

  @override
  State<SongInfoSheet> createState() => _SongInfoSheetState();
}

/// The sheet's state: the four drafts, the tempo stepper's arithmetic and the last outcome.
class _SongInfoSheetState extends State<SongInfoSheet> {
  /// The last tempo that could be read, used only when the field cannot be.
  ///
  /// A half-typed or empty field is not a number, and a stepper that treated it as one would turn a
  /// forgotten keystroke into a tempo of zero. So the stepper reads the FIELD first and falls back
  /// here, which is why this starts as the tempo the song already had.
  late int _tempo = widget.session.song.tempo;

  /// Why the last save attempt did nothing, or null when there has not been one.
  ///
  /// It is cleared as soon as a field is touched, because a reason that outlives the mistake it
  /// describes reads as a reason for the edit being made now.
  String? _outcome;

  late final TextEditingController _title = TextEditingController(
    text: widget.session.song.title,
  );
  late final TextEditingController _composer = TextEditingController(
    text: widget.session.song.composer,
  );
  late final TextEditingController _style = TextEditingController(
    text: widget.session.song.style,
  );
  late final TextEditingController _tempoText = TextEditingController(
    text: '${widget.session.song.tempo}',
  );

  /// Whether the tempo field holds something that can be a tempo, or null while it does.
  ///
  /// Null means the text cannot be read as a whole number of beats per minute, which is reported
  /// beside the field rather than silently becoming zero: a musician who typed "12O" with a letter
  /// must be told, because saving a tempo of 0 would unset it instead.
  bool get _tempoReadable => int.tryParse(_tempoText.text.trim()) != null;

  @override
  void dispose() {
    _title.dispose();
    _composer.dispose();
    _style.dispose();
    _tempoText.dispose();
    super.dispose();
  }

  // PURPOSE: Nudge the tempo by whole beats per minute and show the result in the field.
  // INPUTS: delta — the change, negative to slow down.
  // OUTPUTS: Nothing. The step starts from WHAT IS IN THE FIELD when the field can be read, so
  //          typing 140 and pressing "+1" gives 141 rather than the old value plus one; when it
  //          cannot be read — empty, or half-typed — the step falls back to the last readable
  //          value, so a stray keystroke does not turn "+10" into ten. The tempo never goes below
  //          zero: zero is the model's value for "the chart sets none", and a negative one is not a
  //          tempo anything else can read.
  // KEYWORDS: tempo-stepper, metronome-interval, field-first, floor-at-zero, field-mirror
  void _stepTempo(int delta) {
    final int current = int.tryParse(_tempoText.text.trim()) ?? _tempo;
    setState(() {
      _tempo = current + delta < 0 ? 0 : current + delta;
      _tempoText.text = '$_tempo';
      _outcome = null;
    });
    HapticFeedback.selectionClick();
  }

  // PURPOSE: Apply the four drafts through the session as one event, or say why not.
  // INPUTS: None; reads the four fields.
  // OUTPUTS: Nothing. On success the sheet closes, because a form that stays open after being
  //          saved is a form a musician cannot tell has been saved. When the tempo cannot be read,
  //          and when every field already holds what the song holds, the sheet stays open and the
  //          footer says which of the two it was — rather than appending an event whose two sides
  //          are equal and offering an undo for an edit nobody made.
  // KEYWORDS: apply, single-event, validation, nothing-changed, close-on-success
  void _save() {
    final int? tempo = int.tryParse(_tempoText.text.trim());
    if (tempo == null) {
      setState(
        () => _outcome = 'A tempo is a whole number of beats per minute.',
      );
      debugPrint(
        'viewer.song.info.refused tempo_text="${_tempoText.text}" '
        'reason=not-a-number',
      );
      return;
    }
    final bool applied = widget.session.updateSong(
      title: _title.text,
      composer: _composer.text,
      style: _style.text,
      tempo: tempo,
    );
    debugPrint(
      'viewer.song.info.applied=$applied title_chars=${_title.text.length} '
      'composer_chars=${_composer.text.length} style_chars=${_style.text.length} '
      'tempo=$tempo seq=${widget.session.seq} '
      'undo_depth=${widget.session.undoDepth}',
    );
    if (!applied) {
      setState(
        () => _outcome = 'Nothing changed, so nothing was written to the log.',
      );
      return;
    }
    widget.onChanged?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Song song = widget.session.song;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(song),
              const SizedBox(height: 10),
              _field(
                field: SongMetadataField.title,
                controller: _title,
                label: 'Title',
                hint: 'The name a musician reads at the top of the chart.',
              ),
              _field(
                field: SongMetadataField.composer,
                controller: _composer,
                label: 'Composer',
                hint: 'As written; the order is whatever the format stores.',
              ),
              _field(
                field: SongMetadataField.style,
                controller: _style,
                label: 'Style',
                hint: 'Free text, such as Medium Swing or Ballad.',
              ),
              _buildTempoField(),
              const SizedBox(height: 4),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // PURPOSE: Say whose facts these are, so the sheet cannot be mistaken for a page setting.
  // INPUTS: song — the song as it stands.
  // OUTPUTS: The header row with the tune's current name and the control that closes the sheet.
  // KEYWORDS: header, identity, done
  Widget _buildHeader(Song song) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Song info',
              key: ValueKey<String>('song-info-heading'),
              style: TextStyle(
                color: sheetOnPanelColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              song.title.isEmpty ? 'Untitled' : song.title,
              style: const TextStyle(color: sheetMutedColor, fontSize: 12),
            ),
          ],
        ),
      ),
      TextButton(
        key: const ValueKey<String>('song-info-done'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done', style: TextStyle(color: sheetAccentColor)),
      ),
    ],
  );

  // PURPOSE: One labelled text field of the metadata.
  // INPUTS: field — which of the four this is, used for the key and for the focus. controller —
  //         its text. label and hint — what it is called and what it is for.
  // OUTPUTS: The field, with the cursor already in it when it is the one the reader tapped. Typing
  //          in it clears the footer's last outcome, because a reason that outlives the mistake it
  //          describes reads as a reason for the edit being made now.
  // KEYWORDS: text-field, focus, autofocus, labelled, outcome-cleared
  Widget _field({
    required SongMetadataField field,
    required TextEditingController controller,
    required String label,
    required String hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: ValueKey<String>('song-info-${field.name}'),
      controller: controller,
      autofocus: widget.focus == field,
      textInputAction: TextInputAction.next,
      onChanged: (String _) => setState(() => _outcome = null),
      style: const TextStyle(color: sheetOnPanelColor, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        labelStyle: const TextStyle(color: sheetMutedColor),
        helperStyle: const TextStyle(color: sheetMutedColor, fontSize: 11),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: sheetMutedColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: sheetAccentColor, width: 2),
        ),
      ),
    ),
  );

  // PURPOSE: The tempo field and the stepper beside it, so the common adjustment is a tap and the
  //          exact number is still typeable.
  // INPUTS: None; reads [_tempoText] and [_tempo].
  // OUTPUTS: The field with its four buttons, an error line when the text is not a number, and a
  //          line saying what zero means, because "no tempo" is not an obvious value for an empty
  //          speed.
  // KEYWORDS: tempo-field, stepper, validation, zero-means-unset
  Widget _buildTempoField() {
    final bool readable = _tempoReadable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('song-info-tempo'),
            controller: _tempoText,
            autofocus: widget.focus == SongMetadataField.tempo,
            keyboardType: TextInputType.number,
            onChanged: (String _) => setState(() => _outcome = null),
            style: const TextStyle(color: sheetOnPanelColor, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Tempo (BPM)',
              helperText: readable
                  ? '0 means this chart sets no tempo.'
                  : 'Whole beats per minute, or 0 for none.',
              errorText: readable ? null : 'A tempo is a whole number.',
              labelStyle: const TextStyle(color: sheetMutedColor),
              helperStyle: const TextStyle(
                color: sheetMutedColor,
                fontSize: 11,
              ),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: sheetMutedColor),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: sheetAccentColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _StepButton(
                buttonKey: 'song-info-tempo-minus-10',
                label: '−10',
                onTap: () => _stepTempo(-10),
              ),
              _StepButton(
                buttonKey: 'song-info-tempo-minus-1',
                label: '−1',
                onTap: () => _stepTempo(-1),
              ),
              _StepButton(
                buttonKey: 'song-info-tempo-plus-1',
                label: '+1',
                onTap: () => _stepTempo(1),
              ),
              _StepButton(
                buttonKey: 'song-info-tempo-plus-10',
                label: '+10',
                onTap: () => _stepTempo(10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PURPOSE: Say what saving will do, why the last attempt did nothing, or give the one control that
  //          saves.
  // INPUTS: None; reads [_outcome] and [_tempoReadable].
  // OUTPUTS: A one-line status and the Save button. The last outcome wins when there is one, in the
  //          accent colour because it is information rather than a fault; otherwise the reminder
  //          that the four facts are one edit, or — when the tempo cannot be read — the reason, in
  //          the removal colour, because that line is a refusal. The button is disabled in exactly
  //          that last case.
  // KEYWORDS: footer, save, disabled, status, outcome, honest-refusal
  Widget _buildFooter() => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          _outcome ??
              (_tempoReadable
                  ? 'One edit: the four facts above are written together.'
                  : 'Fix the tempo before saving.'),
          key: const ValueKey<String>('song-info-status'),
          style: TextStyle(
            color: _outcome != null
                ? sheetAccentColor
                : (_tempoReadable ? sheetMutedColor : _dangerColor),
            fontSize: 12,
          ),
        ),
      ),
      FilledButton.icon(
        key: const ValueKey<String>('song-info-save'),
        onPressed: _tempoReadable ? _save : null,
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Save'),
      ),
    ],
  );
}

/// One button of the tempo stepper.
class _StepButton extends StatelessWidget {
  /// Creates a button labelled [label] that calls [onTap], carrying [buttonKey] for tests.
  const _StepButton({
    required this.buttonKey,
    required this.label,
    required this.onTap,
  });

  /// The widget key the tests and the driving tools find this button by.
  final String buttonKey;

  /// The change it makes, written on the button.
  final String label;

  /// What a press does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: sheetCellColor,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: ValueKey<String>(buttonKey),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: sheetOnPanelColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
