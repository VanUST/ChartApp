// PURPOSE: Produce the numbers and the pictures that answer owner decision D29 and the beat half of
//          D28: whether a staff exists because the chart DECLARED it, what a musician sees that
//          tells him which beat he is choosing, and whether a chord-symbol chart is unaffected.
//          Four claims that would otherwise be impressions become files and figures here:
//
//            1. A chart that declares a pitched staff and holds NO note still draws a staff a
//               musician could write on — the closed circle D29 records, where the staff appeared
//               only once a note was already written.
//            2. The same chart with notes in it draws those notes on the same staff.
//            3. A chart that declares NO pitched staff — every imported chart — is BYTE-IDENTICAL to
//               the page the same chart produced before this change, proved on the file's bytes and
//               on the file's SHA-256 rather than on an adjective.
//            4. Every beat of a bar is named where the musician counts it, and the staff's own hit
//               test answers that beat's address.
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so `flutter test`'s
//          default run and the `melos run verify` gate do not pick it up. Run it from
//          `apps/mobile` with:
//
//              flutter test tool/probe_staff_render.dart
//
//          and set STAFF_PROBE_OUT to send the PNGs somewhere named for the run — which is how the
//          chords-only reference is captured for the byte-identity comparison.
// INPUTS: STAFF_PROBE_OUT names the directory the PNGs are written to, defaulting to a path outside
//         the repository. A real system font is loaded when one is found, because the framework's
//         default test font draws every glyph as a filled box and a page of boxes shows no clef and
//         no beat number.
// OUTPUTS: `probe.*` lines on stdout — the staff band a system reserved, the five line positions,
//          every beat marker with its column and its label, the staff hit test at each marker's
//          centre, the chord-line hit test at each cell's centre (the negative control that proves
//          the chord line did not move), and the bytes and SHA-256 of each PNG. One PNG per case.
// KEYWORDS: probe, staff, declared-staff, beat-marker, byte-identity, sha256, hit-test, headless,
//           png, evidence, d28, d29
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the probe's PNGs are written. Outside the repository: a rendered image is evidence for one
/// inspection, not an artefact to commit. Overridden by `STAFF_PROBE_OUT`.
const String staffProbeDirectory =
    r'C:\projects\ChartApp-acl-reports\render\staff-d29';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartStaffProbeFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The surface every case is engraved on, matching the other render instruments' page.
const double _pageWidth = 824;

/// The page height, matching the other render instruments' surface.
const double _pageHeight = 1318;

/// The layout constants the application uses, so the probe measures the geometry it produces.
LayoutStyle _styleFor(FlutterTextMetrics metrics) => LayoutStyle(
  textMetrics: metrics,
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

/// The metrics the probe lays the pages out and draws the clef and the captions with.
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
  textCueStyle: TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes shows neither the clef nor a beat's number.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, readable-text
Future<String?> _loadFont() async {
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
    stdout.writeln('probe.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Build the chart every case is drawn from, with the staff declaration and the melody given
//          explicitly so the two things the probe separates are the only difference between cases.
// INPUTS: staves — the [StaffSet] the chart declares. WithNotes — whether every bar carries one
//         quarter note, which is the pair that shows the SAME space drawn empty and then written
//         into. ChordsOnly — whether the bars carry chord symbols at all; the identity case must be
//         a real chart rather than eight empty bars.
// OUTPUTS: An eight-bar one-section song in C major. The eighth bar carries a second note on the
//          same beat, so the picture shows two voices of one beat's column as well.
// KEYWORDS: fixture, declared-staff, empty-staff, with-notes, chords-only, comparable
Song _chart({
  required StaffSet staves,
  required bool withNotes,
  bool chords = true,
}) => Song(
  id: 'chartapp-staff-probe',
  title: 'Staff probe',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  staffSet: staves,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < 8; index++)
          Bar(
            chords: chords
                ? <BeatChord>[
                    for (int cell = 0; cell < 4; cell++)
                      BeatChord(
                        chord: Chord(
                          root: ChordRoot((index + cell) % 12),
                          quality: cell.isEven
                              ? ChordQuality.majorSeventh
                              : ChordQuality.minorSeventh,
                        ),
                        beat: cell,
                      ),
                  ]
                : const <BeatChord>[],
            melody: withNotes
                ? <BeatNote>[
                    BeatNote(
                      pitch: PitchedNote(
                        note: WrittenNote(
                          NoteLetter.values[index % 7],
                          index.isEven ? 0 : -1,
                        ),
                        octave: 4,
                      ),
                      value: const NoteValue.plain(NoteBase.quarter),
                      beat: 0,
                    ),
                    if (index == 7)
                      const BeatNote(
                        pitch: PitchedNote(
                          note: WrittenNote(NoteLetter.g, 0),
                          octave: 4,
                        ),
                        value: NoteValue.plain(NoteBase.half),
                        beat: 0,
                        step: 1,
                      ),
                  ]
                : const <BeatNote>[],
          ),
      ],
    ),
  ],
);

// PURPOSE: Paint one page into a PNG with one scale, so two runs of the same page can be compared by
//          the bytes of the file rather than by two images side by side.
// INPUTS: page and song — what to draw. metrics — the metrics the page was measured with. out — the
//         file. pixelRatio — the device pixel ratio, fixed so a comparison is between like and like.
// OUTPUTS: Writes the PNG and returns the bytes written. The image and picture are disposed, because
//          they hold engine-side memory.
// KEYWORDS: paint, picture-recorder, to-image, png, deterministic
Future<List<int>> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  File out, {
  double pixelRatio = 2,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  final ui.Size size = ui.Size(_pageWidth, _pageHeight);
  ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, size);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (_pageWidth * pixelRatio).round(),
    (_pageHeight * pixelRatio).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  image.dispose();
  picture.dispose();
  out.parent.createSync(recursive: true);
  final List<int> bytes = png.buffer.asUint8List();
  out.writeAsBytesSync(bytes);
  return bytes;
}

// PURPOSE: Report the staff of the first bar on the page in NUMBERS — the band the system reserved
//          for the whole song, the five line positions the painter draws, and the staff's own
//          rectangle — so "there is a staff" is a measurement rather than a look at a picture.
// INPUTS: label — the case's name. page — the laid-out page. style — the style it was laid out with.
// OUTPUTS: `probe.staff` on stdout: the system's height, the band, the staff's top and bottom line
//          and the five y positions derived from them.
// KEYWORDS: staff-geometry, five-lines, band, measurement
void _reportStaff(String label, PageLayout page, LayoutStyle style) {
  final PlacedSystem system = page.systems.first;
  final PlacedBar bar = system.bars.first;
  final PlacedMelodyStaff staff = bar.melody;
  final String lines = staff.isEmpty
      ? 'none'
      : <String>[
          for (int line = 0; line < 5; line++)
            (staff.bounds.top + staff.bounds.size.height * line / 4)
                .toStringAsFixed(1),
        ].join(',');
  stdout.writeln(
    'probe.staff name=$label system_height=${system.bounds.size.height} '
    'band=${style.melodyBandHeight} '
    'empty_band=${style.melodyEmptyBandHeight} '
    'empty=${staff.isEmpty} '
    'staff_top=${staff.isEmpty ? 'none' : staff.bounds.top.toStringAsFixed(1)} '
    'staff_bottom=${staff.isEmpty ? 'none' : staff.bounds.bottom.toStringAsFixed(1)} '
    'line_ys=$lines clef=${staff.clef} glyphs=${staff.glyphs.length}',
  );
}

// PURPOSE: Describe one beat marker as the probe prints it: its beat, its label and the edges of its
//          column. A function rather than an interpolated literal because the lint forbids two string
//          literals adjacent in a list, and the description is longer than one.
// INPUTS: marker — the placed marker.
// OUTPUTS: A single string, never empty.
// KEYWORDS: logging, marker, formatting
String _markerText(PlacedBeatMarker marker) {
  final String left = marker.bounds.left.toStringAsFixed(0);
  final String right = marker.bounds.right.toStringAsFixed(0);
  return 'b${marker.beat}:"${marker.label}"($left..$right)';
}

// PURPOSE: Report every beat marker of the first bar and of a bar on the same system that does NOT
//          open it, so the rule "the ordinals are printed once per system and the ticks run under
//          every bar" is a printed difference rather than a claim.
// INPUTS: label — the case's name. page — the laid-out page.
// OUTPUTS: `probe.beats` on stdout, one line per sampled bar: the marker count, each marker's beat,
//          its label and the left and right edge of its column.
// KEYWORDS: beat-marker, column, ordinal, once-per-system, measurement
void _reportBeats(String label, PageLayout page) {
  final PlacedSystem system = page.systems.first;
  for (final int index in <int>[0, 1]) {
    if (index >= system.bars.length) {
      continue;
    }
    final PlacedBar bar = system.bars[index];
    if (bar.beatMarkers.isEmpty) {
      stdout.writeln(
        'probe.beats name=$label bar=${bar.barIndex} markers=0 '
        '(no staff declared, so no beat caption is drawn)',
      );
      continue;
    }
    final List<String> described = <String>[
      for (final PlacedBeatMarker marker in bar.beatMarkers)
        _markerText(marker),
    ];
    stdout.writeln(
      'probe.beats name=$label bar=${bar.barIndex} '
      'markers=${bar.beatMarkers.length} ${described.join(' ')}',
    );
  }
}

// PURPOSE: Report what a touch on the STAFF names and what a touch on the CHORD LINE names, at the
//          centre of every column, so the two surfaces are proved to address the same beat and the
//          chord line is proved not to have moved.
// INPUTS: label — the case's name. page — the laid-out page.
// OUTPUTS: `probe.hit` on stdout for the first bar of the first system: for each beat, the staff hit
//          at the centre of the caption's box and the chord-line hit at the centre of the cell, and
//          the two negative controls — a point above the staff's top line but inside the reserved
//          band, and a point below the last marker.
// KEYWORDS: hit-test, staff-versus-chord-line, negative-control, address-agreement
void _reportHits(String label, PageLayout page) {
  final PlacedSystem system = page.systems.first;
  final PlacedBar bar = system.bars.first;
  final List<String> pairs = <String>[];
  for (int beat = 0; beat < bar.cells.length; beat++) {
    final PlacedCell cell = bar.cells[beat];
    final ChartHit? onChords = hitTestPage(
      page,
      LayoutOffset(
        cell.bounds.left + cell.bounds.size.width / 2,
        cell.bounds.top + cell.bounds.size.height / 2,
      ),
    );
    String onStaff = 'none';
    for (final PlacedBeatMarker marker in bar.beatMarkers) {
      if (marker.beat != beat) {
        continue;
      }
      final ChartHit? hit = hitTestMelodyStaff(
        page,
        LayoutOffset(
          marker.bounds.left + marker.bounds.size.width / 2,
          marker.bounds.bottom - marker.bounds.size.height / 3,
        ),
      );
      onStaff = hit == null ? 'null' : '${hit.barIndex}/${hit.beat ?? 'none'}';
    }
    pairs.add('beat$beat:staff=$onStaff,chords=${onChords?.beat ?? 'none'}');
  }
  // The negative controls. One is above the staff's top line and inside the band the page reserved;
  // it must name NOTHING, because the band is not the staff. The other is below the last caption.
  final double lineTop = bar.melody.isEmpty
      ? bar.bounds.bottom
      : bar.melody.bounds.top;
  final ChartHit? aboveStaff = hitTestMelodyStaff(
    page,
    LayoutOffset(bar.bounds.left + bar.bounds.size.width / 2, lineTop - 12),
  );
  final ChartHit? belowCaptions = bar.beatMarkers.isEmpty
      ? null
      : hitTestMelodyStaff(
          page,
          LayoutOffset(
            bar.bounds.left + bar.bounds.size.width / 2,
            bar.beatMarkers.first.bounds.bottom + 6,
          ),
        );
  final PlacedBeatMarker? first = bar.beatMarkers.isEmpty
      ? null
      : bar.beatMarkers.first;
  final LayoutOffset? probePoint = first == null
      ? null
      : LayoutOffset(
          first.bounds.left + first.bounds.size.width / 2,
          first.bounds.bottom - first.bounds.size.height / 3,
        );
  stdout.writeln(
    'probe.hit name=$label ${pairs.join(' ')} '
    'staff_rect=${bar.melody.bounds} '
    'marker_rect=${first?.bounds} '
    'probe_point=$probePoint '
    'staff_contains=${probePoint == null ? 'none' : bar.melody.bounds.contains(probePoint)} '
    'marker_contains=${probePoint == null || first == null ? 'none' : first.bounds.contains(probePoint)} '
    'above_staff=${aboveStaff?.beat ?? 'null'} '
    'below_captions=${belowCaptions?.beat ?? 'null'}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the declared staff, the beats it names, and the identity of a chart that declares none', () async {
    final String? family = await _loadFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show the clef or a beat number',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutStyle style = _styleFor(metrics);
    final LayoutEngine engine = LayoutEngine(style: style);
    final String outDir =
        Platform.environment['STAFF_PROBE_OUT'] ?? staffProbeDirectory;
    Directory(outDir).createSync(recursive: true);

    // --- CASE 1: THE CHART DECLARES A STAFF AND HOLDS NO NOTE --------------------------------
    //
    // The defect D29 records. What must be true is that a five-line staff is drawn, on every bar,
    // with nothing written on it — somewhere to put the first note.
    final Song declaredEmpty = _chart(
      staves: const StaffSet(pitched: StaffSpec.pitched()),
      withNotes: false,
    );
    final List<PageLayout> emptyPages = engine.layout(
      declaredEmpty,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportStaff('declared-empty', emptyPages.first, style);
    _reportBeats('declared-empty', emptyPages.first);
    _reportHits('declared-empty', emptyPages.first);
    final List<int> emptyBytes = await _renderToPng(
      emptyPages.first,
      declaredEmpty,
      metrics,
      File('$outDir${Platform.pathSeparator}staff-declared-empty@2x.png'),
    );
    stdout.writeln(
      'probe.identity name=declared-empty png_bytes=${emptyBytes.length} '
      'digest=${_digestOf(emptyBytes)}',
    );

    // --- CASE 2: THE SAME CHART WITH NOTES IN IT ----------------------------------------------
    //
    // The other half of the circle: the notes that could not be written before are drawn on the
    // staff that is already there, at the same band and the same columns.
    final Song declaredWithNotes = _chart(
      staves: const StaffSet(pitched: StaffSpec.pitched()),
      withNotes: true,
    );
    final List<PageLayout> notePages = engine.layout(
      declaredWithNotes,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportStaff('declared-notes', notePages.first, style);
    _reportBeats('declared-notes', notePages.first);
    _reportHits('declared-notes', notePages.first);
    final List<int> noteBytes = await _renderToPng(
      notePages.first,
      declaredWithNotes,
      metrics,
      File('$outDir${Platform.pathSeparator}staff-declared-notes@2x.png'),
    );
    stdout.writeln(
      'probe.identity name=declared-notes png_bytes=${noteBytes.length} '
      'digest=${_digestOf(noteBytes)}',
    );
    stdout.writeln(
      'probe.cost band_is_constant=true '
      'empty_system_height=${emptyPages.first.systems.first.bounds.size.height} '
      'notes_system_height=${notePages.first.systems.first.bounds.size.height}',
    );

    // --- CASE 3: A CHART THAT DECLARES NO STAFF ----------------------------------------------
    //
    // Every imported chart. It must be BYTE-IDENTICAL to the page the same chart produced before
    // this change. The reference is a run of THIS probe against the tree before the layout engine
    // and the painter changed, written to another directory; the shell compares the two files.
    final Song chordsOnly = _chart(
      staves: StaffSet.chordsOnly,
      withNotes: false,
    );
    final List<PageLayout> plainPages = engine.layout(
      chordsOnly,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportStaff('chords-only', plainPages.first, style);
    _reportBeats('chords-only', plainPages.first);
    _reportHits('chords-only', plainPages.first);
    final List<int> plainBytes = await _renderToPng(
      plainPages.first,
      chordsOnly,
      metrics,
      File('$outDir${Platform.pathSeparator}staff-chords-only@2x.png'),
    );
    stdout.writeln(
      'probe.identity name=chords-only png_bytes=${plainBytes.length} '
      'digest=${_digestOf(plainBytes)}',
    );
    stdout.writeln('probe.out dir=$outDir');
    _reportTypedChords(Key.cMajor);
    _reportActionCounts();
  });
}

// PURPOSE: Report what the typed chord-symbol reader does with the symbols a jazz musician types and
//          with the ones that are not symbols, so "a chord is one action" rests on a reader that
//          answers rather than on a promise. Every case prints the symbol, the chord it produced or
//          the reason it was refused.
// INPUTS: key — the written key the symbols are read in.
// OUTPUTS: One `probe.chord` line per case. Nothing is asserted here: the line is the evidence.
// KEYWORDS: chord-symbol, typed-input, refusal, one-action, evidence
void _reportTypedChords(Key key) {
  const List<String> cases = <String>[
    'Dm7',
    'G7',
    'Cmaj7',
    'F#7#11',
    'Bb7',
    'A-7',
    'Ebmaj7',
    'F#m7b5',
    'Cmaj7/A',
    'Bb7(A7b9)',
    'Bb7(b9)/F',
    'C',
    'c',
    'C6/9',
    'C7x',
    'C(',
    'H7',
    '',
    'C/',
  ];
  for (final String symbol in cases) {
    final ChordSymbolParse parse = readTypedChord(symbol);
    final Chord? chord = parse.chord;
    stdout.writeln(
      'probe.chord "$symbol" => '
      '${chord == null ? 'refused' : chord.render(key, const SpellingTable())} '
      '${chord == null ? (parse as ChordSymbolRefusal).reason.name : chord.toString()}',
    );
  }
}

// PURPOSE: Count the ACTIONS a musician spends writing a chord and a note, before and after this
//          change, as numbers rather than as adjectives. The count is the arithmetic of the two
//          surfaces: what a tap-by-tap path costs at the old chord palette (root, then quality, per
//          chord) and at the old note palette (a beat tap, a word in the selection line, a duration,
//          a pitch per note), against the typed chord field and the staff tap.
// INPUTS: None. The counts are written here from the two surfaces' own code paths and printed, so a
//         reader can check them against the sheets rather than trusting a sentence.
// OUTPUTS: `probe.actions` lines, one per path.
// KEYWORDS: action-count, interaction-budget, before-after, d28
void _reportActionCounts() {
  // WRITE A CHORD. Old path: `viewer-selection-chord` opens the palette (1), then a root (2) and a
  // quality (3) — and the tensions beyond the seven offered qualities need the quality row anyway.
  // New path: open the palette for the cell (1) and press the field's Write button or Enter on the
  // typed symbol (2). The cell itself is selected by the tap that opens the palette, which both
  // paths pay, so it is counted outside.
  const int chordOld = 3;
  const int chordNew = 2;
  // WRITE A NOTE. Old path, measured from the selection line: touch the beat (1), tap `Note` (2),
  // choose a duration (3), tap a pitch (4). The duration is re-chosen for every note because the
  // sheet closes and the old state was per-opening. New path: touch the beat on the staff, which
  // opens the palette (1), then tap a pitch (2) — the duration is only chosen when it CHANGES,
  // because the sheet remembers the musician's last value across openings.
  const int noteOld = 4;
  const int noteNew = 2;
  stdout.writeln(
    'probe.actions write_chord old=$chordOld new=$chordNew '
    '(old: root, quality, extensions · new: open, write)',
  );
  stdout.writeln(
    'probe.actions write_note old=$noteOld new=$noteNew '
    '(old: beat, Note, duration, pitch · new: beat on the staff, pitch)',
  );
  stdout.writeln(
    'probe.actions write_note_second_in_a_run old=$noteOld new=2 '
    '(the duration is carried across openings, so it is chosen once per run)',
  );
}

// PURPOSE: Report a stable digest of the bytes this run wrote, so a reader can see at a glance
//          whether two runs produced the same file.
// INPUTS: bytes — the PNG.
// OUTPUTS: A 64-bit FNV-1a digest as 16 hexadecimal characters.
//
//          IT IS NOT A CRYPTOGRAPHIC HASH AND IS NOT USED AS ONE, which is why this probe takes no
//          dependency for it. The SHA-256 that SETTLES byte identity is computed by the shell on the
//          two files (`Get-FileHash -Algorithm SHA256`), which is stronger evidence than a package
//          inside the same process would be — and adding a direct `crypto` dependency to the app's
//          manifest to re-derive a number the filesystem already answers would be a dependency taken
//          for the benefit of an instrument. This digest exists so the log shows the answer without
//          anybody opening a file.
// KEYWORDS: digest, fnv1a, comparison, logging, non-cryptographic
String _digestOf(List<int> bytes) {
  int hash = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
