// PURPOSE: Ask the two questions a new chart must answer before any bar exists — the key it is
//          written in and the meter its bars are in — and hand the answers back. It is the surface
//          behind "New chart", and it exists because those two facts are the only ones about a new
//          chart that no editor surface can change afterwards: nothing in the event catalogue
//          rewrites a bar's meter, and the key grid moves what is SHOWN rather than what is
//          written. Asking here is what keeps the starting shape a default rather than a lock.
// INPUTS: The build context the dialog is opened from. Nothing else: the choices it offers are
//         defined in this file, and the chart it produces is built by the caller from
//         `newChartSong` in `chart_core`.
// OUTPUTS: A future that completes with the chosen key and meter, or with null when the musician
//          dismissed the dialog. The dialog itself writes nothing and knows no document: the caller
//          turns the answer into a `Song` and adopts it through the same door an opened `.chart`
//          goes through.
// KEYWORDS: new-chart, dialog, key-choice, meter-choice, from-scratch, d21, unchangeable-facts,
//           catalogue-only-strings
//
// WHY A DIALOG AND NOT THREE CONTROLS IN THE EMPTY STATE.
//
// The empty state is a place a musician arrives at rather than a form they fill in: it also has to
// carry the instruction for opening an iReal export, and it is shown again after a library fails
// to load. A dialog can be reached from BOTH shells and from the chart-file dialog, so the same
// three controls serve a musician with nothing loaded and a musician who wants to start over with
// a chart already open — one implementation, one wording, however they got here.
//
// WHY THE KEY IS OFFERED AS A MODE SWITCH AND TWELVE TONICS, AND WHY THOSE TWELVE.
//
// The twelve keys come from `TranspositionGrid.targets` in `chart_core`, the same function the
// transposition grid draws its cells from. That is deliberate: the spelling policy — which of the
// two enharmonic twins a key is written as — lives in one place in the domain, and a second list
// written here would eventually disagree with it. The grid is asked for the twelve keys of C major
// or of A minor depending on the mode, so switching to minor offers the practical minor tonics
// (C, C#, D, Eb, …) rather than respelling the major ones, which is the difference between G#
// minor and the eight-flat spelling nobody writes. A target the grid marks unavailable is drawn
// disabled and cannot be chosen, exactly as in the transposition grid.
//
// WHY THE METERS ARE THESE EIGHT.
//
// The owner's corpus is 1032 bars of 4/4 out of 1045, with 6/4 and 3/4 behind it; the rest are the
// meters a working musician counts in — 2/4, 5/4, 6/8, 7/8, 12/8. The list is an OFFER, not a
// model rule: `TimeSignature` accepts any numerator and denominator, and the meter of a bar the
// musician later adds is inherited from its neighbour rather than read from here. This is the
// one place in the application where a meter is chosen at all.
import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this dialog
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'l10n/app_localizations.dart';
import 'scene_bar.dart';
import 'sheet_surface.dart';

/// What the new-chart dialog answers: the key and the meter the chart is to start in.
///
/// A record rather than a `Song`, because the two facts are the whole of the dialog's knowledge;
/// what bars and how many of them a new chart holds is `newChartSong`'s business in `chart_core`,
/// and a dialog that returned a `Song` would be a second place where a chart's shape is decided.
typedef NewChartChoice = ({Key key, TimeSignature timeSignature});

/// The meters a new chart can start in, in the order they are offered.
///
/// 4/4 leads the second row rather than the first for a reason that is not aesthetic: 2/4 and 3/4
/// are the simple meters a musician swaps between, and 4/4 deliberately sits at the head of its own
/// row where the thumb finds it without reading. The list is stated here rather than in
/// `chart_core` because it is what THIS SURFACE offers, not what the model permits.
const List<TimeSignature> _offeredMeters = <TimeSignature>[
  TimeSignature(numerator: 2, denominator: 4),
  TimeSignature(numerator: 3, denominator: 4),
  TimeSignature(numerator: 5, denominator: 4),
  TimeSignature.fourFour,
  TimeSignature(numerator: 6, denominator: 4),
  TimeSignature.sixEight,
  TimeSignature(numerator: 7, denominator: 8),
  TimeSignature(numerator: 12, denominator: 8),
];

// PURPOSE: Ask for the key and meter of a chart written from scratch, so the starting shape is the
//          musician's choice rather than an assumption.
// INPUTS: context — where the dialog is shown.
// OUTPUTS: A future completing with the [NewChartChoice], or with null when it was dismissed. A
//          dismissal creates nothing and changes nothing on screen.
// KEYWORDS: new-chart, dialog-entry, dismissable, null-on-cancel, one-choice
/// Shows the new-chart dialog and resolves with the chosen key and meter, or null.
Future<NewChartChoice?> showNewChartDialog(BuildContext context) =>
    showDialog<NewChartChoice>(
      context: context,
      builder: (BuildContext context) => const _NewChartDialog(),
    );

/// The dialog itself: the explanation, the meters, the key, and the live summary of what is chosen.
class _NewChartDialog extends StatefulWidget {
  /// Creates the dialog.
  const _NewChartDialog();

  @override
  State<_NewChartDialog> createState() => _NewChartDialogState();
}

/// The dialog's state: the tonic pitch class and the mode that make its key, and the chosen meter.
///
/// The key is held as a PITCH CLASS AND A MODE rather than as a `Key`, because a `Key` carries a
/// spelling and the spelling depends on the mode: C major and C minor are different keys with the
/// same tonic, and switching the mode has to re-spell the chosen tonic through the grid rather
/// than rename the key it was holding.
class _NewChartDialogState extends State<_NewChartDialog> {
  /// The sounding pitch class of the chosen tonic, `0` being C.
  int _tonicPitchClass = 0;

  /// Whether the chart is to be written in a minor key.
  bool _minor = false;

  /// The meter the chart is to be written in.
  TimeSignature _meter = TimeSignature.fourFour;

  /// The twelve keys the grid offers for the mode in force.
  ///
  /// Derived per build rather than stored: it is twelve cheap values, and storing it would mean
  /// keeping a second copy in step with [_minor] — the one thing this dialog must not get wrong,
  /// because the mode switch and the key shown beside it would then disagree.
  List<TranspositionTarget> get _targets =>
      const TranspositionGrid().targets(_minor ? Key.aMinor : Key.cMajor);

  /// The key those targets spell for the chosen tonic.
  ///
  /// Always found: the grid returns exactly one target per pitch class, so the fallback below is
  /// unreachable for a pitch class in `[0, 11]` and exists only so this getter is total.
  Key get _key {
    for (final TranspositionTarget target in _targets) {
      if (target.key.tonicPitchClass == _tonicPitchClass && target.available) {
        return target.key;
      }
    }
    return _minor ? Key.aMinor : Key.cMajor;
  }

  // PURPOSE: Switch the mode while keeping the tonic the musician already chose, which is how a
  //          musician moves a tune from C major to C minor without hunting for the C cell again.
  // INPUTS: minor — the mode to switch to.
  // OUTPUTS: Nothing. Rebuilds so the twelve cells show the new mode's spellings; the chosen tonic
  //          is unchanged, because it is the same note in both modes.
  // KEYWORDS: mode-switch, tonic-kept, respell, rebuild
  void _setMinor(bool minor) => setState(() => _minor = minor);

  // PURPOSE: Choose the tonic of the key, so the mode switch beside it decides how it is spelled.
  // INPUTS: pitchClass — the sounding pitch class of the tonic.
  // OUTPUTS: Nothing. Rebuilds, marking the new cell.
  // KEYWORDS: key-choice, tonic, pitch-class, rebuild
  void _setTonic(int pitchClass) =>
      setState(() => _tonicPitchClass = pitchClass);

  // PURPOSE: Hand the two answers back and close, so the caller can build and adopt the chart.
  // INPUTS: None; reads the state.
  // OUTPUTS: Nothing. Pops the dialog with the chosen key and meter.
  // KEYWORDS: confirm, create, pop-with-value, close
  void _create() =>
      Navigator.of(context)
          .pop<NewChartChoice>((key: _key, timeSignature: _meter));

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Key key = _key;
    return AlertDialog(
      key: const ValueKey<String>('new-chart-dialog'),
      backgroundColor: sheetPanelColor,
      title: Text(
        l10n.newChart,
        style: const TextStyle(color: sheetOnPanelColor, fontSize: 20),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // WHY THE SENTENCE SAYS THE KEY AND THE METER CANNOT BE CHANGED LATER. It is true
              // today, and it is the reason this dialog exists at all: a musician who picks a key
              // to skip past the dialog is choosing a fact about the chart. A message that
              // advertised the choice without saying it is binding would be the false promise this
              // sentence exists to avoid — and it must be corrected here on the day the editor
              // gains either control.
              Text(
                l10n.newChartIntro(l10n.barCount(newChartBarCount)),
                style: const TextStyle(color: sheetMutedColor, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _caption(l10n.newChartMeterLabel),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final TimeSignature meter in _offeredMeters)
                    _ChoiceCell(
                      cellKey:
                          'new-chart-meter-'
                          '${meter.numerator}-${meter.denominator}',
                      // A meter is notation rather than a word, so `4/4` is the same string in
                      // every language and is deliberately not in the catalogue — the same line
                      // drawn for chord symbols and for the letters of the tonics below.
                      label: meter.toString(),
                      selected: meter == _meter,
                      onTap: () => setState(() => _meter = meter),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _caption(l10n.newChartKeyLabel),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  _ChoiceCell(
                    cellKey: 'new-chart-major',
                    label: l10n.newChartMajor,
                    selected: !_minor,
                    onTap: () => _setMinor(false),
                  ),
                  const SizedBox(width: 8),
                  _ChoiceCell(
                    cellKey: 'new-chart-minor',
                    label: l10n.newChartMinor,
                    selected: _minor,
                    onTap: () => _setMinor(true),
                  ),
                  const SizedBox(width: 12),
                  // The chosen key named as a musician says it — the same wording the key badge and
                  // the song list use, from the one function that composes it. It is what makes the
                  // mode switch and the tonic cells read as one answer instead of two.
                  Flexible(
                    child: Text(
                      localizedKeyName(l10n, key),
                      key: const ValueKey<String>('new-chart-key-name'),
                      style: const TextStyle(
                        color: sheetAccentColor,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final TranspositionTarget target in _targets)
                    _ChoiceCell(
                      cellKey: 'new-chart-key-${target.key.tonicPitchClass}',
                      // The letter alone, as on the transposition grid: a chord chart writes roots
                      // in Latin letters in every language, and the mode word is already on the
                      // switch beside these cells.
                      label: '${target.key.tonic}',
                      selected:
                          target.key.tonicPitchClass == _tonicPitchClass &&
                          target.available,
                      onTap: target.available
                          ? () => _setTonic(target.key.tonicPitchClass)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('new-chart-create'),
          onPressed: _create,
          child: Text(l10n.create),
        ),
      ],
    );
  }

  // PURPOSE: Draw the caption above a group of choices, so the two questions are labelled the same
  //          way and neither becomes a row of unexplained buttons.
  // INPUTS: text — the caption, already localized by the caller.
  // OUTPUTS: The caption widget, in the muted panel colour.
  // KEYWORDS: caption, group-label, muted, shared-style
  Widget _caption(String text) => Text(
    text,
    style: const TextStyle(
      color: sheetMutedColor,
      fontSize: 11,
      letterSpacing: 0.8,
    ),
  );
}

/// One pressable choice in the dialog — a meter, a mode or a tonic — drawn so every choice in the
/// surface looks and behaves the same.
///
/// WHY ONE WIDGET FOR THREE GROUPS. The three groups differ in what they mean and not in how they
/// are pressed, and three near-identical cells would be three places for the selected border, the
/// disabled state and the tap target to drift apart. What a cell MEANS is carried by its key and
/// its label; how it answers a press is decided once, here.
class _ChoiceCell extends StatelessWidget {
  /// Creates a cell labelled [label], marked [selected], calling [onTap] when pressed.
  ///
  /// A null [onTap] disables the cell — the state the transposition grid uses for a key it cannot
  /// spell, and one this dialog keeps so a grid answer it cannot honour is shown rather than
  /// silently dropped.
  const _ChoiceCell({
    required this.cellKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// The widget key the tests and the driving tools find this cell by.
  final String cellKey;

  /// What the cell offers: a meter such as `4/4`, a mode, or a tonic letter.
  final String label;

  /// Whether this cell is the choice in force.
  final bool selected;

  /// What a press does, or null when the cell cannot be pressed.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color text = enabled
        ? (selected ? sheetAccentColor : sheetOnPanelColor)
        : sheetMutedColor;
    return Material(
      color: selected ? sheetSelectedCellColor : sheetCellColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey<String>(cellKey),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          // NO `alignment:` HERE, AND THAT IS THE POINT. A `Container` with an alignment wraps its
          // child in an `Align`, and an `Align` with no width factor EXPANDS to the largest size it
          // is offered — so inside a `Wrap` every cell took the full width of the dialog, the eight
          // meters became eight full-width rows, and the key section was pushed below the fold
          // entirely. Measured on the owner's tablet before the fix: the tonics were not reachable
          // without scrolling past a screenful of meters. A cell hugs its label plus this padding,
          // and centring is what the padding plus `textAlign` already give.
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? sheetAccentColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
