// PURPOSE: Offer the chords a musician can write in the cell they have selected, and make the one
//          they pick the edit. It is the sheet half of the edit loop: `chord_palette.dart` decides
//          WHICH chords are offered and this file decides where the buttons go and what a tap does.
// INPUTS: The session being edited, the bar and cell to edit, the key the chord will be PREVIEWED
//         in — normally the key the chart is shown in, which is not always the key it is written in
//         — and a callback the sheet calls after every applied edit.
// OUTPUTS: A modal bottom sheet. Applying a chord appends one event through the session but leaves
//         the sheet open, so a bar of eight chords is eight taps rather than sixteen; [Done] or a
//         tap on the scrim closes it. Nothing here mutates a song: the only way a choice reaches
//         the document is `EditSession.applyChordToCell`, which goes through the operation log.
// KEYWORDS: chord-palette, bottom-sheet, one-hand, sticky-quality, two-taps, d2, d11, editing
//
// WHY A BOTTOM SHEET AND NOT A DIALOG.
//
// Owner decision D11 puts the phone's palette in a bottom dock, and D2 budgets the interaction. A
// modal sheet slides up under the thumb, which is the only part of a phone a hand holding it can
// reach; the twelve-key grid the viewer already uses is a dialog, and at the top of a 6-inch screen
// it is the one control a musician has to shift their grip for. The sheet is bounded to the same
// width as the chart's own pane so that on a tablet it does not stretch a twelve-cell grid across a
// hand's width of glass.
//
// WHY THE QUALITY IS STICKY AND THE SHEET STAYS OPEN.
//
// D2 asks for "sticky parameters": a choice made for one cell staying made for the next. The
// quality is the sticky half — a musician writing a minor 7th bar writes one quality several times
// — so it is remembered in this widget's state and only the root has to be tapped per cell. Staying
// open is what makes that worth anything: an apply-and-close sheet would charge a reopen for every
// cell and turn two taps into four, which is the opposite of the budget D2 set.
//
// WHY THE PREVIEW IS RENDERED IN THE SHOWN KEY.
//
// The chord is stored as a SOUNDING root, and the page renders it by spelling that root in whatever
// key the chart is shown in. So the preview has to spell it the same way or it would show the
// musician one chord and draw another. The `shownKey` argument exists for exactly that, and the
// `semitoneShift` argument carries the interval the viewer is showing the chart at so the preview
// moves with it.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
// `localizedKeyName` is imported rather than re-derived here: the key badge, the song list, the
// twelve-key grid and this sheet all have to name the same key with the same words, exactly as
// `repeatSummary` is the one place the repeat summary is worded.
import 'scene_bar.dart';
import 'sheet_surface.dart';

// PURPOSE: Open the chord palette for one cell and resolve when the musician is finished. The sheet
//          edits the session as choices are made, so its result is not the chosen chord but nothing:
//          by the time it closes the document has already changed, and a caller that wanted the
//          chord would be asking a second time for what the session already holds.
// INPUTS: context — where to open the sheet. session — the document being edited. sectionId,
//         barIndex and beat — the address of the cell, in the model's own zero-based numbering.
//         shownKey — the key to render the preview in. semitoneShift — how far the shown chart is
//         from the written one. onChanged — called after every applied edit so the caller can
//         rebuild; the sheet does not know how the caller draws its page.
// OUTPUTS: A future that completes when the sheet is dismissed, whether anything was edited or not.
//          A cell whose address names no bar in the session opens nothing and completes at once,
//          because there is nothing to edit and an empty sheet would be a lie about what is
//          selectable.
// KEYWORDS: show, bottom-sheet, session-edit, callback, guard
/// Opens the chord palette for one cell.
Future<void> showChordPalette(
  BuildContext context, {
  required EditSession session,
  required String sectionId,
  required int barIndex,
  required int beat,
  required Key shownKey,
  int semitoneShift = 0,
  VoidCallback? onChanged,
}) async {
  final BeatChord? existing = session.existingChordAt(
    sectionId: sectionId,
    barIndex: barIndex,
    beat: beat,
  );
  final Bar? bar = session.song.barAt(sectionId, barIndex);
  if (bar == null) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: sheetPanelColor,
    isScrollControlled: true,
    builder: (BuildContext context) => ChordPaletteSheet(
      session: session,
      sectionId: sectionId,
      barIndex: barIndex,
      beat: beat,
      initialChord: existing,
      shownKey: shownKey,
      semitoneShift: semitoneShift,
      onChanged: onChanged,
    ),
  );
}

/// The palette itself: a root grid, a quality row and a preview.
class ChordPaletteSheet extends StatefulWidget {
  /// Creates a palette over one cell of [session].
  ///
  /// [initialChord] is what the cell holds, or null when it is empty; it decides the quality the
  /// sheet opens with, so a musician editing an existing chord is offered the tension they already
  /// wrote rather than a plain triad.
  const ChordPaletteSheet({
    super.key,
    required this.session,
    required this.sectionId,
    required this.barIndex,
    required this.beat,
    required this.shownKey,
    this.initialChord,
    this.semitoneShift = 0,
    this.onChanged,
  });

  /// The document being edited.
  final EditSession session;

  /// The section the edited bar belongs to.
  final String sectionId;

  /// The bar's index inside its section.
  final int barIndex;

  /// The cell's index inside its bar.
  final int beat;

  /// What the cell held when the sheet opened, or null when it was empty.
  final BeatChord? initialChord;

  /// The key the preview is spelled in.
  final Key shownKey;

  /// How far the shown chart sits from the written one, in semitones.
  final int semitoneShift;

  /// Called after every applied edit.
  final VoidCallback? onChanged;

  @override
  State<ChordPaletteSheet> createState() => _ChordPaletteSheetState();
}

/// The sheet's state: the sticky quality, the root being previewed, and the chord draft.
class _ChordPaletteSheetState extends State<ChordPaletteSheet> {
  /// The quality every tap currently applies.
  ///
  /// Seeded from the cell's own chord so that editing a tension is a change of root and not a
  /// downgrade to a triad, and from a major triad on an empty cell, which is the single most likely
  /// chord to be written there.
  late ChordQuality _quality;

  /// The root the preview shows, or null until a root has been tapped.
  ///
  /// Not seeded from the cell: "nothing chosen yet" and "the chord already there" are the same
  /// picture on the grid, and seeding would make the first tap ambiguous.
  ChordRootChoice? _draftRoot;

  /// The roots the key offers, computed once because the key cannot change while the sheet is open.
  late final List<ChordRootChoice> _roots = chordRootChoicesFor(
    widget.shownKey,
  );

  /// The chord the cell held when the sheet opened, so the grid can mark where the edit started.
  late final BeatChord? _opening = widget.initialChord;

  @override
  void initState() {
    super.initState();
    _quality = _opening?.chord.quality ?? ChordQuality.majorTriad;
  }

  // PURPOSE: Report the chord currently held by the edited cell, read back from the session rather
  //          than remembered, so the grid's marker follows an undo made while the sheet is open
  //          instead of showing where the chord used to be.
  // INPUTS: None.
  // OUTPUTS: The cell's chord, or null when it holds none.
  // KEYWORDS: read-back, live-state, undo-aware
  BeatChord? get _current => widget.session.existingChordAt(
    sectionId: widget.sectionId,
    barIndex: widget.barIndex,
    beat: widget.beat,
  );

  // PURPOSE: Apply one chord to the cell, which is the sheet's only way of changing the document.
  // INPUTS: chord — the chord to place.
  // OUTPUTS: Nothing. Appends exactly one event through the session, keeps the cell's engraved size
  //          when it is replacing a chord, ticks the haptic so a tap is felt without looking, and
  //          tells the caller the page needs rebuilding. The sheet stays open: see the file header
  //          for why that is the interaction and not an oversight.
  // KEYWORDS: apply, haptic, session-append, one-tap-per-root, stay-open
  void _apply(Chord chord) {
    final BeatChord? existing = _current;
    final bool applied = widget.session.applyChordToCell(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
      chord: chord,
      size: existing?.size ?? ChordSize.normal,
    );
    if (!applied) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {});
    widget.onChanged?.call();
  }

  // PURPOSE: Remove the chord from the cell, which is the catalogue's `chord.delete` reached from
  //          the same sheet rather than from a separate mode.
  // INPUTS: None.
  // OUTPUTS: Nothing. Removes the chord at the cell when there is one, leaves the sheet open, and
  //          clears the draft so the grid stops marking a chord that is no longer there.
  // KEYWORDS: delete, chord-remove, same-sheet, no-mode-switch
  void _remove() {
    final bool removed = widget.session.removeChordAt(
      sectionId: widget.sectionId,
      barIndex: widget.barIndex,
      beat: widget.beat,
    );
    if (!removed) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _draftRoot = null);
    widget.onChanged?.call();
  }

  // PURPOSE: Change the sticky quality without applying anything, so a musician can line up root and
  //          quality in either order before committing.
  // INPUTS: quality — the new quality.
  // OUTPUTS: Nothing; rebuilds the preview.
  // KEYWORDS: quality, sticky, preview-only
  void _chooseQuality(ChordQuality quality) =>
      setState(() => _quality = quality);

  // PURPOSE: Describe the edited position the way the musician counts it, so the sheet says which
  //          cell is about to change and not only which chord.
  // INPUTS: l10n — the message catalogue, which supplies the words `Bar` and `cell`. It is passed in
  //         rather than read from a context because this is a getter and not a builder.
  // OUTPUTS: A one-line label such as `Bar 12 · cell 2`, numbered from one across the whole written
  //          chart, which is the same counting the viewer's selection line uses.
  // KEYWORDS: label, one-based, bar-ordinal, musician-numbering, localized
  String _positionLabel(AppLocalizations l10n) {
    int ordinal = 0;
    for (final Section section in widget.session.song.sections) {
      if (section.id == widget.sectionId) {
        ordinal += widget.barIndex + 1;
        break;
      }
      ordinal += section.bars.length;
    }
    return l10n.palettePosition(ordinal, widget.beat + 1);
  }

  // PURPOSE: Render the chord a tap would write, in the key the chart is SHOWN in, using the same
  //          spelling path the page uses.
  // INPUTS: chord — the sounding chord to preview.
  // OUTPUTS: The chart text, moved by the viewer's interval first so that a chart shown two
  //          semitones up previews the symbols the page will actually draw.
  // KEYWORDS: preview, rendering, shown-key, transposition, one-spelling-path
  String _render(Chord chord) {
    final Chord shifted = widget.semitoneShift == 0
        ? chord
        : const Transposer().transposeChord(chord, widget.semitoneShift);
    return shifted.render(widget.shownKey, const SpellingTable());
  }

  @override
  Widget build(BuildContext context) {
    final BeatChord? current = _current;
    final ChordRootChoice? draft = _draftRoot;
    final Chord? preview = draft == null ? null : chordOf(draft, _quality);
    final int? currentPitch = current?.chord.root.pitchClass;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(),
            const SizedBox(height: 8),
            _buildPreview(preview, current),
            const SizedBox(height: 10),
            _buildQualityRow(),
            const SizedBox(height: 10),
            _buildRootGrid(currentPitch),
            const SizedBox(height: 8),
            _buildRemoveRow(current),
          ],
        ),
      ),
    );
  }

  // PURPOSE: Draw the sheet's header: the position being edited, the key the roots are spelled in,
  //          and the control that closes the sheet.
  // INPUTS: None; the position and the key are the widget's own fields, and the words come from the
  //         catalogue in the context this builder was given.
  // OUTPUTS: The header row.
  // KEYWORDS: header, position-label, shown-key, done, localized
  Widget _buildHeader() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _positionLabel(l10n),
                key: const ValueKey<String>('chord-palette-position'),
                style: const TextStyle(
                  color: sheetOnPanelColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                // The key is named through the catalogue and not by `Key.toString()`, which is a
                // diagnostic: a musician reading Russian needs the mode word in Russian, while the
                // tonic letter stays the chart's own notation.
                l10n.paletteChordsIn(localizedKeyName(l10n, widget.shownKey)),
                style: const TextStyle(color: sheetMutedColor, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey<String>('chord-palette-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.done,
            style: const TextStyle(color: sheetAccentColor),
          ),
        ),
      ],
    );
  }

  // PURPOSE: Show the chord the next tap writes, large enough to read at arm's length, so the
  //          musician confirms a symbol rather than trusting that the buttons mean what they say.
  // INPUTS: preview — the chord the draft root and sticky quality make, or null before a root is
  //         chosen. current — the chord in the cell, shown as a secondary line when one is there.
  // OUTPUTS: A two-line card: the preview, or a prompt to pick a root; beneath it, the chord the
  //          cell holds now, which is what makes the change legible before it is made.
  // KEYWORDS: preview-card, current-chord, prompt, falsifiable-feedback, localized
  Widget _buildPreview(Chord? preview, BeatChord? current) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: sheetCellColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            preview == null ? l10n.palettePickRoot : _render(preview),
            key: const ValueKey<String>('chord-palette-preview'),
            style: TextStyle(
              color: preview == null ? sheetMutedColor : sheetAccentColor,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            current == null
                ? l10n.paletteCellEmpty
                : l10n.paletteNow(_render(current.chord)),
            style: const TextStyle(color: sheetMutedColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // PURPOSE: Draw the sticky quality row, one chip per quality the palette offers.
  // INPUTS: None.
  // OUTPUTS: A wrapping row of chips. The chosen one is filled with the accent, so "this is what the
  //          next tap will use" is visible without reading a label.
  // KEYWORDS: quality-row, chips, sticky-state, accent
  Widget _buildQualityRow() => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: <Widget>[
      for (final ChordQuality quality in chordPaletteQualities)
        _QualityChip(
          quality: quality,
          selected: quality == _quality,
          onTap: () => _chooseQuality(quality),
        ),
    ],
  );

  // PURPOSE: Draw the twelve roots, the key's own seven first, in cells large enough for a thumb.
  // INPUTS: currentPitch — the pitch class the cell currently holds, so its root is marked distinct
  //         from the draft root the user is previewing.
  // OUTPUTS: A four-column grid. Four columns is the largest count that keeps a cell wider than the
  //          48 logical pixels a touch target needs on a phone-width sheet, and it makes three rows
  //          of twelve, so the whole vocabulary is on screen with nothing to scroll to.
  // KEYWORDS: root-grid, four-columns, touch-target, degree-label, marker
  Widget _buildRootGrid(int? currentPitch) => GridView.count(
    key: const ValueKey<String>('chord-palette-roots'),
    crossAxisCount: 4,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 1.6,
    children: <Widget>[
      for (final ChordRootChoice root in _roots)
        _RootCell(
          root: root,
          isCurrent: currentPitch == root.pitchClass,
          isDraft: _draftRoot?.pitchClass == root.pitchClass,
          onTap: () {
            setState(() => _draftRoot = root);
            _apply(chordOf(root, _quality));
          },
        ),
    ],
  );

  // PURPOSE: Offer the removal of the chord, in the same sheet rather than behind a second mode.
  // INPUTS: current — the cell's chord; the action is disabled when there is none.
  // OUTPUTS: A row holding one destructive-styled button.
  // KEYWORDS: remove, destructive, disabled-when-empty, same-sheet, localized
  Widget _buildRemoveRow(BeatChord? current) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: <Widget>[
      TextButton.icon(
        key: const ValueKey<String>('chord-palette-remove'),
        onPressed: current == null ? null : _remove,
        icon: const Icon(Icons.backspace_outlined, size: 18),
        label: Text(AppLocalizations.of(context).paletteRemoveChord),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFFF8A80),
          disabledForegroundColor: sheetMutedColor,
        ),
      ),
    ],
  );
}

/// One quality chip in the sticky row.
class _QualityChip extends StatelessWidget {
  /// Creates a chip for [quality], marked [selected] when it is the sticky one.
  const _QualityChip({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  /// The quality this chip selects.
  final ChordQuality quality;

  /// Whether this quality is the one the next tap will apply.
  final bool selected;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? sheetAccentColor : sheetCellColor,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: ValueKey<String>('chord-palette-quality-${quality.token}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          quality.token,
          style: TextStyle(
            color: selected ? sheetPanelColor : sheetOnPanelColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// One root cell in the grid.
class _RootCell extends StatelessWidget {
  /// Creates a cell for [root], marked when it is the cell's own root or the previewed draft.
  const _RootCell({
    required this.root,
    required this.isCurrent,
    required this.isDraft,
    required this.onTap,
  });

  /// The root this cell selects.
  final ChordRootChoice root;

  /// Whether the edited cell already holds this root.
  final bool isCurrent;

  /// Whether this root is the one currently being previewed.
  final bool isDraft;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = isDraft
        ? sheetSelectedCellColor
        : (isCurrent ? sheetSelectedCellColor : sheetCellColor);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey<String>('chord-palette-root-${root.pitchClass}'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDraft ? sheetAccentColor : Colors.transparent,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '${root.written}',
                style: const TextStyle(
                  color: sheetOnPanelColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                root.degreeLabel,
                style: TextStyle(
                  color: isCurrent ? sheetAccentColor : sheetMutedColor,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
