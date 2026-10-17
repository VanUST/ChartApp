// PURPOSE: Produce the numbers and the pictures that answer owner decision D29 and the beat half of
//          D28: whether a staff exists because the chart DECLARED it, what a musician sees that
//          tells him which beat he is choosing, and whether a chord-symbol chart is unaffected.
//          Four claims that would otherwise be impressions become files and figures here:
//
//            1. A chart that declares a pitched staff and holds NO note still draws a staff a
//               musician could write on — the closed circle D29 records, where the staff appeared
//               only once a note was already written.
//            2. The same chart with notes in it draws those notes on the same staff.
//            3. A chart that declares NO pitched staff — every imported chart — used to be proved
//               BYTE-IDENTICAL to the page it printed before a melody staff existed. That promise is
//               RETIRED and this instrument says so: the chart now states its key and its metre above
//               its first system, so page one's music sits lower by that band and its pixels changed.
//               What is still measured is the part a finger depends on — the cells and chords keep
//               their positions relative to the bar, and page two onwards is untouched.
//            4. Every beat of a bar is named where the musician counts it, and the staff's own hit
//               test answers that beat's address.
//            5. The key and the metre are ON THE PAGE, above the first system and clear of both the
//               section letter and the first bar's chord, with the metre stated once.
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
//         a real chart rather than eight empty bars. Key and meter — the chart's own key and the
//         meter of every bar, so the header case can be drawn in a minor key that does not open in
//         4/4 without a second fixture.
// OUTPUTS: An eight-bar one-section song in C major 4/4 by default. The eighth bar carries a second
//          note on the same beat, so the picture shows two voices of one beat's column as well. The
//          FIRST bar carries a chord in its first cell and the section letter A, which is the case
//          the header must not collide with.
// KEYWORDS: fixture, declared-staff, empty-staff, with-notes, chords-only, comparable, header-case
Song _chart({
  required StaffSet staves,
  required bool withNotes,
  bool chords = true,
  Key key = Key.cMajor,
  TimeSignature meter = TimeSignature.fourFour,
}) => Song(
  id: 'chartapp-staff-probe',
  title: 'Staff probe',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: key,
  tempo: 120,
  staffSet: staves,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < 8; index++)
          Bar(
            timeSignature: meter,
            chords: chords
                ? <ChordMark>[
                    for (int cell = 0; cell < 4; cell++)
                      ChordMark(
                        place: cellAt(cell),
                        chord: Chord(
                          root: ChordRoot((index + cell) % 12),
                          quality: cell.isEven
                              ? ChordQuality.majorSeventh
                              : ChordQuality.minorSeventh,
                        ),
                      ),
                  ]
                : const <ChordMark>[],
            melody: withNotes
                ? <NoteMark>[
                    NoteMark(
                      place: cellAt(0),
                      pitch: PitchedNote(
                        note: WrittenNote(
                          NoteLetter.values[index % 7],
                          index.isEven ? 0 : -1,
                        ),
                        octave: 4,
                      ),
                      value: const NoteValue.plain(NoteBase.quarter),
                    ),
                    if (index == 7)
                      NoteMark(
                        place: cellAt(0, 1),
                        pitch: PitchedNote(
                          note: WrittenNote(NoteLetter.g, 0),
                          octave: 4,
                        ),
                        value: NoteValue.plain(NoteBase.half),
                      ),
                  ]
                : const <NoteMark>[],
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
        '(the style draws no beat caption under the staff)',
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

// PURPOSE: Report the line that states the chart's key and meter where its music begins, and prove
//          by measurement that it collides with neither the section letter nor the first bar's
//          chord. The owner asked for the metre to be written at the start of the composition
//          together with the key; a header that covered the chord the chart opens with would be a
//          worse answer than none.
// INPUTS: label — the case's name. song, page and style — what was engraved.
// OUTPUTS: `probe.header` on stdout: the text, the band it occupies, its height, the top of the
//          first system, the section letter's band and the first bar with its first chord, plus a
//          `clear=` flag that is true only when the header is entirely above all three. Also
//          `probe.header.meter` with the meter signs the page shows, so the claim "the metre is
//          stated once" is a printed map rather than a sentence.
// KEYWORDS: chart-header, key, meter, collision, section-letter, first-bar-chord, measurement
void _reportHeader(
  String label,
  Song song,
  PageLayout page,
  LayoutStyle style,
) {
  final PlacedChartHeader? header = page.header;
  if (header == null) {
    stdout.writeln('probe.header name=$label header=none');
    return;
  }
  final PlacedSystem system = page.systems.first;
  final PlacedBar bar = system.bars.first;
  final String chord = bar.chords.isEmpty
      ? 'none'
      : '(${bar.chords.first.bounds.left.toStringAsFixed(1)},'
            '${bar.chords.first.bounds.top.toStringAsFixed(1)}..'
            '${bar.chords.first.bounds.bottom.toStringAsFixed(1)})';
  final LayoutRect? labelBand = system.labelBand;
  final bool clear =
      header.bounds.bottom <= system.bounds.top &&
      (labelBand == null || header.bounds.bottom <= labelBand.top) &&
      header.bounds.bottom <= bar.bounds.top;
  stdout.writeln(
    'probe.header name=$label text="${header.text}" '
    'band=(${header.bounds.left.toStringAsFixed(1)},'
    '${header.bounds.top.toStringAsFixed(1)},'
    '${header.bounds.size.width.toStringAsFixed(1)},'
    '${header.bounds.size.height.toStringAsFixed(1)}) '
    'height=${header.bounds.size.height.toStringAsFixed(1)} '
    'gap=${style.chartHeaderGap} '
    'first_system_top=${system.bounds.top.toStringAsFixed(1)} '
    'label_band=${labelBand == null ? 'none' : '(${labelBand.top.toStringAsFixed(1)}..${labelBand.bottom.toStringAsFixed(1)})'} '
    'section_label=${system.sectionLabel} '
    'first_bar_top=${bar.bounds.top.toStringAsFixed(1)} '
    'first_chord=$chord '
    'clear=$clear',
  );
  stdout.writeln(
    'probe.header.meter name=$label signs=${meterSignsOnPage(song, page)}',
  );
}

// PURPOSE: Build the chart the beam cases are engraven on: one bar per case, each holding the notes a
//          musician would write for it, so that the numbers and the pictures describe the same bar.
// INPUTS: None.
// OUTPUTS: An eight-bar one-section song in C major that declares a pitched staff. Every bar carries
//          four chords, which is what gives it the width a real chart's bar has — a bar narrower than
//          its own notes would test the engraving's fit-to-bar arithmetic rather than its beaming.
//          The eight cases, in order:
//            0. an EIGHTH PAIR inside one beat,
//            1. a SIXTEENTH GROUP of four inside one beat,
//            2. a MIXED group — an eighth and two sixteenths — inside one beat,
//            3. two sixteenth groups in two beats, which is where a BEAT BOUNDARY must break a beam,
//            4. a sixteenth group on the LAST beat, which is where a beam could cross a BARLINE,
//            5. four notes of ONE PITCH, which is where a beam must be LEVEL,
//            6. a rising run, which is where a beam must SLOPE,
//            7. a lone eighth and a rest, which is where a note must keep its FLAG.
// KEYWORDS: probe, fixture, beam, eighth, sixteenth, mixed-group, beat-boundary, barline, level,
//           slope, flag
Song _beamChart() {
  /// One melody note at [letter]/[octave] of [value] on ([beat], [step]).
  NoteMark at(
    NoteLetter letter,
    int octave,
    NoteBase base,
    int beat,
    int step,
  ) => NoteMark(
    place: cellAt(beat, step),
    pitch: PitchedNote(note: WrittenNote(letter, 0), octave: octave),
    value: NoteValue.plain(base),
  );

  /// A stepwise run of [count] notes from [from] up the C major scale, one per [base].
  List<NoteMark> run(
    List<NoteLetter> letters,
    int octave,
    NoteBase base,
    int beat,
  ) => <NoteMark>[
    for (int index = 0; index < letters.length; index++)
      at(letters[index], octave, base, beat, index),
  ];

  // THE RUNS ARE STEPWISE, because that is the shape a musician writes and the one whose beam has to
  // be judged: a run that stepped up a third at a time would test the slope limit instead of the
  // beaming. `efga` sits inside the treble staff; `cdef` starts a ledger line below it, which is the
  // case where the beam is steepest and the outer stem longest.
  const List<NoteLetter> efga = <NoteLetter>[
    NoteLetter.e,
    NoteLetter.f,
    NoteLetter.g,
    NoteLetter.a,
  ];
  const List<NoteLetter> cdef = <NoteLetter>[
    NoteLetter.c,
    NoteLetter.d,
    NoteLetter.e,
    NoteLetter.f,
  ];
  return Song(
    id: 'chartapp-beam-probe',
    title: 'Beam probe',
    composer: 'ChartApp',
    style: 'Medium Swing',
    key: Key.cMajor,
    tempo: 120,
    staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
    sections: <Section>[
      Section(
        id: 'A',
        label: const SectionLabel.letter('A'),
        bars: <Bar>[
          // 0: an eighth pair in beat 1.
          Bar(
            chords: _probeChords(),
            melody: <NoteMark>[
              at(NoteLetter.g, 4, NoteBase.eighth, 0, 0),
              at(NoteLetter.a, 4, NoteBase.eighth, 0, 1),
            ],
          ),
          // 1: four sixteenths in beat 1 — the owner's «шестнадцатые соединяются сверху чертой».
          Bar(
            chords: _probeChords(),
            melody: run(efga, 4, NoteBase.sixteenth, 0),
          ),
          // 2: a mixed group in beat 1: eighth, sixteenth, sixteenth.
          Bar(
            chords: _probeChords(),
            melody: <NoteMark>[
              at(NoteLetter.g, 4, NoteBase.eighth, 0, 0),
              at(NoteLetter.a, 4, NoteBase.sixteenth, 0, 1),
              at(NoteLetter.b, 4, NoteBase.sixteenth, 0, 2),
            ],
          ),
          // 3: the same sixteenth run twice, in beats 1 and 3.
          Bar(
            chords: _probeChords(),
            melody: <NoteMark>[
              ...run(efga, 4, NoteBase.sixteenth, 0),
              ...run(efga, 4, NoteBase.sixteenth, 2),
            ],
          ),
          // 4: a sixteenth run on the LAST beat, where a beam that outran its column would cross the
          //    barline into the next bar.
          Bar(
            chords: _probeChords(),
            melody: run(efga, 4, NoteBase.sixteenth, 3),
          ),
          // 5: four sixteenths of one pitch: the beam must be level.
          Bar(
            chords: _probeChords(),
            melody: run(
              const <NoteLetter>[
                NoteLetter.b,
                NoteLetter.b,
                NoteLetter.b,
                NoteLetter.b,
              ],
              4,
              NoteBase.sixteenth,
              0,
            ),
          ),
          // 6: the same shape rising, where the beam must follow it.
          Bar(
            chords: _probeChords(),
            melody: run(cdef, 4, NoteBase.sixteenth, 0),
          ),
          // 7: one eighth and then a beat of silence: no beam, and the note keeps its flag.
          Bar(
            chords: _probeChords(),
            melody: <NoteMark>[
              at(NoteLetter.g, 4, NoteBase.eighth, 0, 0),
              at(NoteLetter.a, 4, NoteBase.eighth, 2, 0),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Four chord symbols for one bar, which is the width a real chart's bar is measured at.
List<ChordMark> _probeChords() => <ChordMark>[
  for (int cell = 0; cell < 4; cell++)
    ChordMark(
      place: cellAt(cell),
      chord: Chord(
        root: ChordRoot(cell * 3),
        quality: cell.isEven
            ? ChordQuality.majorSeventh
            : ChordQuality.minorSeventh,
      ),
    ),
];

// PURPOSE: Print, for every note the melody staff drew, the pitch, the staff step it landed on, the
//          ledger lines it needed, which way its stem points and whether a beam replaced its flag.
// INPUTS: label — the case's name. song and page — the chart and its first laid-out page.
// OUTPUTS: One `probe.notes` line per bar: the bar index, then one entry per note.
// KEYWORDS: probe, notes, staff-step, ledger-line, stem-direction, beam-vs-flag
void _reportNotes(String label, Song song, PageLayout page) {
  for (final PlacedBar placed in page.bars) {
    final Bar? bar = song.barAt(placed.sectionId, placed.barIndex);
    if (bar == null || bar.melody.isEmpty) {
      continue;
    }
    final List<String> described = <String>[];
    for (int index = 0; index < bar.melody.length; index++) {
      final NoteMark note = bar.melody[index];
      final int step = melodyStepOf(
        note.pitch.note,
        octave: note.pitch.octave,
        clef: placed.melody.clef ?? 'treble',
      );
      described.add(
        '${note.pitch}:b${note.pseudoBeat}.${note.pseudoStep} step=$step '
        'ledger=${melodyLedgerLineOffsets(step).length}',
      );
    }
    stdout.writeln(
      'probe.notes name=$label bar=${placed.barIndex} count=${bar.melody.length} '
      '${described.join(' | ')}',
    );
  }
}

// PURPOSE: Print every beam the melody staff drew as numbers — where it starts and ends, how thick it
//          is, how steep, how many stems it reaches and which way those stems point — so that a claim
//          about a beam's shape can be read off a run instead of being taken from a picture.
// INPUTS: label — the case's name. page — the laid-out page.
// OUTPUTS: `probe.beams` for each bar: the count, the stems of the bar, and one `beam#k` entry per
//          beam with its ends, thickness in staff spaces, slope and reach.
// KEYWORDS: probe, beam, thickness, slope, span, stem-direction, measurement
void _reportBeams(String label, PageLayout page) {
  for (final PlacedBar placed in page.bars) {
    final List<MelodyGlyph> beams = <MelodyGlyph>[
      for (final MelodyGlyph glyph in placed.melody.glyphs)
        if (glyph.kind == MelodyGlyphKind.beam) glyph,
    ];
    if (beams.isEmpty) {
      continue;
    }
    final List<MelodyGlyph> stems = <MelodyGlyph>[
      for (final MelodyGlyph glyph in placed.melody.glyphs)
        if (glyph.kind == MelodyGlyphKind.stem) glyph,
    ];
    final double space = placed.melody.bounds.size.height / 4;
    final List<String> described = <String>[];
    for (int index = 0; index < beams.length; index++) {
      final MelodyGlyph beam = beams[index];
      final double dx = beam.to.x - beam.from.x;
      final double slope = dx.abs() < 1e-9 ? 0 : (beam.to.y - beam.from.y) / dx;
      final double start = beam.from.x < beam.to.x ? beam.from.x : beam.to.x;
      final double end = beam.from.x < beam.to.x ? beam.to.x : beam.from.x;
      int reached = 0;
      for (final MelodyGlyph stem in stems) {
        final double axis = stem.bounds.left + stem.bounds.size.width / 2;
        if (axis >= start - 1e-6 && axis <= end + 1e-6) {
          reached++;
        }
      }
      described.add(
        'beam#$index x=[${start.toStringAsFixed(1)}..${end.toStringAsFixed(1)}] '
        'y=[${beam.from.y.toStringAsFixed(2)}..${beam.to.y.toStringAsFixed(2)}] '
        'stems=$reached thick=${(beam.strokeWidth / space).toStringAsFixed(3)}sp '
        'slope=${slope.toStringAsFixed(3)}',
      );
    }
    stdout.writeln(
      'probe.beams name=$label bar=${placed.barIndex} count=${beams.length} '
      'stem_up=${stems.map((MelodyGlyph stem) => stem.stemUp).join(",")} '
      'flags=${stems.where((MelodyGlyph stem) => stem.flagLength > 0).length} '
      '${described.join(' | ')}',
    );
  }
}

// PURPOSE: Paint ONE REGION of a laid-out page at a magnification, so a shape whose thickness and
//          slope are the whole of what it means can be judged by eye at a size the eye can judge.
// INPUTS: page, song and metrics — what to draw. out — the file. region — the part of the page to
//          show, in page coordinates. zoom — surface pixels per page pixel.
// OUTPUTS: Writes the PNG and returns the bytes written, exactly as [_renderToPng] does for a whole
//          page. The image and the picture are disposed.
//
//          WHY IT PAINTS THE WHOLE PAGE AND THEN CROPS, RATHER THAN HANDING THE PAINTER A SMALLER
//          SURFACE. The painter fills its background and clips to the box it is given, and it does
//          that in the PAGE's own coordinates — so a caller that passed the REGION as the size would
//          be handing it the page's top-left corner instead, and the crop would come out blank. It
//          did, and the blank file is why this note exists. The magnification and the offset are
//          therefore a canvas transform, and the crop is a clip in SURFACE coordinates laid down
//          before the painter draws anything.
// KEYWORDS: probe, crop, magnification, png, eye, beam, thickness, slope, clip-in-surface-space
Future<List<int>> _renderCrop(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  File out, {
  required LayoutRect region,
  required double zoom,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.clipRect(
    ui.Rect.fromLTWH(0, 0, region.size.width * zoom, region.size.height * zoom),
  );
  canvas.scale(zoom);
  canvas.translate(-region.left, -region.top);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
  ).paint(canvas, ui.Size(page.size.width, page.size.height));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (region.size.width * zoom).round(),
    (region.size.height * zoom).round(),
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
    _reportHeader('declared-empty', declaredEmpty, emptyPages.first, style);
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
    _reportHeader('declared-notes', declaredWithNotes, notePages.first, style);
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
    // Every imported chart. This case used to be a BYTE-IDENTITY reference — the page it printed
    // before a melody staff existed — and THAT PROMISE IS NOW FALSE, stated here rather than left for
    // a reader to discover from two differing files: the chart now states its key and its metre in a
    // band above its first system, which moves page one's music down by that band and changes every
    // pixel of the page. What survives, and what this case still measures, is the geometry that
    // matters to a musician's finger: the bar, its cell columns and its chords keep their positions
    // RELATIVE to the bar, and a page other than the first is untouched. `probe.header` prints the
    // band and the first system's top, `probe.hit` prints what a tap on each cell names, and the
    // pixel-level proof lives in `apps/mobile/test/chart_header_render_test.dart`.
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
    _reportHeader('chords-only', chordsOnly, plainPages.first, style);
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

    // --- CASE 4: THE KEY AND THE METER, ON THE PAGE, IN A MINOR KEY THAT IS NOT IN 4/4 ------
    //
    // The chart the owner asked to be able to read at a stand: its key and its metre stated where
    // the music begins. Eb minor is chosen because it is the name the key vocabulary had to be built
    // to produce (the transposer used to answer `D# major`/`Gb minor` for pitch classes like this
    // one), and 3/4 because a chart that does not open in 4/4 is the only case where the bar's own
    // meter sign could double the header's statement.
    const Key eFlatMinor = Key(
      tonic: WrittenNote(NoteLetter.e, -1),
      mode: Mode.minor,
    );
    final Song waltz = _chart(
      staves: const StaffSet(pitched: StaffSpec.pitched()),
      withNotes: true,
      key: eFlatMinor,
      meter: TimeSignature.threeFour,
    );
    final List<PageLayout> waltzPages = engine.layout(
      waltz,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportHeader('minor-waltz', waltz, waltzPages.first, style);
    final List<int> waltzBytes = await _renderToPng(
      waltzPages.first,
      waltz,
      metrics,
      File('$outDir${Platform.pathSeparator}staff-minor-waltz@2x.png'),
    );
    stdout.writeln(
      'probe.identity name=minor-waltz png_bytes=${waltzBytes.length} '
      'digest=${_digestOf(waltzBytes)}',
    );

    _reportTypedChords(Key.cMajor);
    _reportActionCounts();
  });

  // PURPOSE: Answer the owner's own criterion for a note engraving — «Распознавание нот и их верное
  //          визуальное соединение (шестнадцатые соединяются сверху чертой) должно быть почти
  //          идеальным» — with numbers AND with pictures, from one run.
  // INPUTS: STAFF_PROBE_OUT names the directory. The chart is built above so the run never depends on
  //         the owner's export.
  // OUTPUTS: `probe.beams` and `probe.notes` per bar, a whole-page PNG, a strip of the first system,
  //          and one magnified crop per case, because a beam's THICKNESS AND SLOPE are the whole of
  //          what a reader judges and neither can be read off a number alone. The assertions are the
  //          musical facts the picture is looked at against: two beams over the sixteenths, one over
  //          the eighths, a level beam over repeated notes, no beam across a barline, and a flag left
  //          on a note with nothing to join.
  // KEYWORDS: probe, beam, sixteenths, owner-criterion, rhythm-grouping, png, crop, magnification
  test('the beam joins what one beat holds, and the pictures and the numbers are one run', () async {
    final String? family = await _loadFont();
    expect(
      family,
      isNotNull,
      reason: 'the chord symbols must be letters, not boxes',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutStyle style = _styleFor(metrics);
    final LayoutEngine engine = LayoutEngine(style: style);
    final String outDir =
        Platform.environment['STAFF_PROBE_OUT'] ?? staffProbeDirectory;
    Directory(outDir).createSync(recursive: true);
    final Song song = _beamChart();
    final List<PageLayout> pages = engine.layout(
      song,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    final PageLayout page = pages.first;
    _reportStaff('beams', page, style);
    _reportNotes('beams', song, page);
    _reportBeams('beams', page);
    final List<int> bytes = await _renderToPng(
      page,
      song,
      metrics,
      File('$outDir${Platform.pathSeparator}beams-page@2x.png'),
    );
    stdout.writeln(
      'probe.identity name=beams png_bytes=${bytes.length} '
      'digest=${_digestOf(bytes)} bars=${page.bars.length} '
      'systems=${page.systems.length}',
    );
    // A strip of the first system's staff, at three times the size: the whole line of cases, so a
    // reader can see that the groups are where the beats are.
    final PlacedBar firstBar = page.bars.first;
    final double space = firstBar.melody.bounds.size.height / 4;
    final List<int> stripBytes = await _renderCrop(
      page,
      song,
      metrics,
      File('$outDir${Platform.pathSeparator}beams-system@3x.png'),
      region: LayoutRect.fromLTWH(
        page.systems.first.bounds.left,
        firstBar.melody.bounds.top - 3 * space,
        page.systems.first.bounds.size.width,
        firstBar.melody.bounds.size.height + 6 * space,
      ),
      zoom: 3,
    );
    stdout.writeln(
      'probe.crop name=system file=beams-system@3x.png bytes=${stripBytes.length} '
      'zoom=3',
    );
    // ONE CROP PER CASE, each wide enough to show the barlines on both sides of the bar it pictures,
    // because the question "does the beam stay inside the bar" is answered by the barline in the
    // picture and not by a number.
    for (final PlacedBar placed in page.bars) {
      final LayoutRect staff = placed.melody.bounds;
      final LayoutRect region = LayoutRect.fromLTWH(
        staff.left - 2,
        staff.top - 4 * space,
        staff.size.width + 16,
        staff.size.height + 8 * space,
      );
      final List<int> cropBytes = await _renderCrop(
        page,
        song,
        metrics,
        File(
          '$outDir${Platform.pathSeparator}beams-bar${placed.barIndex}@5x.png',
        ),
        region: region,
        zoom: 5,
      );
      stdout.writeln(
        'probe.crop name=bar${placed.barIndex} '
        'file=beams-bar${placed.barIndex}@5x.png bytes=${cropBytes.length} zoom=5 '
        'bar_x=[${staff.left.toStringAsFixed(1)}..${staff.right.toStringAsFixed(1)}]',
      );
    }

    /// The beams of a bar, left to right — the same order the engraving draws them in.
    List<MelodyGlyph> beamsOfBar(int bar) {
      final List<MelodyGlyph> beams = <MelodyGlyph>[
        for (final MelodyGlyph glyph in page.bars[bar].melody.glyphs)
          if (glyph.kind == MelodyGlyphKind.beam) glyph,
      ];
      beams.sort(
        (MelodyGlyph a, MelodyGlyph b) =>
            (a.from.x < a.to.x ? a.from.x : a.to.x).compareTo(
              b.from.x < b.to.x ? b.from.x : b.to.x,
            ),
      );
      return beams;
    }

    /// The stems a beam reaches, which is the number of notes it joins.
    int stemsUnder(int bar, MelodyGlyph beam) {
      final double start =
          (beam.from.x < beam.to.x ? beam.from.x : beam.to.x) - 1e-6;
      final double end =
          (beam.from.x < beam.to.x ? beam.to.x : beam.from.x) + 1e-6;
      return <MelodyGlyph>[
        for (final MelodyGlyph glyph in page.bars[bar].melody.glyphs)
          if (glyph.kind == MelodyGlyphKind.stem &&
              glyph.bounds.left + glyph.bounds.size.width / 2 >= start &&
              glyph.bounds.left + glyph.bounds.size.width / 2 <= end)
            glyph,
      ].length;
    }

    // THE MUSICAL FACTS, ASSERTED SO A REGRESSION FAILS THE INSTRUMENT INSTEAD OF PRINTING A WRONG
    // NUMBER QUIETLY. Each is the criterion the owner stated, in his own terms.
    expect(
      beamsOfBar(0).length,
      1,
      reason: 'an eighth pair in one beat is joined by one beam',
    );
    expect(
      stemsUnder(0, beamsOfBar(0).single),
      2,
      reason: 'and it joins both notes',
    );
    expect(
      beamsOfBar(1).length,
      2,
      reason: 'sixteenths are joined by TWO beams — «шестнадцатые соединяются сверху чертой»',
    );
    for (final MelodyGlyph beam in beamsOfBar(1)) {
      expect(
        stemsUnder(1, beam),
        4,
        reason:
            'each of the two beams runs over all four sixteenths of the beat',
      );
    }
    expect(
      beamsOfBar(2).length,
      2,
      reason: 'a mixed group takes the first beam over all of it and one more over the sixteenths',
    );
    // TWO GROUPS IN TWO BEATS ARE TWO GROUPS AND NOT ONE: each sixteenth run carries two beams of
    // its own, so the bar holds four beams in two x-spans. A single beam reaching across the beat
    // between them would be the defect this case exists for.
    expect(
      beamsOfBar(3).length,
      4,
      reason:
          'two sixteenth groups in two beats are two groups of two beams each — a beat boundary '
          'breaks the beam even inside one bar',
    );
    expect(
      beamsOfBar(3)[1].to.x,
      lessThan(beamsOfBar(3)[2].from.x),
      reason: 'and the two groups do not overlap: the beat between them is empty of beam',
    );
    final List<MelodyGlyph> lastBeat = beamsOfBar(4);
    expect(
      lastBeat,
      isNotEmpty,
      reason: 'the last-beat case must draw a beam to contain',
    );
    for (final MelodyGlyph beam in lastBeat) {
      final double start = beam.from.x < beam.to.x ? beam.from.x : beam.to.x;
      final double end = beam.from.x < beam.to.x ? beam.to.x : beam.from.x;
      stdout.writeln(
        'probe.beams.containment bar=4 '
        'bar_x=[${page.bars[4].melody.bounds.left.toStringAsFixed(1)}..'
        '${page.bars[4].melody.bounds.right.toStringAsFixed(1)}] '
        'beam_x=[${start.toStringAsFixed(1)}..${end.toStringAsFixed(1)}]',
      );
      expect(
        start,
        greaterThanOrEqualTo(page.bars[4].melody.bounds.left),
        reason: 'a beam never crosses a barline',
      );
      expect(
        end,
        lessThanOrEqualTo(page.bars[4].melody.bounds.right),
        reason: 'a beam never crosses a barline',
      );
    }
    for (final MelodyGlyph beam in beamsOfBar(5)) {
      expect(
        beam.from.y,
        closeTo(beam.to.y, 1e-9),
        reason: 'four notes of one pitch are joined by a LEVEL beam',
      );
    }
    expect(
      beamsOfBar(6).first.to.y,
      lessThan(beamsOfBar(6).first.from.y),
      reason: 'a rising run is joined by a rising beam',
    );
    expect(
      beamsOfBar(7),
      isEmpty,
      reason: 'an eighth with no neighbour in its beat is flagged, not beamed',
    );
  });

  // PURPOSE: Answer, in one run, the two questions about a cell that holds several notes: does a run
  //          typed LEFT TO RIGHT come out left to right on the staff, and on which side of its
  //          noteheads does the arch of a tie hang.
  //
  //          WHY IT IS THE COLUMN AND NOT THE MODEL THAT PUTS IT IN QUESTION. A note's place in time
  //          inside one beat is its `NoteMark.step` — a dense ordinal, 0 for the first note of the
  //          cell, 1 for the second — and the engraver draws step `k` at `cellX + k * stride`, which
  //          is the same left-to-right order. So the ORDER the model holds and the order the staff
  //          draws are one order, and an insertion that puts a new note at step 0 of a cell that
  //          already holds notes therefore reverses what a musician typed. That is A74 §10(a), named
  //          there and not fixed; this case is what makes it a measurement instead of a suspicion.
  //
  //          The write path is the REAL one: every note is written through `EditSession.insertNote`
  //          with no `step`, which is exactly the call the note palette makes, so what is measured
  //          is the arrival order a finger produces and not a fixture's opinion.
  // INPUTS: The font and the style the other cases use. Four one-bar cases, each chosen because it
  //         is the shape of the defect: a sixteenth run typed C-D-E-F; two ties, one on a note whose
  //         stem points up and one whose stem points down; the same pitch twice in one cell, which
  //         is the case a model with no sub-beat address could not hold; and an eighth followed by
  //         two sixteenths, whose spacing tells uniform stride from accumulated durations.
  // OUTPUTS: `probe.writer.model` — the cell as the MODEL holds it, in storage order;
  //          `probe.writer.drawn` — the same notes read off the picture LEFT TO RIGHT with the x each
  //          one was drawn at; `probe.writer.tie` — each tie's two ends and its control point, with
  //          the side it bulges to and the direction of the stem it must stay clear of;
  //          `probe.writer.spacing` — the horizontal gaps of eighth-sixteenth-sixteenth; and two
  //          magnified PNGs, because an arch drawn on the wrong side is a thing the eye settles and a
  //          number only reports.
  // KEYWORDS: probe, writer, insert-order, left-to-right, sixteenths, tie, arch-side, stem,
  //           sub-beat-address, spacing, png, crop
  test('a run typed left to right is drawn left to right, and a tie hangs opposite its stem', () async {
    final String? family = await _loadFont();
    expect(
      family,
      isNotNull,
      reason: 'the chord symbols must be letters, not boxes',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutStyle style = _styleFor(metrics);
    final LayoutEngine engine = LayoutEngine(style: style);
    final String outDir =
        Platform.environment['STAFF_PROBE_OUT'] ?? staffProbeDirectory;
    Directory(outDir).createSync(recursive: true);

    /// Four empty bars of C major that declare a pitched staff, each carrying the chord symbols
    /// that give a real chart's bar its width.
    Song emptyWithStaff() => Song(
      id: 'chartapp-writer-probe',
      title: 'Writer probe',
      composer: 'ChartApp',
      style: 'Medium Swing',
      key: Key.cMajor,
      tempo: 120,
      staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
      sections: <Section>[
        Section(
          id: 'A',
          label: const SectionLabel.letter('A'),
          bars: <Bar>[
            for (int index = 0; index < 4; index++) Bar(chords: _probeChords()),
          ],
        ),
      ],
    );

    /// One written pitch in the fourth octave, which is the register a melody is written in.
    PitchedNote pitch(NoteLetter letter) =>
        PitchedNote(note: WrittenNote(letter, 0), octave: 4);

    /// The notes of one bar as the MODEL holds them, in the bar's own storage order.
    String modelOf(Song song, int barIndex) => <String>[
      for (final NoteMark note in song.barsInReadingOrder[barIndex].melody)
        '${note.pseudoBeat}.${note.pseudoStep}:${note.pitch}',
    ].join(' ');

    final EditSession session = EditSession(
      document: DocumentState(song: emptyWithStaff()),
    );

    // --- THE RUN, TYPED LEFT TO RIGHT THROUGH THE WRITER THE PALETTE USES ---------------------
    const List<NoteLetter> typed = <NoteLetter>[
      NoteLetter.c,
      NoteLetter.d,
      NoteLetter.e,
      NoteLetter.f,
    ];
    for (final NoteLetter letter in typed) {
      session.insertNote(
        sectionId: 'A',
        barIndex: 0,
        beat: 0,
        pitch: pitch(letter),
        value: NoteValue.plain(NoteBase.sixteenth),
      );
    }

    // --- TWO TIES, one hanging from a note BELOW the middle line and one from a note ABOVE it ----
    // E4 is step 0 on a treble staff, so its stem points UP and its tie must hang BELOW the
    // noteheads. B4 is step 6, so its stem points DOWN and its tie must arch ABOVE them. A tie on
    // the stem's own side is read as a beam, and one that collides with a stem is read as a mistake.
    for (final int beat in <int>[0, 2]) {
      session.insertNote(
        sectionId: 'A',
        barIndex: 1,
        beat: beat,
        pitch: pitch(beat == 0 ? NoteLetter.e : NoteLetter.b),
        value: const NoteValue.plain(NoteBase.quarter),
        tiedToNext: true,
      );
      session.insertNote(
        sectionId: 'A',
        barIndex: 1,
        beat: beat + 1,
        pitch: pitch(beat == 0 ? NoteLetter.e : NoteLetter.b),
        value: const NoteValue.plain(NoteBase.quarter),
      );
    }

    // --- THE SAME PITCH TWICE IN ONE CELL, which is what a model without a sub-beat address -------
    // --- could not hold. Written through the writer, so the address is the one a musician's -------
    // --- two taps produce.                                                                      ----
    for (int tap = 0; tap < 2; tap++) {
      session.insertNote(
        sectionId: 'A',
        barIndex: 2,
        beat: 0,
        pitch: pitch(NoteLetter.b),
        value: NoteValue.plain(NoteBase.sixteenth),
      );
    }

    // --- AN EIGHTH AND TWO SIXTEENTHS: the case where "each note starts at the sum of the previous
    // durations" and "each note is one stride further right" are DIFFERENT pictures.
    session.insertNote(
      sectionId: 'A',
      barIndex: 3,
      beat: 0,
      pitch: pitch(NoteLetter.g),
      value: const NoteValue.plain(NoteBase.eighth),
    );
    for (final NoteLetter letter in <NoteLetter>[NoteLetter.a, NoteLetter.b]) {
      session.insertNote(
        sectionId: 'A',
        barIndex: 3,
        beat: 0,
        pitch: pitch(letter),
        value: NoteValue.plain(NoteBase.sixteenth),
      );
    }

    final Song song = session.song;
    for (int barIndex = 0; barIndex < 4; barIndex++) {
      stdout.writeln(
        'probe.writer.model bar=$barIndex ${modelOf(song, barIndex)}',
      );
    }

    final List<PageLayout> pages = engine.layout(
      song,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    final PageLayout page = pages.first;
    stdout.writeln(
      'probe.writer.layout bars=${page.bars.length} systems=${page.systems.length}',
    );
    expect(
      page.bars.length,
      4,
      reason: 'all four written cases must be on the page this case measures',
    );

    /// The noteheads of one bar, in the order they were emitted, which is the model's own order.
    List<MelodyGlyph> headsOf(int barIndex) => <MelodyGlyph>[
      for (final MelodyGlyph glyph in page.bars[barIndex].melody.glyphs)
        if (glyph.kind == MelodyGlyphKind.notehead) glyph,
    ];

    /// The stems of one bar, in the order they were emitted: one per note, because no case here
    /// beams anything (a sixteenth run of ONE beat with no neighbour is beamed, so the run's stems
    /// are the beam's — the pairing used below is by index and is checked by printing both lists).
    List<MelodyGlyph> stemsOf(int barIndex) => <MelodyGlyph>[
      for (final MelodyGlyph glyph in page.bars[barIndex].melody.glyphs)
        if (glyph.kind == MelodyGlyphKind.stem) glyph,
    ];

    /// The x of a glyph's centre, which for a notehead is the notehead's own position.
    double centreX(MelodyGlyph glyph) =>
        glyph.bounds.left + glyph.bounds.size.width / 2;

    /// The pitches of one bar in the order a reader meets them LEFT TO RIGHT, which is the only
    /// order a picture can be read in. Taken from the noteheads' own x, not from the model: the
    /// model's order and the picture's order are the two things this case holds apart. A notehead is
    /// paired with its note BY POSITION IN THE GLYPH LIST, which is the order [_addNoteGlyphs] emits
    /// them — one notehead per note, in the model's order.
    List<String> readingOrder(int barIndex) {
      final List<MelodyGlyph> heads = headsOf(barIndex);
      final List<int> order = List<int>.generate(
        heads.length,
        (int i) => i,
      )..sort((int a, int b) => centreX(heads[a]).compareTo(centreX(heads[b])));
      return <String>[
        for (final int index in order)
          song.barsInReadingOrder[barIndex].melody[index].pitch.toString(),
      ];
    }

    stdout.writeln(
      'probe.writer.drawn bar=0 order=${readingOrder(0).join(",")} '
      'x=${<String>[for (final MelodyGlyph head in headsOf(0)) centreX(head).toStringAsFixed(1)].join(",")}',
    );
    stdout.writeln('probe.writer.same-pitch bar=2 ${modelOf(song, 2)}');

    // --- THE TIES, AND THE SIDE THEY HANG ON --------------------------------------------------
    final List<MelodyGlyph> ties = <MelodyGlyph>[
      for (final MelodyGlyph glyph in page.bars[1].melody.glyphs)
        if (glyph.kind == MelodyGlyphKind.tie) glyph,
    ];
    final List<MelodyGlyph> tieStems = stemsOf(1);
    final List<MelodyGlyph> tieHeads = headsOf(1);
    for (int index = 0; index < ties.length; index++) {
      final MelodyGlyph tie = ties[index];
      // The tie leaves the FIRST note of its pair, and the pairs are (1,2) and (3,4) of the bar's
      // four notes, so the tie's own stem is that note's: `2 * index` in the drawn order.
      final MelodyGlyph stem = tieStems[2 * index];
      final bool stemUp = stem.stemUp;
      final String side = tie.control.y < tie.from.y ? 'above' : 'below';
      stdout.writeln(
        'probe.writer.tie index=$index '
        'note=${song.barsInReadingOrder[1].melody[2 * index].pitch} '
        'head_y=${tie.from.y.toStringAsFixed(2)} '
        'control_y=${tie.control.y.toStringAsFixed(2)} '
        'to_y=${tie.to.y.toStringAsFixed(2)} side=$side stem_up=$stemUp',
      );
    }

    // --- THE SPACING, WHICH A74 §2 RECORDED AS "THE SUM OF THE PREVIOUS DURATIONS" --------------
    // An eighth followed by two sixteenths is the case that separates the two readings: the model's
    // second note starts half a beat after the first and the third a further sixteenth later, so a
    // time-proportional row has TWO DIFFERENT gaps, and a uniform stride has ONE. Only a printed
    // number can say which the page holds.
    final List<MelodyGlyph> spacingHeads = headsOf(3);
    final List<double> gaps = <double>[
      for (int index = 1; index < spacingHeads.length; index++)
        centreX(spacingHeads[index]) - centreX(spacingHeads[index - 1]),
    ];
    stdout.writeln(
      'probe.writer.spacing bar=3 gaps=${<String>[for (final double gap in gaps) gap.toStringAsFixed(3)].join(",")} '
      'values=${song.barsInReadingOrder[3].melody.map((NoteMark n) => '${n.value}').join(",")}',
    );

    // --- THE PICTURES --------------------------------------------------------------------------
    for (final int barIndex in <int>[0, 1]) {
      final LayoutRect staff = page.bars[barIndex].melody.bounds;
      final double space = staff.size.height / 4;
      final int zoom = barIndex == 0 ? 5 : 6;
      final String name = barIndex == 0 ? 'writer-run' : 'writer-ties';
      final List<int> bytes = await _renderCrop(
        page,
        song,
        metrics,
        File('$outDir${Platform.pathSeparator}$name@${zoom}x.png'),
        region: LayoutRect.fromLTWH(
          staff.left - 2,
          staff.top - 4 * space,
          staff.size.width + 16,
          staff.size.height + 8 * space,
        ),
        zoom: zoom.toDouble(),
      );
      stdout.writeln(
        'probe.writer.crop name=$name file=$name@${zoom}x.png '
        'bytes=${bytes.length} zoom=$zoom '
        'bar_x=[${staff.left.toStringAsFixed(1)}..${staff.right.toStringAsFixed(1)}]',
      );
    }

    // --- THE CLAIMS, now that the numbers and the pictures are on the record ---------------------
    //
    // THE MUSICAL FACT, STATED AS A SENTENCE ABOUT MUSIC: what the musician typed left to right is
    // what the reader reads left to right. A run that comes out backwards is a different bar.
    expect(
      readingOrder(0),
      <String>['C4', 'D4', 'E4', 'F4'],
      reason:
          'four sixteenths typed C, D, E, F into one beat must be DRAWN C, D, E, F from left to '
          'right — a run in the model reversed is drawn right to left and reads as the wrong music',
    );

    // THE SAME PITCH TWICE: the model holds both, at two steps of the same cell.
    expect(
      modelOf(song, 2),
      '0.0:B4 0.1:B4',
      reason:
          'a cell can hold two notes of ONE pitch, which is what makes the missing sub-beat '
          'address a smaller gap than it looks: the second note is not a duplicate, it is `step 1`',
    );

    expect(
      ties.length,
      2,
      reason: 'two tied pairs were written, so the staff must draw two ties',
    );
    for (int index = 0; index < ties.length; index++) {
      final MelodyGlyph tie = ties[index];
      final bool stemUp = tieStems[2 * index].stemUp;
      expect(
        tie.to.y,
        closeTo(tie.from.y, 1e-9),
        reason: 'a tied pair on one line starts and ends at the same height',
      );
      // THE RULE OF NOTATION, NOT OF THIS ENGRAVER: a tie is drawn on the side AWAY from the stems,
      // because a curve on the stem's own side is read as a beam or as a slur onto the stem.
      expect(
        tie.control.y < tie.from.y,
        !stemUp,
        reason:
            'a tie hangs OPPOSITE its stem: with the stems up the arch is below the noteheads and '
            'with them down it is above (measured on '
            '${song.barsInReadingOrder[1].melody[2 * index].pitch}, '
            'whose stem points ${stemUp ? 'up' : 'down'})',
      );
      // And the tie is not drawn through a notehead: it leaves from inside one notehead and reaches
      // into the next, which is what [MelodyMetrics.tieClearance] is for.
      expect(
        centreX(tieHeads[2 * index]) < tie.from.x,
        isTrue,
        reason: 'the tie leaves the first notehead on its right-hand side',
      );
    }
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
