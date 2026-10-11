// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'ChartApp — читалка iReal';

  @override
  String get openHtmlFile => 'Открыть файл .html';

  @override
  String get iRealHtmlFileLabel => 'Файл iReal .html';

  @override
  String get load => 'Загрузить';

  @override
  String promptFilePath(String path) {
    return 'Загрузите файл iReal .html, чтобы увидеть его песни.\nПо умолчанию: $path';
  }

  @override
  String get promptWeb =>
      'Откройте файл iReal .html, экспортированный из iReal Pro.\nОн читается в браузере и никуда не отправляется.';

  @override
  String get payloadNoSongs => 'В файле не оказалось песен.';

  @override
  String get untitled => 'Без названия';

  @override
  String get noFileLoaded => 'Файл не загружен.';

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песни',
      many: '$count песен',
      few: '$count песни',
      one: '$count песня',
    );
    return '$_temp0';
  }

  @override
  String statusSongsPlaylist(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песни',
      many: '$count песен',
      few: '$count песни',
      one: '$count песня',
    );
    return '$_temp0 · программа «$name»';
  }

  @override
  String drawerSongsPlaylist(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песни',
      many: '$count песен',
      few: '$count песни',
      one: '$count песня',
    );
    return '$_temp0 · «$name»';
  }

  @override
  String barCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count такта',
      many: '$count тактов',
      few: '$count такта',
      one: '$count такт',
    );
    return '$_temp0';
  }

  @override
  String issueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count замечания',
      many: '$count замечаний',
      few: '$count замечания',
      one: '$count замечание',
    );
    return '$_temp0';
  }

  @override
  String get songInfoTooltip => 'О песне: название, автор, стиль и темп';

  @override
  String get songInfoSheetTitle => 'О песне';

  @override
  String issuesTitle(String title) {
    return 'Замечания импорта — $title';
  }

  @override
  String issueLine(int offset, String message) {
    return '@$offset: $message';
  }

  @override
  String get close => 'Закрыть';

  @override
  String get done => 'Готово';

  @override
  String get cancel => 'Отмена';

  @override
  String get tooltipInkOn =>
      'Рисование: перо рисует, палец по-прежнему выбирает';

  @override
  String get tooltipInkOffEraserOn => 'Перо выключено: ластик включён';

  @override
  String get tooltipInkOff => 'Выбор: и перо, и палец выбирают';

  @override
  String get tooltipEraserOn =>
      'Стирание: коснитесь штриха — он исчезнет целиком';

  @override
  String get tooltipEraserOff => 'Ластик выключен';

  @override
  String get tooltipUndo => 'Отменить последнюю правку чарта';

  @override
  String get tooltipRedo => 'Вернуть отменённую правку чарта';

  @override
  String get tooltipForm => 'Такты и разделы (форма)';

  @override
  String get tooltipCues => 'Слова на чарте (To Coda, Solo, 4×)';

  @override
  String get tooltipSetlist =>
      'Программа: порядок, транспонирование и запуск чартов';

  @override
  String get tooltipSettings => 'Настройки';

  @override
  String get tooltipOverflowMenu => 'Чарт, форма и программа';

  @override
  String get menuForm => 'Такты и разделы';

  @override
  String get menuCues => 'Слова на чарте';

  @override
  String get menuSetlist => 'Программа';

  @override
  String get menuChartFile => 'Сохранить или открыть файл .chart';

  @override
  String get menuSettings => 'Настройки';

  @override
  String get selectionPrompt => 'Коснитесь такта, чтобы выбрать его.';

  @override
  String selectionBar(int bar) {
    return 'выбран: такт $bar (весь такт)';
  }

  @override
  String selectionBarCell(int bar, int cell) {
    return 'выбран: такт $bar, доля $cell';
  }

  @override
  String get selectionHintChord => '— коснитесь, чтобы сменить аккорд';

  @override
  String get selectionHintForm => '— коснитесь для тактов и разделов';

  @override
  String get noBars => 'В этой песне нет тактов.';

  @override
  String fitFallbackAuto(int percent) {
    return 'Песня не помещается на одну страницу при пороге читаемости $percent%. Показана страницами.';
  }

  @override
  String fitFallbackExplicit(int percent) {
    return 'Вы попросили одну страницу, но при пороге читаемости $percent% нужно больше. Показана страницами.';
  }

  @override
  String get sceneCaptionPos => 'ПОЗ';

  @override
  String get sceneCaptionBpm => 'ТЕМП';

  @override
  String get sceneCaptionStyle => 'СТИЛЬ';

  @override
  String get sceneCaptionKeyCompact => 'ТОН.';

  @override
  String get sceneCaptionKeyFull => 'ТОН. · коснитесь, чтобы транспонировать';

  @override
  String get sceneCaptionRepeats => 'ПОВТОРЫ';

  @override
  String get sceneCaptionPage => 'СТРАНИЦА';

  @override
  String get sceneModeFit => 'ЦЕЛИКОМ';

  @override
  String get sceneModePages => 'СТРАНИЦЫ';

  @override
  String get sceneDeferredTooltip => 'Стиль и повторы';

  @override
  String sceneDeferredStyleRow(String style) {
    return 'СТИЛЬ · $style';
  }

  @override
  String sceneDeferredRepeatsRow(String repeats) {
    return 'ПОВТОРЫ · $repeats';
  }

  @override
  String get repeatNone => 'нет';

  @override
  String repeatPassages(int count) {
    return '$count×';
  }

  @override
  String repeatVoltas(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вольты',
      many: '$count вольт',
      few: '$count вольты',
      one: '$count вольта',
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
    return '$signed пт';
  }

  @override
  String keyGridTitle(String writtenKey) {
    return 'Транспонирование — написано в $writtenKey';
  }

  @override
  String get keyGridWritten => 'как написано';

  @override
  String get keyGridNotSpellable => 'нет написания';

  @override
  String keyNameMajor(String tonic) {
    return '$tonic мажор';
  }

  @override
  String keyNameMinor(String tonic) {
    return '$tonic минор';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsLanguageHeading => 'Язык';

  @override
  String get settingsFollowSystem => 'Как на устройстве';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsRussian => 'Русский';

  @override
  String get settingsStorageNote =>
      'Выбор запоминается на этом устройстве. Это настройка, а не часть ваших чартов.';

  @override
  String get settingsStorageNoteWeb =>
      'Выбор запоминается в хранилище этого браузера. Safari очищает такое хранилище после семи дней без использования, и тогда язык снова берётся с устройства. Ваши чарты — это файлы, их это не касается.';

  @override
  String languageChanged(String language) {
    return 'Язык: $language';
  }
}
