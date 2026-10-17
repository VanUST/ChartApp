// PURPOSE: Produce the strings a musician READS on the native code path, on stdout, so "the native
//          half has never been looked at" becomes a printed list instead of a claim. It renders the
//          real dialogs the viewer opens — the `.chart` plate, the `.setlist` plate and the
//          programme sheet — AND the viewer's own source bar with its empty state, under the io
//          implementation of the conditional import, and prints the field label, the buttons and
//          every status sentence in Russian and in English.
//
//          WHY IT HAS TO BE A FLUTTER PROBE AND NOT A `dart run` ONE. The `tool/probe_*_seam.dart`
//          probes exercise the io FUNCTIONS without Flutter, which is what they are for; the strings
//          under test here are chosen inside widgets by `chartSourceIsFilePath` and rendered by
//          `AppLocalizations`, neither of which exists outside the Flutter test binding. `flutter
//          test` runs on the VM, so the conditional import resolves to `chart_source_io.dart` and
//          `ireal_source_io.dart` — the implementations an Android tablet runs — which is exactly
//          the half the web build never compiles.
//
//          **THE CLAIM IN THAT PARAGRAPH — that the `tool/probe_*_seam.dart` probes "exercise the io
//          FUNCTIONS without Flutter" — IS NO LONGER TRUE, and it is left standing above beside this
//          correction rather than quietly rewritten, the same form `docs/sdd.md` A30 and A52 use.**
//          It described those probes as `dart run` instruments, and A55 made that false: they reach
//          `chart_source.dart` -> `chart_source_io.dart` -> `file_selector` -> `dart:ui`. They are
//          `flutter test` probes now (`flutter test tool/probe_chart_seam.dart` and its two
//          siblings). That changes nothing about WHY this file is one: the seam probes exercise the
//          io functions directly, while the strings here are chosen inside widgets and need the
//          test binding.
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so it is not picked up
//          by `flutter test`'s default run or by the `melos run verify` gate. It writes one
//          temporary `.chart` and one `.setlist` file and deletes them. Run it from `apps/mobile`
//          with:
//
//              flutter test tool/probe_native_path.dart
//
//          It opens no window: `flutter test` runs the engine headless.
// INPUTS: None. Every song is synthetic, so nothing is read from the owner's machine.
// OUTPUTS: `probe.*` lines on stdout: the platform constants, and, per locale, every string each
//          dialog shows and every status sentence it reaches — including the save status, the
//          empty-path refusal and the opened-document status — plus the viewer's source bar and empty
//          state with which of its three controls are present. The temporary files are removed
//          before the probe returns. The probe runs on the VM, so the form it prints is the DESKTOP
//          one (`iRealSourceIsFilePath == true`); the hand-held form is the same widgets with the
//          chooser alone, and is observed on the device rather than here.
// KEYWORDS: probe, native-path, io-implementation, chart-file, setlist-file, localization,
//           russian, english, status-line, evidence
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_file_bar.dart';
import 'package:chartapp/chart_source.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/ireal_source.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/setlist_file_bar.dart';
import 'package:chartapp/setlist_sheet.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's widget-identity `Key` would collide with the musical Key this file names.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The locales the app supports, in the order the probe prints them.
const List<Locale> _locales = <Locale>[Locale('ru'), Locale('en')];

/// A chart with a name, used for every dialog the probe renders.
Song _namedSong() => Song(
  id: 'probe-song',
  title: 'Ракета',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(0),
              chord: Chord(root: ChordRoot(0)),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// A chart the export left without a name, used to show which language words that absence.
Song _namelessSong() => Song(
  id: 'probe-untitled',
  title: '',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(0),
              chord: Chord(root: ChordRoot(0)),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Every string a `Text` widget would draw, in tree order.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .where((String value) => value.isNotEmpty)
    .toList();

/// Prints the list with the index a reader can quote.
void _printTexts(String label, List<String> values) {
  stdout.writeln('probe.$label count=${values.length}');
  for (int index = 0; index < values.length; index++) {
    stdout.writeln('probe.$label[$index]="${values[index]}"');
  }
}

/// The `labelText` the dialog's one text field currently shows.
String _fieldLabel(WidgetTester tester) {
  final TextField field = tester.widget<TextField>(find.byType(TextField));
  return field.decoration?.labelText ?? '';
}

/// The text the dialog's one text field currently holds.
String _fieldText(WidgetTester tester) {
  final TextField field = tester.widget<TextField>(find.byType(TextField));
  return field.controller?.text ?? '';
}

/// Pumps a one-screen app holding a body, with the application's own delegates.
Future<void> _pumpApp(WidgetTester tester, Locale locale, Widget body) async {
  // Tear the previous tree down first: a dialog left open by the previous section would otherwise
  // survive the re-pump (the navigator is reused) and its modal barrier would swallow every tap.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: AppBar(actions: <Widget>[body]),
        body: const SizedBox.expand(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the native path, in the strings a musician reads', (
    WidgetTester tester,
  ) async {
    stdout.writeln(
      'probe.constants chartSourceIsFilePath=$chartSourceIsFilePath',
    );
    stdout.writeln(
      'probe.constants chartSourceSaveMode=${chartSourceSaveMode().name}',
    );
    stdout.writeln(
      'probe.constants iRealSourceIsFilePath=$iRealSourceIsFilePath',
    );
    stdout.writeln(
      'probe.constants iRealSourceIsBrowser=$iRealSourceIsBrowser',
    );
    stdout.writeln(
      'probe.constants defaultIRealPath_exists='
      '${File(defaultIRealPath).existsSync()}',
    );
    expect(
      chartSourceIsFilePath,
      isTrue,
      reason: 'this probe is only meaningful on the io implementation',
    );

    final Directory directory = Directory.systemTemp.createTempSync(
      'chartapp-native-probe-',
    );
    final String chartPath =
        '${directory.path}${Platform.pathSeparator}probe.chart';
    final String setlistPath =
        '${directory.path}${Platform.pathSeparator}probe.setlist';
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    for (final Locale locale in _locales) {
      await _chartDialog(tester, locale, chartPath);
      await _setlistDialog(tester, locale, setlistPath);
      await _untitledFileName(tester, locale);
      await _programmeSheet(tester, locale);
      await _viewerSourceBar(tester, locale);
    }

    stdout.writeln('probe.done');
  });
}

/// Renders the viewer's OWN source bar and empty state, which is the screen the tablet defect was
/// about: it is where a musician decides how to reach their file, and where the two forms of the bar
/// are chosen. Nothing is loaded and `autoLoad` is false, so the loader below is never called and
/// the empty state is exactly what a first launch shows.
Future<void> _viewerSourceBar(WidgetTester tester, Locale locale) async {
  // Torn down first for the same reason `_pumpApp` does it: the dialogs the previous sections left
  // open would otherwise survive the re-pump and their modal barriers would swallow every tap.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: IRealViewerScreen(
        loader: (String reference) async =>
            const IRealLibrary(playlistName: '', songs: <IRealSong>[]),
        initialPath: '',
        autoLoad: false,
      ),
    ),
  );
  await tester.pumpAndSettle();

  stdout.writeln('probe.viewer.locale=${locale.languageCode}');
  stdout.writeln(
    'probe.viewer.path_field='
    '${find.byKey(const ValueKey<String>('viewer-path-field')).evaluate().isNotEmpty}',
  );
  stdout.writeln(
    'probe.viewer.choose_button='
    '${find.byKey(const ValueKey<String>('viewer-choose-file')).evaluate().isNotEmpty}',
  );
  stdout.writeln(
    'probe.viewer.open_button='
    '${find.byKey(const ValueKey<String>('viewer-open-file')).evaluate().isNotEmpty}',
  );
  _printTexts('viewer.${locale.languageCode}', _texts(tester));
}

/// Renders the `.chart` dialog and drives Save, an empty-path Open and a real-file Open.
Future<void> _chartDialog(
  WidgetTester tester,
  Locale locale,
  String chartPath,
) async {
  final AppLocalizations l10n = lookupAppLocalizations(locale);
  final DocumentState document = DocumentState(song: _namedSong());
  final List<String> opened = <String>[];
  await _pumpApp(
    tester,
    locale,
    ChartFileAction(
      document: document,
      initialPath: chartPath,
      onOpened: (OpenedChart result) => opened.add(result.document.song.title),
    ),
  );

  stdout.writeln('probe.chart.locale=${locale.languageCode}');
  stdout.writeln('probe.chart.tooltip="${l10n.menuChartFile}"');
  await tester.tap(find.byTooltip(l10n.menuChartFile));
  await tester.pumpAndSettle();
  stdout.writeln('probe.chart.field_label="${_fieldLabel(tester)}"');
  _printTexts('chart.dialog.${locale.languageCode}', _texts(tester));
  stdout.writeln(
    'probe.chart.initial_path_offered='
    '${chartPath.split(Platform.pathSeparator).last}',
  );

  // --- SAVE, through the io implementation the Android tablet runs -----------------------------
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  stdout.writeln(
    'probe.chart.file_exists_after_save=${File(chartPath).existsSync()} '
    'bytes=${File(chartPath).existsSync() ? File(chartPath).lengthSync() : -1}',
  );
  _printTexts('chart.saved.${locale.languageCode}', _texts(tester));

  // --- OPEN with an empty path: the native-only refusal ----------------------------------------
  await tester.enterText(find.byType(TextField), '');
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(TextButton, l10n.chartFileOpenButton));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  });
  final List<String> refused = _texts(tester);
  stdout.writeln(
    'probe.chart.empty_open_status.${locale.languageCode}='
    '"${l10n.chartFileNameToOpen}" '
    'shown=${refused.contains(l10n.chartFileNameToOpen)}',
  );

  // --- OPEN the file that Save just wrote ------------------------------------------------------
  await tester.enterText(find.byType(TextField), chartPath);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(TextButton, l10n.chartFileOpenButton));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  _printTexts('chart.opened.${locale.languageCode}', _texts(tester));
  stdout.writeln('probe.chart.opened_titles.${locale.languageCode}=$opened');
}

/// Renders the `.setlist` dialog and drives its label, title and one save.
Future<void> _setlistDialog(
  WidgetTester tester,
  Locale locale,
  String setlistPath,
) async {
  final AppLocalizations l10n = lookupAppLocalizations(locale);
  final SetlistSession session = SetlistSession(
    setlist: const Setlist(id: 'probe-setlist', title: 'Ракета Русское'),
  );
  await _pumpApp(
    tester,
    locale,
    SetlistFileAction(
      session: session,
      initialPath: setlistPath,
      onOpened: (OpenedSetlist result) => 'opened',
    ),
  );

  stdout.writeln('probe.setlist.locale=${locale.languageCode}');
  await tester.tap(find.byTooltip(l10n.setlistFileTooltip));
  await tester.pumpAndSettle();
  stdout.writeln('probe.setlist.field_label="${_fieldLabel(tester)}"');
  _printTexts('setlist.dialog.${locale.languageCode}', _texts(tester));

  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  stdout.writeln(
    'probe.setlist.file_exists_after_save=${File(setlistPath).existsSync()} '
    'bytes=${File(setlistPath).existsSync() ? File(setlistPath).lengthSync() : -1}',
  );
  _printTexts('setlist.saved.${locale.languageCode}', _texts(tester));
}

/// Renders the `.chart` dialog for a NAMELESS chart with nothing to sit beside, which is the one
/// place the interface frame and the file-name payload can be read side by side: the field offers a
/// file name while the catalogue holds the word the musician would read for the same chart.
Future<void> _untitledFileName(WidgetTester tester, Locale locale) async {
  final AppLocalizations l10n = lookupAppLocalizations(locale);
  await _pumpApp(
    tester,
    locale,
    ChartFileAction(
      document: DocumentState(song: _namelessSong()),
      onOpened: (OpenedChart result) {},
    ),
  );
  await tester.tap(find.byTooltip(l10n.menuChartFile));
  await tester.pumpAndSettle();
  stdout.writeln('probe.untitled_file.locale=${locale.languageCode}');
  stdout.writeln('probe.untitled_file.field_text="${_fieldText(tester)}"');
  stdout.writeln('probe.untitled_file.catalogue_word="${l10n.untitled}"');
}

/// Renders the programme sheet over a nameless chart, both as a row and in the chart picker.
Future<void> _programmeSheet(WidgetTester tester, Locale locale) async {
  final AppLocalizations l10n = lookupAppLocalizations(locale);
  final IRealSong nameless = IRealSong(index: 0, song: _namelessSong());
  final SetlistSession session = SetlistSession(
    setlist: Setlist(
      id: 'probe-setlist',
      items: <SetlistItem>[
        SetlistItem(
          documentId: nameless.song.id,
          chartIdentity: nameless.identity,
        ),
      ],
    ),
  );
  // The resolver the viewer hands the sheet: the raw title, empty when the chart has none, and
  // null only when the library does not hold the chart.
  String? titleFor(SetlistItem item) =>
      item.chartIdentity == nameless.identity ? nameless.song.title : null;

  // Tear the previous tree down first, for the same reason `_pumpApp` does: the `.setlist` dialog
  // the previous section left open would otherwise block the taps below.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SetlistSheet(
          session: session,
          songs: <IRealSong>[nameless],
          titleFor: titleFor,
          onPlay: (int index) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  stdout.writeln('probe.programme.locale=${locale.languageCode}');
  final String row = tester
      .widget<Text>(find.byKey(const ValueKey<String>('setlist-entry-title-0')))
      .data!;
  stdout.writeln('probe.programme.row_title="$row"');

  await tester.tap(find.byKey(const ValueKey<String>('setlist-insert')));
  await tester.pumpAndSettle();
  final String picked = tester
      .widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('setlist-add-0')),
              matching: find.byType(Text),
            )
            .first,
      )
      .data!;
  stdout.writeln('probe.programme.picker_title="$picked"');
  stdout.writeln(
    'probe.programme.picker_title_is_catalogue_untitled='
    '${picked == l10n.untitled}',
  );
}
