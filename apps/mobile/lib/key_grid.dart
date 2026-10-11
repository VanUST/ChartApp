// PURPOSE: Offer the twelve keys a chart can be shown in as a grid a musician can hit with one
//          finger, so that transposing is "tap the key badge, tap the key" — two taps, which is
//          the benchmark the owner set (D9). The grid is deliberately a performance control: large
//          targets, high contrast and no scrolling, because it is used on a dark stage as well as
//          in the editor.
// INPUTS: The written key of the chart, the pitch class currently shown, and the build context the
//         dialog is opened from. The targets come from `TranspositionGrid` in chart_core, so the
//         spelling policy lives with the domain and this file only draws it.
// OUTPUTS: The [TranspositionTarget] the musician picked, or null when the dialog was dismissed
//          without a pick. A target the grid marks unavailable is shown disabled and cannot be
//          picked, because offering a key the chart cannot be spelled in would be a lie.
// KEYWORDS: transposition, key-grid, twelve-keys, dialog, touch-target, dark-surface, two-taps

import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;

import 'l10n/app_localizations.dart';
import 'scene_bar.dart';

/// The dark panel colour the grid is drawn on.
const Color _panelColor = Color(0xFF0F1B2A);

/// The colour of a cell a musician can press.
const Color _cellColor = Color(0xFF1C2E44);

/// The colour of the cell matching the key currently shown.
const Color _selectedCellColor = Color(0xFF2E5D8A);

/// The accent that marks the current key and the pickable borders.
const Color _accentColor = Color(0xFFFFC857);

/// The colour of text on the dark panel.
const Color _onPanelColor = Color(0xFFF5F8FB);

/// The colour of a target that cannot be spelled and therefore cannot be picked.
const Color _unavailableColor = Color(0xFF54708F);

// PURPOSE: Ask the musician which key to show the chart in, using the domain's own twelve targets.
// INPUTS: context — where to open the dialog. writtenKey — the key the chart is written in, which
//         decides how each target is spelled. currentPitchClass — the tonic pitch class currently
//         shown, used only to mark the current cell. The grid is built from
//         `TranspositionGrid.targets(writtenKey)`.
// OUTPUTS: A future that completes with the picked [TranspositionTarget], or with null when the
//          dialog is dismissed. An unavailable target is disabled and is never returned.
// KEYWORDS: key-picker, dialog, twelve-keys, two-taps, dismissable, dark-surface
/// Opens the twelve-key grid and resolves to the key the musician picked, or null if dismissed.
Future<TranspositionTarget?> showKeyGrid(
  BuildContext context, {
  required Key writtenKey,
  required int currentPitchClass,
}) {
  const TranspositionGrid grid = TranspositionGrid();
  final List<TranspositionTarget> targets = grid.targets(writtenKey);
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showDialog<TranspositionTarget>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: _panelColor,
      title: Text(
        l10n.keyGridTitle(localizedKeyName(l10n, writtenKey)),
        style: const TextStyle(color: _onPanelColor, fontSize: 20),
      ),
      content: SizedBox(
        width: 420,
        child: GridView.count(
          key: const ValueKey<String>('key-grid'),
          crossAxisCount: 4,
          shrinkWrap: true,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.3,
          children: <Widget>[
            for (final TranspositionTarget target in targets)
              _KeyCell(
                target: target,
                selected:
                    target.key.tonicPitchClass ==
                    normalizePitchClass(currentPitchClass),
                l10n: l10n,
              ),
          ],
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
}

/// One key in the grid.
class _KeyCell extends StatelessWidget {
  /// Creates a cell for [target], marked [selected] when it is the key already shown.
  const _KeyCell({
    required this.target,
    required this.selected,
    required this.l10n,
  });

  /// The key this cell offers.
  final TranspositionTarget target;

  /// Whether this cell is the key the chart is currently shown in.
  final bool selected;

  /// The catalogue, used for the interval caption and the unavailable note.
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final bool available = target.available;
    final Color background = selected ? _selectedCellColor : _cellColor;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey<String>('key-grid-${target.semitones}'),
        borderRadius: BorderRadius.circular(10),
        onTap: available ? () => Navigator.of(context).pop(target) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _accentColor : Colors.transparent,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '${target.key.tonic}',
                style: TextStyle(
                  color: available ? _onPanelColor : _unavailableColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _intervalLabel(target.semitones),
                style: TextStyle(
                  color: available ? _accentColor : _unavailableColor,
                  fontSize: 13,
                ),
              ),
              if (!available)
                Text(
                  l10n.keyGridNotSpellable,
                  style: const TextStyle(
                    color: _unavailableColor,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // PURPOSE: Write an interval the way a musician says it, so a grid cell answers "how far is
  //          this?" and not only "which key?".
  // INPUTS: semitones — the signed interval from the written key.
  // OUTPUTS: The catalogue's word for the written key itself at zero, otherwise a signed number
  //          with the unit the scene bar's key badge uses as well, such as `+2 st`. The unit comes
  //          from `scene_bar.dart` rather than from a second literal here, because the badge and
  //          the grid name the same distance and must not abbreviate it differently.
  // KEYWORDS: interval, label, semitones, formatting, one-definition
  String _intervalLabel(int semitones) {
    if (semitones == 0) {
      return l10n.keyGridWritten;
    }
    return localizedSemitoneInterval(l10n, semitones);
  }
}
