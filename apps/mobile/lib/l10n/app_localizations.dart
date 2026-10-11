import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// The application title in the app bar on a surface wide enough for two words.
  ///
  /// In en, this message translates to:
  /// **'ChartApp — iReal reader'**
  String get appTitle;

  /// The button that opens the browser's file chooser for an iReal export.
  ///
  /// In en, this message translates to:
  /// **'Open .html file'**
  String get openHtmlFile;

  /// The label of the text field holding the path to an iReal export.
  ///
  /// In en, this message translates to:
  /// **'iReal .html file'**
  String get iRealHtmlFileLabel;

  /// The button that loads the file named in the path field.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// The empty state on a platform where a path names the file.
  ///
  /// In en, this message translates to:
  /// **'Load an iReal .html file to see its songs.\nDefault: {path}'**
  String promptFilePath(String path);

  /// The empty state in a browser, where no path exists.
  ///
  /// In en, this message translates to:
  /// **'Open an iReal .html file exported from iReal Pro.\nIt is read in the browser and is not uploaded.'**
  String get promptWeb;

  /// Shown when a parsed export contains no songs at all.
  ///
  /// In en, this message translates to:
  /// **'The payload carried no songs.'**
  String get payloadNoSongs;

  /// The name shown for a chart whose title is empty. Never data: it is the interface's own fallback.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// The status bar before anything at all has been loaded.
  ///
  /// In en, this message translates to:
  /// **'No file loaded.'**
  String get noFileLoaded;

  /// How many songs a loaded library holds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} song} other{{count} songs}}'**
  String songCount(int count);

  /// The status bar with a named playlist.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} song} other{{count} songs}} · playlist \"{name}\"'**
  String statusSongsPlaylist(int count, String name);

  /// The song drawer's header with a named playlist.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} song} other{{count} songs}} · \"{name}\"'**
  String drawerSongsPlaylist(int count, String name);

  /// How many bars a chart has. Russian needs three written forms here.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} bar} other{{count} bars}}'**
  String barCount(int count);

  /// How many import issues a song produced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} issue} other{{count} issues}}'**
  String issueCount(int count);

  /// The tooltip on the song title, which opens the song-info sheet.
  ///
  /// In en, this message translates to:
  /// **'Song info: title, composer, style and tempo'**
  String get songInfoTooltip;

  /// The heading of the song-info sheet.
  ///
  /// In en, this message translates to:
  /// **'Song info'**
  String get songInfoSheetTitle;

  /// The heading of the import-issue list for one song.
  ///
  /// In en, this message translates to:
  /// **'Import issues — {title}'**
  String issuesTitle(String title);

  /// One import issue: where in the file it was found, and what the importer said.
  ///
  /// In en, this message translates to:
  /// **'@{offset}: {message}'**
  String issueLine(int offset, String message);

  /// The button that dismisses a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// The button that closes a sheet, keeping what was applied.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// The button that dismisses a picker without applying anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// The pen toggle's tooltip while drawing is on.
  ///
  /// In en, this message translates to:
  /// **'Drawing: the pen draws, a finger still selects'**
  String get tooltipInkOn;

  /// The pen toggle's tooltip while drawing is off and the eraser is on.
  ///
  /// In en, this message translates to:
  /// **'Pen off: the eraser is on'**
  String get tooltipInkOffEraserOn;

  /// The pen toggle's tooltip while drawing is off.
  ///
  /// In en, this message translates to:
  /// **'Selecting: the pen and a finger both select'**
  String get tooltipInkOff;

  /// The eraser toggle's tooltip while erasing is on.
  ///
  /// In en, this message translates to:
  /// **'Erasing: tap a stroke and its whole length goes'**
  String get tooltipEraserOn;

  /// The eraser toggle's tooltip while erasing is off.
  ///
  /// In en, this message translates to:
  /// **'Eraser off'**
  String get tooltipEraserOff;

  /// The undo button's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Undo the last chart edit'**
  String get tooltipUndo;

  /// The redo button's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Redo the last undone chart edit'**
  String get tooltipRedo;

  /// The tooltip of the button that opens the bars-and-sections sheet.
  ///
  /// In en, this message translates to:
  /// **'Bars and sections (the form)'**
  String get tooltipForm;

  /// The tooltip of the button that opens the text-cue sheet.
  ///
  /// In en, this message translates to:
  /// **'Words on the chart (To Coda, Solo, 4×)'**
  String get tooltipCues;

  /// The tooltip of the button that opens the programme sheet.
  ///
  /// In en, this message translates to:
  /// **'Programme (setlist): order, transpose and play the charts'**
  String get tooltipSetlist;

  /// The tooltip of the button that opens the settings sheet.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// The phone app bar's overflow menu button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Chart, form and programme'**
  String get tooltipOverflowMenu;

  /// The overflow menu row that opens the bars-and-sections sheet.
  ///
  /// In en, this message translates to:
  /// **'Bars and sections'**
  String get menuForm;

  /// The overflow menu row that opens the text-cue sheet.
  ///
  /// In en, this message translates to:
  /// **'Words on the chart'**
  String get menuCues;

  /// The overflow menu row that opens the programme sheet.
  ///
  /// In en, this message translates to:
  /// **'Programme (setlist)'**
  String get menuSetlist;

  /// The overflow menu row and app-bar action for the chart file dialog.
  ///
  /// In en, this message translates to:
  /// **'Save or open a .chart file'**
  String get menuChartFile;

  /// The overflow menu row that opens the settings sheet.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// The selection line before anything is selected.
  ///
  /// In en, this message translates to:
  /// **'Tap a bar to select it.'**
  String get selectionPrompt;

  /// The selection line when the touch landed on a bar and not on a cell.
  ///
  /// In en, this message translates to:
  /// **'selected: bar {bar} (whole bar)'**
  String selectionBar(int bar);

  /// The selection line for a chosen cell. Both numbers are one-based, the way a musician counts.
  ///
  /// In en, this message translates to:
  /// **'selected: bar {bar} cell {cell}'**
  String selectionBarCell(int bar, int cell);

  /// The hint beside the selection line when the selection is a cell.
  ///
  /// In en, this message translates to:
  /// **'— tap to change the chord'**
  String get selectionHintChord;

  /// The hint beside the selection line when the selection is a whole bar.
  ///
  /// In en, this message translates to:
  /// **'— tap for bars & sections'**
  String get selectionHintForm;

  /// Shown in place of a page when the chart has nothing to engrave.
  ///
  /// In en, this message translates to:
  /// **'This song has no bars.'**
  String get noBars;

  /// The strip pinned over the chart when the automatic FIT request could not be honoured.
  ///
  /// In en, this message translates to:
  /// **'This song does not fit on one page at the {percent}% legible floor. Shown as pages instead.'**
  String fitFallbackAuto(int percent);

  /// The same strip after an explicit FIT press, answered in the second person.
  ///
  /// In en, this message translates to:
  /// **'You asked for one page, but at the {percent}% legible floor it needs more. Shown as pages instead.'**
  String fitFallbackExplicit(int percent);

  /// The scene bar's caption over the running-order position.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get sceneCaptionPos;

  /// The scene bar's caption over the tempo.
  ///
  /// In en, this message translates to:
  /// **'BPM'**
  String get sceneCaptionBpm;

  /// The scene bar's caption over the style.
  ///
  /// In en, this message translates to:
  /// **'STYLE'**
  String get sceneCaptionStyle;

  /// The key badge's caption in the scene bar's narrow form.
  ///
  /// In en, this message translates to:
  /// **'KEY'**
  String get sceneCaptionKeyCompact;

  /// The key badge's caption in the scene bar's full form, naming the gesture.
  ///
  /// In en, this message translates to:
  /// **'KEY · tap to transpose'**
  String get sceneCaptionKeyFull;

  /// The scene bar's caption over the repeat summary.
  ///
  /// In en, this message translates to:
  /// **'REPEATS'**
  String get sceneCaptionRepeats;

  /// The scene bar's caption over the page-mode toggle.
  ///
  /// In en, this message translates to:
  /// **'PAGE'**
  String get sceneCaptionPage;

  /// The page-mode toggle's label for one page fitted to the surface.
  ///
  /// In en, this message translates to:
  /// **'FIT'**
  String get sceneModeFit;

  /// The page-mode toggle's label for the song paginated.
  ///
  /// In en, this message translates to:
  /// **'PAGES'**
  String get sceneModePages;

  /// The tooltip of the narrow scene bar's control for the two deferred readings.
  ///
  /// In en, this message translates to:
  /// **'Style and repeats'**
  String get sceneDeferredTooltip;

  /// The deferred-readings menu row naming the style.
  ///
  /// In en, this message translates to:
  /// **'STYLE · {style}'**
  String sceneDeferredStyleRow(String style);

  /// The deferred-readings menu row naming the repeat summary.
  ///
  /// In en, this message translates to:
  /// **'REPEATS · {repeats}'**
  String sceneDeferredRepeatsRow(String repeats);

  /// The repeat summary for a chart that carries no repeat sign at all.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get repeatNone;

  /// How many bars start a repeated passage. The multiplication sign is the notation, not a word.
  ///
  /// In en, this message translates to:
  /// **'{count}×'**
  String repeatPassages(int count);

  /// How many alternative endings the chart brackets. English writes 'volta' for every count; Russian does not.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} volta} other{{count} volta}}'**
  String repeatVoltas(int count);

  /// How many bars carry the repeat-previous sign.
  ///
  /// In en, this message translates to:
  /// **'{count} %'**
  String repeatPrevious(int count);

  /// The key the chart is shown in, then the distance from the written key.
  ///
  /// In en, this message translates to:
  /// **'{key} · {interval}'**
  String keyBadgeLabel(String key, String interval);

  /// A signed interval in semitones, as a musician abbreviates it.
  ///
  /// In en, this message translates to:
  /// **'{signed} st'**
  String semitonesShort(String signed);

  /// The twelve-key grid's heading.
  ///
  /// In en, this message translates to:
  /// **'Transpose — written in {writtenKey}'**
  String keyGridTitle(String writtenKey);

  /// The interval label of the key the chart is written in.
  ///
  /// In en, this message translates to:
  /// **'written'**
  String get keyGridWritten;

  /// Shown on a key a chart in this written key has no practical spelling for.
  ///
  /// In en, this message translates to:
  /// **'not spellable'**
  String get keyGridNotSpellable;

  /// A major key named for a reader. The tonic letter is the chart's own notation and is not translated; the mode word is.
  ///
  /// In en, this message translates to:
  /// **'{tonic} major'**
  String keyNameMajor(String tonic);

  /// A minor key named for a reader, on the same rule as keyNameMajor.
  ///
  /// In en, this message translates to:
  /// **'{tonic} minor'**
  String keyNameMinor(String tonic);

  /// The settings sheet's heading.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// The caption over the language choices.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageHeading;

  /// The language choice that follows whatever the device is set to.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get settingsFollowSystem;

  /// The name of English, written in English so it is readable either way.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsEnglish;

  /// The name of Russian, written in Russian so it is readable either way.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get settingsRussian;

  /// Says where the language choice lives on a platform with a filesystem.
  ///
  /// In en, this message translates to:
  /// **'The choice is remembered on this device. It is a setting, not part of your charts.'**
  String get settingsStorageNote;

  /// Says where the language choice lives in a browser, and what losing it costs.
  ///
  /// In en, this message translates to:
  /// **'The choice is remembered in this browser\'s storage. Safari clears that storage after seven days without use, and the language then follows the device again. Your charts are files and are never affected.'**
  String get settingsStorageNoteWeb;

  /// The confirmation shown after the language is switched.
  ///
  /// In en, this message translates to:
  /// **'Language: {language}'**
  String languageChanged(String language);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
