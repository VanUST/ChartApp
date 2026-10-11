// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ChartApp — iReal reader';

  @override
  String get chooseFile => 'Choose a file…';

  @override
  String get openHtmlFile => 'Open .html file';

  @override
  String get iRealHtmlFileLabel => 'iReal .html file';

  @override
  String get load => 'Load';

  @override
  String get promptNativePath =>
      'Open an iReal .html file exported from iReal Pro.\nType its path, or choose it with the button above.';

  @override
  String get promptNativeChooser =>
      'Open an iReal .html file exported from iReal Pro.\nThe file stays on this device.';

  @override
  String get promptWeb =>
      'Open an iReal .html file exported from iReal Pro.\nIt is read in the browser and is not uploaded.';

  @override
  String get payloadNoSongs => 'The payload carried no songs.';

  @override
  String get untitled => 'Untitled';

  @override
  String get noFileLoaded => 'No file loaded.';

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '$count song',
    );
    return '$_temp0';
  }

  @override
  String statusSongsPlaylist(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '$count song',
    );
    return '$_temp0 · playlist \"$name\"';
  }

  @override
  String drawerSongsPlaylist(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '$count song',
    );
    return '$_temp0 · \"$name\"';
  }

  @override
  String barCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bars',
      one: '$count bar',
    );
    return '$_temp0';
  }

  @override
  String issueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count issues',
      one: '$count issue',
    );
    return '$_temp0';
  }

  @override
  String get songInfoTooltip => 'Song info: title, composer, style and tempo';

  @override
  String get songInfoSheetTitle => 'Song info';

  @override
  String issuesTitle(String title) {
    return 'Import issues — $title';
  }

  @override
  String issueLine(int offset, String message) {
    return '@$offset: $message';
  }

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get cancel => 'Cancel';

  @override
  String get newChart => 'New chart';

  @override
  String newChartIntro(String bars) {
    return 'A new chart starts as one section of $bars. Choose a key and a meter — the editor cannot change either afterwards.';
  }

  @override
  String get newChartMeterLabel => 'Meter';

  @override
  String get newChartKeyLabel => 'Key';

  @override
  String get newChartMajor => 'Major';

  @override
  String get newChartMinor => 'Minor';

  @override
  String get create => 'Create';

  @override
  String get tooltipInkOn => 'Drawing: the pen draws, a finger still selects';

  @override
  String get tooltipInkOffEraserOn => 'Pen off: the eraser is on';

  @override
  String get tooltipInkOff => 'Selecting: the pen and a finger both select';

  @override
  String get tooltipEraserOn =>
      'Erasing: tap a stroke and its whole length goes';

  @override
  String get tooltipEraserOff => 'Eraser off';

  @override
  String get tooltipUndo => 'Undo the last chart edit';

  @override
  String get tooltipRedo => 'Redo the last undone chart edit';

  @override
  String get tooltipForm => 'Bars and sections (the form)';

  @override
  String get tooltipCues => 'Words on the chart (To Coda, Solo, 4×)';

  @override
  String get tooltipSetlist =>
      'Programme (setlist): order, transpose and play the charts';

  @override
  String get tooltipSettings => 'Settings';

  @override
  String get tooltipOverflowMenu => 'Chart, form and programme';

  @override
  String get menuForm => 'Bars and sections';

  @override
  String get menuCues => 'Words on the chart';

  @override
  String get menuSetlist => 'Programme (setlist)';

  @override
  String get menuChartFile => 'Save or open a .chart file';

  @override
  String get menuSettings => 'Settings';

  @override
  String get selectionPrompt => 'Tap a bar to select it.';

  @override
  String selectionBar(int bar) {
    return 'selected: bar $bar (whole bar)';
  }

  @override
  String selectionBarCell(int bar, int cell) {
    return 'selected: bar $bar cell $cell';
  }

  @override
  String get selectionHintChord => '— tap to change the chord';

  @override
  String get selectionHintForm => '— tap for bars & sections';

  @override
  String get noBars => 'This song has no bars.';

  @override
  String fitFallbackAuto(int percent) {
    return 'This song does not fit on one page at the $percent% legible floor. Shown as pages instead.';
  }

  @override
  String fitFallbackExplicit(int percent) {
    return 'You asked for one page, but at the $percent% legible floor it needs more. Shown as pages instead.';
  }

  @override
  String get sceneCaptionPos => 'POS';

  @override
  String get sceneCaptionBpm => 'BPM';

  @override
  String get sceneCaptionStyle => 'STYLE';

  @override
  String get sceneCaptionKeyCompact => 'KEY';

  @override
  String get sceneCaptionKeyFull => 'KEY · tap to transpose';

  @override
  String get sceneCaptionRepeats => 'REPEATS';

  @override
  String get sceneCaptionPage => 'PAGE';

  @override
  String get sceneModeFit => 'FIT';

  @override
  String get sceneModePages => 'PAGES';

  @override
  String get sceneDeferredTooltip => 'Style and repeats';

  @override
  String sceneDeferredStyleRow(String style) {
    return 'STYLE · $style';
  }

  @override
  String sceneDeferredRepeatsRow(String repeats) {
    return 'REPEATS · $repeats';
  }

  @override
  String get repeatNone => 'none';

  @override
  String repeatPassages(int count) {
    return '$count×';
  }

  @override
  String repeatVoltas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count volta',
      one: '$count volta',
    );
    return '$_temp0';
  }

  @override
  String repeatPrevious(int count) {
    return '$count %';
  }

  @override
  String keyBadgeLabel(String key, String interval) {
    return '$key · $interval';
  }

  @override
  String semitonesShort(String signed) {
    return '$signed st';
  }

  @override
  String keyGridTitle(String writtenKey) {
    return 'Transpose — written in $writtenKey';
  }

  @override
  String get keyGridWritten => 'written';

  @override
  String get keyGridNotSpellable => 'not spellable';

  @override
  String keyNameMajor(String tonic) {
    return '$tonic major';
  }

  @override
  String keyNameMinor(String tonic) {
    return '$tonic minor';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguageHeading => 'Language';

  @override
  String get settingsFollowSystem => 'Device language';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsRussian => 'Русский';

  @override
  String get settingsStorageNote =>
      'The choice is remembered on this device. It is a setting, not part of your charts.';

  @override
  String get settingsStorageNoteWeb =>
      'The choice is remembered in this browser\'s storage. Safari clears that storage after seven days without use, and the language then follows the device again. Your charts are files and are never affected.';

  @override
  String languageChanged(String language) {
    return 'Language: $language';
  }

  @override
  String get save => 'Save';

  @override
  String get ok => 'OK';

  @override
  String get fileNameLabel => 'File name';

  @override
  String fileSaveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String fileOpenFailed(String error) {
    return 'Could not open: $error';
  }

  @override
  String get fileChooserCancelled => 'No file was chosen.';

  @override
  String fileWarningSuffix(String warnings, String message) {
    return ' $warnings: $message';
  }

  @override
  String byteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
      one: '$count byte',
    );
    return '$_temp0';
  }

  @override
  String operationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count operations',
      one: '$count operation',
    );
    return '$_temp0';
  }

  @override
  String warningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '$count warning',
    );
    return '$_temp0';
  }

  @override
  String entryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '$count entry',
    );
    return '$_temp0';
  }

  @override
  String get chartFileDialogTitle => 'Chart file';

  @override
  String get chartFileLabelPath => '.chart file';

  @override
  String get chartFileOpenButton => 'Open .chart';

  @override
  String get chartFileNoDocument => 'Load or import a song before saving it.';

  @override
  String get chartFileNameToSave => 'Name a .chart file to save to.';

  @override
  String get chartFileNameToOpen => 'Name a .chart file to open.';

  @override
  String chartFileSavedTo(String bytes, String path, String operations) {
    return 'Saved $bytes to $path · $operations.';
  }

  @override
  String chartFileSavedAs(String bytes, String path, String operations) {
    return 'Saved $bytes as $path · $operations.';
  }

  @override
  String chartFileOpened(String title, String operations) {
    return 'Opened \"$title\" · $operations.';
  }

  @override
  String get saveModeChosenLocation => 'Each Save asks where to put the file.';

  @override
  String get saveModeRewriteInPlace =>
      'This browser re-writes that file in place, so the next Save updates it.';

  @override
  String get saveModeDownload =>
      'This browser cannot update a file in place, so each Save downloads a NEW copy.';

  @override
  String get chartFileSaveHintChosenLocation =>
      'This device has no file path you can type, so Save opens the system\'s own file chooser, where you pick the folder and the name.';

  @override
  String get chartFileSaveHintRewriteInPlace =>
      'This browser can re-write a chart file it has already been given. The first Save asks where to put the file; every Save after that updates that same file.';

  @override
  String get chartFileSaveHintDownload =>
      'This browser cannot re-write a file in place, so every Save downloads a NEW copy. The browser chooses where it lands, and may rename it when a file of that name is already there.';

  @override
  String get setlistFileTooltip => 'Save or open a .setlist file';

  @override
  String get setlistFileDialogTitle => 'Programme file';

  @override
  String get setlistFileLabelPath => '.setlist file';

  @override
  String get setlistFileOpenButton => 'Open .setlist';

  @override
  String get setlistFileNameToSave => 'Name a .setlist file to save to.';

  @override
  String get setlistFileNameToOpen => 'Name a .setlist file to open.';

  @override
  String setlistFileSavedTo(
    String bytes,
    String path,
    String entries,
    String operations,
  ) {
    return 'Saved $bytes to $path · $entries · $operations.';
  }

  @override
  String setlistFileSavedAs(
    String bytes,
    String path,
    String entries,
    String operations,
  ) {
    return 'Saved $bytes as $path · $entries · $operations.';
  }

  @override
  String get setlistFileSaveHintChosenLocation =>
      'This device has no file path you can type, so Save opens the system\'s own file chooser, where you pick the folder and the name.';

  @override
  String get setlistFileSaveHintRewriteInPlace =>
      'This browser can re-write a setlist file it has already been given. The first Save asks where to put the file; every Save after that updates that same file.';

  @override
  String get setlistFileSaveHintDownload =>
      'This browser cannot re-write a file in place, so every Save downloads a NEW copy. The browser chooses where it lands, and may rename it when a file of that name is already there.';

  @override
  String setlistOpened(String name, String entries) {
    return 'Opened \"$name\" · $entries.';
  }

  @override
  String missingEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count not found in this library.',
      one: '$count not found in this library.',
    );
    return '$_temp0';
  }

  @override
  String get metadataTitle => 'Title';

  @override
  String get metadataTitleHint =>
      'The name a musician reads at the top of the chart.';

  @override
  String get metadataComposer => 'Composer';

  @override
  String get metadataComposerHint =>
      'As written; the order is whatever the format stores.';

  @override
  String get metadataStyle => 'Style';

  @override
  String get metadataStyleHint => 'Free text, such as Medium Swing or Ballad.';

  @override
  String get metadataTempo => 'Tempo (BPM)';

  @override
  String get metadataTempoHelperZero => '0 means this chart sets no tempo.';

  @override
  String get metadataTempoHelperHint =>
      'Whole beats per minute, or 0 for none.';

  @override
  String get metadataTempoError => 'A tempo is a whole number.';

  @override
  String get metadataTempoRefused =>
      'A tempo is a whole number of beats per minute.';

  @override
  String get metadataNothingChanged =>
      'Nothing changed, so nothing was written to the log.';

  @override
  String get metadataFooterHint =>
      'One edit: the four facts above are written together.';

  @override
  String get metadataFooterFixTempo => 'Fix the tempo before saving.';

  @override
  String palettePosition(int bar, int cell) {
    return 'Bar $bar · cell $cell';
  }

  @override
  String paletteChordsIn(String key) {
    return 'Chords in $key';
  }

  @override
  String get palettePickRoot => 'Pick a root';

  @override
  String get paletteCellEmpty => 'This cell is empty.';

  @override
  String paletteNow(String chord) {
    return 'Now: $chord';
  }

  @override
  String get paletteRemoveChord => 'Remove chord';

  @override
  String get melodyGroup => 'MELODY';

  @override
  String get melodyDuration => 'DURATION';

  @override
  String get melodyPitch => 'PITCH';

  @override
  String get melodyAlteration => 'ALTERATION';

  @override
  String get melodyNewNote => '+ New note';

  @override
  String get melodyPickCell => 'Tap a beat on the chart to write a note.';

  @override
  String get melodyBeatEmpty => 'This beat carries no note.';

  @override
  String melodyNoteLine(int step, String pitch, String value) {
    return 'Note $step · $pitch $value';
  }

  @override
  String get melodyOctaveLower => 'Octave down';

  @override
  String get melodyOctaveHigher => 'Octave up';

  @override
  String get melodyValueTooLong =>
      'Longer than the bar — pick a shorter value.';

  @override
  String get melodyValueOverflow =>
      'This bar is already longer than its meter allows.';

  @override
  String get melodyTie => 'Tie';

  @override
  String get melodyUntie => 'Untie';

  @override
  String get melodyRemove => 'Remove note';

  @override
  String get melodyTapBeatHint => 'Tap the chart to change the beat.';

  @override
  String get viewerNote => 'Note';

  @override
  String get viewerChord => 'Chord';

  @override
  String get formGroupBar => 'BAR';

  @override
  String get formGroupRepeat => 'REPEAT';

  @override
  String get formGroupMarks => 'MARKS';

  @override
  String get formGroupSection => 'SECTION';

  @override
  String get formBarBefore => 'Bar before';

  @override
  String get formBarAfter => 'Bar after';

  @override
  String get formDuplicateBar => 'Duplicate bar';

  @override
  String get formDeleteBar => 'Delete bar';

  @override
  String get formRepeatStart => 'Repeat start';

  @override
  String get formRepeatEnd => 'Repeat end';

  @override
  String formPreviousLabel(String state) {
    return 'Previous: $state';
  }

  @override
  String formEndingLabel(String state) {
    return 'Ending: $state';
  }

  @override
  String get formSectionBefore => 'Section before';

  @override
  String get formSectionAfter => 'Section after';

  @override
  String get formDuplicateSection => 'Duplicate section';

  @override
  String get formRenameSection => 'Rename section';

  @override
  String get moveEarlier => 'Move earlier';

  @override
  String get moveLater => 'Move later';

  @override
  String get formDeleteSection => 'Delete section';

  @override
  String get formNoBarSelected => 'No bar selected';

  @override
  String formPosition(int bar, String section) {
    return 'Bar $bar · section $section';
  }

  @override
  String get formBarGone => 'The selected bar is no longer in the song.';

  @override
  String formDetail(int bar, int bars, int section, int sections) {
    return 'bar $bar of $bars in this section · section $section of $sections';
  }

  @override
  String get formRefusedDefault =>
      'Nothing changed: that operation is not possible here.';

  @override
  String get formBarInsertedBefore => 'Inserted a bar before.';

  @override
  String get formBarInsertedAfter => 'Inserted a bar after.';

  @override
  String get formNoSuchBarInsert =>
      'Nothing was inserted: the song has no such bar.';

  @override
  String get formBarDuplicated => 'Duplicated this bar.';

  @override
  String get formNoSuchBarCopy =>
      'Nothing was copied: the song has no such bar.';

  @override
  String get formBarDeleted => 'Deleted this bar.';

  @override
  String get formLastBarRefused =>
      'Nothing was deleted: a section keeps at least one bar, or it could not be shown or selected.';

  @override
  String get formRepeatStartSet => 'Repeat start set.';

  @override
  String get formRepeatStartCleared => 'Repeat start cleared.';

  @override
  String get formBarlineSame =>
      'Nothing changed: the bar already carries that barline.';

  @override
  String get formRepeatEndSet => 'Repeat end set.';

  @override
  String get formRepeatEndCleared => 'Repeat end cleared.';

  @override
  String formRepeatPreviousStatus(String state) {
    return 'Repeat previous: $state.';
  }

  @override
  String get formSymbolSame =>
      'Nothing changed: the bar already carries that symbol.';

  @override
  String get formEndingRemoved => 'Ending bracket removed.';

  @override
  String formEndingSetTo(String volta) {
    return 'Ending bracket set to $volta';
  }

  @override
  String get formBracketSame =>
      'Nothing changed: the bar already carries that bracket.';

  @override
  String formMarkSet(String mark) {
    return '$mark set.';
  }

  @override
  String formMarkCleared(String mark) {
    return '$mark cleared.';
  }

  @override
  String get formSignPresent =>
      'Nothing changed: the bar already carries that sign.';

  @override
  String get formSignAbsent =>
      'Nothing changed: the bar does not carry that sign.';

  @override
  String get formSectionInsertedBefore => 'Inserted a new section before.';

  @override
  String get formSectionInsertedAfter => 'Inserted a new section after.';

  @override
  String get formNoSuchSectionInsert =>
      'Nothing was inserted: the song has no such section.';

  @override
  String get formSectionDuplicated => 'Duplicated this section.';

  @override
  String get formNoSuchSectionCopy =>
      'Nothing was copied: the song has no such section.';

  @override
  String get formSectionMovedEarlier => 'Moved this section earlier.';

  @override
  String get formSectionMovedLater => 'Moved this section later.';

  @override
  String get formSectionAtEnd =>
      'Nothing moved: the section is already at that end of the form.';

  @override
  String get formSectionDeleted => 'Deleted this section.';

  @override
  String get formLastSectionRefused =>
      'Nothing was deleted: a song keeps at least one section, or there would be nothing left to show.';

  @override
  String formSectionRenamed(String name) {
    return 'Renamed this section to \"$name\".';
  }

  @override
  String get formNameSame =>
      'Nothing was renamed: it already carries that name.';

  @override
  String get formVoltaNone => 'none';

  @override
  String get formVoltaUnnumbered => 'unnumbered';

  @override
  String get formRepeatPreviousOff => 'off';

  @override
  String get formRepeatPreviousOneBar => '1 bar';

  @override
  String get formRepeatPreviousTwoBars => '2 bars';

  @override
  String get formRenameLabel => 'Rehearsal letter or name';

  @override
  String get formRenameHelper => 'A single letter becomes a rehearsal letter.';

  @override
  String get formRenameButton => 'Rename';

  @override
  String get formEndingTitle => 'Alternative ending';

  @override
  String get formNoBracket => 'No bracket';

  @override
  String get formUnnumberedBracket => 'Unnumbered [';

  @override
  String get markSegno => 'Segno';

  @override
  String get markCoda => 'Coda';

  @override
  String get markFermata => 'Fermata';

  @override
  String get markPlayerEnding => 'Player end';

  @override
  String get cueGroupThisBar => 'THIS BAR';

  @override
  String get cueGroupTheCue => 'THE CUE';

  @override
  String get cueWriteWords => 'Write words here';

  @override
  String get cuePreviousBar => 'Previous bar';

  @override
  String get cueNextBar => 'Next bar';

  @override
  String get cueSaveWords => 'Save words';

  @override
  String get cueBarEarlier => 'A bar earlier';

  @override
  String get cueBarLater => 'A bar later';

  @override
  String get cueUpLine => 'Up a line';

  @override
  String get cueDownLine => 'Down a line';

  @override
  String get cueRemove => 'Remove the cue';

  @override
  String cuePosition(int bar) {
    return 'Words · bar $bar';
  }

  @override
  String cueDetail(int bar, int bars, String place, String cues) {
    return 'bar $bar of $bars in this section · $place · $cues here';
  }

  @override
  String cueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cues',
      one: '$count cue',
    );
    return '$_temp0';
  }

  @override
  String get cueWholeBar => 'whole bar';

  @override
  String cueCell(int cell) {
    return 'cell $cell';
  }

  @override
  String get cueRefusedDefault => 'Nothing changed: that is not possible here.';

  @override
  String get cueAdded => 'Added a cue.';

  @override
  String get cueNoSuchBarAdd => 'Nothing was added: the song has no such bar.';

  @override
  String get cueAddedTypeWords => 'Added a cue — type the words.';

  @override
  String get cueNothingHappened => 'Nothing happened.';

  @override
  String get cueNoSelectionSave => 'Nothing was saved: no cue is selected.';

  @override
  String get cueWordsSaved => 'Saved the words.';

  @override
  String get cueSameWords => 'Nothing changed: the cue already says that.';

  @override
  String get cueNoSelectionRemove => 'Nothing was removed: no cue is selected.';

  @override
  String get cueRemoved => 'Removed the cue.';

  @override
  String get cueAlreadyGone => 'Nothing was removed: the cue is already gone.';

  @override
  String get cueNoSelectionMove => 'Nothing moved: no cue is selected.';

  @override
  String get cueEndOfSong => 'Nothing moved: that is the end of the song.';

  @override
  String get cueMovedEarlier => 'Moved the cue a bar earlier.';

  @override
  String get cueMovedLater => 'Moved the cue a bar later.';

  @override
  String get cueAlreadyThere => 'Nothing moved: the cue is already there.';

  @override
  String get cueNudgedUp => 'Nudged the cue up.';

  @override
  String get cueNudgedDown => 'Nudged the cue down.';

  @override
  String get cueNothingMoved => 'Nothing moved.';

  @override
  String cueNowOnBar(int bar) {
    return 'Now on bar $bar.';
  }

  @override
  String get cueNoneHere => 'No words on this bar yet.';

  @override
  String get cueNoWordsYet => '(no words yet)';

  @override
  String get cueWordsLabel => 'The words';

  @override
  String get cueWordsHelper =>
      'For example: To Coda · D.C. al Fine · Solo · Vamp · 4×';

  @override
  String get setlistSheetTitle => 'Programme';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get setlistNameLabel => 'Programme name';

  @override
  String setlistMissingCharts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count entries name a chart this library does not hold. The programme keeps them; the chart is not here to play.',
      one:
          '$count entry names a chart this library does not hold. The programme keeps it; the chart is not here to play.',
    );
    return '$_temp0';
  }

  @override
  String get setlistEmpty =>
      'The programme is empty.\nAdd a chart from the library.';

  @override
  String get setlistAddChart => 'Add a chart to the programme';

  @override
  String get setlistAddChartTitle => 'Add a chart';

  @override
  String get setlistPlayTooltip => 'Play this chart from the programme';

  @override
  String get setlistEntryTooltip => 'How this entry is played';

  @override
  String get setlistRemoveTooltip => 'Remove from the programme';

  @override
  String get setlistTranspositionHint =>
      'Transposition for this entry (the chart keeps its written key)';

  @override
  String get setlistNotesLabel => 'Note for the performer';

  @override
  String setlistEntrySubtitle(String interval, String notes) {
    return '$interval · $notes';
  }

  @override
  String setlistSongSubtitle(String key, String bars) {
    return '$key · $bars';
  }

  @override
  String get untitledProgramme => 'Untitled programme';

  @override
  String get setlistMissingChart => '(missing chart)';

  @override
  String get formGroupMeter => 'METER';

  @override
  String formMeterLabel(String meter) {
    return 'Meter: $meter';
  }

  @override
  String get formMeterTitle => 'Bar meter M/N';

  @override
  String get formMeterNumerator => 'Numerator M';

  @override
  String get formMeterDenominator => 'Denominator N';

  @override
  String get formMeterHelper => 'Two whole numbers, for example 15/8.';

  @override
  String get formMeterApply => 'Set';

  @override
  String formMeterSet(String meter, String range) {
    return 'Meter $meter set on $range.';
  }

  @override
  String get formMeterSame =>
      'Nothing changed: every bar in the range is already in that meter.';

  @override
  String get formMeterNone => 'none';

  @override
  String get formZoneFrom => 'From bar';

  @override
  String get formZoneTo => 'To bar';

  @override
  String get formZoneHelper => 'Bars of this section, counted from its first.';

  @override
  String get formZoneErrorEmpty => 'Type a bar number in both boxes.';

  @override
  String get formZoneErrorNotAnInteger =>
      'Bar numbers are whole numbers written in digits.';

  @override
  String formZoneErrorOutOfRange(int bars) {
    return 'This section has $bars bar(s).';
  }

  @override
  String get formZoneErrorReversed =>
      'The first bar must not come after the last one.';

  @override
  String get formZoneErrorNoSection => 'That range is not inside this section.';

  @override
  String get formMeterErrorEmpty => 'Type a whole number in both boxes.';

  @override
  String get formMeterErrorNotAnInteger =>
      'Both figures are whole numbers written in digits.';

  @override
  String get formMeterErrorNotPositive =>
      'Both figures must be greater than zero.';

  @override
  String formMeterErrorTooLarge(int max) {
    return 'Too large: each figure is at most $max.';
  }

  @override
  String get paletteSymbolLabel => 'Type the chord';

  @override
  String get paletteSymbolHelper => 'Dm7 · G7 · Cmaj7 · F#7#11';

  @override
  String get paletteSymbolApply => 'Write';

  @override
  String get paletteSymbolErrorEmpty => 'Type a chord symbol, for example Dm7.';

  @override
  String paletteSymbolErrorNotANoteLetter(String character) {
    return 'A chord starts with a note letter A to G. \"$character\" is not one.';
  }

  @override
  String get paletteSymbolErrorUnclosedBracket =>
      'A bracket was opened and not closed.';

  @override
  String get paletteSymbolErrorBadBass =>
      'After the slash write a note letter, for example Cmaj7/A.';

  @override
  String get paletteSymbolErrorBadAccidental =>
      'A root takes at most two sharps or two flats.';

  @override
  String get paletteSymbolErrorCellNotWritable =>
      'This cell cannot hold a chord: the beat is outside the bar.';

  @override
  String get formGroupStaff => 'STAFF';

  @override
  String get formStaffMelodyOn => 'Melody staff: on';

  @override
  String get formStaffMelodyOff => 'Melody staff: off';

  @override
  String get formStaffMelodyShown =>
      'The staff is drawn on every bar of the chart, empty or not.';

  @override
  String get formStaffMelodyHidden =>
      'Turn the staff on to write notes. What is already written is kept.';

  @override
  String get melodyTapStaffHint =>
      'Touch a beat of the staff to write its note.';
}
