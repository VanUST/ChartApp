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
  String get chooseFile => 'Выбрать файл…';

  @override
  String get openHtmlFile => 'Открыть файл .html';

  @override
  String get iRealHtmlFileLabel => 'Файл iReal .html';

  @override
  String get load => 'Загрузить';

  @override
  String get promptNativePath =>
      'Откройте файл .html, экспортированный из iReal Pro.\nВведите путь или выберите файл кнопкой выше.';

  @override
  String get promptNativeChooser =>
      'Откройте файл .html, экспортированный из iReal Pro.\nФайл остаётся на этом устройстве.';

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
  String get newChart => 'Новый чарт';

  @override
  String newChartIntro(String bars) {
    return 'Новый чарт — это один раздел из $bars. Выберите тональность и размер: потом их нельзя будет изменить.';
  }

  @override
  String get newChartMeterLabel => 'Размер';

  @override
  String get newChartKeyLabel => 'Тональность';

  @override
  String get newChartMajor => 'Major';

  @override
  String get newChartMinor => 'Minor';

  @override
  String get create => 'Создать';

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
    return '$signed st';
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
    return '$tonic major';
  }

  @override
  String keyNameMinor(String tonic) {
    return '$tonic minor';
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

  @override
  String get save => 'Сохранить';

  @override
  String get ok => 'ОК';

  @override
  String get fileNameLabel => 'Имя файла';

  @override
  String fileSaveFailed(String error) {
    return 'Не удалось сохранить: $error';
  }

  @override
  String fileOpenFailed(String error) {
    return 'Не удалось открыть: $error';
  }

  @override
  String get fileChooserCancelled => 'Файл не выбран.';

  @override
  String fileWarningSuffix(String warnings, String message) {
    return ' $warnings: $message';
  }

  @override
  String byteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count байта',
      many: '$count байт',
      few: '$count байта',
      one: '$count байт',
    );
    return '$_temp0';
  }

  @override
  String operationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count операции',
      many: '$count операций',
      few: '$count операции',
      one: '$count операция',
    );
    return '$_temp0';
  }

  @override
  String warningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count предупреждения',
      many: '$count предупреждений',
      few: '$count предупреждения',
      one: '$count предупреждение',
    );
    return '$_temp0';
  }

  @override
  String entryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
    );
    return '$_temp0';
  }

  @override
  String get chartFileDialogTitle => 'Файл чарта';

  @override
  String get chartFileLabelPath => 'Файл .chart';

  @override
  String get chartFileOpenButton => 'Открыть .chart';

  @override
  String get chartFileNoDocument =>
      'Загрузите или импортируйте песню, прежде чем сохранять её.';

  @override
  String get chartFileNameToSave => 'Укажите файл .chart, в который сохранять.';

  @override
  String get chartFileNameToOpen => 'Укажите файл .chart, который открыть.';

  @override
  String chartFileSavedTo(String bytes, String path, String operations) {
    return 'Сохранено $bytes в $path · $operations.';
  }

  @override
  String chartFileSavedAs(String bytes, String path, String operations) {
    return 'Сохранено $bytes как $path · $operations.';
  }

  @override
  String chartFileOpened(String title, String operations) {
    return 'Открыт «$title» · $operations.';
  }

  @override
  String get saveModeChosenLocation =>
      'Каждое сохранение спрашивает, куда положить файл.';

  @override
  String get saveModeRewriteInPlace =>
      'Этот браузер перезаписывает тот файл на месте, поэтому следующее «Сохранить» обновит его.';

  @override
  String get saveModeDownload =>
      'Этот браузер не может обновить файл на месте, поэтому каждое «Сохранить» скачивает НОВУЮ копию.';

  @override
  String get chartFileSaveHintChosenLocation =>
      'На этом устройстве нельзя ввести путь к файлу, поэтому «Сохранить» открывает системный выбор файла: папку и имя вы выбираете там.';

  @override
  String get chartFileSaveHintRewriteInPlace =>
      'Этот браузер может перезаписать файл чарта, который ему уже давали. Первое «Сохранить» спросит, куда положить файл; каждое следующее обновляет тот же файл.';

  @override
  String get chartFileSaveHintDownload =>
      'Этот браузер не может перезаписать файл на месте, поэтому каждое «Сохранить» скачивает НОВУЮ копию. Куда её положить, выбирает браузер, и он может переименовать её, если файл с таким именем уже есть.';

  @override
  String get setlistFileTooltip => 'Сохранить или открыть файл .setlist';

  @override
  String get setlistFileDialogTitle => 'Файл программы';

  @override
  String get setlistFileLabelPath => 'Файл .setlist';

  @override
  String get setlistFileOpenButton => 'Открыть .setlist';

  @override
  String get setlistFileNameToSave =>
      'Укажите файл .setlist, в который сохранять.';

  @override
  String get setlistFileNameToOpen => 'Укажите файл .setlist, который открыть.';

  @override
  String setlistFileSavedTo(
    String bytes,
    String path,
    String entries,
    String operations,
  ) {
    return 'Сохранено $bytes в $path · $entries · $operations.';
  }

  @override
  String setlistFileSavedAs(
    String bytes,
    String path,
    String entries,
    String operations,
  ) {
    return 'Сохранено $bytes как $path · $entries · $operations.';
  }

  @override
  String get setlistFileSaveHintChosenLocation =>
      'На этом устройстве нельзя ввести путь к файлу, поэтому «Сохранить» открывает системный выбор файла: папку и имя вы выбираете там.';

  @override
  String get setlistFileSaveHintRewriteInPlace =>
      'Этот браузер может перезаписать файл программы, который ему уже давали. Первое «Сохранить» спросит, куда положить файл; каждое следующее обновляет тот же файл.';

  @override
  String get setlistFileSaveHintDownload =>
      'Этот браузер не может перезаписать файл на месте, поэтому каждое «Сохранить» скачивает НОВУЮ копию. Куда её положить, выбирает браузер, и он может переименовать её, если файл с таким именем уже есть.';

  @override
  String setlistOpened(String name, String entries) {
    return 'Открыта «$name» · $entries.';
  }

  @override
  String missingEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count не найдены в библиотеке.',
      many: '$count не найдены в библиотеке.',
      few: '$count не найдены в библиотеке.',
      one: '$count не найдена в библиотеке.',
    );
    return '$_temp0';
  }

  @override
  String get metadataTitle => 'Название';

  @override
  String get metadataTitleHint => 'Имя, которое музыкант читает над чартом.';

  @override
  String get metadataComposer => 'Автор';

  @override
  String get metadataComposerHint =>
      'Как записано; порядок — тот, что хранит формат.';

  @override
  String get metadataStyle => 'Стиль';

  @override
  String get metadataStyleHint =>
      'Свободный текст, например Medium Swing или Ballad.';

  @override
  String get metadataTempo => 'Темп (BPM)';

  @override
  String get metadataTempoHelperZero => '0 означает, что чарт не задаёт темп.';

  @override
  String get metadataTempoHelperHint =>
      'Целые удары в минуту или 0, если темпа нет.';

  @override
  String get metadataTempoError => 'Темп — целое число.';

  @override
  String get metadataTempoRefused => 'Темп — целое число ударов в минуту.';

  @override
  String get metadataNothingChanged =>
      'Ничего не изменилось, поэтому в журнал ничего не записано.';

  @override
  String get metadataFooterHint =>
      'Одна правка: четыре факта выше записываются вместе.';

  @override
  String get metadataFooterFixTempo => 'Исправьте темп перед сохранением.';

  @override
  String palettePosition(int bar, int cell) {
    return 'Такт $bar · доля $cell';
  }

  @override
  String paletteChordsIn(String key) {
    return 'Аккорды в $key';
  }

  @override
  String get palettePickRoot => 'Выберите основной тон';

  @override
  String get paletteCellEmpty => 'Эта доля пуста.';

  @override
  String paletteNow(String chord) {
    return 'Сейчас: $chord';
  }

  @override
  String get paletteRemoveChord => 'Удалить аккорд';

  @override
  String get melodyGroup => 'МЕЛОДИЯ';

  @override
  String get melodyDuration => 'ДЛИТЕЛЬНОСТЬ';

  @override
  String get melodyPitch => 'ВЫСОТА';

  @override
  String get melodyAlteration => 'АЛЬТЕРАЦИЯ';

  @override
  String get melodyNewNote => '+ Новая нота';

  @override
  String get melodyPickCell =>
      'Коснитесь доли на ча́рте, чтобы поставить ноту.';

  @override
  String get melodyBeatEmpty => 'На этой доле нот нет.';

  @override
  String melodyNoteLine(int step, String pitch, String value) {
    return 'Нота $step · $pitch $value';
  }

  @override
  String get melodyOctaveLower => 'Октава ниже';

  @override
  String get melodyOctaveHigher => 'Октава выше';

  @override
  String get melodyValueTooLong => 'Длиннее такта — выберите короче.';

  @override
  String get melodyValueOverflow => 'Этот такт уже длиннее своего размера.';

  @override
  String get melodyTie => 'Связка';

  @override
  String get melodyUntie => 'Снять связку';

  @override
  String get melodyRemove => 'Удалить ноту';

  @override
  String get melodyTapBeatHint => 'Коснитесь ча́рта, чтобы сменить долю.';

  @override
  String get viewerNote => 'Нота';

  @override
  String get viewerChord => 'Аккорд';

  @override
  String get formGroupBar => 'ТАКТЫ';

  @override
  String get formGroupRepeat => 'ПОВТОРЫ';

  @override
  String get formGroupMarks => 'ЗНАКИ';

  @override
  String get formGroupSection => 'РАЗДЕЛЫ';

  @override
  String get formBarBefore => 'Такт до';

  @override
  String get formBarAfter => 'Такт после';

  @override
  String get formDuplicateBar => 'Дублировать такт';

  @override
  String get formDeleteBar => 'Удалить такт';

  @override
  String get formRepeatStart => 'Начало повтора';

  @override
  String get formRepeatEnd => 'Конец повтора';

  @override
  String formPreviousLabel(String state) {
    return 'Предыдущий: $state';
  }

  @override
  String formEndingLabel(String state) {
    return 'Вольта: $state';
  }

  @override
  String get formSectionBefore => 'Раздел до';

  @override
  String get formSectionAfter => 'Раздел после';

  @override
  String get formDuplicateSection => 'Дублировать раздел';

  @override
  String get formRenameSection => 'Переименовать раздел';

  @override
  String get moveEarlier => 'Раньше';

  @override
  String get moveLater => 'Позже';

  @override
  String get formDeleteSection => 'Удалить раздел';

  @override
  String get formNoBarSelected => 'Такт не выбран';

  @override
  String formPosition(int bar, String section) {
    return 'Такт $bar · раздел $section';
  }

  @override
  String get formBarGone => 'Выбранного такта больше нет в песне.';

  @override
  String formDetail(int bar, int bars, int section, int sections) {
    return 'такт $bar из $bars в этом разделе · раздел $section из $sections';
  }

  @override
  String get formRefusedDefault =>
      'Ничего не изменилось: эта операция здесь невозможна.';

  @override
  String get formBarInsertedBefore => 'Такт вставлен до.';

  @override
  String get formBarInsertedAfter => 'Такт вставлен после.';

  @override
  String get formNoSuchBarInsert =>
      'Ничего не вставлено: в песне нет такого такта.';

  @override
  String get formBarDuplicated => 'Такт продублирован.';

  @override
  String get formNoSuchBarCopy =>
      'Ничего не скопировано: в песне нет такого такта.';

  @override
  String get formBarDeleted => 'Такт удалён.';

  @override
  String get formLastBarRefused =>
      'Ничего не удалено: в разделе остаётся хотя бы один такт, иначе его нельзя было бы показать или выбрать.';

  @override
  String get formRepeatStartSet => 'Начало повтора поставлено.';

  @override
  String get formRepeatStartCleared => 'Начало повтора снято.';

  @override
  String get formBarlineSame =>
      'Ничего не изменилось: такт уже несёт эту тактовую черту.';

  @override
  String get formRepeatEndSet => 'Конец повтора поставлен.';

  @override
  String get formRepeatEndCleared => 'Конец повтора снят.';

  @override
  String formRepeatPreviousStatus(String state) {
    return 'Повтор предыдущего: $state.';
  }

  @override
  String get formSymbolSame =>
      'Ничего не изменилось: такт уже несёт этот знак.';

  @override
  String get formEndingRemoved => 'Вольта убрана.';

  @override
  String formEndingSetTo(String volta) {
    return 'Вольта: $volta';
  }

  @override
  String get formBracketSame =>
      'Ничего не изменилось: такт уже несёт эту вольту.';

  @override
  String formMarkSet(String mark) {
    return '$mark поставлен.';
  }

  @override
  String formMarkCleared(String mark) {
    return '$mark снят.';
  }

  @override
  String get formSignPresent =>
      'Ничего не изменилось: такт уже несёт этот знак.';

  @override
  String get formSignAbsent =>
      'Ничего не изменилось: такт не несёт этого знака.';

  @override
  String get formSectionInsertedBefore => 'Новый раздел вставлен до.';

  @override
  String get formSectionInsertedAfter => 'Новый раздел вставлен после.';

  @override
  String get formNoSuchSectionInsert =>
      'Ничего не вставлено: в песне нет такого раздела.';

  @override
  String get formSectionDuplicated => 'Раздел продублирован.';

  @override
  String get formNoSuchSectionCopy =>
      'Ничего не скопировано: в песне нет такого раздела.';

  @override
  String get formSectionMovedEarlier => 'Раздел перемещён раньше.';

  @override
  String get formSectionMovedLater => 'Раздел перемещён позже.';

  @override
  String get formSectionAtEnd =>
      'Ничего не перемещено: раздел уже стоит с этого края формы.';

  @override
  String get formSectionDeleted => 'Раздел удалён.';

  @override
  String get formLastSectionRefused =>
      'Ничего не удалено: в песне остаётся хотя бы один раздел, иначе показывать было бы нечего.';

  @override
  String formSectionRenamed(String name) {
    return 'Раздел переименован в «$name».';
  }

  @override
  String get formNameSame => 'Ничего не переименовано: он уже так называется.';

  @override
  String get formVoltaNone => 'нет';

  @override
  String get formVoltaUnnumbered => 'без номера';

  @override
  String get formRepeatPreviousOff => 'выкл.';

  @override
  String get formRepeatPreviousOneBar => '1 такт';

  @override
  String get formRepeatPreviousTwoBars => '2 такта';

  @override
  String get formRenameLabel => 'Репетиционная буква или название';

  @override
  String get formRenameHelper => 'Одна буква становится репетиционной буквой.';

  @override
  String get formRenameButton => 'Переименовать';

  @override
  String get formEndingTitle => 'Альтернативная концовка';

  @override
  String get formNoBracket => 'Без вольты';

  @override
  String get formUnnumberedBracket => 'Без номера [';

  @override
  String get markSegno => 'Сегно';

  @override
  String get markCoda => 'Кода';

  @override
  String get markFermata => 'Фермата';

  @override
  String get markPlayerEnding => 'Стоп игрока';

  @override
  String get cueGroupThisBar => 'ЭТОТ ТАКТ';

  @override
  String get cueGroupTheCue => 'ЗАМЕТКА';

  @override
  String get cueWriteWords => 'Написать слова здесь';

  @override
  String get cuePreviousBar => 'Предыдущий такт';

  @override
  String get cueNextBar => 'Следующий такт';

  @override
  String get cueSaveWords => 'Сохранить слова';

  @override
  String get cueBarEarlier => 'На такт раньше';

  @override
  String get cueBarLater => 'На такт позже';

  @override
  String get cueUpLine => 'Выше на строку';

  @override
  String get cueDownLine => 'Ниже на строку';

  @override
  String get cueRemove => 'Удалить заметку';

  @override
  String cuePosition(int bar) {
    return 'Слова · такт $bar';
  }

  @override
  String cueDetail(int bar, int bars, String place, String cues) {
    return 'такт $bar из $bars в этом разделе · $place · $cues';
  }

  @override
  String cueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count заметки',
      many: '$count заметок',
      few: '$count заметки',
      one: '$count заметка',
    );
    return '$_temp0';
  }

  @override
  String get cueWholeBar => 'весь такт';

  @override
  String cueCell(int cell) {
    return 'доля $cell';
  }

  @override
  String get cueRefusedDefault => 'Ничего не изменилось: здесь это невозможно.';

  @override
  String get cueAdded => 'Заметка добавлена.';

  @override
  String get cueNoSuchBarAdd =>
      'Ничего не добавлено: в песне нет такого такта.';

  @override
  String get cueAddedTypeWords => 'Заметка добавлена — наберите слова.';

  @override
  String get cueNothingHappened => 'Ничего не произошло.';

  @override
  String get cueNoSelectionSave => 'Ничего не сохранено: заметка не выбрана.';

  @override
  String get cueWordsSaved => 'Слова сохранены.';

  @override
  String get cueSameWords => 'Ничего не изменилось: заметка уже это говорит.';

  @override
  String get cueNoSelectionRemove => 'Ничего не удалено: заметка не выбрана.';

  @override
  String get cueRemoved => 'Заметка удалена.';

  @override
  String get cueAlreadyGone => 'Ничего не удалено: заметки уже нет.';

  @override
  String get cueNoSelectionMove => 'Ничего не перемещено: заметка не выбрана.';

  @override
  String get cueEndOfSong => 'Ничего не перемещено: это край песни.';

  @override
  String get cueMovedEarlier => 'Заметка перемещена на такт раньше.';

  @override
  String get cueMovedLater => 'Заметка перемещена на такт позже.';

  @override
  String get cueAlreadyThere => 'Ничего не перемещено: заметка уже там.';

  @override
  String get cueNudgedUp => 'Заметка сдвинута вверх.';

  @override
  String get cueNudgedDown => 'Заметка сдвинута вниз.';

  @override
  String get cueNothingMoved => 'Ничего не перемещено.';

  @override
  String cueNowOnBar(int bar) {
    return 'Теперь такт $bar.';
  }

  @override
  String get cueNoneHere => 'На этом такте слов пока нет.';

  @override
  String get cueNoWordsYet => '(слов пока нет)';

  @override
  String get cueWordsLabel => 'Слова';

  @override
  String get cueWordsHelper =>
      'Например: To Coda · D.C. al Fine · Solo · Vamp · 4×';

  @override
  String get setlistSheetTitle => 'Программа';

  @override
  String get undo => 'Отменить';

  @override
  String get redo => 'Вернуть';

  @override
  String get setlistNameLabel => 'Название программы';

  @override
  String setlistMissingCharts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count записи называют чарты, которых нет в этой библиотеке. Программа их сохраняет; играть эти чарты нечем.',
      many:
          '$count записей называют чарты, которых нет в этой библиотеке. Программа их сохраняет; играть эти чарты нечем.',
      few:
          '$count записи называют чарты, которых нет в этой библиотеке. Программа их сохраняет; играть эти чарты нечем.',
      one:
          '$count запись называет чарт, которого нет в этой библиотеке. Программа её сохраняет; играть этот чарт нечем.',
    );
    return '$_temp0';
  }

  @override
  String get setlistEmpty => 'Программа пуста.\nДобавьте чарт из библиотеки.';

  @override
  String get setlistAddChart => 'Добавить чарт в программу';

  @override
  String get setlistAddChartTitle => 'Добавить чарт';

  @override
  String get setlistPlayTooltip => 'Играть этот чарт из программы';

  @override
  String get setlistEntryTooltip => 'Как играется эта запись';

  @override
  String get setlistRemoveTooltip => 'Убрать из программы';

  @override
  String get setlistTranspositionHint =>
      'Транспонирование для этой записи (чарт сохраняет записанную тональность)';

  @override
  String get setlistNotesLabel => 'Заметка для исполнителя';

  @override
  String setlistEntrySubtitle(String interval, String notes) {
    return '$interval · $notes';
  }

  @override
  String setlistSongSubtitle(String key, String bars) {
    return '$key · $bars';
  }

  @override
  String get untitledProgramme => 'Программа без названия';

  @override
  String get setlistMissingChart => '(чарт не найден)';

  @override
  String get formGroupMeter => 'РАЗМЕР';

  @override
  String formMeterLabel(String meter) {
    return 'Размер: $meter';
  }

  @override
  String get formMeterTitle => 'Размер такта M/N';

  @override
  String get formMeterNumerator => 'Числитель M';

  @override
  String get formMeterDenominator => 'Знаменатель N';

  @override
  String get formMeterHelper => 'Два целых числа, например 15/8.';

  @override
  String get formMeterApply => 'Поставить';

  @override
  String formMeterSet(String meter, String range) {
    return 'Размер $meter поставлен: $range.';
  }

  @override
  String get formMeterSame =>
      'Ничего не изменилось: все такты диапазона уже в этом размере.';

  @override
  String get formMeterNone => 'нет';

  @override
  String get formZoneFrom => 'С такта';

  @override
  String get formZoneTo => 'По такт';

  @override
  String get formZoneHelper => 'Такты этого раздела, считая с первого.';

  @override
  String get formZoneErrorEmpty => 'Введите номер такта в оба поля.';

  @override
  String get formZoneErrorNotAnInteger => 'Номера тактов вводятся цифрами.';

  @override
  String formZoneErrorOutOfRange(int bars) {
    return 'В этом разделе тактов: $bars.';
  }

  @override
  String get formZoneErrorReversed =>
      'Первый такт не должен быть позже последнего.';

  @override
  String get formZoneErrorNoSection =>
      'Такой диапазон не попадает в этот раздел.';

  @override
  String get formMeterErrorEmpty => 'Введите целое число в оба поля.';

  @override
  String get formMeterErrorNotAnInteger =>
      'Оба числа вводятся цифрами, без дробей и точек.';

  @override
  String get formMeterErrorNotPositive => 'Оба числа должны быть больше нуля.';

  @override
  String formMeterErrorTooLarge(int max) {
    return 'Слишком большой размер: каждое число не больше $max.';
  }
}
