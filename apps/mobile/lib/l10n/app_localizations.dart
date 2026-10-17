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

  /// The button and tooltip that opens the operating system's own file chooser, shown beside the path field on a desktop where a typed path is offered as well.
  ///
  /// In en, this message translates to:
  /// **'Choose a file…'**
  String get chooseFile;

  /// The button that opens the platform's own file chooser for an iReal export, on a platform that offers no path field.
  ///
  /// In en, this message translates to:
  /// **'Open .html file'**
  String get openHtmlFile;

  /// The label of the text field holding the path to an iReal export. Shown on a desktop only.
  ///
  /// In en, this message translates to:
  /// **'iReal .html file'**
  String get iRealHtmlFileLabel;

  /// The button that loads the file named in the path field.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// The empty state on a desktop, where the export can be named by a typed path or picked in the system chooser.
  ///
  /// In en, this message translates to:
  /// **'Open an iReal .html file exported from iReal Pro.\nType its path, or choose it with the button above.'**
  String get promptNativePath;

  /// The empty state on a hand-held, where the system's own file chooser is the only way to the export and no path can be typed.
  ///
  /// In en, this message translates to:
  /// **'Open an iReal .html file exported from iReal Pro.\nThe file stays on this device.'**
  String get promptNativeChooser;

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

  /// The action that starts a chart from scratch. It stands in the empty state, in the `.chart` dialog and in the phone overflow menu, and it is also the title of the dialog it opens.
  ///
  /// In en, this message translates to:
  /// **'New chart'**
  String get newChart;

  /// What the new-chart dialog says about the chart it is about to make, and why it asks for two things here. The bar count is passed as an already-worded plural so the number and the catalogue's own bar wording cannot drift apart; the claim about the key and the meter being unchangeable is a fact about the editor and must be corrected here when the editor gains those controls.
  ///
  /// In en, this message translates to:
  /// **'A new chart starts as one section of {bars}. Choose a key and a meter — the editor cannot change either afterwards.'**
  String newChartIntro(String bars);

  /// The caption above the row of meters a new chart can start in.
  ///
  /// In en, this message translates to:
  /// **'Meter'**
  String get newChartMeterLabel;

  /// The caption above the key a new chart is written in: the mode switch and the twelve tonics under it.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get newChartKeyLabel;

  /// The mode switch's major half in the new-chart dialog. NOT TRANSLATED - `Major` is how the mode is written in any language, and a Russian `Мажор` beside an English `C major` key name would show the same fact two ways. See D27.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get newChartMajor;

  /// The mode switch's minor half in the new-chart dialog. NOT TRANSLATED, on the same rule as newChartMajor.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get newChartMinor;

  /// The button that makes the new chart with the key and meter chosen beside it.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

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
  /// **'Erasing: touch a stroke or drag across it, and its whole length goes'**
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
  /// **'KEY'**
  String get sceneCaptionKeyFull;

  /// Tooltip of the lock button while the scale is free: pressing it fixes the scale so nothing can zoom, pan or re-engrave the chart at a different size.
  ///
  /// In en, this message translates to:
  /// **'Fix the scale'**
  String get tooltipViewLockOff;

  /// Tooltip of the lock button while the scale is fixed: pressing it releases the lock.
  ///
  /// In en, this message translates to:
  /// **'Release the fixed scale'**
  String get tooltipViewLockOn;

  /// Tooltip of the three МАСШТАБ buttons while the scale is locked and they cannot answer.
  ///
  /// In en, this message translates to:
  /// **'The scale is fixed'**
  String get zoomLockedTooltip;

  /// One sentence in the selection line while the view lock is on and nothing is selected, saying what the lock covers and how to leave it.
  ///
  /// In en, this message translates to:
  /// **'The scale is fixed: nothing can zoom, pan or re-scale the chart. Press the padlock to release it.'**
  String get viewLockActiveHint;

  /// Tooltip of the key badge in the scene bar; the instruction the full form's caption used to carry.
  ///
  /// In en, this message translates to:
  /// **'Tap to transpose'**
  String get keyBadgeTooltip;

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

  /// The scene bar's caption over the zoom control. The magnification itself is a multiplication sign and a number, which is notation and is not translated.
  ///
  /// In en, this message translates to:
  /// **'ZOOM'**
  String get sceneCaptionZoom;

  /// The tooltip of the scene bar's button that magnifies the chart one step.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomInTooltip;

  /// The tooltip of the scene bar's button that shrinks the chart one step, without going below the page mode's own view.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOutTooltip;

  /// The tooltip of the scene bar's middle zoom button, which returns the chart to the view its page mode gives it — the way back after a two-finger pan.
  ///
  /// In en, this message translates to:
  /// **'Back to the whole page'**
  String get zoomResetTooltip;

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

  /// A signed interval in semitones, as a musician abbreviates it. NOT TRANSLATED - `st` is the abbreviation in any language; the Russian catalogue carries the same string. See D27.
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

  /// A major key named for a reader. NEITHER THE TONIC LETTER NOR THE MODE WORD IS TRANSLATED: a musician writes and reads `A major` in every language, and `A минор` is a chart no other musician would recognise as notation. The Russian catalogue carries the SAME string on purpose - see A53 for the rule and D27 for the owner's decision. Do not translate this row; translating it was the defect.
  ///
  /// In en, this message translates to:
  /// **'{tonic} major'**
  String keyNameMajor(String tonic);

  /// A minor key named for a reader, on the same rule as keyNameMajor: the whole name is notation and is NOT translated.
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

  /// The button that writes a document to a file, shared by the song-info sheet and both file dialogs.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// The confirming button of the programme sheet's entry-edit dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// The file dialogs' field label in a browser, where the field holds a name to offer the chooser rather than a path.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get fileNameLabel;

  /// The status a file dialog shows when the write threw. The error text is the platform's own description and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String fileSaveFailed(String error);

  /// The status a file dialog shows when the read or the decode threw. The error text is the platform's or the container's own description and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Could not open: {error}'**
  String fileOpenFailed(String error);

  /// What a file dialog says after the reader dismissed the platform's file chooser. The dialog words the outcome from this catalogue rather than from the exception, because changing one's mind is an outcome and not a fault.
  ///
  /// In en, this message translates to:
  /// **'No file was chosen.'**
  String get fileChooserCancelled;

  /// The tail of a file dialog's status: how many warnings the container's codec produced, and the first of them. The codec's own message is a diagnostic the container wrote and is not translated.
  ///
  /// In en, this message translates to:
  /// **' {warnings}: {message}'**
  String fileWarningSuffix(String warnings, String message);

  /// How many bytes a container wrote, as a file dialog reports it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} byte} other{{count} bytes}}'**
  String byteCount(int count);

  /// How many log operations a container carries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} operation} other{{count} operations}}'**
  String operationCount(int count);

  /// How many warnings a container's codec produced.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} warning} other{{count} warnings}}'**
  String warningCount(int count);

  /// How many running-order entries a programme holds. Russian needs three written forms here.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} entry} other{{count} entries}}'**
  String entryCount(int count);

  /// The title of the `.chart` save/open dialog.
  ///
  /// In en, this message translates to:
  /// **'Chart file'**
  String get chartFileDialogTitle;

  /// The `.chart` dialog's field label on a platform where the field holds a path that addresses the file.
  ///
  /// In en, this message translates to:
  /// **'.chart file'**
  String get chartFileLabelPath;

  /// The `.chart` dialog's button that reads the named file.
  ///
  /// In en, this message translates to:
  /// **'Open .chart'**
  String get chartFileOpenButton;

  /// What the `.chart` dialog says when Save is pressed with no document on screen.
  ///
  /// In en, this message translates to:
  /// **'Load or import a song before saving it.'**
  String get chartFileNoDocument;

  /// What the `.chart` dialog says when Save is pressed with an empty field.
  ///
  /// In en, this message translates to:
  /// **'Name a .chart file to save to.'**
  String get chartFileNameToSave;

  /// What the `.chart` dialog says when Open is pressed with an empty field on a platform where the field is a path.
  ///
  /// In en, this message translates to:
  /// **'Name a .chart file to open.'**
  String get chartFileNameToOpen;

  /// The `.chart` dialog's success line on a platform where the field names a destination path.
  ///
  /// In en, this message translates to:
  /// **'Saved {bytes} to {path} · {operations}.'**
  String chartFileSavedTo(String bytes, String path, String operations);

  /// The `.chart` dialog's success line in a browser, where the save hands the reader a file rather than writing a path.
  ///
  /// In en, this message translates to:
  /// **'Saved {bytes} as {path} · {operations}.'**
  String chartFileSavedAs(String bytes, String path, String operations);

  /// The `.chart` dialog's success line after a file was read and handed to the viewer.
  ///
  /// In en, this message translates to:
  /// **'Opened \"{title}\" · {operations}.'**
  String chartFileOpened(String title, String operations);

  /// The tail of a file dialog's success line where the platform's own save dialog chose the destination and will ask again next time.
  ///
  /// In en, this message translates to:
  /// **'Each Save asks where to put the file.'**
  String get saveModeChosenLocation;

  /// The tail of a file dialog's success line where the browser can overwrite the file it already has a handle on.
  ///
  /// In en, this message translates to:
  /// **'This browser re-writes that file in place, so the next Save updates it.'**
  String get saveModeRewriteInPlace;

  /// The tail of a file dialog's success line where every save produces a fresh download.
  ///
  /// In en, this message translates to:
  /// **'This browser cannot update a file in place, so each Save downloads a NEW copy.'**
  String get saveModeDownload;

  /// The `.chart` dialog's up-front promise on a hand-held, where a save must go through the operating system's save dialog.
  ///
  /// In en, this message translates to:
  /// **'This device has no file path you can type, so Save opens the system\'s own file chooser, where you pick the folder and the name.'**
  String get chartFileSaveHintChosenLocation;

  /// The `.chart` dialog's up-front promise on a browser with the File System Access API.
  ///
  /// In en, this message translates to:
  /// **'This browser can re-write a chart file it has already been given. The first Save asks where to put the file; every Save after that updates that same file.'**
  String get chartFileSaveHintRewriteInPlace;

  /// The `.chart` dialog's up-front promise on a browser that can only download.
  ///
  /// In en, this message translates to:
  /// **'This browser cannot re-write a file in place, so every Save downloads a NEW copy. The browser chooses where it lands, and may rename it when a file of that name is already there.'**
  String get chartFileSaveHintDownload;

  /// The tooltip of the programme sheet's app-bar-shaped `.setlist` control.
  ///
  /// In en, this message translates to:
  /// **'Save or open a .setlist file'**
  String get setlistFileTooltip;

  /// The title of the `.setlist` save/open dialog.
  ///
  /// In en, this message translates to:
  /// **'Programme file'**
  String get setlistFileDialogTitle;

  /// The `.setlist` dialog's field label on a platform where the field holds a path.
  ///
  /// In en, this message translates to:
  /// **'.setlist file'**
  String get setlistFileLabelPath;

  /// The `.setlist` dialog's button that reads the named file.
  ///
  /// In en, this message translates to:
  /// **'Open .setlist'**
  String get setlistFileOpenButton;

  /// What the `.setlist` dialog says when Save is pressed with an empty field.
  ///
  /// In en, this message translates to:
  /// **'Name a .setlist file to save to.'**
  String get setlistFileNameToSave;

  /// What the `.setlist` dialog says when Open is pressed with an empty field on a platform where the field is a path.
  ///
  /// In en, this message translates to:
  /// **'Name a .setlist file to open.'**
  String get setlistFileNameToOpen;

  /// The `.setlist` dialog's success line on a platform where the field names a destination path.
  ///
  /// In en, this message translates to:
  /// **'Saved {bytes} to {path} · {entries} · {operations}.'**
  String setlistFileSavedTo(
    String bytes,
    String path,
    String entries,
    String operations,
  );

  /// The `.setlist` dialog's success line in a browser.
  ///
  /// In en, this message translates to:
  /// **'Saved {bytes} as {path} · {entries} · {operations}.'**
  String setlistFileSavedAs(
    String bytes,
    String path,
    String entries,
    String operations,
  );

  /// The `.setlist` dialog's up-front promise on a hand-held, where a save must go through the operating system's save dialog.
  ///
  /// In en, this message translates to:
  /// **'This device has no file path you can type, so Save opens the system\'s own file chooser, where you pick the folder and the name.'**
  String get setlistFileSaveHintChosenLocation;

  /// The `.setlist` dialog's up-front promise on a browser with the File System Access API.
  ///
  /// In en, this message translates to:
  /// **'This browser can re-write a setlist file it has already been given. The first Save asks where to put the file; every Save after that updates that same file.'**
  String get setlistFileSaveHintRewriteInPlace;

  /// The `.setlist` dialog's up-front promise on a browser that can only download.
  ///
  /// In en, this message translates to:
  /// **'This browser cannot re-write a file in place, so every Save downloads a NEW copy. The browser chooses where it lands, and may rename it when a file of that name is already there.'**
  String get setlistFileSaveHintDownload;

  /// The `.setlist` dialog's success line after a programme was read and adopted.
  ///
  /// In en, this message translates to:
  /// **'Opened \"{name}\" · {entries}.'**
  String setlistOpened(String name, String entries);

  /// How many of an opened programme's entries name a chart the loaded library does not hold. English writes the same words for every count; Russian agrees the verb with the noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} not found in this library.} other{{count} not found in this library.}}'**
  String missingEntryCount(int count);

  /// The song-info sheet's label for the tune's name.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get metadataTitle;

  /// What the title field of the song-info sheet is for.
  ///
  /// In en, this message translates to:
  /// **'The name a musician reads at the top of the chart.'**
  String get metadataTitleHint;

  /// The song-info sheet's label for who wrote the tune.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get metadataComposer;

  /// What the composer field of the song-info sheet is for, including why its order is not normalised.
  ///
  /// In en, this message translates to:
  /// **'As written; the order is whatever the format stores.'**
  String get metadataComposerHint;

  /// The song-info sheet's label for the style or feel the tune is played in.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get metadataStyle;

  /// What the style field of the song-info sheet is for. The examples are iReal's own style words and are data a musician types, not interface text.
  ///
  /// In en, this message translates to:
  /// **'Free text, such as Medium Swing or Ballad.'**
  String get metadataStyleHint;

  /// The song-info sheet's label for the tempo in beats per minute.
  ///
  /// In en, this message translates to:
  /// **'Tempo (BPM)'**
  String get metadataTempo;

  /// What the tempo field says about the model's zero, when the field holds a number.
  ///
  /// In en, this message translates to:
  /// **'0 means this chart sets no tempo.'**
  String get metadataTempoHelperZero;

  /// What the tempo field asks for, when the field cannot be read as a whole number.
  ///
  /// In en, this message translates to:
  /// **'Whole beats per minute, or 0 for none.'**
  String get metadataTempoHelperHint;

  /// The tempo field's own error line while its text cannot be read as a whole number.
  ///
  /// In en, this message translates to:
  /// **'A tempo is a whole number.'**
  String get metadataTempoError;

  /// The song-info sheet's footer after Save was refused because the tempo is not a number.
  ///
  /// In en, this message translates to:
  /// **'A tempo is a whole number of beats per minute.'**
  String get metadataTempoRefused;

  /// The song-info sheet's footer after Save found every field already equal to the song's own values.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed, so nothing was written to the log.'**
  String get metadataNothingChanged;

  /// The song-info sheet's footer before anything is pressed.
  ///
  /// In en, this message translates to:
  /// **'One edit: the four facts above are written together.'**
  String get metadataFooterHint;

  /// The song-info sheet's footer, in the removal colour, while the tempo cannot be read and Save is disabled.
  ///
  /// In en, this message translates to:
  /// **'Fix the tempo before saving.'**
  String get metadataFooterFixTempo;

  /// The chord palette's header: which bar and which cell it is about to edit, numbered from one across the whole chart.
  ///
  /// In en, this message translates to:
  /// **'Bar {bar} · cell {cell}'**
  String palettePosition(int bar, int cell);

  /// The chord palette's subtitle: the key the roots on the grid are spelled in. The key is named through the catalogue so the mode word is the reader's language and the tonic letter stays the chart's own notation.
  ///
  /// In en, this message translates to:
  /// **'Chords in {key}'**
  String paletteChordsIn(String key);

  /// The chord palette's preview before a root has been tapped.
  ///
  /// In en, this message translates to:
  /// **'Pick a root'**
  String get palettePickRoot;

  /// The chord palette's preview when the edited cell holds no chord.
  ///
  /// In en, this message translates to:
  /// **'This cell is empty.'**
  String get paletteCellEmpty;

  /// The chord the edited cell holds right now, shown beneath the preview of what a tap would write.
  ///
  /// In en, this message translates to:
  /// **'Now: {chord}'**
  String paletteNow(String chord);

  /// The chord palette's destructive button that clears the edited cell.
  ///
  /// In en, this message translates to:
  /// **'Remove chord'**
  String get paletteRemoveChord;

  /// The note palette's caption over the pitch and duration pickers.
  ///
  /// In en, this message translates to:
  /// **'MELODY'**
  String get melodyGroup;

  /// The note palette's caption over the note-value chips.
  ///
  /// In en, this message translates to:
  /// **'DURATION'**
  String get melodyDuration;

  /// The note palette's caption over the row of scale degrees.
  ///
  /// In en, this message translates to:
  /// **'PITCH'**
  String get melodyPitch;

  /// The note palette's caption over the accidental chips.
  ///
  /// In en, this message translates to:
  /// **'ALTERATION'**
  String get melodyAlteration;

  /// The note palette's row that clears the note selection so the next pitch tap writes another note on the same beat.
  ///
  /// In en, this message translates to:
  /// **'+ New note'**
  String get melodyNewNote;

  /// Shown in the note palette when the selection names a bar but no cell, so there is nowhere to place a note yet.
  ///
  /// In en, this message translates to:
  /// **'Tap a beat on the chart to write a note.'**
  String get melodyPickCell;

  /// The note palette's status when the edited beat holds no note. Choosing a pitch inserts the first one.
  ///
  /// In en, this message translates to:
  /// **'This beat carries no note.'**
  String get melodyBeatEmpty;

  /// One note of the edited beat, as the note palette lists it. The step is one-based so that the first note of a beat reads as Note 1. The pitch and the value inside it are NOTATION and are Latin in every language (owner decision A53); only the word Note is interface.
  ///
  /// In en, this message translates to:
  /// **'Note {step} · {pitch} {value}'**
  String melodyNoteLine(int step, String pitch, String value);

  /// The note palette's control that moves the pitch row one octave lower. An ACTION, not notation, so it is translated; the octave's own name in the row is notation and is not in this catalogue.
  ///
  /// In en, this message translates to:
  /// **'Octave down'**
  String get melodyOctaveLower;

  /// The note palette's control that moves the pitch row one octave higher. An action, not notation.
  ///
  /// In en, this message translates to:
  /// **'Octave up'**
  String get melodyOctaveHigher;

  /// Shown when the chosen duration does not fit the edited bar, so the note was not written. A sentence about the interface, so it is translated; the DURATION NAMES the palette offers are notation and are not in this catalogue.
  ///
  /// In en, this message translates to:
  /// **'Longer than the bar — pick a shorter value.'**
  String get melodyValueTooLong;

  /// Shown when the edited bar's existing notes already exceed the bar's length, so the meter and the melody disagree. It reports the state and refuses nothing.
  ///
  /// In en, this message translates to:
  /// **'This bar is already longer than its meter allows.'**
  String get melodyValueOverflow;

  /// The note palette's action that ties the chosen note into the next one.
  ///
  /// In en, this message translates to:
  /// **'Tie'**
  String get melodyTie;

  /// The note palette's action that clears the tie on the chosen note.
  ///
  /// In en, this message translates to:
  /// **'Untie'**
  String get melodyUntie;

  /// The note palette's destructive button that deletes the chosen note.
  ///
  /// In en, this message translates to:
  /// **'Remove note'**
  String get melodyRemove;

  /// The note palette's footer: the chart behind the sheet is still the way to choose another beat.
  ///
  /// In en, this message translates to:
  /// **'Tap the chart to change the beat.'**
  String get melodyTapBeatHint;

  /// The selection line's action that opens the note palette for the chosen beat.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get viewerNote;

  /// The selection line's action that opens the chord palette for the chosen beat, beside the note action.
  ///
  /// In en, this message translates to:
  /// **'Chord'**
  String get viewerChord;

  /// The form sheet's caption over the operations that add, copy and remove one bar.
  ///
  /// In en, this message translates to:
  /// **'BAR'**
  String get formGroupBar;

  /// The form sheet's caption over the repeat barline and alternative-ending controls.
  ///
  /// In en, this message translates to:
  /// **'REPEAT'**
  String get formGroupRepeat;

  /// The form sheet's caption over the four signs a bar can carry.
  ///
  /// In en, this message translates to:
  /// **'MARKS'**
  String get formGroupMarks;

  /// The form sheet's caption over the operations that add, copy, move and remove a section.
  ///
  /// In en, this message translates to:
  /// **'SECTION'**
  String get formGroupSection;

  /// The form sheet's button that inserts a bar in front of the selected one.
  ///
  /// In en, this message translates to:
  /// **'Bar before'**
  String get formBarBefore;

  /// The form sheet's button that inserts a bar behind the selected one.
  ///
  /// In en, this message translates to:
  /// **'Bar after'**
  String get formBarAfter;

  /// The form sheet's button that copies the selected bar behind itself.
  ///
  /// In en, this message translates to:
  /// **'Duplicate bar'**
  String get formDuplicateBar;

  /// The form sheet's destructive button that removes the selected bar.
  ///
  /// In en, this message translates to:
  /// **'Delete bar'**
  String get formDeleteBar;

  /// The form sheet's toggle for the repeat-start barline on the selected bar.
  ///
  /// In en, this message translates to:
  /// **'Repeat start'**
  String get formRepeatStart;

  /// The form sheet's toggle for the repeat-end barline on the selected bar.
  ///
  /// In en, this message translates to:
  /// **'Repeat end'**
  String get formRepeatEnd;

  /// The form sheet's cycle button for the repeat-previous sign, carrying the sign the bar holds now.
  ///
  /// In en, this message translates to:
  /// **'Previous: {state}'**
  String formPreviousLabel(String state);

  /// The form sheet's button that opens the alternative-ending chooser, carrying the bracket the bar holds now.
  ///
  /// In en, this message translates to:
  /// **'Ending: {state}'**
  String formEndingLabel(String state);

  /// The form sheet's button that inserts a section in front of the selected one.
  ///
  /// In en, this message translates to:
  /// **'Section before'**
  String get formSectionBefore;

  /// The form sheet's button that inserts a section behind the selected one.
  ///
  /// In en, this message translates to:
  /// **'Section after'**
  String get formSectionAfter;

  /// The form sheet's button that copies the selected section, with everything in it, behind itself.
  ///
  /// In en, this message translates to:
  /// **'Duplicate section'**
  String get formDuplicateSection;

  /// The form sheet's button that opens the rename box, and the box's own title.
  ///
  /// In en, this message translates to:
  /// **'Rename section'**
  String get formRenameSection;

  /// The button and tooltip that move a section, or a programme entry, one place towards the top.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get moveEarlier;

  /// The button and tooltip that move a section, or a programme entry, one place towards the end.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get moveLater;

  /// The form sheet's destructive button that removes the selected section and its bars.
  ///
  /// In en, this message translates to:
  /// **'Delete section'**
  String get formDeleteSection;

  /// The form sheet's and the text-cue sheet's header when their cursor names no bar in the song.
  ///
  /// In en, this message translates to:
  /// **'No bar selected'**
  String get formNoBarSelected;

  /// The form sheet's header naming the bar and section the next operation acts on.
  ///
  /// In en, this message translates to:
  /// **'Bar {bar} · section {section}'**
  String formPosition(int bar, String section);

  /// The form sheet's and the text-cue sheet's header when their cursor names a bar a form edit removed.
  ///
  /// In en, this message translates to:
  /// **'The selected bar is no longer in the song.'**
  String get formBarGone;

  /// The form sheet's header detail line: how far into its section the cursor's bar is, and where that section sits in the song.
  ///
  /// In en, this message translates to:
  /// **'bar {bar} of {bars} in this section · section {section} of {sections}'**
  String formDetail(int bar, int bars, int section, int sections);

  /// The form sheet's status when an operation was refused and the caller named no reason.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: that operation is not possible here.'**
  String get formRefusedDefault;

  /// The form sheet's status after a bar was inserted in front of the cursor.
  ///
  /// In en, this message translates to:
  /// **'Inserted a bar before.'**
  String get formBarInsertedBefore;

  /// The form sheet's status after a bar was inserted behind the cursor.
  ///
  /// In en, this message translates to:
  /// **'Inserted a bar after.'**
  String get formBarInsertedAfter;

  /// The form sheet's status when an insert was refused because the cursor names no bar.
  ///
  /// In en, this message translates to:
  /// **'Nothing was inserted: the song has no such bar.'**
  String get formNoSuchBarInsert;

  /// The form sheet's status after the selected bar was copied.
  ///
  /// In en, this message translates to:
  /// **'Duplicated this bar.'**
  String get formBarDuplicated;

  /// The form sheet's status when a bar copy was refused because the cursor names no bar.
  ///
  /// In en, this message translates to:
  /// **'Nothing was copied: the song has no such bar.'**
  String get formNoSuchBarCopy;

  /// The form sheet's status after the selected bar was removed.
  ///
  /// In en, this message translates to:
  /// **'Deleted this bar.'**
  String get formBarDeleted;

  /// The form sheet's status when deleting a section's last bar was refused, with the reason.
  ///
  /// In en, this message translates to:
  /// **'Nothing was deleted: a section keeps at least one bar, or it could not be shown or selected.'**
  String get formLastBarRefused;

  /// The form sheet's status after the repeat-start barline was put on the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'Repeat start set.'**
  String get formRepeatStartSet;

  /// The form sheet's status after the repeat-start barline was taken off the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'Repeat start cleared.'**
  String get formRepeatStartCleared;

  /// The form sheet's status when a repeat barline toggle changed nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the bar already carries that barline.'**
  String get formBarlineSame;

  /// The form sheet's status after the repeat-end barline was put on the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'Repeat end set.'**
  String get formRepeatEndSet;

  /// The form sheet's status after the repeat-end barline was taken off the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'Repeat end cleared.'**
  String get formRepeatEndCleared;

  /// The form sheet's status after the repeat-previous sign was stepped, naming the state it reached.
  ///
  /// In en, this message translates to:
  /// **'Repeat previous: {state}.'**
  String formRepeatPreviousStatus(String state);

  /// The form sheet's status when the repeat-previous cycle changed nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the bar already carries that symbol.'**
  String get formSymbolSame;

  /// The form sheet's status after the alternative-ending bracket was taken off the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'Ending bracket removed.'**
  String get formEndingRemoved;

  /// The form sheet's status after an alternative-ending bracket was chosen. It deliberately carries no full stop: the bracket is named the way it is drawn and already ends in the dot that belongs to it.
  ///
  /// In en, this message translates to:
  /// **'Ending bracket set to {volta}'**
  String formEndingSetTo(String volta);

  /// The form sheet's status when an ending choice equal to the bar's own was made.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the bar already carries that bracket.'**
  String get formBracketSame;

  /// The form sheet's status after a sign was put on the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'{mark} set.'**
  String formMarkSet(String mark);

  /// The form sheet's status after a sign was taken off the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'{mark} cleared.'**
  String formMarkCleared(String mark);

  /// The form sheet's status when a sign was already on the bar.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the bar already carries that sign.'**
  String get formSignPresent;

  /// The form sheet's status when a sign was already off the bar.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the bar does not carry that sign.'**
  String get formSignAbsent;

  /// The form sheet's status after a section was inserted in front of the cursor's section.
  ///
  /// In en, this message translates to:
  /// **'Inserted a new section before.'**
  String get formSectionInsertedBefore;

  /// The form sheet's status after a section was inserted behind the cursor's section.
  ///
  /// In en, this message translates to:
  /// **'Inserted a new section after.'**
  String get formSectionInsertedAfter;

  /// The form sheet's status when a section insert was refused.
  ///
  /// In en, this message translates to:
  /// **'Nothing was inserted: the song has no such section.'**
  String get formNoSuchSectionInsert;

  /// The form sheet's status after the selected section was copied.
  ///
  /// In en, this message translates to:
  /// **'Duplicated this section.'**
  String get formSectionDuplicated;

  /// The form sheet's status when a section copy was refused.
  ///
  /// In en, this message translates to:
  /// **'Nothing was copied: the song has no such section.'**
  String get formNoSuchSectionCopy;

  /// The form sheet's status after the selected section was moved one place towards the top.
  ///
  /// In en, this message translates to:
  /// **'Moved this section earlier.'**
  String get formSectionMovedEarlier;

  /// The form sheet's status after the selected section was moved one place towards the end.
  ///
  /// In en, this message translates to:
  /// **'Moved this section later.'**
  String get formSectionMovedLater;

  /// The form sheet's status when a section move was refused at either end of the form.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved: the section is already at that end of the form.'**
  String get formSectionAtEnd;

  /// The form sheet's status after the selected section and its bars were removed.
  ///
  /// In en, this message translates to:
  /// **'Deleted this section.'**
  String get formSectionDeleted;

  /// The form sheet's status when deleting the song's last section was refused, with the reason.
  ///
  /// In en, this message translates to:
  /// **'Nothing was deleted: a song keeps at least one section, or there would be nothing left to show.'**
  String get formLastSectionRefused;

  /// The form sheet's status after the selected section was renamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed this section to \"{name}\".'**
  String formSectionRenamed(String name);

  /// The form sheet's status when a rename asked for the name the section already had.
  ///
  /// In en, this message translates to:
  /// **'Nothing was renamed: it already carries that name.'**
  String get formNameSame;

  /// The form sheet's word for a bar that carries no alternative-ending bracket.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get formVoltaNone;

  /// The form sheet's word for the bracket with no figure, which the page draws as a bare bracket. It is a different state from having no bracket.
  ///
  /// In en, this message translates to:
  /// **'unnumbered'**
  String get formVoltaUnnumbered;

  /// The form sheet's word for a bar that carries no repeat-previous sign.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get formRepeatPreviousOff;

  /// The form sheet's word for the repeat-previous sign that means the previous bar.
  ///
  /// In en, this message translates to:
  /// **'1 bar'**
  String get formRepeatPreviousOneBar;

  /// The form sheet's word for the repeat-previous sign that means the previous two bars.
  ///
  /// In en, this message translates to:
  /// **'2 bars'**
  String get formRepeatPreviousTwoBars;

  /// The label of the rename box's field.
  ///
  /// In en, this message translates to:
  /// **'Rehearsal letter or name'**
  String get formRenameLabel;

  /// What the rename box's field is for, and what a one-letter name becomes.
  ///
  /// In en, this message translates to:
  /// **'A single letter becomes a rehearsal letter.'**
  String get formRenameHelper;

  /// The rename box's confirming button.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get formRenameButton;

  /// The title of the dialog that chooses an alternative-ending bracket.
  ///
  /// In en, this message translates to:
  /// **'Alternative ending'**
  String get formEndingTitle;

  /// The ending dialog's choice that removes the bracket. It is not the same as the unnumbered bracket, which the page draws.
  ///
  /// In en, this message translates to:
  /// **'No bracket'**
  String get formNoBracket;

  /// The ending dialog's choice of the bracket with no figure, written so it echoes the bare bracket the page draws.
  ///
  /// In en, this message translates to:
  /// **'Unnumbered ['**
  String get formUnnumberedBracket;

  /// The name of the segno sign on the form sheet's toggle. The sign on the page is notation; this is the interface's word for it.
  ///
  /// In en, this message translates to:
  /// **'Segno'**
  String get markSegno;

  /// The name of the coda sign on the form sheet's toggle.
  ///
  /// In en, this message translates to:
  /// **'Coda'**
  String get markCoda;

  /// The name of the fermata sign on the form sheet's toggle.
  ///
  /// In en, this message translates to:
  /// **'Fermata'**
  String get markFermata;

  /// The name of the player's-stop sign on the form sheet's toggle.
  ///
  /// In en, this message translates to:
  /// **'Player end'**
  String get markPlayerEnding;

  /// The text-cue sheet's caption over the controls that add a cue and walk to another bar.
  ///
  /// In en, this message translates to:
  /// **'THIS BAR'**
  String get cueGroupThisBar;

  /// The text-cue sheet's caption over the controls that change the selected cue.
  ///
  /// In en, this message translates to:
  /// **'THE CUE'**
  String get cueGroupTheCue;

  /// The text-cue sheet's button that inserts a cue on the cursor's bar.
  ///
  /// In en, this message translates to:
  /// **'Write words here'**
  String get cueWriteWords;

  /// The text-cue sheet's button that walks the cursor one bar earlier.
  ///
  /// In en, this message translates to:
  /// **'Previous bar'**
  String get cuePreviousBar;

  /// The text-cue sheet's button that walks the cursor one bar later.
  ///
  /// In en, this message translates to:
  /// **'Next bar'**
  String get cueNextBar;

  /// The text-cue sheet's button that writes the field into the selected cue.
  ///
  /// In en, this message translates to:
  /// **'Save words'**
  String get cueSaveWords;

  /// The text-cue sheet's button that moves the selected cue one bar earlier.
  ///
  /// In en, this message translates to:
  /// **'A bar earlier'**
  String get cueBarEarlier;

  /// The text-cue sheet's button that moves the selected cue one bar later.
  ///
  /// In en, this message translates to:
  /// **'A bar later'**
  String get cueBarLater;

  /// The text-cue sheet's button that nudges the selected cue up the page.
  ///
  /// In en, this message translates to:
  /// **'Up a line'**
  String get cueUpLine;

  /// The text-cue sheet's button that nudges the selected cue down the page.
  ///
  /// In en, this message translates to:
  /// **'Down a line'**
  String get cueDownLine;

  /// The text-cue sheet's destructive button that removes the selected cue.
  ///
  /// In en, this message translates to:
  /// **'Remove the cue'**
  String get cueRemove;

  /// The text-cue sheet's header naming the bar the next cue goes on.
  ///
  /// In en, this message translates to:
  /// **'Words · bar {bar}'**
  String cuePosition(int bar);

  /// The text-cue sheet's header detail line: how far into its section the cursor's bar is, which part of it the cue is anchored to, and how many cues are already on it.
  ///
  /// In en, this message translates to:
  /// **'bar {bar} of {bars} in this section · {place} · {cues} here'**
  String cueDetail(int bar, int bars, String place, String cues);

  /// How many remarks a bar carries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} cue} other{{count} cues}}'**
  String cueCount(int count);

  /// The text-cue sheet's word for a remark anchored to the bar rather than to one of its cells.
  ///
  /// In en, this message translates to:
  /// **'whole bar'**
  String get cueWholeBar;

  /// The text-cue sheet's word for a remark anchored to one cell of a bar.
  ///
  /// In en, this message translates to:
  /// **'cell {cell}'**
  String cueCell(int cell);

  /// The text-cue sheet's status when an operation was refused and the caller named no reason.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: that is not possible here.'**
  String get cueRefusedDefault;

  /// The text-cue sheet's status when adding a cue was refused, so the refuse branch names what was attempted.
  ///
  /// In en, this message translates to:
  /// **'Added a cue.'**
  String get cueAdded;

  /// The text-cue sheet's status when a cue insert was refused because the cursor names no bar.
  ///
  /// In en, this message translates to:
  /// **'Nothing was added: the song has no such bar.'**
  String get cueNoSuchBarAdd;

  /// The text-cue sheet's status after a cue was inserted, telling the musician the field is waiting.
  ///
  /// In en, this message translates to:
  /// **'Added a cue — type the words.'**
  String get cueAddedTypeWords;

  /// The text-cue sheet's status when a press needed a selected cue and there is none, in the cases where the refusal has no more specific reason.
  ///
  /// In en, this message translates to:
  /// **'Nothing happened.'**
  String get cueNothingHappened;

  /// The text-cue sheet's status when Save words was pressed with nothing selected.
  ///
  /// In en, this message translates to:
  /// **'Nothing was saved: no cue is selected.'**
  String get cueNoSelectionSave;

  /// The text-cue sheet's status after the words were written to the selected cue.
  ///
  /// In en, this message translates to:
  /// **'Saved the words.'**
  String get cueWordsSaved;

  /// The text-cue sheet's status when the field held the words the cue already had.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the cue already says that.'**
  String get cueSameWords;

  /// The text-cue sheet's status when the cue was removed with nothing selected.
  ///
  /// In en, this message translates to:
  /// **'Nothing was removed: no cue is selected.'**
  String get cueNoSelectionRemove;

  /// The text-cue sheet's status after the selected cue was taken off the chart.
  ///
  /// In en, this message translates to:
  /// **'Removed the cue.'**
  String get cueRemoved;

  /// The text-cue sheet's status when the selected cue had already been removed.
  ///
  /// In en, this message translates to:
  /// **'Nothing was removed: the cue is already gone.'**
  String get cueAlreadyGone;

  /// The text-cue sheet's status when a move was asked for with nothing selected.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved: no cue is selected.'**
  String get cueNoSelectionMove;

  /// The text-cue sheet's status when a move or a cursor walk would leave the song.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved: that is the end of the song.'**
  String get cueEndOfSong;

  /// The text-cue sheet's status after the selected cue was moved to the previous bar.
  ///
  /// In en, this message translates to:
  /// **'Moved the cue a bar earlier.'**
  String get cueMovedEarlier;

  /// The text-cue sheet's status after the selected cue was moved to the next bar.
  ///
  /// In en, this message translates to:
  /// **'Moved the cue a bar later.'**
  String get cueMovedLater;

  /// The text-cue sheet's status when a move landed on the bar the cue already sat on.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved: the cue is already there.'**
  String get cueAlreadyThere;

  /// The text-cue sheet's status after the selected cue's offset was moved up.
  ///
  /// In en, this message translates to:
  /// **'Nudged the cue up.'**
  String get cueNudgedUp;

  /// The text-cue sheet's status after the selected cue's offset was moved down.
  ///
  /// In en, this message translates to:
  /// **'Nudged the cue down.'**
  String get cueNudgedDown;

  /// The text-cue sheet's status when a nudge changed nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved.'**
  String get cueNothingMoved;

  /// The text-cue sheet's status after the cursor walked to another bar.
  ///
  /// In en, this message translates to:
  /// **'Now on bar {bar}.'**
  String cueNowOnBar(int bar);

  /// The text-cue sheet's cue list when the cursor's bar carries no remark.
  ///
  /// In en, this message translates to:
  /// **'No words on this bar yet.'**
  String get cueNoneHere;

  /// The cue list's name for a cue that was inserted and not yet typed into. It is the interface's own word, not the cue's text.
  ///
  /// In en, this message translates to:
  /// **'(no words yet)'**
  String get cueNoWordsYet;

  /// The label of the text-cue sheet's words field.
  ///
  /// In en, this message translates to:
  /// **'The words'**
  String get cueWordsLabel;

  /// The text-cue sheet's examples under the words field. The EXAMPLES ARE NOT TRANSLATED AND ARE THE SAME IN EVERY LOCALE: they are the conventional notation a musician writes on a chart, which Russian players read in the Italian/English form, and a translated example would teach them to write a word no other chart carries. Only the framing words 'For example' belong to the interface.
  ///
  /// In en, this message translates to:
  /// **'For example: To Coda · D.C. al Fine · Solo · Vamp · 4×'**
  String get cueWordsHelper;

  /// The programme sheet's own heading.
  ///
  /// In en, this message translates to:
  /// **'Programme'**
  String get setlistSheetTitle;

  /// The label of a button that undoes the last edit, distinct from the app-bar icon's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// The label of a button that redoes the last undone edit.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// The label of the programme sheet's title field.
  ///
  /// In en, this message translates to:
  /// **'Programme name'**
  String get setlistNameLabel;

  /// How many of the programme's entries name a chart the loaded library does not hold, and what that means. Russian needs three written forms and agrees its verb with the noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} entry names a chart this library does not hold. The programme keeps it; the chart is not here to play.} other{{count} entries name a chart this library does not hold. The programme keeps them; the chart is not here to play.}}'**
  String setlistMissingCharts(int count);

  /// The programme sheet's body before any entry was added.
  ///
  /// In en, this message translates to:
  /// **'The programme is empty.\nAdd a chart from the library.'**
  String get setlistEmpty;

  /// The programme sheet's button that opens the chart picker.
  ///
  /// In en, this message translates to:
  /// **'Add a chart to the programme'**
  String get setlistAddChart;

  /// The title of the programme sheet's chart picker.
  ///
  /// In en, this message translates to:
  /// **'Add a chart'**
  String get setlistAddChartTitle;

  /// The tooltip of a programme row's play button.
  ///
  /// In en, this message translates to:
  /// **'Play this chart from the programme'**
  String get setlistPlayTooltip;

  /// The tooltip of a programme row's entry-edit button.
  ///
  /// In en, this message translates to:
  /// **'How this entry is played'**
  String get setlistEntryTooltip;

  /// The tooltip of a programme row's delete button.
  ///
  /// In en, this message translates to:
  /// **'Remove from the programme'**
  String get setlistRemoveTooltip;

  /// The entry-edit dialog's caption over the interval stepper, saying that the document keeps its written key.
  ///
  /// In en, this message translates to:
  /// **'Transposition for this entry (the chart keeps its written key)'**
  String get setlistTranspositionHint;

  /// The label of the entry-edit dialog's note field.
  ///
  /// In en, this message translates to:
  /// **'Note for the performer'**
  String get setlistNotesLabel;

  /// A programme row's subtitle: how the entry is transposed, then the note the performer wrote. The note is the musician's own data and is not translated.
  ///
  /// In en, this message translates to:
  /// **'{interval} · {notes}'**
  String setlistEntrySubtitle(String interval, String notes);

  /// A row of the chart picker: the chart's key, then its bar count.
  ///
  /// In en, this message translates to:
  /// **'{key} · {bars}'**
  String setlistSongSubtitle(String key, String bars);

  /// The name shown for a programme whose title is empty. Never data: it is the interface's own fallback.
  ///
  /// In en, this message translates to:
  /// **'Untitled programme'**
  String get untitledProgramme;

  /// The programme row's name for an entry that names no chart the loaded library holds.
  ///
  /// In en, this message translates to:
  /// **'(missing chart)'**
  String get setlistMissingChart;

  /// The form sheet's caption over the bar-meter control.
  ///
  /// In en, this message translates to:
  /// **'METER'**
  String get formGroupMeter;

  /// The form sheet's meter button, naming the meter the cursor's bar carries now.
  ///
  /// In en, this message translates to:
  /// **'Meter: {meter}'**
  String formMeterLabel(String meter);

  /// The title of the box that asks for the two figures of a bar's meter.
  ///
  /// In en, this message translates to:
  /// **'Bar meter M/N'**
  String get formMeterTitle;

  /// The label of the upper figure of a meter: how many beats the bar is counted in.
  ///
  /// In en, this message translates to:
  /// **'Numerator M'**
  String get formMeterNumerator;

  /// The label of the lower figure of a meter: the note value that gets the beat.
  ///
  /// In en, this message translates to:
  /// **'Denominator N'**
  String get formMeterDenominator;

  /// The hint under the two meter fields, showing a meter a fixed list would not offer.
  ///
  /// In en, this message translates to:
  /// **'Two whole numbers, for example 15/8.'**
  String get formMeterHelper;

  /// The button that applies the typed meter.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get formMeterApply;

  /// The form sheet's status after a meter was set, naming the meter and the bars it covers; a zone of one bar prints that one bar's number.
  ///
  /// In en, this message translates to:
  /// **'Meter {meter} set on {range}.'**
  String formMeterSet(String meter, String range);

  /// The refusal shown when the meter is already in force on every bar of the zone.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: every bar in the range is already in that meter.'**
  String get formMeterSame;

  /// The meter button's word when the sheet's cursor names no bar, so no meter is in view.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get formMeterNone;

  /// The label of the first bar of a zone, counted inside the cursor's section.
  ///
  /// In en, this message translates to:
  /// **'From bar'**
  String get formZoneFrom;

  /// The label of the last bar of a zone, counted inside the cursor's section.
  ///
  /// In en, this message translates to:
  /// **'To bar'**
  String get formZoneTo;

  /// The hint under the two bar-number fields of a zone.
  ///
  /// In en, this message translates to:
  /// **'Bars of this section, counted from its first.'**
  String get formZoneHelper;

  /// The zone box's refusal when one of the two bar numbers is blank.
  ///
  /// In en, this message translates to:
  /// **'Type a bar number in both boxes.'**
  String get formZoneErrorEmpty;

  /// The zone box's refusal when a bar number is not a whole number.
  ///
  /// In en, this message translates to:
  /// **'Bar numbers are whole numbers written in digits.'**
  String get formZoneErrorNotAnInteger;

  /// The zone box's refusal when a bar number is outside the cursor's section, naming how many bars it has.
  ///
  /// In en, this message translates to:
  /// **'This section has {bars} bar(s).'**
  String formZoneErrorOutOfRange(int bars);

  /// The zone box's refusal when the last bar is before the first.
  ///
  /// In en, this message translates to:
  /// **'The first bar must not come after the last one.'**
  String get formZoneErrorReversed;

  /// The zone box's refusal when the range names a section the song does not have, or one with no bars.
  ///
  /// In en, this message translates to:
  /// **'That range is not inside this section.'**
  String get formZoneErrorNoSection;

  /// The meter box's refusal when one of the two figures is blank.
  ///
  /// In en, this message translates to:
  /// **'Type a whole number in both boxes.'**
  String get formMeterErrorEmpty;

  /// The meter box's refusal when a figure is not a whole number: a fraction, a decimal or letters.
  ///
  /// In en, this message translates to:
  /// **'Both figures are whole numbers written in digits.'**
  String get formMeterErrorNotAnInteger;

  /// The meter box's refusal for a zero or a negative figure. A bar of no beats is not a meter.
  ///
  /// In en, this message translates to:
  /// **'Both figures must be greater than zero.'**
  String get formMeterErrorNotPositive;

  /// The meter box's refusal for a figure above the accepted bound.
  ///
  /// In en, this message translates to:
  /// **'Too large: each figure is at most {max}.'**
  String formMeterErrorTooLarge(int max);

  /// The chord palette's caption over the field a chord symbol is typed into, such as Dm7 or F#7#11.
  ///
  /// In en, this message translates to:
  /// **'Type the chord'**
  String get paletteSymbolLabel;

  /// The hint inside the typed-chord field, showing symbols a jazz chart writes.
  ///
  /// In en, this message translates to:
  /// **'Dm7 · G7 · Cmaj7 · F#7#11'**
  String get paletteSymbolHelper;

  /// The button that writes the typed chord symbol into the selected cell.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get paletteSymbolApply;

  /// The typed-chord field's refusal when nothing was typed.
  ///
  /// In en, this message translates to:
  /// **'Type a chord symbol, for example Dm7.'**
  String get paletteSymbolErrorEmpty;

  /// The typed-chord field's refusal when the symbol does not begin with a note letter, naming the character that was typed.
  ///
  /// In en, this message translates to:
  /// **'A chord starts with a note letter A to G. \"{character}\" is not one.'**
  String paletteSymbolErrorNotANoteLetter(String character);

  /// The typed-chord field's refusal when a parenthesis has no closing one.
  ///
  /// In en, this message translates to:
  /// **'A bracket was opened and not closed.'**
  String get paletteSymbolErrorUnclosedBracket;

  /// The typed-chord field's refusal when the slash bass is missing or is not a note letter.
  ///
  /// In en, this message translates to:
  /// **'After the slash write a note letter, for example Cmaj7/A.'**
  String get paletteSymbolErrorBadBass;

  /// The typed-chord field's refusal when the root's accidental is malformed, such as b# or ###.
  ///
  /// In en, this message translates to:
  /// **'A root takes at most two sharps or two flats.'**
  String get paletteSymbolErrorBadAccidental;

  /// The typed-chord field's refusal when the symbol was read but the edited cell is outside its bar.
  ///
  /// In en, this message translates to:
  /// **'This cell cannot hold a chord: the beat is outside the bar.'**
  String get paletteSymbolErrorCellNotWritable;

  /// The form sheet's caption over the staff controls.
  ///
  /// In en, this message translates to:
  /// **'STAFF'**
  String get formGroupStaff;

  /// The form sheet's staff button when the chart declares a pitched melodic staff, so its bars are drawn with staff lines.
  ///
  /// In en, this message translates to:
  /// **'Melody staff: on'**
  String get formStaffMelodyOn;

  /// The form sheet's staff button when the chart declares no staff, so its bars are drawn as chords only.
  ///
  /// In en, this message translates to:
  /// **'Melody staff: off'**
  String get formStaffMelodyOff;

  /// The form sheet's note under the staff button when the staff is on.
  ///
  /// In en, this message translates to:
  /// **'The staff is drawn on every bar of the chart, empty or not.'**
  String get formStaffMelodyShown;

  /// The form sheet's note under the staff button when the staff is off, stating that the notes are not deleted.
  ///
  /// In en, this message translates to:
  /// **'Turn the staff on to write notes. What is already written is kept.'**
  String get formStaffMelodyHidden;

  /// The note palette's hint, stating that the duration and the alteration stay armed for the next notes, which is the thing a musician cannot discover by looking.
  ///
  /// In en, this message translates to:
  /// **'The duration and the alteration are kept for the following notes.'**
  String get melodyStickyHint;

  /// The armed value line in the note palette: the duration and the accidental a pitch tap would write. The duration is notation ('1/4 · Quarter') and is not translated.
  ///
  /// In en, this message translates to:
  /// **'Will write {duration} · {accidental}'**
  String melodyArmed(Object accidental, Object duration);

  /// The note palette's state line while a note is selected. It used to repeat the note's own line, which is already the row above it.
  ///
  /// In en, this message translates to:
  /// **'Editing the selected note: a pitch tap changes it.'**
  String get melodyEditingSelected;

  /// The note palette's subtitle naming the WRITTEN key its pitches are spelled in. The key itself is notation and is not translated (D27/A53).
  ///
  /// In en, this message translates to:
  /// **'Notes are written in {key}'**
  String melodySpelledIn(Object key);

  /// The one always-visible button's tooltip while the library rail and the top block are shown.
  ///
  /// In en, this message translates to:
  /// **'Hide the list and the panels: more room for the chart'**
  String get tooltipChromeHide;

  /// The same button's tooltip while the rail and the top block are hidden, so the musician can get them back.
  ///
  /// In en, this message translates to:
  /// **'Show the list and the panels'**
  String get tooltipChromeShow;

  /// The selection line's text while the eraser is the active tool, so the mode and what it does are stated in words rather than by a lit icon.
  ///
  /// In en, this message translates to:
  /// **'Eraser on: touch a stroke or drag across it, and the whole stroke goes'**
  String get eraserActiveHint;
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
