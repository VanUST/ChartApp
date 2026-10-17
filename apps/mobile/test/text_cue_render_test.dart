// PURPOSE: LOOK at the words written on a chart. Render the SAME music to a PNG before a cue is
//          added and after it is written, changed and moved, through the same session, the same
//          operation log and the same reducer the application uses, and render the FITTED page for
//          each case — because that is where geometry goes silently wrong. It is the instrument the
//          text-cue slice is verified with, and it exists because an assertion cannot answer the two
//          questions this feature is actually about: whether the words can be READ at arm's length,
//          and whether they are still on the bar they were written on.
// INPUTS: None. The chart is synthetic, so this instrument runs on any machine. A real system font
//         is loaded when one is found, because the framework's default test font draws every glyph
//         as a filled box and a page of boxes cannot show a sentence.
// OUTPUTS: PNGs under [textCueRenderDirectory], outside the repository, named for the case — before,
//          after the cue is written, after its words change, after it moves, and the fitted page for
//          each — plus `cue.*` lines on stdout carrying the cue's address, the anchor's origin on the
//          page, the position it is therefore drawn at, a fingerprint of every image (so "the same
//          music" and "the image really changed" are checkable rather than plausible), the whole
//          `DocumentState` comparison after every undo, and the three survival cases.
// KEYWORDS: headless-render, png, text-cue, before-and-after, fitted-page, transposition,
//           round-trip, evidence, no-window, font, undo-document-equality, negative-control
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/chart_document.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logical page width and height: the tablet viewport the other render instruments use.
const double cuePageWidth = 824;
const double cuePageHeight = 600;

/// A surface deliberately narrower than one system of this chart, so the fitter must shrink the
/// engravings and `page.scale` comes out below 1. A surface that happened to fit would give scale 1,
/// which is exactly the case this instrument must avoid — a position computed without the scale is
/// right for every ordinary page and wrong only for a fitted one.
const double cueFitWidth = 260;
const double cueFitHeight = 180;

/// Where the PNGs are written. Outside the repository: a rendered image is evidence for one
/// inspection, not an artefact to commit.
const String textCueRenderDirectory =
    r'C:\projects\ChartApp-acl-reports\render\text-cue';

/// The section the cue is written on.
const String _section = 'A';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartCueRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The words the cue starts with — the example the sheet's own helper text names.
const String _firstWords = 'To Coda';

/// The words it is edited to, which is the whole point of the feature: a sentence, not a symbol.
const String _editedWords = 'D.C. al Fine';

// PURPOSE: Build the chart this instrument writes on. One section of four bars, every bar carrying a
//          chord on its first cell and a second chord on its third, so that a cue drawn over one bar
//          has a neighbour on each side to be compared against and cannot be mistaken for one drawn
//          over the page.
// INPUTS: None.
// OUTPUTS: A song in C major whose bars hold `C^7` on cell 1 and `E-7` on cell 3.
// KEYWORDS: fixture, synthetic-song, one-section, four-bars, two-chords-per-bar
Song textCueChart() => Song(
  id: 'chartapp-text-cue',
  title: 'Text cue',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: _section,
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < 4; index++)
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: cellAt(0),
                chord: Chord(
                  root: ChordRoot(index),
                  quality: ChordQuality.majorSeventh,
                ),
              ),
              ChordMark(
                place: cellAt(2),
                chord: Chord(
                  root: ChordRoot(index + 2),
                  quality: ChordQuality.minorSeventh,
                ),
              ),
            ],
          ),
      ],
    ),
  ],
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot show which words are written.
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
  // The cue is measured with the style it is drawn with, so the row the layout reserves above a
  // bar and the plate drawn in it are the same box. The family matches the painter's style, which
  // this instrument passes to `TextCuePainter`.
  textCueStyle: TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
);

/// The engine this instrument lays the chart out with — the viewer's own constants.
LayoutEngine _engineFor(FlutterTextMetrics metrics) => LayoutEngine(
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

// PURPOSE: Resolve every cue against one page exactly as the viewer's `_resolveCues` does — by
//          reading the row the LAYOUT placed it in — so the instrument measures the product's own
//          placement and not a second implementation of it.
// INPUTS: page — the layout to resolve against. document — the state holding the cues.
// OUTPUTS: The cues this page has a row for, with the row's origin and box in the page's engraved
//          coordinates, in the document's render order.
// KEYWORDS: cue-row-lookup, viewer-parity, single-implementation, render-order
List<ResolvedTextCue> _resolveCues(PageLayout page, DocumentState document) {
  final Map<String, PlacedTextCue> placedById = <String, PlacedTextCue>{};
  for (final PlacedBar bar in page.bars) {
    for (final PlacedTextCue placed in bar.textCues) {
      placedById[placed.id] = placed;
    }
  }
  final List<ResolvedTextCue> resolved = <ResolvedTextCue>[];
  for (final TextCue cue in document.textCues) {
    final PlacedTextCue? placed = placedById[cue.id];
    if (placed == null) {
      continue;
    }
    resolved.add(
      ResolvedTextCue(cue: cue, origin: placed.origin, size: placed.size),
    );
  }
  return resolved;
}

// PURPOSE: Paint one page into a PNG, stacked exactly as the viewer stacks it: the chart, then the
//          cue layer, with both given the page's own scale.
// INPUTS: page, song, metrics and out as in the other render instruments. document — the state
//         holding the cues, so the layer draws the words the log produced. logicalWidth and
//         logicalHeight — the surface the painter is handed, which for a fitted page is the
//         SHRUNKEN surface the page scale maps onto.
// OUTPUTS: Writes the PNG and returns nothing. The image and picture are disposed, because they hold
//          engine-side memory.
// KEYWORDS: paint, picture-recorder, to-image, png, fitted-surface, cue-layer, dispose
Future<void> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  DocumentState document,
  File out, {
  double logicalWidth = cuePageWidth,
  double logicalHeight = cuePageHeight,
}) async {
  const double pixelRatio = 2;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  final ui.Size size = ui.Size(logicalWidth, logicalHeight);
  ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, size);
  TextCuePainter(
    cues: _resolveCues(page, document),
    pageScale: page.scale,
    textStyle: TextCuePainter.defaultTextStyle.copyWith(
      fontFamily: metrics.staffTextStyle.fontFamily,
    ),
  ).paint(canvas, size);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (logicalWidth * pixelRatio).round(),
    (logicalHeight * pixelRatio).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  image.dispose();
  picture.dispose();
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(png.buffer.asUint8List());
}

// PURPOSE: Fingerprint a written PNG, so "the image really changed" and "the fixture really came
//          back to the same music" are numbers to compare rather than impressions. FNV-1a rather
//          than a cryptographic hash because this is a check against ACCIDENTAL identity, not
//          against a forger, and it needs no dependency.
// INPUTS: file — the PNG just written.
// OUTPUTS: Eight hexadecimal digits of the file's bytes. Two renders of the same state give the
//          same digits; a changed page gives different ones with overwhelming likelihood.
// KEYWORDS: fingerprint, fnv1a, byte-comparison, accidental-identity, no-dependency
String _fingerprint(File file) {
  int hash = 0x811C9DC5;
  for (final int byte in file.readAsBytesSync()) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// PURPOSE: Render one case — the ordinary page and, separately, the fitted one — and print the
//          address, the row the layout reserved for the cue, the box it occupies and the chord
//          bounds of the same bar, so the PNG and the report describe the same page and the
//          reservation is a pair of numbers rather than an impression.
// INPUTS: engine — the layout engine. song — the music. metrics — the measured styles. document —
//         the state to draw, whose cues are handed to the engine. name — the case's name, which
//         becomes the file name. outDir — where to write. fitted — true to lay the page out through
//         `fitToPage` instead of `layout`.
// OUTPUTS: The written file for the ordinary case, and one `cue.case` line plus one `cue.wrote`
//          line per render, and one `cue.reserve` line per placed cue carrying the cue's surface
//          box, the top of the lowest chord of the same bar and the overlap between them. The
//          overlap line is the claim the image is being read to check.
// KEYWORDS: case-render, ordinary-and-fitted, report, fingerprint, reservation-numbers, evidence
Future<File> _renderCase({
  required LayoutEngine engine,
  required Song song,
  required FlutterTextMetrics metrics,
  required DocumentState document,
  required String name,
  required Directory outDir,
  bool fitted = false,
}) async {
  final List<PageLayout> pages;
  double scale = 1;
  if (fitted) {
    final FitOutcome outcome = engine.fitToPage(
      song,
      pageWidth: cueFitWidth,
      pageHeight: cueFitHeight,
      cues: document.textCues,
    );
    expect(
      outcome.page,
      isNotNull,
      reason: 'the four-bar fixture must fit a 260x180 surface legibly',
    );
    pages = <PageLayout>[outcome.page!];
    scale = outcome.page!.scale;
    expect(scale, lessThan(1), reason: 'the fitted case must actually shrink');
  } else {
    pages = engine.layout(
      song,
      pageWidth: cuePageWidth,
      pageHeight: cuePageHeight,
      cues: document.textCues,
    );
    expect(pages, hasLength(1), reason: 'the fixture is meant to be one page');
  }
  final PageLayout page = pages.first;
  final String suffix = fitted ? '-fit' : '';
  final File file = File(
    '${outDir.path}${Platform.pathSeparator}$name$suffix@2x.png',
  );
  await _renderToPng(
    page,
    song,
    metrics,
    document,
    file,
    logicalWidth: fitted ? cueFitWidth : cuePageWidth,
    logicalHeight: fitted ? cueFitHeight : cuePageHeight,
  );
  final List<ResolvedTextCue> resolved = _resolveCues(page, document);
  stdout.writeln(
    'cue.case name=$name$suffix page=${page.index} '
    'mode=${fitted ? 'fit' : 'pages'} scale=$scale '
    'bars=${page.bars.length} cues_drawn=${resolved.length} '
    'cues_in_document=${document.textCues.length}',
  );
  for (final ResolvedTextCue placed in resolved) {
    final TextCue cue = placed.cue;
    final double left = (placed.origin.x + cue.place.offsetX) * scale;
    final double top = (placed.origin.y + cue.place.offsetY) * scale;
    final double right = left + placed.size.width * scale;
    final double bottom = top + placed.size.height * scale;
    final PlacedBar bar = page.bars.firstWhere(
      (PlacedBar candidate) =>
          candidate.sectionId == cue.place.anchor.sectionId &&
          candidate.barIndex == cue.place.anchor.bar,
      orElse: () => throw StateError(
        'cue ${cue.id} resolved to a bar that is not on the page',
      ),
    );
    stdout.writeln(
      'cue.placed id=${cue.id} text="${cue.text}" '
      'anchor=${cue.place.anchor.sectionId}[${cue.place.anchor.bar}] '
      // The cell the cue names is read from its own x through the shim, because an anchor is a bar
      // and the position inside it is the offset printed on the next line.
      'cell=${cue.place.pseudoBeat} '
      'offset=(${cue.place.offsetX},${cue.place.offsetY}) '
      'origin_engraved=(${placed.origin.x.toStringAsFixed(2)},'
      '${placed.origin.y.toStringAsFixed(2)}) '
      'box_engraved=(${placed.size.width.toStringAsFixed(2)}x'
      '${placed.size.height.toStringAsFixed(2)}) '
      'drawn_surface=(${left.toStringAsFixed(2)},${top.toStringAsFixed(2)}) '
      'bar_engraved=(${bar.bounds.left.toStringAsFixed(2)},'
      '${bar.bounds.top.toStringAsFixed(2)})',
    );
    // The reservation, in the coordinates the reader sees: the cue's plate on the surface and the
    // bounds of the lowest chord of the same bar on the same surface. The plate must end above the
    // chord's top; a negative clearance would be the plate lying on a glyph.
    PlacedChord? highest;
    for (final PlacedChord chord in bar.chords) {
      if (highest == null || chord.bounds.top < highest.bounds.top) {
        highest = chord;
      }
    }
    final String clearance = highest == null
        ? 'no chord on this bar'
        : 'clearance_surface='
              '${(highest.bounds.top * scale - bottom).toStringAsFixed(2)} '
              'plate_bottom_surface=${bottom.toStringAsFixed(2)} '
              'chord_surface=(${(highest.bounds.left * scale).toStringAsFixed(2)},'
              '${(highest.bounds.top * scale).toStringAsFixed(2)})..'
              '(${(highest.bounds.right * scale).toStringAsFixed(2)},'
              '${(highest.bounds.bottom * scale).toStringAsFixed(2)})';
    stdout.writeln(
      'cue.reserve id=${cue.id} '
      'plate_surface=(${left.toStringAsFixed(2)},${top.toStringAsFixed(2)})..'
      '(${right.toStringAsFixed(2)},${bottom.toStringAsFixed(2)}) '
      '$clearance',
    );
  }
  stdout.writeln(
    'cue.wrote path=${file.path} bytes=${file.lengthSync()} '
    'fingerprint=${_fingerprint(file)} '
    'pixels=${((fitted ? cueFitWidth : cuePageWidth) * 2).round()}x'
    '${((fitted ? cueFitHeight : cuePageHeight) * 2).round()}',
  );
  return file;
}

// PURPOSE: Take one edit back and print the comparison the whole log-and-reducer design rests on,
//          then redo it so the next case starts from the edited document. The comparison is the
//          whole `DocumentState` — song, strokes, annotations and cues — not a boolean about the cue.
// INPUTS: session — the session being driven. before — the document as it was before the edit.
//         what — the edit's name, for the printed line. applied — the document the edit produced,
//         which the redo must reach again.
// OUTPUTS: Nothing. Prints `undo.*` lines and fails the instrument if the document after the undo is
//          not EQUAL to the one before the edit, or if the redo does not reach the edited document
//          again.
// KEYWORDS: undo, exact-restore, document-state-equality, redo-round-trip, evidence
void _undoAndRedo(
  EditSession session,
  DocumentState before,
  String what,
  DocumentState applied,
) {
  final bool undone = session.undo();
  final DocumentState afterUndo = session.document;
  stdout.writeln('undo.$what before=$before');
  stdout.writeln('undo.$what after =$afterUndo');
  stdout.writeln(
    'undo.$what reported=$undone doc_equal=${afterUndo == before} '
    'song_equal=${afterUndo.song == before.song} '
    'strokes=${afterUndo.strokes.length}==${before.strokes.length} '
    'annotations=${afterUndo.annotations.length}==${before.annotations.length} '
    'cues=${afterUndo.textCues.length}==${before.textCues.length} '
    'cue_texts=${afterUndo.textCues.map((TextCue cue) => cue.text).toList()}'
    '==${before.textCues.map((TextCue cue) => cue.text).toList()}',
  );
  expect(undone, isTrue, reason: 'there must be an edit to take back');
  expect(
    afterUndo,
    before,
    reason: 'the undo of "$what" must restore the whole document exactly',
  );
  final bool redone = session.redo();
  expect(redone, isTrue, reason: 'the undo must be redoable');
  expect(
    session.document,
    applied,
    reason: 'the redo of "$what" must reach the edited document again',
  );
  stdout.writeln(
    'redo.$what reported=$redone applied_equal_redone=${session.document == applied}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('renders the words on the chart before and after they are written, '
      'changed and moved, fitted and not', () async {
    final String? family = await _loadChartFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show which words are written',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = _engineFor(metrics);
    final Directory outDir = Directory(textCueRenderDirectory);
    outDir.createSync(recursive: true);

    final EditSession session = EditSession(
      document: DocumentState(song: textCueChart()),
    );
    final Song written = session.song;

    // --- BEFORE: the music with no words on it --------------------------------------------------
    final File beforePng = await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'before',
      outDir: outDir,
    );
    await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'before',
      outDir: outDir,
      fitted: true,
    );

    // --- THE CUE IS WRITTEN, through the operation log and nothing else -------------------------
    //
    // Two events, in the order the sheet writes them: a `textcue.insert` carrying an EMPTY cue —
    // the state the model documents as "inserted and not yet typed into" — and then a
    // `textcue.edit` carrying the words. The insert is what gives the words somewhere to go, and
    // the catalogue keeps the two apart on purpose (`textcue_events.dart`): one "changed" event
    // would force undo to decide which of the two it was undoing.
    //
    // Each operation is taken back and put again SEPARATELY, because that is what "undo after each
    // operation" can mean when one gesture is two events, and because the two are different
    // documents: undoing the insert removes the cue, and undoing the edit leaves it there with no
    // words in it — the intermediate state the model allows and the app must not keep.
    final DocumentState beforeInsert = session.document;
    final String? id = session.insertTextCue(
      sectionId: _section,
      barIndex: 0,
      offsetX: 2,
    );
    expect(id, isNotNull, reason: 'bar 0 of section A exists in the fixture');
    final DocumentState afterInsert = session.document;
    stdout.writeln(
      'cue.ops insert types=${session.log.map((ChartEvent event) => event.type).toList()} '
      'seq=${session.seq} cue_id=$id text="${session.textCueById(id!)?.text}"',
    );
    _undoAndRedo(session, beforeInsert, 'insert', afterInsert);

    final DocumentState beforeWords = session.document;
    final bool firstEdit = session.editTextCue(id, _firstWords);
    expect(firstEdit, isTrue);
    final DocumentState afterWords = session.document;
    stdout.writeln(
      'cue.ops words types=${session.log.map((ChartEvent event) => event.type).toList()} '
      'seq=${session.seq} text="${session.textCueById(id)?.text}"',
    );
    _undoAndRedo(session, beforeWords, 'words', afterWords);

    // The two halves are reported as what they produce, so the consequence is a measurement and not
    // a claim: ONE undo after writing the words leaves an empty cue, and the SECOND removes it.
    session.undo();
    final int afterFirstUndo = session.document.textCues.length;
    final String? textAfterFirstUndo = session.textCueById(id)?.text;
    session.undo();
    final int afterSecondUndo = session.document.textCues.length;
    session.redo();
    session.redo();
    stdout.writeln(
      'cue.undo.two_halves after_one_undo_cues=$afterFirstUndo '
      'text="$textAfterFirstUndo" after_two_undo_cues=$afterSecondUndo '
      'restored_cues=${session.document.textCues.length} '
      'restored_text="${session.textCueById(id)?.text}"',
    );
    expect(afterFirstUndo, 1);
    expect(textAfterFirstUndo, '');
    expect(afterSecondUndo, 0);
    expect(session.document, afterWords);

    final File afterAddPng = await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'after-add',
      outDir: outDir,
    );
    await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'after-add',
      outDir: outDir,
      fitted: true,
    );

    // --- THE WORDS CHANGE ----------------------------------------------------------------------
    final DocumentState beforeEdit = session.document;
    expect(session.editTextCue(id, _editedWords), isTrue);
    final DocumentState afterEdit = session.document;
    stdout.writeln(
      'cue.ops edit types=${session.log.map((ChartEvent event) => event.type).toList()} '
      'text="${session.textCueById(id)?.text}"',
    );
    _undoAndRedo(session, beforeEdit, 'edit', afterEdit);

    final File afterEditPng = await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'after-edit',
      outDir: outDir,
    );
    await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'after-edit',
      outDir: outDir,
      fitted: true,
    );

    // --- THE CUE MOVES ONE BAR LATER -----------------------------------------------------------
    final DocumentState beforeMove = session.document;
    expect(
      session.moveTextCue(id, sectionId: _section, barIndex: 1, offsetX: 2),
      isTrue,
    );
    final DocumentState afterMove = session.document;
    stdout.writeln(
      'cue.ops move types=${session.log.map((ChartEvent event) => event.type).toList()} '
      'anchor=${session.textCueById(id)?.place}',
    );
    _undoAndRedo(session, beforeMove, 'move', afterMove);

    final File afterMovePng = await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'after-move',
      outDir: outDir,
    );
    await _renderCase(
      engine: engine,
      song: written,
      metrics: metrics,
      document: session.document,
      name: 'after-move',
      outDir: outDir,
      fitted: true,
    );

    // --- THE IMAGES REALLY DIFFER, AND THE BEFORE IMAGE REALLY CAME BACK ------------------------
    //
    // Without this, four PNGs that all showed the same page would read as a feature that worked.
    // FNV-1a is a check against ACCIDENTAL identity, not against a forger, and it needs no
    // dependency — see [_fingerprint].
    final String beforeHash = _fingerprint(beforePng);
    final String addedHash = _fingerprint(afterAddPng);
    final String editedHash = _fingerprint(afterEditPng);
    final String movedHash = _fingerprint(afterMovePng);
    stdout.writeln(
      'cue.fingerprints before=$beforeHash after_add=$addedHash '
      'after_edit=$editedHash after_move=$movedHash',
    );
    expect(
      <String>{beforeHash, addedHash, editedHash, movedHash},
      hasLength(4),
      reason: 'each case must draw a different page',
    );

    // --- SURVIVAL 1: A FITTED PAGE --------------------------------------------------------------
    //
    // The claim: on a page the fitter shrank, the cue is still on the bar its anchor names, and its
    // drawn position is the anchor's position times the page scale. The check is the bar the cue
    // resolved to, compared with the bar the anchor names — a cue drawn on the wrong bar under FIT
    // would pass every hash above and fail this.
    final FitOutcome fit = engine.fitToPage(
      written,
      pageWidth: cueFitWidth,
      pageHeight: cueFitHeight,
      cues: session.document.textCues,
    );
    final PageLayout fitted = fit.page!;
    final ResolvedTextCue fittedCue = _resolveCues(
      fitted,
      session.document,
    ).single;
    final PlacedBar fittedBar = fitted.bars.firstWhere(
      (PlacedBar bar) =>
          bar.sectionId == fittedCue.cue.place.anchor.sectionId &&
          bar.barIndex == fittedCue.cue.place.anchor.bar,
    );
    stdout.writeln(
      'cue.survival fit scale=${fitted.scale} id=${fittedCue.cue.id} '
      'anchor=${fittedCue.cue.place.anchor} '
      'origin_engraved=(${fittedCue.origin.x.toStringAsFixed(2)},'
      '${fittedCue.origin.y.toStringAsFixed(2)}) '
      'drawn_surface=('
      '${((fittedCue.origin.x + fittedCue.cue.place.offsetX) * fitted.scale).toStringAsFixed(2)},'
      '${((fittedCue.origin.y + fittedCue.cue.place.offsetY) * fitted.scale).toStringAsFixed(2)}) '
      'bar_engraved=(${fittedBar.bounds.left.toStringAsFixed(2)},'
      '${fittedBar.bounds.top.toStringAsFixed(2)})',
    );
    expect(
      fittedCue.origin.x,
      fittedBar.bounds.left,
      reason: 'under FIT the cue must resolve to the bar its anchor names',
    );
    expect(
      fitted.scale,
      lessThan(1),
      reason: 'this surface must genuinely shrink the page',
    );

    // --- SURVIVAL 2: A TRANSPOSITION ------------------------------------------------------------
    //
    // The music is re-engraved in another key and the SAME address is resolved again. The words are
    // NOT transposed — a cue is a sentence, not a chord — and the check is that the address still
    // names the same bar of the transposed chart and that the cue's own words and offset are the
    // bytes they were. `E-7` becomes `F#-7` on the page while `D.C. al Fine` does not change.
    final Song transposed = transposeSong(
      written,
      2,
      toKey: const TranspositionGrid()
          .targets(written.key)
          .firstWhere((TranspositionTarget target) => target.semitones == 2)
          .key,
    );
    final List<PageLayout> transposedPages = engine.layout(
      transposed,
      pageWidth: cuePageWidth,
      pageHeight: cuePageHeight,
      cues: session.document.textCues,
    );
    final ResolvedTextCue transposedCue = _resolveCues(
      transposedPages.first,
      session.document,
    ).single;
    final Bar transposedBar = transposed.barAt(_section, 1)!;
    stdout.writeln(
      'cue.survival transpose written=${written.key} shown=${transposed.key} '
      'id=${transposedCue.cue.id} text="${transposedCue.cue.text}" '
      'anchor=${transposedCue.cue.place.anchor} '
      'origin_engraved=(${transposedCue.origin.x.toStringAsFixed(2)},'
      '${transposedCue.origin.y.toStringAsFixed(2)}) '
      'bar_chords=${transposedBar.chords.map((ChordMark placed) => placed.chord.render(transposed.key, const SpellingTable())).toList()}',
    );
    expect(transposedCue.cue.place.anchor.sectionId, _section);
    expect(transposedCue.cue.place.anchor.bar, 1);
    expect(transposedCue.cue.text, _editedWords);
    final PlacedBar transposedPlacedBar = transposedPages.first.bars.firstWhere(
      (PlacedBar bar) => bar.sectionId == _section && bar.barIndex == 1,
    );
    expect(
      transposedCue.origin.x,
      transposedPlacedBar.bounds.left,
      reason: 'after a transposition the cue must resolve to the same bar',
    );
    // The transposition is also RENDERED and looked at, because the address check above would pass
    // for a cue drawn in the wrong place within the right bar. The fingerprint must differ from the
    // written key's page — the chords really were re-engraved — while the words did not change.
    final File transposedPng = await _renderCase(
      engine: engine,
      song: transposed,
      metrics: metrics,
      document: session.document,
      name: 'transposed',
      outDir: outDir,
    );
    expect(
      _fingerprint(transposedPng),
      isNot(_fingerprint(afterMovePng)),
      reason: 'the transposed page must not be the written page',
    );

    // --- SURVIVAL 3: A SAVE AND A RELOAD --------------------------------------------------------
    //
    // The container stores a snapshot plus the operations AFTER it, so the file is written as the
    // session's BASE document plus its log — writing the current document with its own log beside
    // it is the defect A38 records. The comparison is the whole `DocumentState`, and the reopened
    // session is opened the way the viewer opens one.
    final ChartFile file = chartFileFor(
      session.baseDocument,
      events: session.log,
      modifiedAt: DateTime.utc(2026, 10, 11, 12, 0),
    );
    final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
    final ChartFileDecodeResult decoded = ChartFileCodec.decode(encoded.bytes);
    stdout.writeln(
      'cue.survival roundtrip bytes=${encoded.bytes.length} '
      'operations=${file.events.length} '
      'operation_types=${file.events.map((ChartEvent event) => event.type).toList()} '
      'warnings=${decoded.warnings.length} '
      'snapshot_cues=${decoded.file.snapshot.textCues.length} '
      'reduced_cues=${decoded.file.reducedDocument.textCues.length}',
    );
    expect(decoded.warnings, isEmpty);
    expect(
      decoded.file.reducedDocument,
      session.document,
      reason: 'the file must decode to the document the session holds',
    );
    final EditSession reopened = EditSession(
      document: decoded.file.snapshot,
      docId: decoded.file.metadata.docId,
      seq: decoded.file.events.last.seq,
      restored: decoded.file.events,
    );
    final TextCue? reopenedCue = reopened.textCueById(id);
    stdout.writeln(
      'cue.survival reopened doc_equal=${reopened.document == session.document} '
      'cue_id=$id text="${reopenedCue?.text}" place=${reopenedCue?.place} '
      'seq=${reopened.seq}',
    );
    expect(
      reopened.document,
      session.document,
      reason: 'a session opened from the file must hold the saved chart',
    );
    expect(reopenedCue?.text, _editedWords);
    expect(reopenedCue?.place, session.textCueById(id)?.place);
    // And the reloaded document is RENDERED too, then compared byte for byte with the page the
    // session drew before the save. A round trip that lost the cue, moved it or re-ordered the
    // document would pass neither the equality above nor this fingerprint, and the two failing
    // together is what makes "it survived the file" a picture rather than an assertion.
    final File reopenedPng = await _renderCase(
      engine: engine,
      song: reopened.song,
      metrics: metrics,
      document: reopened.document,
      name: 'reopened',
      outDir: outDir,
    );
    stdout.writeln(
      'cue.survival reopened_png fingerprint=${_fingerprint(reopenedPng)} '
      'same_as_before_the_save='
      '${_fingerprint(reopenedPng) == _fingerprint(afterMovePng)}',
    );
    expect(
      _fingerprint(reopenedPng),
      _fingerprint(afterMovePng),
      reason: 'the reopened chart must draw the same page as the saved one',
    );

    // --- NEGATIVE CONTROL: a file of the OLD shape must NOT read back ---------------------------
    //
    // The opening check above can only mean something if it is able to fail. The old shape — the
    // CURRENT document as the snapshot, with the log that produced it beside it — is written here
    // and reopened: the tail re-inserts a cue the snapshot already holds, which the reducer refuses
    // outright. Printing the refusal is the point; silence would be the defect.
    final ChartFile doubled = chartFileFor(
      session.document,
      events: session.log,
      modifiedAt: DateTime.utc(2026, 10, 11, 12, 0),
    );
    final ChartFileDecodeResult doubledDecoded = ChartFileCodec.decode(
      ChartFileCodec.encode(doubled).bytes,
    );
    String refusal = 'DID NOT FAIL';
    try {
      EditSession(
        document: doubledDecoded.file.snapshot,
        docId: doubledDecoded.file.metadata.docId,
        seq: doubledDecoded.file.events.last.seq,
        restored: doubledDecoded.file.events,
      );
    } on DocumentReducerException catch (error) {
      refusal = error.message;
    }
    stdout.writeln('cue.control old_shape_refusal="$refusal"');
    expect(
      refusal,
      isNot('DID NOT FAIL'),
      reason: 'the opening check must be able to fail',
    );
  });
}
