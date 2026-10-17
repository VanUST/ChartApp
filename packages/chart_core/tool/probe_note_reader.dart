// PURPOSE: Put NUMBERS on the pure-geometry note reader, on two kinds of ink that matter:
//          the repository's OWN engraving, and the owner's REAL handwriting. It is the instrument
//          that decides whether the feature is worth having, and it is built so that its own
//          number can be checked against an answer known independently.
//
//          PART 1 — THE REPOSITORY'S OWN ENGRAVING. The measured claim being ported was 16/16 pitch
//          and 0 false positives on four notes per bar on ADJACENT beats, engraved by this
//          repository's own `LayoutEngine` at the application's own layout style. This probe
//          rebuilds exactly that: four bars of four notes on adjacent beats, pitches whose staff
//          positions are written down by hand from musical notation (the bottom line of a treble
//          staff is E4, so C4 is the ledger line below it and that is step −2), laid out by the
//          real engine, then COPIED INTO INK — every glyph the engraver publishes for that bar is
//          traced as a stroke at a real pen's nib width, which is the input the application
//          actually receives. The reader must recover the sixteen positions from that ink.
//
//          WHY THE INK IS BUILT FROM THE GLYPHS AND WHAT THAT DOES AND DOES NOT PROVE. The glyph
//          boxes are where the engraver drew each element, so tracing them is the most faithful
//          "pen copy of the engraving" available without a hand: it carries the noteheads, and it
//          carries the STEMS, BEAMS, LEDGER LINES, DOTS AND ACCIDENTALS the engraver drew beside
//          them — which is what makes the false-positive half of the number mean something, because
//          every one of those is ink that a reader could mistake for a note. What it does NOT prove
//          is anything about a human hand: the trace is smooth and evenly weighted, and a real pen's
//          tremor, overshoot and heavy nib are modelled in the degradation pass and nowhere else.
//
//          PART 2 — THE DEGRADED COPY. The same ink with three things a hand does that a trace does
//          not: a heavier nib, a tremor added to every sample, and a wobble in the closed ring of
//          each notehead. The measured claim reported 16/16 on a pen-degraded render too, so the
//          same number is asked for here. ROTATION is deliberately NOT part of this pass and the
//          reason is structural rather than convenient: a stroke is stored in ANCHOR-LOCAL
//          coordinates that the capture path derives by dividing the page transform out
//          (`PageLayout.pagePointOf`), so a rotated page does not rotate the stored ink. There is
//          no rotation to model.
//
//          PART 3 — THE SPACING DEFECT, IN BOTH DIRECTIONS. The same bar is read twice: once with
//          `LayoutStyle.minCellWidth` at the 14 it used to default to, and once at the 18 it
//          defaults to now and that the application passes. At 14 two adjacent-beat noteheads
//          overlap and the reader must report fewer notes than were written; at 18 it must report
//          all four. That pair is the evidence for the layout change, and it is the same mistake
//          the measured claim hit on its first render.
//
//          PART 4 — THE OWNER'S REAL INK, WHICH IS CHORD SYMBOLS AND NO NOTES. His sample holds
//          five chord symbols written by hand and not one note, so the honest score on it is not an
//          accuracy: it is a FALSE-POSITIVE COUNT. Read against the staff the page declares, the
//          reader must report no heads at all. And because a zero can mean "the instrument was not
//          plugged in", the same ink is then read with the PLACE gate disabled — a control that
//          shows what the shape gates alone would have said — so the number that protects the
//          feature is the difference between the two, not either one alone.
//
//          NOT PART OF THE LIBRARY AND NOT PART OF THE SUITE. It lives in `tool/`, so neither
//          `dart test` nor `melos run verify` picks it up; it is run by hand:
//
//              dart run packages/chart_core/tool/probe_note_reader.dart
//
//          It writes no files: the repository is public and a rendered image is evidence for one
//          inspection rather than an artefact to commit.
// INPUTS: The chart path (first argument, defaulting to the owner's sample), which part 4 decodes
//         with the repository's own codec.
// OUTPUTS: `probe.*` lines on stdout and exit code 0. Exit code 2 when the sample chart cannot be
//          read or laid out, so a missing input never prints a misleading zero.
// KEYWORDS: probe, note-reader, geometry, pitch, false-positive, engraving, pen-degradation,
//           spacing-defect, owner-ink, evidence, not-part-of-the-library
import 'dart:io';
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';

/// The owner's sample, unless a path is given on the command line.
const String defaultChartPath =
    r'C:\projects\ChartApp-acl-reports\omr-sample\untitled.chart';

/// The page the probe engraves on, matching the other render instruments' surface.
const double probePageWidth = 824;

/// The page height the probe engraves on.
const double probePageHeight = 1318;

/// The nib width a trace is drawn with, in page pixels — a fine pen at the default staff size.
const double traceNib = 2.2;

/// The nib width of a pen heavier than the fine trace, and heavier than the owner's own stylus:
/// his strokes are stored at `size` 3.0.
const double penNib = 3.2;

/// The nib width of a MARKER, which is past what the spacing the application uses can keep apart.
/// It is measured rather than chosen for plausibility: see the note beside it in the run below.
const double markerNib = 4.4;

/// The amplitude of the tremor the degradation pass adds to every sample, in page pixels.
const double tremorAmplitude = 0.6;

/// How many samples the tremor is stepped through, so the same run is reproducible.
const int tremorPeriod = 7;

/// Prints one number to one decimal place, or `inf`, so a column of them stays readable.
String f(double value) => value.isFinite ? value.toStringAsFixed(1) : 'inf';

/// The layout style the application uses, so the geometry measured here is the geometry a musician
/// is given rather than one invented for the probe.
LayoutStyle appStyle({double? minCellWidth}) => LayoutStyle(
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: minCellWidth ?? 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

// PURPOSE: Say what staff step a written pitch occupies, from MUSICAL NOTATION and not from the
//          code under test — the rule this repository learned the hard way (A70): an expectation
//          copied out of the implementation cannot fail when the implementation is wrong.
// INPUTS: octave and letter index — the letter as C=0, D=1, E=2, F=3, G=4, A=5, B=6, which is the
//          order the lines are written in.
// OUTPUTS: The staff step, counting 0 at the staff's bottom line. The derivation, stated so it can
//          be checked by eye: on a TREBLE staff the bottom line is E4, the space above it is F4, the
//          second line is G4 and the middle line is B4. A step is HALF a space, so a letter is two
//          steps and an octave is fourteen. E4 is therefore 0, C4 — two letters below E — is −2,
//          B4 — four letters above E — is 4, and C5 is 5.
// KEYWORDS: staff-step, hand-derived, music-theory, not-from-the-code, a70
int trebleStepOf(int octave, int letterIndex) =>
    7 * octave + letterIndex - (7 * 4 + 2);

// PURPOSE: Build one bar of four notes on adjacent beats from a table of written pitches, so the
//          melody the probe reads is a melody someone wrote down rather than a by-product of the
//          layout.
// INPUTS: the four pitches as (octave, letter) pairs, all in the same section and bar.
// OUTPUTS: A [Bar] whose melody holds one quarter note per beat, in the order given.
// KEYWORDS: fixture, melody, adjacent-beats, bar-builder
Bar barOfFour(List<(int, int)> pitches) => Bar(
  melody: <BeatNote>[
    for (int beat = 0; beat < pitches.length; beat++)
      BeatNote(
        pitch: PitchedNote(
          note: WrittenNote(NoteLetter.values[pitches[beat].$2], 0),
          octave: pitches[beat].$1,
        ),
        value: const NoteValue.plain(NoteBase.quarter),
        beat: beat,
      ),
  ],
);

// PURPOSE: Assemble the four-bar fixture whose sixteen staff positions are known by hand: a rising
//          run from the ledger line below the staff, two bars inside it, and a descending bar.
// INPUTS: None.
// OUTPUTS: The song, with a declared pitched treble staff so the layout draws one (D29).
// KEYWORDS: fixture, song, treble, sixteen-notes, four-bars
Song fixtureSong() => Song(
  id: 'probe-note-reader',
  title: 'sixteen notes',
  composer: '',
  style: '',
  key: Key.cMajor,
  tempo: 120,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'sec-1',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        // C4 D4 E4 F4 — the ledger line below the staff, the space below it, its bottom line, and
        // the space above that. Steps -2, -1, 0, 1.
        barOfFour(<(int, int)>[(4, 0), (4, 1), (4, 2), (4, 3)]),
        // G4 A4 B4 C5 — steps 2, 3, 4, 5. The middle line is B4.
        barOfFour(<(int, int)>[(4, 4), (4, 5), (4, 6), (5, 0)]),
        // D5 E5 F5 G5 — steps 6, 7, 8, 9. Step 8 is the top line, step 9 a ledger line above it.
        barOfFour(<(int, int)>[(5, 1), (5, 2), (5, 3), (5, 4)]),
        // C5 B4 A4 G4 — steps 5, 4, 3, 2, descending, so a reader that sorted by height instead of
        // by position would still agree and a reader that read only the first head would not.
        barOfFour(<(int, int)>[(5, 0), (4, 6), (4, 5), (4, 4)]),
      ],
    ),
  ],
);

// PURPOSE: Trace one engraved glyph as a pen stroke, which is how the engraving becomes the input
//          this reader is written for: a notehead becomes a closed ring, a stem a line, a beam a
//          thick line, a ledger line a thin one, a dot a blob.
// INPUTS: glyph — one piece of the staff as the engraver published it; pen — the nib width to draw
//         it with; pageOrigin — the bar's top-left corner, which the stored coordinates are
//         measured from, exactly as the capture path measures them.
// OUTPUTS: The stroke's points in ANCHOR-LOCAL coordinates (page minus the bar's origin), or an
//          empty list for a glyph that is not ink (a tie's curve is skipped: a tie is not read and
//          its curve is not one of the things this reader has to survive).
//
//          A NOTEHEAD IS DRAWN AS A RING AT ITS OWN OUTER SIZE, one nib smaller, so that the ink's
//          extent is exactly the notehead's box — which is what a pen does: the nib straddles the
//          line it draws. A hollow head and a filled one are traced the same way because the
//          gates measure the ink's EXTENT per row, and a ring and a disc have the same extent.
// KEYWORDS: trace, glyph-to-stroke, nib, anchor-local, ink-fixture
List<LayoutOffset> traceGlyph(
  MelodyGlyph glyph, {
  required double pen,
  required LayoutOffset pageOrigin,
}) {
  final LayoutRect box = glyph.bounds;
  final double cx = box.left + box.size.width / 2;
  final double cy = box.top + box.size.height / 2;
  List<LayoutOffset> page;
  switch (glyph.kind) {
    case MelodyGlyphKind.notehead:
      final double rx = math.max(0.5, (box.size.width - pen) / 2);
      final double ry = math.max(0.5, (box.size.height - pen) / 2);
      page = <LayoutOffset>[
        for (int i = 0; i <= 24; i++)
          LayoutOffset(
            cx + rx * math.cos(i * math.pi / 12),
            cy + ry * math.sin(i * math.pi / 12),
          ),
      ];
    case MelodyGlyphKind.stem:
    case MelodyGlyphKind.ledgerLine:
      final bool vertical = box.size.height > box.size.width;
      page = <LayoutOffset>[
        LayoutOffset(vertical ? cx : box.left, vertical ? box.top : cy),
        LayoutOffset(vertical ? cx : box.right, vertical ? box.bottom : cy),
      ];
    case MelodyGlyphKind.beam:
      page = <LayoutOffset>[glyph.from, glyph.to];
    case MelodyGlyphKind.accidental:
      // A narrow zigzag, which is what a `#` reads as at a stroke's weight: the reader has to
      // refuse it as too narrow and this is the ink that asks it to.
      page = <LayoutOffset>[
        LayoutOffset(box.left, box.top),
        LayoutOffset(box.right, box.bottom),
        LayoutOffset(box.right, box.top),
        LayoutOffset(box.left, box.bottom),
      ];
    case MelodyGlyphKind.dot:
      page = <LayoutOffset>[
        for (int i = 0; i <= 8; i++)
          LayoutOffset(
            cx + box.size.width / 2 * math.cos(i * math.pi / 4),
            cy + box.size.height / 2 * math.sin(i * math.pi / 4),
          ),
      ];
    case MelodyGlyphKind.flag:
    case MelodyGlyphKind.tie:
      return const <LayoutOffset>[];
  }
  return <LayoutOffset>[
    for (final LayoutOffset point in page)
      LayoutOffset(point.x - pageOrigin.x, point.y - pageOrigin.y),
  ];
}

// PURPOSE: Copy one engraved bar into ink: one stroke per glyph the engraver drew, each with a nib
//          wide enough to be that glyph's own weight, then optionally degraded the way a hand
//          degrades a trace.
// INPUTS: bar — the placed bar, whose `melody.glyphs` are everything drawn on its staff; pen — the
//         fine-pen nib; degraded — whether to model a hand (heavier nib, tremor, a loose ring).
// OUTPUTS: The strokes, each anchored to the BAR, which is the anchor the capture path chooses for
//          ink written on the staff: the staff lies below every cell, so `resolveInkAnchor` hangs
//          such a stroke on the nearest bar. The points are therefore bar-anchor-local, which is
//          what a real capture would store and what the reader is given.
// KEYWORDS: ink-fixture, glyph-trace, anchor-bar, pen-degradation, tremor, heavy-nib
List<InkStroke> inkOfBar(
  PlacedBar bar, {
  double nib = traceNib,
  bool degraded = false,
}) {
  final EventAnchor anchor = EventAnchor(
    sectionId: bar.sectionId,
    bar: bar.barIndex,
  );
  final List<InkStroke> strokes = <InkStroke>[];
  int index = 0;
  for (final MelodyGlyph glyph in bar.melody.glyphs) {
    final double glyphNib = glyph.kind == MelodyGlyphKind.beam ? nib * 3 : nib;
    final List<LayoutOffset> points = traceGlyph(
      glyph,
      pen: glyphNib,
      pageOrigin: bar.bounds.origin,
    );
    if (points.isEmpty) {
      continue;
    }
    strokes.add(
      InkStroke(
        id: 'ink-${bar.sectionId}-${bar.barIndex}-${index++}',
        tool: StrokeTool.pen,
        color: '#102a43',
        size: glyphNib,
        anchor: anchor,
        points: <InkPoint>[
          for (int i = 0; i < points.length; i++)
            InkPoint(
              x: points[i].x + (degraded ? _tremor(i) : 0),
              y: points[i].y + (degraded ? _tremor(i + 3) : 0),
              w: 1,
              t: i.toDouble(),
            ),
        ],
      ),
    );
  }
  return strokes;
}

// PURPOSE: Give sample [index] a small displacement, deterministically, so the degradation pass is
//          a measurement that can be repeated rather than a random run.
// INPUTS: index — the sample's position in its stroke.
// OUTPUTS: A displacement in `[-tremorAmplitude, +tremorAmplitude]`, stepped through a short period
//          so that consecutive samples move together the way a hand's tremor does.
// KEYWORDS: tremor, deterministic, reproducible, pen-model
double _tremor(int index) =>
    tremorAmplitude *
    math.sin(2 * math.pi * (index % tremorPeriod) / tremorPeriod) /
    2;

// PURPOSE: Read every bar of a laid-out fixture and score the reader against the truth that was
//          written down by hand, printing the two numbers that decide the feature: how many of the
//          written notes came back at the right staff position, and how many notes the reader
//          invented.
// INPUTS: tag — the name this run is reported under; song — the fixture; style — the layout style,
//         which is what makes the spacing comparison possible; degraded — whether the ink is the
//         pen-degraded copy.
// OUTPUTS: One `probe.read` line per bar and a totals line. The truth is per bar and per beat: the
//          note written on beat b must come back as the head at beat b, with the step the hand
//          derivation above names. A head at a beat nothing was written on is a false positive, and
//          so is a second head in a cell that holds one note.
// KEYWORDS: score, pitch, false-positive, per-bar, hand-truth
void scoreFixture({
  required String tag,
  required Song song,
  required LayoutStyle style,
  required bool degraded,
  double nib = traceNib,
  bool dumpInk = false,
}) {
  final List<PageLayout> pages = LayoutEngine(style: style)
      .layout(song, pageWidth: probePageWidth, pageHeight: probePageHeight);
  stdout.writeln(
    'probe.fixture tag=$tag cell=${f(style.minCellWidth)} '
    'nib=$nib tremor=$degraded pages=${pages.length}',
  );
  int written = 0;
  int right = 0;
  int emitted = 0;
  for (final PageLayout page in pages) {
    for (final PlacedBar bar in page.bars) {
      final Bar model = song.barAt(bar.sectionId, bar.barIndex)!;
      final List<InkStroke> ink = inkOfBar(bar, nib: nib, degraded: degraded);
      if (dumpInk) {
        for (final InkStroke stroke in ink) {
          double minX = 1e9;
          double minY = 1e9;
          double maxX = -1e9;
          double maxY = -1e9;
          for (final InkPoint point in stroke.points) {
            minX = math.min(minX, point.x);
            minY = math.min(minY, point.y);
            maxX = math.max(maxX, point.x);
            maxY = math.max(maxY, point.y);
          }
          stdout.writeln(
            'probe.ink bar=${bar.barIndex} ${stroke.id} nib=${f(stroke.size)} '
            'box=[${f(minX + bar.bounds.left)},${f(minY + bar.bounds.top)} '
            '${f(maxX - minX)}x${f(maxY - minY)}]',
          );
        }
      }
      final MelodyNoteReading reading = readMelodyNotesOfBar(
        page: page,
        strokes: ink,
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
      );
      final StringBuffer detail = StringBuffer();
      for (final BeatNote note in model.melody) {
        written++;
        final int want = trebleStepOf(
          note.pitch.octave,
          note.pitch.note.letter.index,
        );
        MelodyNoteHead? found;
        for (final MelodyNoteHead head in reading.heads) {
          if (head.beat == note.beat) {
            found = head;
            break;
          }
        }
        final bool ok = found != null && found.step == want;
        if (ok) {
          right++;
        }
        detail.write(
          ' ${note.pitch}${ok ? '=step$want' : '!step$want/${found?.step}'}',
        );
      }
      emitted += reading.heads.length;
      stdout.writeln(
        'probe.read bar=${bar.barIndex} truth=${model.melody.length} '
        'heads=${reading.heads.length} ${detail.toString().trim()} '
        'refused=${reading.refusals.length}',
      );
      for (final MelodyNoteRefusal refusal in reading.refusals) {
        stdout.writeln(
          'probe.refuse bar=${bar.barIndex} ${refusal.reason.token} '
          'x=${f(refusal.x)} y=${f(refusal.y)} w=${f(refusal.widthFraction)} '
          'h=${f(refusal.bandFraction)} nib=${f(refusal.nib)}',
        );
      }
    }
  }
  final int falsePositives = emitted - right;
  stdout.writeln(
    'probe.score tag=$tag pitch=$right/$written '
    'heads=$emitted false_positives=${falsePositives < 0 ? 0 : falsePositives}',
  );
}

// PURPOSE: Read the owner's own strokes, which are chord symbols and no notes, and report the one
//          number that matters on them: how many noteheads the reader invents.
// INPUTS: chartPath — his `.chart`; withPlaceGate — false to disable the place gate, which is the
//         CONTROL: it is the same shape gates reading the same ink with the one rule removed that
//         tells a chord row from a staff.
// OUTPUTS: One line per bar that holds ink, then the total. A nonzero total with the gate on is a
//          false positive in the field the feature will be used in, and the gate-off total is what
//          separates "the reader has no false positives" from "the reader was never shown the ink".
// KEYWORDS: owner-ink, chord-symbol, false-positive, control, place-gate
void readOwnerInk(String chartPath, {required bool withPlaceGate}) {
  final File file = File(chartPath);
  if (!file.existsSync()) {
    stderr.writeln('no such chart file: $chartPath');
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
    stderr.writeln('the owner chart laid out to no pages');
    exit(2);
  }
  int heads = 0;
  int blobs = 0;
  stdout.writeln(
    'probe.owner ink=${document.strokes.length} strokes place_gate=$withPlaceGate',
  );
  for (final PageLayout page in pages) {
    final Map<String, MelodyStaffFrame> frames = melodyFramesOfPage(page);
    for (final PlacedBar bar in page.bars) {
      final MelodyStaffFrame? frame =
          frames['${bar.sectionId}\u0000${bar.barIndex}'];
      final List<PageInkStroke> ink = melodyInkOfBar(
        page: page,
        strokes: document.strokes,
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
      );
      if (ink.isEmpty) {
        continue;
      }
      // The control opens the whole page as the window a head may lie in; the measurement uses the
      // window the page actually reserved.
      final MelodyStaffFrame used = frame == null
          ? MelodyStaffFrame(
              middleLineY: bar.bounds.top,
              staffSpace: 13,
              headTop: withPlaceGate ? bar.bounds.bottom : -1e6,
              headBottom: 1e6,
              beatColumns: const <MelodyBeatColumn>[],
            )
          : (withPlaceGate
                ? frame
                : MelodyStaffFrame(
                    middleLineY: frame.middleLineY,
                    staffSpace: frame.staffSpace,
                    headTop: -1e6,
                    headBottom: 1e6,
                    beatColumns: frame.beatColumns,
                    clef: frame.clef,
                  ));
      final MelodyNoteReading reading = const MelodyNoteReader().read(
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
        ink: ink,
        frame: used,
      );
      heads += reading.heads.length;
      blobs += reading.blobsConsidered;
      stdout.writeln(
        'probe.owner.bar bar=${bar.barIndex} strokes=${ink.length} '
        'blobs=${reading.blobsConsidered} heads=${reading.heads.length} '
        'refused=${reading.refusals.length}',
      );
      for (final MelodyNoteRefusal refusal in reading.refusals) {
        stdout.writeln(
          'probe.owner.refuse bar=${bar.barIndex} ${refusal.reason.token} '
          'w=${f(refusal.widthFraction)} h=${f(refusal.bandFraction)}',
        );
      }
      for (final MelodyNoteHead head in reading.heads) {
        stdout.writeln(
          'probe.owner.head bar=${bar.barIndex} ${head.pitch} '
          'beat=${head.beat}.${head.orderInBeat} w=${f(head.widthFraction)} '
          'h=${f(head.bandFraction)}',
        );
      }
    }
  }
  stdout.writeln(
    'probe.owner.total place_gate=$withPlaceGate blobs=$blobs heads=$heads',
  );
}

void main(List<String> arguments) {
  final String chartPath = arguments.isEmpty || arguments.first.startsWith('--')
      ? defaultChartPath
      : arguments.first;
  final bool dumpInk = arguments.contains('--ink');

  stdout.writeln('probe.note-reader version=1');
  final Song song = fixtureSong();

  // PART 1: the repository's own engraving at the application's own spacing, as a fine-pen trace.
  scoreFixture(
    tag: 'engraving',
    song: song,
    style: appStyle(),
    degraded: false,
    dumpInk: dumpInk,
  );

  // PART 2: the same ink with a hand's three additions — a heavier nib than the trace's, a tremor on
  // every sample, and a wobble in each head's ring. 3.2 is heavier than the owner's own stored
  // stylus width of 3.0, so this is not a gentle pass.
  scoreFixture(
    tag: 'engraving-pen',
    song: song,
    style: appStyle(),
    degraded: true,
    nib: penNib,
  );

  // PART 2b: WHERE THE SPACING MARGIN RUNS OUT, AND WHY THIS RUN EXISTS AT ALL. A nib of 4.4 draws
  // a notehead whose ring is 15.6 wide and whose STEM lies at the head's right edge, so the stem's
  // own ink reaches 2.2 beyond the head — and the neighbour on the next beat stands 18 away, which
  // leaves 18 − 15.6 = 2.4 of clear space. A marker closes it, the two marks become one component,
  // and the reader REFUSES the pair rather than inventing a pitch for the pair: this row is the
  // measurement of a margin, not of a reader, and it is reported so that the margin cannot be
  // mistaken for something that has no limit.
  scoreFixture(
    tag: 'engraving-marker',
    song: song,
    style: appStyle(),
    degraded: true,
    nib: markerNib,
  );

  // PART 3: the same fixture at the OLD default cell width, which is the defect the layout change
  // repairs. Four notes per bar at 14 with a 15.6-pixel notehead must read worse than at 18.
  scoreFixture(
    tag: 'old-default-14',
    song: song,
    style: appStyle(minCellWidth: 14),
    degraded: false,
  );

  // PART 4: the owner's real handwriting.
  readOwnerInk(chartPath, withPlaceGate: true);
  readOwnerInk(chartPath, withPlaceGate: false);
}
