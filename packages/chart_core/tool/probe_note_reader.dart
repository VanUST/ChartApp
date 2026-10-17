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

// PURPOSE: Build a one-bar song whose melody is exactly [melody], so that a measurement of ONE
//          beat's run is not disturbed by anything else on the page.
// INPUTS: melody — the bar's notes, addressed by beat and step; title — a name for the run, so the
//         lines below can be read apart.
// OUTPUTS: The song, with a declared pitched staff (D29) so the layout draws one and the frame the
//          reader needs exists.
// KEYWORDS: fixture, one-bar, melody-only, declared-staff
Song oneBarSong(List<BeatNote> melody, String title) => Song(
  id: 'probe-$title',
  title: title,
  composer: '',
  style: '',
  key: Key.cMajor,
  tempo: 120,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'sec-1',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[Bar(melody: melody)],
    ),
  ],
);

/// One model note in a chosen beat and position, written with [base].
BeatNote probeNote(
  NoteLetter letter,
  int octave, {
  int beat = 0,
  int step = 0,
  NoteBase base = NoteBase.quarter,
}) => BeatNote(
  pitch: PitchedNote(note: WrittenNote(letter, 0), octave: octave),
  value: NoteValue.plain(base),
  beat: beat,
  step: step,
);

// PURPOSE: Report one reading against the notes that were written, in the addresses the model uses,
//          and say what each engraved head's x fell in — the two halves of the beat question.
// INPUTS: tag — the run's name; melody — the written notes; ink — the ink one bar's engraving was
//         traced into; frame — the columns and the staff the page published.
// OUTPUTS: `probe.run.drawn.*` per engraved head position, `probe.run.read` per accepted head,
//          `probe.run.refuse` per refused blob, and one `probe.run.score` total. Nothing is
//          returned: the numbers are the answer.
// KEYWORDS: report, round-trip, address, false-positive, taper, refusal
void reportRun({
  required String tag,
  required List<BeatNote> melody,
  required List<MelodyGlyph> glyphs,
  required List<PageInkStroke> ink,
  required MelodyStaffFrame frame,
}) {
  final List<MelodyGlyph> heads = <MelodyGlyph>[
    for (final MelodyGlyph glyph in glyphs)
      if (glyph.kind == MelodyGlyphKind.notehead) glyph,
  ];
  for (int index = 0; index < heads.length; index++) {
    final MelodyGlyph glyph = heads[index];
    final double centre = glyph.bounds.left + glyph.bounds.size.width / 2;
    final MelodyBeatColumn? column = frame.columnAt(centre);
    stdout.writeln(
      'probe.run.drawn index=$index x=${f(centre)} '
      'column=${column == null ? 'none' : '${column.beat}'}',
    );
  }
  stdout.writeln(
    'probe.run.glyphs noteheads=${heads.length} '
    'beams=${glyphs.where((MelodyGlyph glyph) => glyph.kind == MelodyGlyphKind.beam).length} '
    'flags=${glyphs.where((MelodyGlyph glyph) => glyph.kind == MelodyGlyphKind.flag).length} '
    'stems=${glyphs.where((MelodyGlyph glyph) => glyph.kind == MelodyGlyphKind.stem).length}',
  );
  final MelodyNoteReading reading = const MelodyNoteReader().read(
    sectionId: 'sec-1',
    barIndex: 0,
    ink: ink,
    frame: frame,
  );
  final Set<String> truth = <String>{
    for (final BeatNote note in melody) '${note.beat}.${note.step}',
  };
  int right = 0;
  final Set<String> seen = <String>{};
  for (final MelodyNoteHead one in reading.heads) {
    final String address = '${one.beat}.${one.orderInBeat}';
    seen.add(address);
    final bool ok = truth.contains(address);
    if (ok) {
      right++;
    }
    stdout.writeln(
      'probe.run.read address=$address pitch=${one.pitch} '
      'x=${f(one.x)} step=${one.step} w=${f(one.widthFraction)} '
      'h=${f(one.bandFraction)} ${ok ? 'right' : 'not-written'} '
      'ink=${one.strokeIds.length}',
    );
  }
  for (final MelodyNoteRefusal refusal in reading.refusals) {
    stdout.writeln(
      'probe.run.refuse ${refusal.reason.token} x=${f(refusal.x)} '
      'w=${f(refusal.widthFraction)} h=${f(refusal.bandFraction)}',
    );
  }
  stdout.writeln(
    'probe.run.score tag=$tag right=$right/${melody.length} '
    'heads=${reading.heads.length} '
    'false_positives=${seen.difference(truth).length} '
    'refused=${reading.refusals.length}',
  );
}

// PURPOSE: Put the DEFECT OF THE LAYOUT on the record with numbers: does a beat's second note stand
//          inside its own beat's column, and does the reader put it back on the beat it was written
//          on? One engraving, one trace, one reading.
// INPUTS: tag — the run's name; melody — the bar, addressed by beat and step; style — the layout
//         style, which is where the cell width lives; degraded — whether the ink models a hand.
// OUTPUTS: `probe.run.*` lines: the cell's width and the stride, each engraved notehead's centre and
//          the beat column the page gave it, then the reading. A note is RIGHT when the reader's
//          (beat, step) equals the written one; a head is a FALSE POSITIVE when its address was
//          never written.
// KEYWORDS: stride, cell-width, column, beat-assignment, round-trip, engraved-then-read
void measureBeatRun({
  required String tag,
  required List<BeatNote> melody,
  LayoutStyle? style,
  bool degraded = false,
}) {
  final LayoutStyle used = style ?? appStyle();
  final Song song = oneBarSong(melody, tag);
  final List<PageLayout> pages = LayoutEngine(style: used)
      .layout(song, pageWidth: probePageWidth, pageHeight: probePageHeight);
  if (pages.isEmpty || pages.first.bars.isEmpty) {
    stderr.writeln('probe.run: the fixture laid out to no bar');
    exit(2);
  }
  final PageLayout page = pages.first;
  final PlacedBar bar = page.bars.first;
  const MelodyMetrics metrics = MelodyMetrics();
  final double head = metrics.noteheadWidth * used.melodyStaffSpace;
  final double stride = metrics.stepOffset * used.melodyStaffSpace;
  final MelodyStaffFrame? frame = melodyFramesOfPage(
    page,
  )['${bar.sectionId}\u0000${bar.barIndex}'];
  if (frame == null) {
    stderr.writeln('probe.run: the page published no melody frame');
    exit(2);
  }
  stdout.writeln(
    'probe.run tag=$tag notes=${melody.length} '
    'cell=${f(bar.cells.isEmpty ? 0 : bar.cells.first.bounds.size.width)} '
    'stride=${f(stride)} head=${f(head)} bars_on_page=${page.bars.length}',
  );
  for (final PlacedCell cell in bar.cells) {
    stdout.writeln(
      'probe.run.cell beat=${cell.beat} '
      'x=[${f(cell.bounds.left)},${f(cell.bounds.right)}] '
      'w=${f(cell.bounds.size.width)}',
    );
  }
  final List<InkStroke> strokes = inkOfBar(bar, degraded: degraded);
  reportRun(
    tag: tag,
    melody: melody,
    glyphs: bar.melody.glyphs,
    ink: melodyInkOfBar(
      page: page,
      strokes: strokes,
      sectionId: bar.sectionId,
      barIndex: bar.barIndex,
    ),
    frame: frame,
  );
}

// PURPOSE: The CONTROL for [measureBeatRun]: the same beat's run engraved the way the page drew it
//          BEFORE the cell was widened — one 18-pixel column per beat, a 20.8-pixel stride, and the
//          second note therefore past its own column's right edge. It exists so that the repair is a
//          difference between two numbers rather than a claim, and so that a future reader can see
//          what the defect WAS without reconstructing it.
// INPUTS: tag — the run's name; melody — the same notes the repaired run used.
// OUTPUTS: The same `probe.run.*` lines, from a bar whose cells are the old width.
// KEYWORDS: control, old-cell, 18, before-the-fix, defect-reproduction
void measureOldCellRun({required String tag, required List<BeatNote> melody}) {
  final LayoutStyle style = appStyle();
  final Bar bar = Bar(melody: melody);
  final double space = style.melodyStaffSpace;
  final double cell = style.minCellWidth;
  const int beats = 4;
  const double left = 100;
  const double middle = 260;
  final List<double> cellX = <double>[
    for (int beat = 0; beat < beats; beat++) style.barPadding + beat * cell,
  ];
  final double barWidth = 2 * style.barPadding + beats * cell;
  final PlacedMelodyStaff staff = placeMelodyStaff(
    bar: bar,
    left: left,
    width: barWidth,
    staffMiddleLineY: middle,
    staffSpace: space,
    clef: 'treble',
    cellX: cellX,
  );
  final MelodyStaffFrame frame = MelodyStaffFrame(
    middleLineY: middle,
    staffSpace: space,
    // The staff's own ledger range, generous enough that the place gate cannot be what refuses a
    // head: this run is about the COLUMN, and a second refusal reason would blur the number.
    headTop: middle - 10 * space,
    headBottom: middle + 10 * space,
    beatColumns: <MelodyBeatColumn>[
      for (int beat = 0; beat < beats; beat++)
        MelodyBeatColumn(
          beat: beat,
          left: left + cellX[beat],
          right: left + cellX[beat] + cell,
        ),
    ],
    clef: 'treble',
  );
  final List<PageInkStroke> ink = <PageInkStroke>[];
  int index = 0;
  for (final MelodyGlyph glyph in staff.glyphs) {
    final double glyphNib = glyph.kind == MelodyGlyphKind.beam
        ? traceNib * 3
        : traceNib;
    final List<LayoutOffset> points = traceGlyph(
      glyph,
      pen: glyphNib,
      pageOrigin: LayoutOffset.zero,
    );
    if (points.isEmpty) {
      continue;
    }
    ink.add(PageInkStroke(id: 'old-${index++}', points: points, nib: glyphNib));
  }
  stdout.writeln(
    'probe.run tag=$tag notes=${melody.length} cell=${f(cell)} '
    'stride=${f(const MelodyMetrics().stepOffset * space)} '
    'head=${f(const MelodyMetrics().noteheadWidth * space)} bars_on_page=1',
  );
  for (int beat = 0; beat < beats; beat++) {
    stdout.writeln(
      'probe.run.cell beat=$beat '
      'x=[${f(left + cellX[beat])},${f(left + cellX[beat] + cell)}] '
      'w=${f(cell)}',
    );
  }
  reportRun(
    tag: tag,
    melody: melody,
    glyphs: staff.glyphs,
    ink: ink,
    frame: frame,
  );
}

// PURPOSE: Measure the ONE exposure the place gate cannot close: a chord symbol written BELOW the
//          bar, i.e. inside the band the melody staff occupies.
//
//          WHY IT NEEDS MEASURING RATHER THAN REASONING. Shape alone does not separate the owner's
//          chord symbols from noteheads — twelve of his seventeen blobs pass every shape gate, which
//          the last section of this probe already prints. What refuses them is PLACE: their centres
//          are in the chord row, above the bar's bottom edge. A symbol written BELOW that edge moves
//          into the window the staff reserves, and then nothing but the shape gates stands between
//          his handwriting and a note nobody wrote. This function moves his real ink there and
//          counts what comes out, so the exposure is a number rather than a fear.
// INPUTS: chartPath — his `.chart`, whose chord symbols are the ink that is moved.
// OUTPUTS: `probe.owner-below.*`: per bar, how many heads the reader reports when the bar's ink is
//          shifted down onto the staff, and the staff steps they land on. Every head printed here is
//          a chord symbol that would become a note if he wrote it below the bar instead of above it.
// KEYWORDS: place-gate, exposure, chord-symbol, below-the-bar, measured-limit, no-gate-can-close
void readOwnerInkBelowBar(String chartPath) {
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
  int heads = 0;
  int blobs = 0;
  for (final PageLayout page in pages) {
    final Map<String, MelodyStaffFrame> frames = melodyFramesOfPage(page);
    for (final PlacedBar bar in page.bars) {
      final MelodyStaffFrame? frame =
          frames['${bar.sectionId}\u0000${bar.barIndex}'];
      if (frame == null) {
        continue;
      }
      final List<PageInkStroke> ink = melodyInkOfBar(
        page: page,
        strokes: document.strokes,
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
      );
      if (ink.isEmpty) {
        continue;
      }
      // The ink is moved DOWN onto the staff's middle line, keeping its own shape: this is exactly
      // the position of a symbol the musician wrote inside the staff band instead of above it.
      double top = double.infinity;
      double bottom = double.negativeInfinity;
      for (final PageInkStroke stroke in ink) {
        for (final LayoutOffset point in stroke.points) {
          top = math.min(top, point.y);
          bottom = math.max(bottom, point.y);
        }
      }
      final double dy = frame.middleLineY - (top + bottom) / 2;
      final List<PageInkStroke> moved = <PageInkStroke>[
        for (final PageInkStroke stroke in ink)
          PageInkStroke(
            id: stroke.id,
            points: <LayoutOffset>[
              for (final LayoutOffset point in stroke.points)
                LayoutOffset(point.x, point.y + dy),
            ],
            nib: stroke.nib,
          ),
      ];
      final MelodyNoteReading reading = const MelodyNoteReader().read(
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
        ink: moved,
        frame: frame,
      );
      heads += reading.heads.length;
      blobs += reading.blobsConsidered;
      if (reading.heads.isEmpty && reading.refusals.isEmpty) {
        continue;
      }
      stdout.writeln(
        'probe.owner-below.bar bar=${bar.barIndex} strokes=${ink.length} '
        'blobs=${reading.blobsConsidered} heads=${reading.heads.length} '
        'refused=${reading.refusals.length} '
        'steps=${reading.heads.map((MelodyNoteHead head) => head.step).join(',')}',
      );
      for (final MelodyNoteHead head in reading.heads) {
        stdout.writeln(
          'probe.owner-below.head bar=${bar.barIndex} ${head.pitch} '
          'beat=${head.beat}.${head.orderInBeat} step=${head.step} '
          'w=${f(head.widthFraction)} h=${f(head.bandFraction)}',
        );
      }
    }
  }
  stdout.writeln('probe.owner-below.total blobs=$blobs heads=$heads');
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

  // PART 4b: THE SAME INK WRITTEN BELOW THE BAR, which is the one exposure the place gate cannot
  // close. Numbers, not a fear: see the function's own note.
  readOwnerInkBelowBar(chartPath);

  // PART 5: ONE BEAT, TWO NOTES — where the engraver's stride and the cell's width disagree. The
  // engraver draws a beat's k-th note at `k * 1.6` staff spaces, which is 20.8 pixels at the
  // application's space of 13, while a cell is 18: the second note is drawn 10.6 pixels into the
  // NEXT beat's column and the reader reports it there, correctly, because a head is read at the
  // place it was drawn. THE WIDENING WAS BUILT AND THEN REVERTED, and this run records WHY it was
  // ever proposed: with the cell at 18 the same two notes read as two beats and one of them is a
  // note nobody wrote on that beat. The owner removed the quantised grid as a class, so the fix is
  // no longer a wider cell — see A79 in `docs/sdd.md`.
  measureBeatRun(
    tag: 'one-beat-two-notes',
    melody: <BeatNote>[
      probeNote(NoteLetter.c, 5, beat: 0, step: 0),
      probeNote(NoteLetter.e, 5, beat: 0, step: 1),
    ],
  );
  // AND THE SAME RUN AT THE OLD 18-PIXEL CELL, built by hand, as the explicit control: it is the
  // fixture a musician's own ink is NOT — this is the engraving's own round trip, and it is where the
  // defect is measured.
  measureOldCellRun(
    tag: 'one-beat-two-notes-old-cell',
    melody: <BeatNote>[
      probeNote(NoteLetter.c, 5, beat: 0, step: 0),
      probeNote(NoteLetter.e, 5, beat: 0, step: 1),
    ],
  );

  // PART 6: A BEAMED PAIR, which the reader's own author named and did not measure. A beam is ink
  // that JOINS two heads at different heights, and the suspicion is that the joined component's rows
  // either refuse the pair (no taper) or average the two heights into a pitch nobody wrote. The
  // fixture is two EIGHTHS in one beat at different heights, which is exactly what the engraver
  // beams, and the two are also measured at the OLD cell so the height difference is not the only
  // variable.
  measureBeatRun(
    tag: 'beamed-pair',
    melody: <BeatNote>[
      probeNote(NoteLetter.e, 4, beat: 0, step: 0, base: NoteBase.eighth),
      probeNote(NoteLetter.c, 5, beat: 0, step: 1, base: NoteBase.eighth),
    ],
  );
  measureBeatRun(
    tag: 'beamed-pair-pen',
    melody: <BeatNote>[
      probeNote(NoteLetter.e, 4, beat: 0, step: 0, base: NoteBase.eighth),
      probeNote(NoteLetter.c, 5, beat: 0, step: 1, base: NoteBase.eighth),
    ],
    degraded: true,
  );
  // A beamed pair on the SAME pitch, so that a failure can be attributed: if this one reads and the
  // pair above does not, the cause is the height difference and not the beam.
  measureBeatRun(
    tag: 'beamed-pair-level',
    melody: <BeatNote>[
      probeNote(NoteLetter.b, 4, beat: 0, step: 0, base: NoteBase.eighth),
      probeNote(NoteLetter.b, 4, beat: 0, step: 1, base: NoteBase.eighth),
    ],
  );
}
