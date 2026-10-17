// PURPOSE: Put NUMBERS on the barline detector against the ink the owner actually wrote, so that
//          "it works" is a measurement and not an adjective. It decodes a real `.chart` with the
//          repository's own codec, lays the page out with the application's own style, weighs every
//          stroke against the detector's gates, and prints one line per stroke plus the totals that
//          matter: how many marks were accepted, how many were refused, and — the number that
//          decides whether the feature is worth having — HOW MANY OF HIS CHORD-SYMBOL LETTERS IT
//          WOULD HAVE CALLED A BARLINE.
//
//          It prints the MEASUREMENT of every stroke, not only the verdict, because a threshold that
//          refuses real ink has to be visible doing it: `height=22.8 aspect=4.5 verticality=0.93`
//          beside `gate=too-short` is the argument, and a bare count of zero is not.
//
//          AND IT PUTS THE SAME NUMBERS ON THE MELODY STAFF, which is where the owner reported that
//          the detector does nothing. A division across the staff is a different height, at a
//          different y, in a different band of the page from a division between two chord symbols,
//          and the gates were derived from the chord row. His own page declares no staff, so this
//          section rebuilds his song WITH one — declared and empty, and again with a note in it, so
//          both bands the layout can reserve are measured — and lays a known set of strokes on the
//          staff the application's own engine produced: a division across the five lines, one short
//          of them, a note stem with and without its notehead, a ledger line, a staff line, the marks
//          of his chord symbols, and a division in the chord row for comparison.
//
//          THOSE STROKES ARE ARITHMETIC AND NOT HANDWRITING, and this instrument says so where it
//          prints them: what they measure is the GEOMETRY — heights, spans, gaps — which is what the
//          gates are made of. Whether his hand passes them is a question for the tablet.
// INPUTS: The chart path (first argument, defaulting to the owner's sample).
// OUTPUTS: `probe.*` lines on stdout and exit code 0. Exit code 2 when the file cannot be read or
//          laid out, so a missing input never prints a misleading zero.
// KEYWORDS: probe, barline, detector, false-positive, threshold, handwriting, evidence, d37,
//           melody-staff, staff-band, not-part-of-the-library
import 'dart:io';
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';

import '../support/place_fixture.dart';

/// The sample the owner wrote, unless a path is given on the command line.
const String defaultChartPath =
    r'C:\projects\ChartApp-acl-reports\omr-sample\untitled.chart';

/// The page the probe engraves on, matching the application's own proportions.
const double probePageWidth = 824;

/// The page height the probe engraves on.
const double probePageHeight = 1318;

// PURPOSE: The layout constants the application uses, so the row heights the detector divides by
//          are the row heights the musician's ink was written against.
// INPUTS: None.
// OUTPUTS: The same [LayoutStyle] `viewer_screen.dart` builds.
// KEYWORDS: layout-style, application-geometry, measurement-fidelity
LayoutStyle appStyle() => const LayoutStyle(
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

/// One decimal place, so a printed column stays readable and a difference of a pixel still shows.
String f(double value) => value.isFinite ? value.toStringAsFixed(1) : 'inf';

void main(List<String> arguments) {
  final String path = arguments.isEmpty || arguments.first.startsWith('--')
      ? defaultChartPath
      : arguments.first;
  final File file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no such chart file: $path');
    exit(2);
  }
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(
    file.readAsBytesSync(),
  );
  final DocumentState document = decoded.file.reducedDocument;
  final List<PageLayout> pages = LayoutEngine(style: appStyle()).layout(
    document.song,
    pageWidth: probePageWidth,
    pageHeight: probePageHeight,
  );
  if (pages.isEmpty) {
    stderr.writeln('the chart laid out to no pages');
    exit(2);
  }
  final PageLayout page = pages.first;
  final List<PlacedInkStroke> placed = placeInkStrokes(page, document.strokes);
  final Map<String, BarlineFrame> frames = barlineFramesOfPage(page);
  const BarlineDetector detector = BarlineDetector();
  stdout.writeln(
    'probe.input chart=$path strokes=${document.strokes.length} '
    'placed=${placed.length} divisions_in_file=${document.divisions.length} '
    'bars=${page.bars.length} '
    'declared_staff=${document.song.staffSet.pitched?.kind.name ?? 'none'} '
    '${detector.thresholds}',
  );
  for (final MapEntry<String, BarlineFrame> entry in frames.entries) {
    stdout.writeln(
      'probe.frame key=${entry.key.replaceAll('\u0000', '#')} '
      'reference=${f(entry.value.referenceHeight)} '
      'minimum_height=${f(detector.thresholds.minimumHeightFor(entry.value.referenceHeight))} '
      'minimum_gap=${f(detector.thresholds.minimumIsolationFor(entry.value.referenceHeight))} '
      'bands=${entry.value.bands.map((BarlineBand band) => '${band.kind.token}@${f(band.top)}..${f(band.bottom)}').join(',')}',
    );
  }
  final List<BarlineVerdict> verdicts = measureBarlineDivisions(
    strokes: placed,
    barFrames: frames,
    detector: detector,
  );
  int accepted = 0;
  final Map<String, int> byGate = <String, int>{};
  double tallestVerticalMark = 0;
  String closestId = '';
  double closestHeadroom = 0;
  for (final BarlineVerdict verdict in verdicts) {
    final BarlineMeasurement m = verdict.measurement;
    if (m.verticality >= detector.thresholds.minVerticality &&
        m.aspect >= detector.thresholds.minAspect) {
      tallestVerticalMark = m.height > tallestVerticalMark
          ? m.height
          : tallestVerticalMark;
    }
    final String verdictToken = verdict.accepted
        ? 'ACCEPT'
        : verdict.rejection!.token;
    // HOW CLOSE THIS MARK CAME TO BEING ACCEPTED, as a fraction of the gate it fell short of.
    //
    // `headroom` is the SMALLEST of the mark's ratios to the gates it must pass — its height over
    // the height the page allows, its verticality over the verticality floor, and so on — so a value
    // of 1.0 would have passed and 0.585 falls 41% short. The number exists because "no false
    // positives" says nothing about how much room is left: the closest call is what tells a reader
    // how far the detector is from firing on a musician's letters.
    final double headroom = _headroomOf(m, detector.thresholds);
    if (headroom > closestHeadroom) {
      closestHeadroom = headroom;
      closestId = m.strokeId;
    }
    if (verdict.accepted) {
      accepted++;
    } else {
      byGate[verdict.rejection!.token] =
          (byGate[verdict.rejection!.token] ?? 0) + 1;
    }
    stdout.writeln(
      'probe.stroke id=${m.strokeId} '
      'bar=${m.anchor.sectionId}#${m.anchor.bar} '
      'x=${f(m.minX)}..${f(m.maxX)} y=${f(m.minY)}..${f(m.maxY)} '
      'height=${f(m.height)} width=${f(m.width)} '
      'aspect=${f(m.aspect)} verticality=${m.verticality.toStringAsFixed(2)} '
      'barline=${f(m.referenceHeight)} band=${m.band?.kind.token ?? 'none'} '
      'band_overlap=${m.bandOverlap.toStringAsFixed(2)} '
      'row_overlap=${m.rowOverlap.toStringAsFixed(2)} '
      'isolation=${f(m.isolation)} headroom=${headroom.toStringAsFixed(3)} '
      'gate=$verdictToken',
    );
  }
  // THE SHAPE GATES ON THEIR OWN, with the company gate switched off by passing no neighbours. The
  // difference between this count and the count above is exactly what the isolation rule contributes
  // on this page, and it is printed because a rule whose effect cannot be measured is a rule nobody
  // can defend.
  int shapeOnly = 0;
  for (final PlacedInkStroke one in placed) {
    final BarlineFrame? frame = barlineFrameFor(
      barFrames: frames,
      anchor: one.stroke.anchor,
      origin: one.origin,
    );
    if (frame == null) {
      continue;
    }
    final BarlineVerdict verdict = detector.measure(
      stroke: one.stroke,
      frame: frame,
    );
    if (verdict.accepted) {
      shapeOnly++;
    }
  }
  final double shortestAllowed = frames.isEmpty
      ? 0
      : detector.thresholds.minimumHeightFor(
          frames.values.first.referenceHeight,
        );
  stdout.writeln(
    'probe.totals strokes=${verdicts.length} accepted=$accepted '
    'refused=${verdicts.length - accepted} '
    'accepted_by_shape_alone=$shapeOnly '
    'tallest_vertical_mark=${f(tallestVerticalMark)} '
    'shortest_allowed_line=${f(shortestAllowed)} '
    'margin=${f(shortestAllowed - tallestVerticalMark)} '
    'closest=$closestId closest_headroom=${closestHeadroom.toStringAsFixed(3)} '
    'gates=${byGate.entries.map((MapEntry<String, int> e) => '${e.key}:${e.value}').join(',')}',
  );
  for (final PlacedBarlineCandidate candidate in detectBarlineDivisions(
    strokes: placed,
    barFrames: frames,
    detector: detector,
  )) {
    stdout.writeln(
      'probe.division from=${candidate.candidate.strokeId} '
      'x=${f(candidate.candidate.centreX)} '
      'top=${f(candidate.candidate.top)} '
      'height=${f(candidate.candidate.height)} '
      'page_x=${f(candidate.pageX)}',
    );
  }
  _probeStaff(
    document: document,
    hisInk: placed,
    frames: frames,
    detector: detector,
  );
}

// -------------------------------------------------------------------------------------------------
// THE STAFF SECTION
//
// The owner's report is that a division drawn INSIDE THE MELODY STAFF is not recognised, and his
// page declares no staff, so the geometry he drew on has to be produced here instead of being read
// from his file. The song is therefore rebuilt WITH a declared pitched staff, laid out by the
// application's own engine, and every stroke below is placed against the staff box THAT ENGINE
// PUBLISHED — so a number printed here is a number about the page the app really draws.
//
// TWO VARIANTS, because the layout reserves a different amount of paper for a staff with no note in
// it than for one being written on (`LayoutStyle.melodyEmptyBandHeight` against `melodyBandHeight`),
// and the staff therefore sits at a different y in each. Both are states of the owner's chart, so a
// detector that worked in one and not the other would be the same bug again.
// -------------------------------------------------------------------------------------------------

/// The owner's song with a pitched staff declared, and — when [withNote] — one note on the staff so
/// the layout reserves the band it reserves for a staff that carries music.
///
/// HIS BARS, CHORDS AND SECTIONS ARE COPIED VERBATIM, so the page this produces carries his own ink
/// in the chord rows and a real staff beneath it at the same time: the false-positive corpus and the
/// staff measurement are then one page.
Song songWithStaff(Song song, {required bool withNote}) {
  if (song.sections.isEmpty) {
    return Song(
      id: song.id,
      title: song.title,
      key: song.key,
      staffSet: newChartDefaultStaffSet,
      sections: <Section>[
        Section(
          id: newChartFirstSectionId,
          label: newChartFirstSectionLabel,
          bars: <Bar>[withNote ? _barWithOneNote(const Bar()) : const Bar()],
        ),
      ],
    );
  }
  return Song(
    id: song.id,
    title: song.title,
    composer: song.composer,
    style: song.style,
    key: song.key,
    tempo: song.tempo,
    staffSet: newChartDefaultStaffSet,
    sections: <Section>[
      for (final Section section in song.sections)
        Section(
          id: section.id,
          label: section.label,
          bars: <Bar>[
            for (int index = 0; index < section.bars.length; index++)
              withNote && index == 0
                  ? _barWithOneNote(section.bars[index])
                  : section.bars[index],
          ],
        ),
    ],
  );
}

/// [bar] with one quarter note on its first beat, which is the least music that makes the layout
/// reserve the full melody band instead of the shallower one it reserves for a blank staff.
Bar _barWithOneNote(Bar bar) => Bar(
  timeSignature: bar.timeSignature,
  size: bar.size,
  chords: bar.chords,
  openingBarline: bar.openingBarline,
  closingBarline: bar.closingBarline,
  volta: bar.volta,
  repeatPrevious: bar.repeatPrevious,
  slashRepeat: bar.slashRepeat,
  noChord: bar.noChord,
  marks: bar.marks,
  staffText: bar.staffText,
  melody: <NoteMark>[
    NoteMark(
      place: placeAt(0),
      pitch: PitchedNote(note: WrittenNote(NoteLetter.b, -1), octave: 4),
      value: NoteValue.plain(NoteBase.quarter),
    ),
  ],
  percussion: bar.percussion,
);

/// One synthesised stroke, in page coordinates, with the name the probe prints for it.
class ProbeInk {
  /// Creates a stroke called [name] through [points], in the page's engraved coordinates.
  const ProbeInk({required this.name, required this.points});

  /// The name this stroke is printed and weighed under.
  final String name;

  /// Its samples, in page coordinates.
  final List<LayoutOffset> points;
}

/// One case: the stroke being weighed, plus the strokes drawn beside it.
class ProbeCase {
  /// Creates a case named [name] whose candidate is [points].
  const ProbeCase({
    required this.name,
    required this.note,
    required this.points,
    this.companions = const <ProbeInk>[],
  });

  /// The name printed for this case.
  final String name;

  /// What the case is here to show, printed beside the numbers.
  final String note;

  /// The candidate stroke, in page coordinates.
  final List<LayoutOffset> points;

  /// Other strokes drawn on the same page — a notehead under a stem — each anchored and weighed
  /// exactly as the candidate is, and each a neighbour of it.
  final List<ProbeInk> companions;
}

/// A vertical stroke from ([x], [y0]) to ([x], [y1]) with the one-pixel wobble a hand has and a
/// machine does not: the detector measures wobble, so a stroke without any would measure better than
/// any stroke the owner ever wrote.
List<LayoutOffset> vertical(
  double x,
  double y0,
  double y1, {
  double lean = 0,
  int samples = 14,
}) => <LayoutOffset>[
  for (int index = 0; index < samples; index++)
    LayoutOffset(
      x + lean * index / (samples - 1) + (index.isEven ? 0.4 : -0.4),
      y0 + (y1 - y0) * index / (samples - 1),
    ),
];

/// A horizontal stroke from ([x0], [y]) to ([x1], [y]).
List<LayoutOffset> horizontal(
  double x0,
  double x1,
  double y, {
  int samples = 10,
}) => <LayoutOffset>[
  for (int index = 0; index < samples; index++)
    LayoutOffset(x0 + (x1 - x0) * index / (samples - 1), y),
];

/// A closed loop of [width] by [height] centred at ([cx], [cy]) — a notehead, which is the thing a
/// stem hangs from and the reason a stem is not a division.
List<LayoutOffset> loop(
  double cx,
  double cy,
  double width,
  double height, {
  int samples = 16,
}) => <LayoutOffset>[
  for (int index = 0; index < samples; index++)
    LayoutOffset(
      cx + width / 2 * math.cos(index / (samples - 1) * 2 * math.pi),
      cy + height / 2 * math.sin(index / (samples - 1) * 2 * math.pi),
    ),
];

/// The cases laid on the staff [staff] of [bar], in page coordinates.
///
/// EVERY MEASUREMENT THE OWNER'S BUG TURNS ON IS ONE CASE. The division across the five lines is the
/// mark that must be found; the stem is the vertical mark that must not be, and it is drawn twice —
/// once attached to a notehead, which is what a stem is, and once alone, which is what a stem looks
/// like to a detector that cannot see the notehead. The ledger line and the staff's own line are
/// horizontal and are here to show the shape gates still refuse them; the letters of his chord
/// symbols are here at the size A73 measured them, on the staff rather than in the row, because a
/// letter and a division can be drawn in the same band and must still be told apart.
///
/// [emptyBar] is a bar whose chord row carries NO INK — the page's own bars after his five written
/// ones — so the chord-row division is weighed as the mark alone rather than as a mark inside his
/// handwriting. Without it the row case measures `crowded` against the symbols he drew in bar 0, which
/// is a true number about the wrong question.
List<ProbeCase> staffCases(PlacedBar bar, PlacedBar emptyBar) {
  final LayoutRect staff = bar.melody.bounds;
  final LayoutRect row = emptyBar.bounds;
  final double space = staff.size.height / 4;
  final double top = staff.origin.y;
  final double bottom = staff.origin.y + staff.size.height;
  final double x = bar.bounds.origin.x + bar.bounds.size.width * 0.55;
  final double x2 = bar.bounds.origin.x + bar.bounds.size.width * 0.75;
  final double rowX = row.origin.x + row.size.width * 0.35;
  // THE NOTEHEAD the stem hangs from: a filled head on the staff's middle line, drawn as a loop, and
  // its stem rising 3.5 staff spaces from the head's right edge — the engraved proportions, drawn as
  // two strokes because that is how a hand draws a note.
  final double headCx = bar.bounds.origin.x + bar.bounds.size.width * 0.4;
  final double headCy = top + 2 * space;
  final double headW = 1.2 * space;
  final double headH = 0.9 * space;
  return <ProbeCase>[
    ProbeCase(
      name: 'staff-division',
      note: 'a division drawn across the five lines, overshooting them as a hand does',
      points: vertical(x, top - 2, bottom + 2),
    ),
    ProbeCase(
      name: 'staff-division-exact',
      note: 'a division drawn exactly from the top line to the bottom line',
      points: vertical(x2, top, bottom),
    ),
    ProbeCase(
      name: 'staff-division-short',
      note: 'a division stopping a staff space short at each end',
      points: vertical(x, top + space, bottom - space),
    ),
    ProbeCase(
      name: 'chord-row-division',
      note: 'the A73 positive, drawn in the chord row of an ink-free bar of the same page',
      points: vertical(
        rowX,
        row.origin.y + 3,
        row.origin.y + row.size.height - 3,
      ),
    ),
    ProbeCase(
      name: 'chord-row-division-overshoot',
      note: 'the machine line A73 measured at 70.6 px: taller than the row it divides',
      points: vertical(
        row.origin.x + row.size.width * 0.65,
        row.origin.y - 9,
        row.origin.y + row.size.height + 9,
      ),
    ),
    ProbeCase(
      name: 'stem-with-notehead',
      note: 'a stem rising 3.5 spaces from a notehead drawn beside it',
      points: vertical(headCx + headW / 2 + 0.5, headCy - 3.5 * space, headCy),
      companions: <ProbeInk>[
        ProbeInk(name: 'notehead', points: loop(headCx, headCy, headW, headH)),
      ],
    ),
    ProbeCase(
      name: 'stem-alone',
      note: 'the same stem with its notehead missing from the ink',
      points: vertical(headCx + headW / 2 + 0.5, headCy - 3.5 * space, headCy),
    ),
    ProbeCase(
      name: 'ledger-line',
      note: 'a ledger line under the staff: horizontal and short',
      points: horizontal(
        headCx - 1.3 * space,
        headCx + 1.3 * space,
        bottom + 2 * space,
      ),
    ),
    ProbeCase(
      name: 'staff-line',
      note: "the staff's own top line: horizontal and as wide as the bar",
      points: horizontal(
        bar.bounds.origin.x + 1,
        bar.bounds.origin.x + bar.bounds.size.width - 1,
        top,
      ),
    ),
    ProbeCase(
      name: 'paren-on-staff',
      note:
          'the "(" of "(b9)": 22.8 x 5.1, verticality 0.93, drawn on the staff',
      points: vertical(x, top + 6, top + 28.8, lean: 5),
    ),
    ProbeCase(
      name: 'seven-on-staff',
      note: 'the "7" of "Bb7(b9)": 18.7 x 3.3, drawn on the staff',
      points: vertical(x2, top + 6, top + 24.7, lean: 3),
    ),
    ProbeCase(
      name: 'slash-on-staff',
      note: 'the "/" of "6/9": 17.1 x 8.3, drawn on the staff',
      points: vertical(x, top + 6, top + 23.1, lean: 8),
    ),
    ProbeCase(
      name: 'staff-division-before-note',
      note:
          'a division at the head of a beat that PRINTS a note: where a bar opening on a note '
          'puts one, and the case a gate reading the engraved glyphs would refuse',
      points: vertical(headCx - headW / 2 - 1.5, top - 2, bottom + 2),
    ),
    ProbeCase(
      name: 'accidental-on-staff',
      note: 'an accidental beside a notehead: 1.7 spaces tall, which is 22.1 px here',
      points: vertical(
        headCx - headW / 2 - 0.6 * space,
        headCy - 0.85 * space,
        headCy + 0.85 * space,
      ),
      companions: <ProbeInk>[
        ProbeInk(name: 'notehead', points: loop(headCx, headCy, headW, headH)),
      ],
    ),
  ];
}

/// Runs the staff section: both variants of the page, every case, one printed line each.
void _probeStaff({
  required DocumentState document,
  required List<PlacedInkStroke> hisInk,
  required Map<String, BarlineFrame> frames,
  required BarlineDetector detector,
}) {
  for (final bool withNote in <bool>[false, true]) {
    final String variant = withNote ? 'staff-with-note' : 'staff-empty';
    final Song song = songWithStaff(document.song, withNote: withNote);
    final List<PageLayout> pages = LayoutEngine(style: appStyle())
        .layout(song, pageWidth: probePageWidth, pageHeight: probePageHeight);
    if (pages.isEmpty || pages.first.bars.isEmpty) {
      stdout.writeln('probe.staff variant=$variant skipped=no-page');
      continue;
    }
    final PageLayout page = pages.first;
    final PlacedBar bar = page.bars.first;
    if (bar.melody.isEmpty) {
      stdout.writeln('probe.staff variant=$variant skipped=no-staff');
      continue;
    }
    final LayoutRect staff = bar.melody.bounds;
    final LayoutRect row = bar.bounds;
    final double staffTop = staff.origin.y;
    final double staffBottom = staff.origin.y + staff.size.height;
    stdout.writeln(
      'probe.staff variant=$variant bars=${page.bars.length} '
      'glyphs=${bar.melody.glyphs.length} '
      'chord_row_page=(y=${f(row.origin.y)}..${f(row.origin.y + row.size.height)}) '
      'staff_page=(y=${f(staffTop)}..${f(staffBottom)}) '
      'staff_in_row_local=(y=${f(staffTop - row.origin.y)}..'
      '${f(staffBottom - row.origin.y)}) '
      'staff_height=${f(staff.size.height)} space=${f(staff.size.height / 4)} '
      'row_height=${f(row.size.height)}',
    );
    // HIS OWN INK IS ON THIS PAGE, anchored to the same bars, so every case is weighed with the
    // company gate seeing exactly the neighbours the real page has.
    final List<PlacedInkStroke> his = placeInkStrokes(page, document.strokes);
    // THE LAST BAR OF THE PAGE, whose chord row his hand did not write on, so the chord-row division
    // is measured as the mark and not as a mark inside a chord symbol.
    final PlacedBar emptyBar = page.bars.last;
    for (final ProbeCase probeCase in staffCases(bar, emptyBar)) {
      final PlacedInkStroke? candidate = _placeStroke(
        page: page,
        ink: ProbeInk(name: probeCase.name, points: probeCase.points),
      );
      if (candidate == null) {
        stdout.writeln(
          'probe.staffcase variant=$variant case=${probeCase.name} '
          'skipped=no-anchor note="${probeCase.note}"',
        );
        continue;
      }
      final List<PlacedInkStroke> neighbours = <PlacedInkStroke>[...his];
      for (final ProbeInk companion in probeCase.companions) {
        final PlacedInkStroke? placedCompanion = _placeStroke(
          page: page,
          ink: companion,
        );
        if (placedCompanion != null) {
          neighbours.add(placedCompanion);
        }
      }
      final BarlineVerdict verdict = measureBarlineStroke(
        stroke: candidate,
        strokes: <PlacedInkStroke>[...neighbours, candidate],
        barFrames: barlineFramesOfPage(page),
        detector: detector,
      );
      final BarlineMeasurement m = verdict.measurement;
      stdout.writeln(
        'probe.staffcase variant=$variant case=${probeCase.name} '
        'bar=${m.anchor.sectionId}#${m.anchor.bar} '
        'local_y=${f(m.minY)}..${f(m.maxY)} '
        'height=${f(m.height)} aspect=${f(m.aspect)} '
        'verticality=${m.verticality.toStringAsFixed(2)} '
        'barline=${f(m.referenceHeight)} band=${m.band?.kind.token ?? 'none'} '
        'band_overlap=${m.bandOverlap.toStringAsFixed(2)} '
        'row_overlap=${m.rowOverlap.toStringAsFixed(2)} '
        'isolation=${f(m.isolation)} '
        'printed_gap=${f(_printedGapOf(bar, candidate.stroke.points, candidate.origin))} '
        'gate=${verdict.rejection?.token ?? 'accept'} '
        '${verdict.accepted ? 'line_top=${f(verdict.candidate!.top)} '
                  'line_height=${f(verdict.candidate!.height)} ' : ''}'
        'note="${probeCase.note}"',
      );
    }
  }
}

/// The narrowest horizontal gap between the candidate stroke and an ENGRAVED glyph of the same bar
/// — the printed notes the application drew, which are not ink and which the company gate therefore
/// cannot see.
///
/// WHY THIS NUMBER IS PRINTED RATHER THAN ACTED ON. A note stem is a vertical segment attached to a
/// notehead, and the company gate rejects it by measuring the gap to that notehead — but only when
/// the notehead is HANDWRITING. When the notehead is engraved, the gate is blind to it, and a stem
/// drawn onto a printed note would pass. The obvious repair is to feed the printed glyph boxes into
/// the company gate as well; this column is the measurement that says what that would cost, because
/// a division drawn at the head of a beat that prints a note stands exactly this far from the
/// notehead, and the gate's floor is 7.8 px. The decision and its price belong together.
double _printedGapOf(
  PlacedBar bar,
  List<InkPoint> points,
  LayoutOffset origin,
) {
  if (bar.melody.isEmpty || points.isEmpty) {
    return double.infinity;
  }
  double minX = double.infinity;
  double maxX = -double.infinity;
  double minY = double.infinity;
  double maxY = -double.infinity;
  for (final InkPoint point in points) {
    final double x = point.x + origin.x;
    final double y = point.y + origin.y;
    if (x < minX) {
      minX = x;
    }
    if (x > maxX) {
      maxX = x;
    }
    if (y < minY) {
      minY = y;
    }
    if (y > maxY) {
      maxY = y;
    }
  }
  double nearest = double.infinity;
  for (final MelodyGlyph glyph in bar.melody.glyphs) {
    final LayoutRect box = glyph.bounds;
    if (box.origin.y + box.size.height < minY || box.origin.y > maxY) {
      continue;
    }
    final double gap = box.origin.x + box.size.width < minX
        ? minX - (box.origin.x + box.size.width)
        : box.origin.x > maxX
        ? box.origin.x - maxX
        : 0;
    if (gap < nearest) {
      nearest = gap;
    }
  }
  return nearest;
}

/// The smallest of a mark's ratios to the gates it must pass: 1.0 would have been accepted, 0.585
/// falls 41 per cent short of the gate that stopped it.
///
/// WHY IT EXISTS BESIDE THE VERDICT. "No false positives" is a count, and a count says nothing about
/// how much room is left before a musician's letters start firing the detector. The closest call on
/// the page is that room, expressed as the fraction of the gate the mark reached — and because it is
/// the MINIMUM over all five gates rather than the gate that happened to be reported first, it cannot
/// flatter a mark that clears one rule and fails the next by a hair.
double _headroomOf(BarlineMeasurement m, BarlineThresholds t) {
  final double heightRatio = t.minimumHeightFor(m.referenceHeight) <= 0
      ? double.infinity
      : m.height / t.minimumHeightFor(m.referenceHeight);
  final double isolationRatio = t.minimumIsolationFor(m.referenceHeight) <= 0
      ? double.infinity
      : (m.isolation.isFinite ? m.isolation : double.infinity) /
            t.minimumIsolationFor(m.referenceHeight);
  return <double>[
    m.verticality / t.minVerticality,
    m.aspect / t.minAspect,
    heightRatio,
    m.bandOverlap / t.minBandOverlapFraction,
    isolationRatio,
  ].reduce((double a, double b) => a < b ? a : b);
}

/// Anchors [ink] by the application's OWN rule — cell, then bar, then nearest bar — and returns it in
/// anchor-local coordinates, which is the only form the detector is ever given.
///
/// The rule is `resolveInkAnchor`, the same function `InkStrokeAssembler.begin` calls, so a stroke
/// synthesised here is anchored exactly as the pen's stroke would be: a division drawn on the staff
/// lands on the staff, which is over no cell and no bar, and therefore hangs on the bar nearest it.
PlacedInkStroke? _placeStroke({
  required PageLayout page,
  required ProbeInk ink,
}) {
  if (ink.points.isEmpty) {
    return null;
  }
  final InkAnchorChoice? choice = resolveInkAnchor(page, ink.points.first);
  if (choice == null) {
    return null;
  }
  final LayoutOffset origin = choice.origin;
  return PlacedInkStroke(
    stroke: InkStroke(
      id: ink.name,
      tool: StrokeTool.pen,
      color: '#102a43',
      size: 3,
      anchor: choice.anchor,
      points: <InkPoint>[
        for (final LayoutOffset point in ink.points)
          InkPoint(x: point.x - origin.x, y: point.y - origin.y, w: 0.5, t: 0),
      ],
    ),
    origin: origin,
  );
}
