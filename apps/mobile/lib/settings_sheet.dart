// PURPOSE: Let the musician choose the language the interface is drawn in, and say honestly where
//          that choice is kept — because on one of the two platforms this application ships on,
//          the answer is "for seven days, unless you install it".
// INPUTS: context — where the sheet is raised from. language — the choice in force right now, so
//         the sheet opens showing what the musician is already reading. onChanged — called with the
//         new choice the moment one is tapped.
// OUTPUTS: A modal bottom sheet that closes when a language is picked, having reported it. Picking
//          the language already in force closes the sheet too and changes nothing, which is not a
//          failure: the sheet is a choice, and re-confirming a choice is a choice.
// KEYWORDS: settings, language, sheet, runtime-switch, persistence-note, d20, arm-length
//
// WHY THE CHANGE APPLIES IMMEDIATELY AND NOT ON A SAVE BUTTON. The thing being changed is the words
// on the screen, so the confirmation IS the effect: the sheet's own heading and the button under the
// thumb come back in the chosen language on the next frame. A Save button would make the musician
// press a control to find out what they chose, and the choice is already irreversible-by-accident
// safe — going back to the device's language is the first row.
//
// WHY THE STORAGE NOTE IS ON THIS SHEET AND NOT IN A DOCUMENT. D20 distributes the application as a
// web page, where the preference lives in storage the browser may clear after seven days. That is a
// real limitation of the choice, not an implementation detail, and the person it affects is the one
// looking at this sheet. The note names the loss and what does NOT follow from it — the charts are
// files and are unaffected — so nobody concludes that a cleared preference could cost them music.
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'settings_contract.dart';
import 'sheet_surface.dart';

/// Raise the settings sheet and report the language the musician picked.
///
/// [onChanged] is called once per tap and always before the sheet closes, so the caller's state and
/// the strings on screen cannot disagree about which row is ticked while the sheet is still up.
Future<void> showSettingsSheet(
  BuildContext context, {
  required LanguageChoice language,
  required ValueChanged<LanguageChoice> onChanged,
  required bool browserStorage,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: sheetPanelColor,
  isScrollControlled: true,
  builder: (BuildContext context) => SettingsSheet(
    language: language,
    onChanged: onChanged,
    browserStorage: browserStorage,
  ),
);

/// The settings surface: the language choices, and where the choice is kept.
class SettingsSheet extends StatelessWidget {
  /// Creates the sheet showing [language] as the choice in force.
  ///
  /// [browserStorage] selects the note about where the preference lives: true in a browser, where
  /// the storage is the page's own and the browser may clear it, and false on a platform with a
  /// configuration file that stays until it is deleted.
  const SettingsSheet({
    super.key,
    required this.language,
    required this.onChanged,
    required this.browserStorage,
  });

  /// The choice in force when the sheet opened.
  final LanguageChoice language;

  /// Called with a new choice as soon as one is tapped.
  final ValueChanged<LanguageChoice> onChanged;

  /// Whether this build runs in a browser.
  final bool browserStorage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      key: const ValueKey<String>('settings-sheet'),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l10n.settingsTitle,
                style: const TextStyle(
                  color: sheetOnPanelColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.settingsLanguageHeading,
                style: const TextStyle(
                  color: sheetMutedColor,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              // The order is the order of decreasing specificity: the device first, because that is
              // what a first run does and what a musician who wants to stop thinking about it goes
              // back to, then the two named languages.
              _LanguageRow(
                rowKey: 'settings-language-system',
                label: l10n.settingsFollowSystem,
                selected: language == LanguageChoice.system,
                onTap: () => onChanged(LanguageChoice.system),
              ),
              _LanguageRow(
                rowKey: 'settings-language-en',
                label: l10n.settingsEnglish,
                selected: language == LanguageChoice.english,
                onTap: () => onChanged(LanguageChoice.english),
              ),
              _LanguageRow(
                rowKey: 'settings-language-ru',
                label: l10n.settingsRussian,
                selected: language == LanguageChoice.russian,
                onTap: () => onChanged(LanguageChoice.russian),
              ),
              const SizedBox(height: 16),
              Text(
                browserStorage
                    ? l10n.settingsStorageNoteWeb
                    : l10n.settingsStorageNote,
                key: const ValueKey<String>('settings-storage-note'),
                style: const TextStyle(color: sheetMutedColor, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey<String>('settings-done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.done,
                    style: const TextStyle(
                      color: sheetAccentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One language choice, drawn as a full-width row so a thumb finds it without aiming.
class _LanguageRow extends StatelessWidget {
  /// Creates the row labelled [label], ticked when [selected], reporting a tap through [onTap].
  const _LanguageRow({
    required this.rowKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// The widget key the tests and the driving tools find this row by.
  final String rowKey;

  /// What the row says. Shown in the language it names where that is readable, which is why the two
  /// named rows carry their own endonym.
  final String label;

  /// Whether this is the choice in force.
  final bool selected;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: selected ? sheetSelectedCellColor : sheetCellColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey<String>(rowKey),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? sheetAccentColor : sheetMutedColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  // Wrap rather than clip: a translated name may be longer than the English one,
                  // and a choice that is cut off is a choice the musician cannot read.
                  softWrap: true,
                  style: TextStyle(
                    color: selected ? sheetAccentColor : sheetOnPanelColor,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
