// PURPOSE: Put the WHOLE SHELL — app bar, path bar, song header, scene bar, selection line, the
//          document pane and the status line — into PNG files at the sizes the owner actually holds
//          the tablet at, headless, and print the rectangle every band of the shell occupies so the
//          numbers and the pictures come from ONE run. It exists because the owner's complaint about
//          the top of the screen is a complaint about how it LOOKS, and because this project has
//          three times caught itself asserting what a layout looked like instead of looking at it.
//
//          IT IS AN INSTRUMENT AND IT ASSERTS NOTHING. It lives in `tool/` for that reason, beside
//          `probe_staff_render.dart` and `probe_view_transform.dart`: `flutter test`'s default run
//          and the `melos run verify` gate must not pay for a PNG on every verify, and an instrument
//          that writes images is evidence for one inspection rather than a guard.
//
//          Run it from `apps/mobile` with:
//
//              flutter test tool/probe_shell_render.dart
//
//          and set SHELL_PROBE_OUT to send the PNGs somewhere named for the run.
// INPUTS: SHELL_PROBE_OUT names the directory the PNGs are written to, defaulting to a path OUTSIDE
//         the repository — this repository is public and a rendered screen is evidence, not source.
//         A real system font is loaded and registered as the theme's family, because the framework's
//         test font draws every glyph as a filled box and a screen of boxes shows no title, no
//         caption and no scene reading.
// OUTPUTS: One `ui.band` line per band of the shell: its top, its height, its width and THE TEXT IT
//          IS CARRYING, so "what is in this row" is read off the run instead of remembered. One
//          `ui.render.written` line per PNG. Nothing is asserted.
// KEYWORDS: probe, shell, geometry, render, screenshot, headless, no-window, owner-tablet,
//           chrome-shown, chrome-hidden, transitional, note-palette, evidence
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/rendering.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the probe's PNGs are written: outside the repository, on purpose.
const String shellProbeDirectory = r'C:\projects\ChartApp-acl-reports\ui';

/// The owner's tablet in LANDSCAPE: 2800x1752 physical pixels at a device pixel ratio of 2.125.
const Size tabletLandscape = Size(2800 / 2.125, 1752 / 2.125);

/// The short landscape surface this project has already paid for twice: A49's 915x412, where a
/// two-row scene bar left the chart pane 65 logical pixels tall.
const Size shortLandscape = Size(915, 412);

/// The family every glyph in these images is drawn in.
const String _fontFamily = 'ChartRenderFont';

/// A chart with a declared pitched staff and notes written on it, which is the surface the owner
/// says looks bad and unclear, and which also gives the shell a real title, tempo and style.
Song notationChart() {
  Bar makeBar(int index) {
    // Four bars of melody: a diatonic line, a raised fourth (an accidental that has to be drawn),
    // an eighth-note pair with a tie, and a whole note.
    final List<NoteMark> melody = switch (index) {
      0 => <NoteMark>[
        NoteMark(
          place: cellAt(0),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
        NoteMark(
          place: cellAt(1),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
        NoteMark(
          place: cellAt(2),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.g, 0), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
        NoteMark(
          place: cellAt(3),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.a, 0), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
      ],
      1 => <NoteMark>[
        NoteMark(
          place: cellAt(0),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.b, 0), octave: 4),
          value: NoteValue.plain(NoteBase.eighth),
          tiedToNext: true,
        ),
        NoteMark(
          place: cellAt(1),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.b, 0), octave: 4),
          value: NoteValue.plain(NoteBase.eighth),
        ),
        NoteMark(
          place: cellAt(2),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 5),
          value: NoteValue.plain(NoteBase.half),
        ),
      ],
      2 => <NoteMark>[
        NoteMark(
          place: cellAt(0),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.b, -1), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
        NoteMark(
          place: cellAt(1),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.a, 0), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
        NoteMark(
          place: cellAt(2),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.g, 0), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
        NoteMark(
          place: cellAt(3),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.f, 1), octave: 4),
          value: NoteValue.plain(NoteBase.quarter),
        ),
      ],
      _ => <NoteMark>[
        NoteMark(
          place: cellAt(0),
          pitch: PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
          value: NoteValue.plain(NoteBase.whole),
        ),
      ],
    };
    return Bar(
      chords: <ChordMark>[
        ChordMark(
          place: cellAt(0),
          chord: Chord(
            root: ChordRoot(index % 12),
            quality: index.isEven
                ? ChordQuality.minorSeventh
                : ChordQuality.dominantSeventh,
          ),
        ),
        ChordMark(
          place: cellAt(2),
          chord: Chord(
            root: ChordRoot((index + 5) % 12),
            quality: ChordQuality.dominantSeventh,
          ),
        ),
      ],
      melody: melody,
    );
  }

  return Song(
    id: 'shell-probe',
    title: 'Autumn Leaves',
    composer: 'ChartApp',
    style: 'Medium Swing',
    key: Key.cMajor,
    tempo: 132,
    staffSet: const StaffSet(pitched: StaffSpec.pitched()),
    sections: <Section>[
      Section(
        id: 'A',
        label: const SectionLabel.letter('A'),
        bars: <Bar>[for (int index = 0; index < 8; index++) makeBar(index % 4)],
      ),
    ],
  );
}

/// A one-song library holding [song].
IRealLibrary libraryOf(Song song) => IRealLibrary(
  playlistName: '',
  songs: <IRealSong>[IRealSong(index: 0, song: song)],
);

/// Registers a real font under the family the theme asks for, so the images carry words instead of
/// the framework's test boxes.
Future<String?> loadFont() async {
  const List<String> candidates = <String>[
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  for (final String path in candidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final ByteData face = ByteData.sublistView(file.readAsBytesSync());
    // THE FONT IS REGISTERED UNDER THREE FAMILY NAMES, and the second and third are the point: a
    // widget test's default text style carries no family, so the theme's family covers the SHELL and
    // nothing else — the chord symbols are drawn from `FlutterTextMetrics`, whose styles name no
    // family and fell back to the framework's box font. Registering the same face as `Roboto` gives
    // the page real words in a screenshot that is meant to be looked at.
    for (final String family in <String>[_fontFamily, 'Roboto', 'Segoe UI']) {
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(face));
      await loader.load();
    }
    stdout.writeln('ui.render.font path=$path family=$_fontFamily+Roboto');
    await _loadIconFont();
    return _fontFamily;
  }
  stdout.writeln('ui.render.font NONE — the images are layout-only');
  return null;
}

/// Registers the Material Icons font the application's own controls draw with, so a screenshot shows
/// the pen and the lock instead of the framework's placeholder boxes. Taken from the Flutter cache
/// when it exists and skipped when it does not: a missing icon font changes no rectangle, and the
/// geometry is what this instrument measures.
Future<void> _loadIconFont() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  final List<String> candidates = <String>[
    if (root != null)
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ];
  for (final String path in candidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final FontLoader loader = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    await loader.load();
    stdout.writeln('ui.render.iconfont path=$path');
    return;
  }
  stdout.writeln('ui.render.iconfont NONE — controls are drawn as boxes');
}

/// Wraps the viewer in the application's own theme and a Russian locale, because the owner's tablet
/// is in Russian and a screen read in English would not be the screen he complained about.
Widget shell() => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
    fontFamily: _fontFamily,
  ),
  locale: const Locale('ru'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: IRealViewerScreen(
    loader: (String path) async => libraryOf(notationChart()),
    initialPath: 'synthetic',
    // THE OWNER'S TABLET HAS NO PATH FIELD, and the platform the probe happens to run on does: a
    // Windows test run reports a filesystem source, so the shell it drew was the DESKTOP one — a
    // path FIELD, a chooser and a load button on a row of their own — while the tablet's shell has a
    // single action in the bar. Measured on the wrong shell, the composition question is answered
    // about a screen nobody in this report uses, so the probe pins the platform's answer.
    sourceIsFilePath: false,
  ),
);

/// The page the chart painter is currently drawing.
PageLayout page(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return (tester.widget<CustomPaint>(finder).painter! as ChartPainter).page;
}

/// Writes the whole widget tree [key] names into a PNG at [name].
Future<void> capture(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  double pixelRatio = 1.6,
}) async {
  final Finder finder = find.byKey(key);
  final RenderRepaintBoundary boundary =
      finder.evaluate().first.renderObject! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    if (png == null) {
      stdout.writeln('ui.render.failed name=$name');
      return;
    }
    final String outDir =
        Platform.environment['SHELL_PROBE_OUT'] ?? shellProbeDirectory;
    final File out = File('$outDir${Platform.pathSeparator}$name.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(png.buffer.asUint8List());
    stdout.writeln(
      'ui.render.written name=$name path=${out.path} '
      'bytes=${png.lengthInBytes}',
    );
  });
}

/// Every string a band of the shell is showing, so "what is in this row" is read off the run.
String texts(WidgetTester tester, Finder within) {
  final List<String> found = <String>[];
  for (final Element element in within.evaluate()) {
    void visit(Element node) {
      final Widget widget = node.widget;
      if (widget is Text && widget.data != null) {
        found.add(widget.data!);
      }
      node.visitChildren(visit);
    }

    visit(element);
  }
  return found.isEmpty ? '—' : found.join(' | ');
}

/// Prints one band of the shell: its rectangle, its height, and what it says.
void band(WidgetTester tester, String label, Finder finder) {
  if (finder.evaluate().isEmpty) {
    stdout.writeln('ui.band $label absent');
    return;
  }
  final Rect rect = tester.getRect(finder.first);
  stdout.writeln(
    'ui.band $label top=${rect.top.toStringAsFixed(1)} '
    'height=${rect.height.toStringAsFixed(1)} '
    'width=${rect.width.toStringAsFixed(1)} '
    'texts=${texts(tester, finder)}',
  );
}

/// Reports every band of the shown shell, top to bottom, and the pane the music is left with.
void reportShownShell(WidgetTester tester, String prefix) {
  band(tester, '$prefix.app-bar', find.byType(AppBar));
  band(
    tester,
    '$prefix.open-file-row',
    find.ancestor(
      of: find.byKey(const ValueKey<String>('viewer-open-file')),
      matching: find.byType(Padding),
    ),
  );
  band(
    tester,
    '$prefix.song-header',
    find.ancestor(
      of: find.byKey(const ValueKey<String>('viewer-song-info')),
      matching: find.byType(Padding),
    ),
  );
  band(
    tester,
    '$prefix.scene-bar',
    find.byKey(const ValueKey<String>('scene-bar')),
  );
  band(
    tester,
    '$prefix.selection-line',
    find.ancestor(
      of: find.byKey(const ValueKey<String>('viewer-selection-label')),
      matching: find.byType(Padding),
    ),
  );
  band(
    tester,
    '$prefix.document-frame',
    find.byKey(const ValueKey<String>('viewer-document-frame')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the shown and hidden shell at the owner tablet', (
    WidgetTester tester,
  ) async {
    await loadFont();
    tester.view.physicalSize = tabletLandscape;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GlobalKey root = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: root, child: shell()));
    await tester.pumpAndSettle();
    stdout.writeln(
      'ui.window tablet '
      'logical=${tabletLandscape.width.toStringAsFixed(1)}x'
      '${tabletLandscape.height.toStringAsFixed(1)}',
    );
    reportShownShell(tester, 'shown');
    final Size window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final Rect frame = tester.getRect(
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    stdout.writeln(
      'ui.band shown.status-line top=${frame.bottom.toStringAsFixed(1)} '
      'height=${(window.height - frame.bottom).toStringAsFixed(1)}',
    );
    stdout.writeln(
      'ui.sum shown.top_block_cost=${frame.top.toStringAsFixed(1)} '
      'pane=${frame.width.toStringAsFixed(1)}x${frame.height.toStringAsFixed(1)} '
      'scale=${page(tester).scale.toStringAsFixed(4)} '
      'systems=${page(tester).systems.length}',
    );
    await capture(tester, root, 'tablet-chrome-shown');

    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
    );
    await tester.pumpAndSettle();
    band(
      tester,
      'hidden.document-frame',
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    final Rect hiddenFrame = tester.getRect(
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    stdout.writeln(
      'ui.sum hidden.top_block_cost=${hiddenFrame.top.toStringAsFixed(1)} '
      'pane=${hiddenFrame.width.toStringAsFixed(1)}x'
      '${hiddenFrame.height.toStringAsFixed(1)} '
      'scale=${page(tester).scale.toStringAsFixed(4)}',
    );
    await capture(tester, root, 'tablet-chrome-hidden');
  });

  testWidgets('the short landscape surface in all three states', (
    WidgetTester tester,
  ) async {
    await loadFont();
    tester.view.physicalSize = shortLandscape;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GlobalKey root = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: root, child: shell()));
    await tester.pumpAndSettle();
    reportShownShell(tester, 'short.shown');
    final Rect shown = tester.getRect(
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    stdout.writeln(
      'ui.sum short.shown pane=${shown.width.toStringAsFixed(1)}x'
      '${shown.height.toStringAsFixed(1)}',
    );
    await capture(tester, root, 'short-chrome-shown');
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
    );
    // ONE FRAME, NOT `pumpAndSettle`: the transitional state is the one this probe exists for.
    await tester.pump();
    final Rect transition = tester.getRect(
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    stdout.writeln(
      'ui.sum short.transition pane=${transition.width.toStringAsFixed(1)}x'
      '${transition.height.toStringAsFixed(1)}',
    );
    await capture(tester, root, 'short-chrome-transition');
    await tester.pumpAndSettle();
    final Rect hidden = tester.getRect(
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    stdout.writeln(
      'ui.sum short.hidden pane=${hidden.width.toStringAsFixed(1)}x'
      '${hidden.height.toStringAsFixed(1)}',
    );
    await capture(tester, root, 'short-chrome-hidden');
  });

  testWidgets('the note palette over a staff that carries notes', (
    WidgetTester tester,
  ) async {
    await loadFont();
    tester.view.physicalSize = tabletLandscape;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GlobalKey root = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: root, child: shell()));
    await tester.pumpAndSettle();
    final PageLayout chart = page(tester);
    final PlacedSystem system = chart.systems.first;
    final PlacedBar firstBar = system.bars.first;
    final LayoutRect staff = firstBar.melody.bounds;
    final PlacedCell cell = firstBar.cells[1];
    final LayoutOffset surface = chart.surfacePointOf(
      LayoutOffset(
        cell.bounds.left + cell.bounds.size.width / 2,
        staff.top + staff.size.height / 2,
      ),
    );
    final Offset frame = tester.getTopLeft(
      find.byKey(const ValueKey<String>('viewer-document-frame')),
    );
    stdout.writeln(
      'ui.staff bar=${firstBar.barIndex} beat=${cell.beat} '
      'page_staff=(${staff.left.toStringAsFixed(1)},'
      '${staff.top.toStringAsFixed(1)},'
      '${staff.size.width.toStringAsFixed(1)}x'
      '${staff.size.height.toStringAsFixed(1)}) '
      'surface=(${surface.x.toStringAsFixed(1)},${surface.y.toStringAsFixed(1)}) '
      'scale=${chart.scale.toStringAsFixed(4)}',
    );
    await tester.tapAt(frame + Offset(surface.x, surface.y));
    await tester.pumpAndSettle();
    band(tester, 'palette', find.byType(BottomSheet));
    await capture(tester, root, 'tablet-note-palette');
    final Finder done = find.byKey(const ValueKey<String>('note-palette-done'));
    if (done.evaluate().isNotEmpty) {
      await tester.tap(done);
      await tester.pumpAndSettle();
    }
    await capture(tester, root, 'tablet-staff-selected');
  });

  testWidgets('the staff under the zoom control, where a musician reads it', (
    WidgetTester tester,
  ) async {
    await loadFont();
    tester.view.physicalSize = tabletLandscape;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GlobalKey root = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: root, child: shell()));
    await tester.pumpAndSettle();
    for (int step = 0; step < 2; step++) {
      final Finder zoomIn = find.byKey(
        const ValueKey<String>('scene-bar-zoom-in'),
      );
      if (zoomIn.evaluate().isEmpty) {
        break;
      }
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
    }
    final PageLayout chart = page(tester);
    stdout.writeln(
      'ui.zoom scale=${chart.scale.toStringAsFixed(4)} '
      'zoom=${chart.zoom.toStringAsFixed(4)} '
      'drawnScale=${chart.drawnScale.toStringAsFixed(4)} '
      'pan=(${chart.pan.x.toStringAsFixed(1)},'
      '${chart.pan.y.toStringAsFixed(1)})',
    );
    await capture(tester, root, 'tablet-staff-zoomed');
  });
}
