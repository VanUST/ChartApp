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
  String get openHtmlFile => 'Open .html file';

  @override
  String get iRealHtmlFileLabel => 'iReal .html file';

  @override
  String get load => 'Load';

  @override
  String promptFilePath(String path) {
    return 'Load an iReal .html file to see its songs.\nDefault: $path';
  }

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
}
