// PURPOSE: LOOK at every form operation — a bar put in, copied and taken out; a section added,
//          renamed, copied, moved and removed — as a PNG of the page before and a PNG after, taken
//          through the same `EditSession`, the same operation log and the same reducer the
//          application uses, and prove that undo restores the document exactly. A comparison of two
//          images that differ by exactly one bar is the only evidence that says WHICH bar changed,
//          and a boolean assertion cannot: `engine.layout(...).bars.length` is `9` whether the ninth
//          bar appeared in the right place or the wrong one.
//
//          The round trip at the end is the same kind of evidence for the file: the edited document
//          is written through `chartFileFor` — the function the Save button calls — read back through
//          the container's codec, and every half of the file is compared to what was put in. When
//          those comparisons disagree, the line says what disagreed, because the disagreement is the
//          finding.
// INPUTS: None. The chart is synthetic, so this instrument runs on any machine. A real system font
//         is loaded when one is found, because the framework's default test font draws every glyph
//         as a filled box and a page of boxes cannot show which bar moved.
// OUTPUTS: PNGs under [formRenderDirectory], outside the repository, named for the case and the
//          side; `form.*` lines on stdout carrying every section with its label and the chords of
//          each bar on both sides of every edit; and the round-trip comparison. Rendering happens
//          under `flutter test`, which runs the real engine with no window: a window on this machine
//          would take focus from whoever is working at it.
// KEYWORDS: headless-render, png, before-and-after, song-form, bars, sections, op-log, undo,
//           exact-restore, chart-file, round-trip, evidence, no-window
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/chart_document.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The logical page the instrument engraves at. Narrow enough that a section of four bars is close
/// to a full system, so adding one bar visibly re-flows the page rather than hiding in the margin.
const double formPageWidth = 640;
const double formPageHeight = 620;

/// Where the PNGs and the round-trip file are written. Outside the repository: an image is evidence
/// for one inspection, not an artefact to commit.
const String formRenderDirectory =
    r'C:\projects\ChartApp-acl-reports\render\song-form';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartFormRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The document id the instrument's session writes under.
const String _docId = 'chartapp-song-form';

/// One form operation the instrument exercises: what it is called, what a musician asked for in
/// words, and the call that performs it.
typedef FormOp = ({String name, String asked, bool Function(EditSession) run});

/// The operations, one case each. Every case starts from the same two-section fixture and is undone
/// before the next one, so each pair of images is about one operation and nothing else.
final List<FormOp> formOps = <FormOp>[
  (
    name: 'bar-insert-before',
    asked: 'a blank bar in front of the second bar of A',
    run: (EditSession session) =>
        session.insertBarBefore(sectionId: 'A', barIndex: 1),
  ),
  (
    name: 'bar-insert-after',
    asked: 'a blank bar behind the second bar of A',
    run: (EditSession session) =>
        session.insertBarAfter(sectionId: 'A', barIndex: 1),
  ),
  (
    name: 'bar-duplicate',
    asked: 'a copy of the second bar of A, after it',
    run: (EditSession session) =>
        session.duplicateBar(sectionId: 'A', barIndex: 1),
  ),
  (
    name: 'bar-delete',
    asked: 'the second bar of A removed',
    run: (EditSession session) =>
        session.deleteBar(sectionId: 'A', barIndex: 1),
  ),
  (
    name: 'section-insert-before',
    asked: 'a new one-bar section in front of A',
    run: (EditSession session) => session.insertSectionBefore('A') != null,
  ),
  (
    name: 'section-insert-after',
    asked: 'a new one-bar section behind A',
    run: (EditSession session) => session.insertSectionAfter('A') != null,
  ),
  (
    name: 'section-duplicate',
    asked: 'a copy of section A, after it, under a new identity',
    run: (EditSession session) => session.duplicateSection('A') != null,
  ),
  (
    name: 'section-rename',
    asked: 'section B relabelled Vamp',
    run: (EditSession session) =>
        session.renameSection('B', const SectionLabel.custom('Vamp')),
  ),
  (
    name: 'section-reorder',
    asked: 'section B moved in front of A',
    run: (EditSession session) => session.moveSection('B', -1),
  ),
  (
    name: 'section-delete',
    asked: 'section B removed',
    run: (EditSession session) => session.deleteSection('B'),
  ),
  // The song's own facts are an operation like any other and belong in this instrument for the same
  // reason: undo must restore them exactly. Their two PNGs are IDENTICAL, and that is the finding
  // rather than a defect — a title, a composer, a style and a tempo are not page geometry, so a
  // metadata edit must not re-flow the chart. The comparison below states that explicitly.
  (
    name: 'song-update',
    asked: 'the tune renamed, retitled, and set to Ballad at 96',
    run: (EditSession session) => session.updateSong(
      title: 'Song form (edited)',
      composer: 'ChartApp & co',
      style: 'Ballad',
      tempo: 96,
    ),
  ),
];

// PURPOSE: Build the chart every case starts from: two sections of four bars, each bar carrying a
//          major seventh on its first cell and a minor seventh on its third, with a different root
//          per bar so a bar's identity is readable on the page and in the dump.
// INPUTS: None.
// OUTPUTS: A [Song] in C major with sections A and B, eight bars in total.
// KEYWORDS: fixture, synthetic-song, two-sections, visible-chords, bar-identity
Song formChart() => Song(
  id: _docId,
  title: 'Song form',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    for (int section = 0; section < 2; section++)
      Section(
        id: section == 0 ? 'A' : 'B',
        label: SectionLabel.letter(section == 0 ? 'A' : 'B'),
        bars: <Bar>[
          for (int index = 0; index < 4; index++)
            Bar(
              chords: <ChordMark>[
                ChordMark(
                  place: placeIn(section == 0 ? 'A' : 'B', index, 0),
                  chord: Chord(
                    root: ChordRoot(section * 4 + index),
                    quality: ChordQuality.majorSeventh,
                  ),
                ),
                ChordMark(
                  place: placeIn(section == 0 ? 'A' : 'B', index, 2),
                  chord: Chord(
                    root: ChordRoot(section * 4 + index),
                    quality: ChordQuality.minorSeventh,
                  ),
                ),
              ],
            ),
        ],
      ),
  ],
);

/// The metrics the page is measured and drawn with, in the loaded family.
FlutterTextMetrics _metricsFor(String family) => FlutterTextMetrics(
  chordStyle: TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
  smallChordStyle: TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
  sectionLabelStyle: TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF2E5D8A),
  ),
  staffTextStyle: TextStyle(
    fontFamily: family,
    fontSize: 10,
    color: const Color(0xFF486581),
  ),
);

/// The engine the pages are produced with: the viewer's own spacing constants.
LayoutEngine _layoutEngine(FlutterTextMetrics metrics) => LayoutEngine(
  style: LayoutStyle(
    textMetrics: metrics,
    pageMargin: 20,
    barMinWidth: 64,
    barPadding: 8,
    chordSpacing: 12,
    minCellWidth: 18,
    barHeight: 52,
    systemSpacing: 18,
    sectionLabelHeight: 26,
  ),
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot show which bar moved.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, readable-text
Future<String?> _loadChartFont() async {
  for (final String path in _fontCandidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final FontLoader loader = FontLoader(_fontFamily)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    await loader.load();
    stdout.writeln('render.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Paint the first laid-out page of [song] into a PNG.
// INPUTS: song — the chart to draw. engine and metrics — how it is engraved. out — where the bytes
//         go.
// OUTPUTS: Writes the file and returns the page it drew, so the caller can report the page count
//          and the scale. Throws when the engine produced no page, because a missing page is not a
//          rendering of "nothing".
// KEYWORDS: paint, picture-recorder, to-image, png, page-count, dispose
Future<PageLayout> _renderPage(
  Song song,
  LayoutEngine engine,
  FlutterTextMetrics metrics,
  File out,
) async {
  const double pixelRatio = 2;
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: formPageWidth,
    pageHeight: formPageHeight,
  );
  if (pages.isEmpty) {
    throw StateError('the engine produced no page for ${out.path}');
  }
  final PageLayout page = pages.first;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
  ).paint(canvas, ui.Size(formPageWidth, formPageHeight));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (formPageWidth * pixelRatio).round(),
    (formPageHeight * pixelRatio).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  image.dispose();
  picture.dispose();
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(png.buffer.asUint8List());
  return page;
}

// PURPOSE: Write down every section of [song] with its label and the chords of each of its bars, so
//          the PNG and this text can be read against each other. The image says what the page looks
//          like; this says what the document holds, and a disagreement between them is the kind of
//          defect neither one alone can show.
// INPUTS: label — the column this dump is tagged with. song — the chart to describe.
// OUTPUTS: One line per section, plus one line per bar. A section with no bars prints `(no bars)`
//          and a bar with no chords prints `(blank)`, so an absence is stated rather than omitted.
// KEYWORDS: document-dump, section-list, bar-chords, before-and-after, falsifiable
void _dumpSections(String label, Song song) {
  stdout.writeln(
    'form.$label song="${song.title}" sections=${song.sections.length} '
    'bars=${song.writtenBarCount}',
  );
  for (int index = 0; index < song.sections.length; index++) {
    final Section section = song.sections[index];
    stdout.writeln(
      'form.$label section[$index] id="${section.id}" '
      'label="${section.label}" bars=${section.bars.length}',
    );
    for (int barIndex = 0; barIndex < section.bars.length; barIndex++) {
      stdout.writeln(
        'form.$label   ${section.id}[$barIndex] '
        '${_barText(song, section.bars[barIndex])}',
      );
    }
  }
}

/// One bar of [song] as `chord@beat` pairs, or `(blank)` when it holds none.
String _barText(Song song, Bar bar) => bar.chords.isEmpty
    ? '(blank)'
    : bar.chords
          .map(
            (ChordMark placed) =>
                '${placed.chord.render(song.key, const SpellingTable())}'
                '@${placed.offsetX.toStringAsFixed(1)}',
          )
          .join(',');

// PURPOSE: Compare two operation tails element by element, because `List ==` in Dart is identity
//          and a line printed from it would say two equal lists differ — a false finding is worse
//          than no finding.
// INPUTS: left and right — the two event lists, in log order.
// OUTPUTS: True when they have the same length and every event is equal by its own `==`; false
//          otherwise, including when either list is empty and the other is not.
// KEYWORDS: list-equality, deep-comparison, element-order, evidence-correctness
bool _sameEvents(List<ChartEvent> left, List<ChartEvent> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

// PURPOSE: Fingerprint a written PNG so two renderings can be compared without a picture viewer in
//          the loop, which is what makes "the same page came out again" checkable for cases whose
//          images a reader would otherwise have to compare by eye one at a time.
// INPUTS: file — the file to fingerprint.
// OUTPUTS: Eight hex digits of the FNV-1a hash of the file's bytes. It is a comparison aid and not
//          a security hash: it is here to say two files are byte-identical, and a collision would
//          make it say so wrongly, which is a risk this instrument accepts and names.
// KEYWORDS: fingerprint, fnv1a, byte-identity, comparison-aid, honest-limit
String _fingerprint(File file) {
  int hash = 0x811c9dc5;
  for (final int byte in file.readAsBytesSync()) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the page before and after every form operation, and undo restores it', () async {
    final String? family = await _loadChartFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show which bar moved',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = _layoutEngine(metrics);
    final Directory outDir = Directory(formRenderDirectory);
    outDir.createSync(recursive: true);
    final EditSession session = EditSession(
      document: DocumentState(song: formChart()),
      docId: _docId,
    );
    final DocumentState fixture = session.document;

    for (final FormOp op in formOps) {
      // Every case starts from the restored fixture, which is only true if the previous case's undo
      // put the whole document back. That check is what makes the before image of the next case
      // describe the fixture rather than whatever the last edit left behind.
      expect(
        session.document,
        fixture,
        reason: '${op.name} must start from the unedited fixture',
      );
      final File beforePng = File(
        '${outDir.path}${Platform.pathSeparator}${op.name}-before@2x.png',
      );
      final File afterPng = File(
        '${outDir.path}${Platform.pathSeparator}${op.name}-after@2x.png',
      );
      final PageLayout beforePage = await _renderPage(
        session.song,
        engine,
        metrics,
        beforePng,
      );
      _dumpSections('${op.name}.before', session.song);

      final bool applied = op.run(session);
      expect(applied, isTrue, reason: '${op.name}: ${op.asked}');

      final PageLayout afterPage = await _renderPage(
        session.song,
        engine,
        metrics,
        afterPng,
      );
      _dumpSections('${op.name}.after', session.song);
      stdout.writeln(
        'form.case name=${op.name} asked="${op.asked}" '
        'sections_after=${session.song.sections.length} '
        'bars_after=${session.song.writtenBarCount} '
        'events=${session.log.map((ChartEvent event) => event.type).toList()} '
        'before_page_bars=${beforePage.bars.length} '
        'after_page_bars=${afterPage.bars.length} '
        'before_png=${beforePng.path} after_png=${afterPng.path} '
        'before_fp=${_fingerprint(beforePng)} after_fp=${_fingerprint(afterPng)}',
      );

      final bool undone = session.undo();
      final DocumentState restored = session.document;
      stdout.writeln(
        'form.undo name=${op.name} undone=$undone '
        'doc_equal=${restored == fixture} song_equal=${restored.song == fixture.song} '
        'strokes=${restored.strokes.length}==${fixture.strokes.length} '
        'annotations=${restored.annotations.length}==${fixture.annotations.length} '
        'cues=${restored.textCues.length}==${fixture.textCues.length} '
        'sections=${restored.song.sections.length} '
        'bars=${restored.song.writtenBarCount}',
      );
      expect(undone, isTrue, reason: 'undo must be available after ${op.name}');
      expect(
        restored,
        fixture,
        reason: 'undo of ${op.name} must restore the whole DocumentState',
      );
    }
  });

  test('an edited session survives the .chart container and reopens equal', () {
    final EditSession session = EditSession(
      document: DocumentState(song: formChart()),
      docId: _docId,
    );
    final List<String> steps = <String>[];
    void record(String what, bool applied) =>
        steps.add('$what=${applied ? 'ok' : 'REFUSED'}');

    record(
      'bar.insert.after.A0',
      session.insertBarAfter(sectionId: 'A', barIndex: 0),
    );
    record(
      'bar.duplicate.A0',
      session.duplicateBar(sectionId: 'A', barIndex: 0),
    );
    record('bar.delete.B0', session.deleteBar(sectionId: 'B', barIndex: 0));
    record('section.insert.after.B', session.insertSectionAfter('B') != null);
    record('section.duplicate.A', session.duplicateSection('A') != null);
    record(
      'section.rename.B',
      session.renameSection('B', const SectionLabel.custom('Vamp')),
    );
    record('section.reorder.B.earlier', session.moveSection('B', -1));
    record(
      'song.update',
      session.updateSong(
        title: 'Form Fixture (edited)',
        style: 'Ballad',
        tempo: 96,
      ),
    );

    final DocumentState saved = session.document;
    // THE SHAPE THE APPLICATION WRITES: the snapshot is the session's BASE document — the state
    // before its log — and the tail is the log. Writing the CURRENT document here, with the log
    // beside it, is measured by the negative control at the end of this test.
    final ChartFile file = chartFileFor(
      session.baseDocument,
      events: session.log,
      modifiedAt: DateTime.utc(2026, 10, 10, 12),
    );
    final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
    final Directory outDir = Directory(formRenderDirectory);
    outDir.createSync(recursive: true);
    final File path = File(
      '${outDir.path}${Platform.pathSeparator}song-form-round-trip.chart',
    );
    path.writeAsBytesSync(encoded.bytes);
    final ChartFileDecodeResult decoded = ChartFileCodec.decode(
      path.readAsBytesSync(),
    );

    _dumpSections('roundtrip.saved', saved.song);
    stdout.writeln(
      'form.roundtrip path=${path.path} bytes=${encoded.bytes.length} '
      'warnings=${decoded.warnings.length} '
      'operations_saved=${file.events.length} '
      'operations_read=${decoded.file.events.length} '
      'steps=${steps.join(',')}',
    );

    // WHAT IS COMPARED, HALF BY HALF. The file is a snapshot plus a tail, so each half is compared
    // to the value that went in: the snapshot to the state the session started from, and the tail to
    // the operations made since.
    expect(
      decoded.file.snapshot,
      session.baseDocument,
      reason: 'the snapshot must be the state before the operations',
    );
    expect(
      _sameEvents(decoded.file.events, session.log),
      isTrue,
      reason: 'the tail must be the operations that were made',
    );
    stdout.writeln(
      'form.roundtrip.halves file_equal=${decoded.file == file} '
      'snapshot_equal=${decoded.file.snapshot == session.baseDocument} '
      'tail_equal=${_sameEvents(decoded.file.events, session.log)} '
      'tail_types=${decoded.file.events.map((ChartEvent event) => event.type).toList()}',
    );

    // THE PROOF IS REOPENING, NOT ARITHMETIC. A session opened the way the viewer opens one — from
    // the snapshot with the tail restored — must hold the chart that was saved: same form, same
    // strokes, same title, style and tempo.
    final EditSession reopened = EditSession(
      document: decoded.file.snapshot,
      docId: decoded.file.metadata.docId,
      seq: decoded.file.events.last.seq,
      restored: decoded.file.events,
    );
    stdout.writeln(
      'form.roundtrip.reopened equal_to_saved=${reopened.document == saved} '
      'bars_saved=${saved.song.writtenBarCount} '
      'bars_reopened=${reopened.song.writtenBarCount} '
      'sections_saved=${saved.song.sections.length} '
      'sections_reopened=${reopened.song.sections.length} '
      'strokes_reopened=${reopened.document.strokes.length} '
      'title="${reopened.song.title}" style=${reopened.song.style} '
      'tempo=${reopened.song.tempo} seq=${reopened.seq} '
      'undo_depth=${reopened.undoDepth}',
    );
    _dumpSections('roundtrip.reopened', reopened.song);
    expect(
      reopened.document,
      saved,
      reason: 'the reopened chart must be the chart that was saved',
    );
    expect(reopened.document.song.title, 'Form Fixture (edited)');
    expect(reopened.document.song.style, 'Ballad');
    expect(reopened.document.song.tempo, 96);

    // THE NEGATIVE CONTROL, WITHOUT WHICH THE CHECK ABOVE PROVES NOTHING. It builds the shape this
    // writer used to produce — the CURRENT document as the snapshot with the log beside it — and
    // requires that reopening it is NOT the saved chart. If a run ever reports these as equal, the
    // reopen check has stopped being able to fail and the test is worthless.
    final ChartFile doubled = chartFileFor(
      saved,
      events: session.log,
      modifiedAt: DateTime.utc(2026, 10, 10, 12),
    );
    final ChartFile decodedDoubled = ChartFileCodec.decode(
      ChartFileCodec.encode(doubled).bytes,
    ).file;
    DocumentState? doubledReopened;
    String doubledOutcome;
    try {
      doubledReopened = EditSession(
        document: decodedDoubled.snapshot,
        docId: decodedDoubled.metadata.docId,
        seq: decodedDoubled.events.last.seq,
        restored: decodedDoubled.events,
      ).document;
      doubledOutcome = doubledReopened == saved
          ? 'EQUAL, WHICH WOULD MAKE THE REOPEN CHECK WORTHLESS'
          : 'different, as it must be';
    } on DocumentReducerException catch (error) {
      doubledOutcome = 'refused by the reducer: ${error.message}';
    }
    stdout.writeln(
      'form.roundtrip.negative_control outcome="$doubledOutcome" '
      'bars_saved=${saved.song.writtenBarCount} '
      'bars_doubled=${doubledReopened?.song.writtenBarCount} '
      'sections_saved=${saved.song.sections.length} '
      'sections_doubled=${doubledReopened?.song.sections.length}',
    );
    expect(
      doubledReopened == saved,
      isFalse,
      reason:
          'the doubled shape must reopen differently or be refused, or the reopen check '
          'above proves nothing',
    );
  });
}
