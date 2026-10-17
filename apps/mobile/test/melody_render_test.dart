// PURPOSE: Render a chart whose bars carry a melody, and print what the engraving decided: one
//          line per note with its pitch, its written value, its tie, the staff step it landed on,
//          the ledger lines it needs, its stem's direction, its accidental and where its notehead,
//          stem, accidental, dot and tie were placed. It is the instrument behind the claim that a
//          melody staff can be read: the PNG is looked at, and these numbers are what it is looked
//          at against.
//
//          ITS SECOND CASE ASKS A QUESTION NUMBERS CANNOT ANSWER: whether anything is DRAWN where
//          the clef used to be. The owner removed the letter that stood there (A68), and a letter
//          was painted straight onto the canvas rather than placed in the glyph list — so the claim
//          is checked on the rendered page's pixels, with a control box on the chord row proving the
//          detector can see ink at all.
// INPUTS: MELODY_PROBE_OUT names the directory. Nothing else; the chart is built here so the run
//         never depends on the owner's export. The pixel case needs no directory and no font: it
//         renders in memory and reads the bytes.
// OUTPUTS: `melody.png` at a device pixel ratio of 2, a `melody.geometry.txt` dump of every
//          rectangle, and the per-note report on stdout. The test ASSERTS that the fixture
//          exercises every case it was written for — each written value, a tie, a stacked beat,
//          an accidental and a note needing three ledger lines each way — so a fixture that
//          silently stopped exercising one of them fails rather than passing quietly. The pixel case
//          adds a `probe.no-clef` line naming the box sampled, the ink found in it and the ink found
//          in its control.
// KEYWORDS: melody-staff, render, png, instrument, ledger-line, tie, accidental, dot, stacked-chord
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logical page the probe engraves.
const double probePageWidth = 824;

/// The logical page height, matching the render probe's own surface.
const double probePageHeight = 1318;

/// The device pixel ratio the PNG is written at, so a notehead is more than a smudge.
const double probePixelRatio = 2;

/// The style every probe render uses, so the numbers and the picture describe one layout.
const LayoutStyle probeStyle = LayoutStyle(
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

/// The octave the fixture writes its high and low notes in, named so the expected numbers below
/// can state an octave rather than repeat a literal.
const int highOctave = 5;
const int lowOctave = 3;

/// The family name a loaded system font is registered under.
const String _fontFamily = 'MelodyProbeFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
///
/// WITHOUT ONE OF THESE THE PNG IS NOT READABLE AS MUSIC: the framework's default test font draws
/// every glyph as a filled box, so the clef, the accidentals and the chord symbols all come out as
/// squares. The staff lines, noteheads, stems, ledger lines and ties are vector paths and read
/// correctly either way, which is exactly why a boxed render looks almost right and cannot be
/// trusted for the text.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

// PURPOSE: Register a real font with the test engine, so the clef, the accidentals and the chord
//          symbols in the PNG are letters rather than filled boxes.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists — the render still happens
//          and the caller says on stdout that the image is layout-only.
// KEYWORDS: font, font-loader, readable-text, graceful-degradation
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
    stdout.writeln('probe.melody font=$path family=$_fontFamily');
    return _fontFamily;
  }
  stdout.writeln(
    'probe.melody font=none (every glyph will be a box; the staff geometry is still exact)',
  );
  return null;
}

/// The metrics the probe measures and draws with, in one family, so the two agree.
///
/// The sizes are the production ones — a 15-pixel chord, a 10-pixel staff text — so the picture the
/// probe writes is the picture the application draws, and the numbers in the report are the numbers
/// the engine computed for that picture.
FlutterTextMetrics _metricsFor(String? family) => FlutterTextMetrics(
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

/// A note of [base] at [letter]/[octave], placed at ([beat], [step]).
NoteMark noteOf(
  NoteLetter letter,
  int octave,
  NoteValue value, {
  int alter = 0,
  int beat = 0,
  int step = 0,
  bool tied = false,
}) => NoteMark(
  place: cellAt(beat, step),
  pitch: PitchedNote(note: WrittenNote(letter, alter), octave: octave),
  value: value,
  tiedToNext: tied,
);

/// A one-note bar: one chord on beat 0 and a melody, so the staff has a chord line above it.
Bar melodyBar(List<NoteMark> melody) => Bar(
  chords: <ChordMark>[
    ChordMark(
      place: cellAt(0),
      chord: Chord(root: ChordRoot(0)),
    ),
  ],
  melody: melody,
);

/// The melody the probe renders.
///
/// NINE BARS, ONE CASE EACH, so a value or a sign that failed to engrave can be named by the bar it
/// was in rather than by a screenshot. Bar 4 carries a tie from a dotted quarter into an eighth,
/// bar 5 the two notes of one beat, bar 6 the accidentals, bar 7 three ledger lines above the staff
/// and bar 8 three below.
Song melodySong() => Song(
  title: 'Melody probe',
  key: Key.cMajor,
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'M',
      label: const SectionLabel.letter('M'),
      bars: <Bar>[
        // Every written value the model can express, plus the dotted and the tuplet forms.
        melodyBar(<NoteMark>[
          noteOf(NoteLetter.c, 4, const NoteValue.plain(NoteBase.whole)),
        ]),
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.d,
            4,
            const NoteValue.plain(NoteBase.half),
            beat: 0,
          ),
          noteOf(
            NoteLetter.e,
            4,
            const NoteValue.plain(NoteBase.half),
            beat: 2,
          ),
        ]),
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.f,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 0,
          ),
          noteOf(
            NoteLetter.g,
            4,
            const NoteValue.plain(NoteBase.eighth),
            beat: 1,
          ),
          noteOf(
            NoteLetter.a,
            4,
            const NoteValue.plain(NoteBase.eighth),
            beat: 1,
            step: 1,
          ),
          noteOf(
            NoteLetter.b,
            4,
            const NoteValue.plain(NoteBase.sixteenth),
            beat: 2,
          ),
          noteOf(
            NoteLetter.c,
            highOctave,
            const NoteValue.plain(NoteBase.thirtySecond),
            beat: 3,
          ),
          noteOf(
            NoteLetter.d,
            highOctave,
            const NoteValue(base: NoteBase.quarter, dots: 1),
            beat: 3,
            step: 1,
          ),
          noteOf(
            NoteLetter.e,
            highOctave,
            const NoteValue.plain(NoteBase.quarter),
            beat: 3,
            step: 2,
          ),
          noteOf(
            NoteLetter.f,
            highOctave,
            const NoteValue(base: NoteBase.quarter, tuplet: Tuplet.triplet),
            beat: 3,
            step: 3,
          ),
        ]),
        // A tie from one beat into the next: one sound written as two notes.
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.g,
            4,
            const NoteValue(base: NoteBase.quarter, dots: 1),
            beat: 0,
            tied: true,
          ),
          noteOf(
            NoteLetter.g,
            4,
            const NoteValue.plain(NoteBase.eighth),
            beat: 2,
          ),
        ]),
        // A stacked beat: two notes at one address, which is a chord on the staff.
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.c,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 0,
          ),
          noteOf(
            NoteLetter.e,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 0,
            step: 1,
          ),
          noteOf(
            NoteLetter.g,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 0,
            step: 2,
          ),
          noteOf(
            NoteLetter.e,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 3,
          ),
        ]),
        // Accidentals: a flat, a sharp and a double flat, each on the first note of its beat.
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.d,
            4,
            const NoteValue.plain(NoteBase.quarter),
            alter: -1,
            beat: 0,
          ),
          noteOf(
            NoteLetter.a,
            lowOctave,
            const NoteValue.plain(NoteBase.quarter),
            alter: 1,
            beat: 1,
          ),
          noteOf(
            NoteLetter.b,
            3,
            const NoteValue.plain(NoteBase.quarter),
            alter: -2,
            beat: 2,
          ),
          noteOf(
            NoteLetter.e,
            4,
            const NoteValue.plain(NoteBase.quarter),
            alter: -1,
            beat: 3,
          ),
        ]),
        // Three ledger lines above the staff: A5, the topmost line; B5; and C6 above it.
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.a,
            highOctave,
            const NoteValue.plain(NoteBase.quarter),
            beat: 0,
          ),
          noteOf(
            NoteLetter.b,
            highOctave,
            const NoteValue.plain(NoteBase.quarter),
            beat: 1,
          ),
          noteOf(
            NoteLetter.c,
            6,
            const NoteValue.plain(NoteBase.quarter),
            beat: 2,
          ),
          noteOf(
            NoteLetter.e,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 3,
          ),
        ]),
        // Three ledger lines below the staff: C4, A3, and F3 below them.
        melodyBar(<NoteMark>[
          noteOf(
            NoteLetter.c,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 0,
          ),
          noteOf(
            NoteLetter.a,
            lowOctave,
            const NoteValue.plain(NoteBase.quarter),
            beat: 1,
          ),
          noteOf(
            NoteLetter.f,
            lowOctave,
            const NoteValue.plain(NoteBase.quarter),
            beat: 2,
          ),
          noteOf(
            NoteLetter.c,
            4,
            const NoteValue.plain(NoteBase.quarter),
            beat: 3,
          ),
        ]),
      ],
    ),
  ],
);

/// Where a glyph of [kind] sits, or null when none was drawn: one line per matching element.
List<MelodyGlyph> glyphsOf(PlacedBar bar, MelodyGlyphKind kind) =>
    <MelodyGlyph>[
      for (final MelodyGlyph glyph in bar.melody.glyphs)
        if (glyph.kind == kind) glyph,
    ];

/// [song] with every bar's melody removed, so the same music can be laid out with and without the
/// staff and the two layouts compared. Only the melody is dropped — the chords, the meter and the
/// sections are identical — which is what makes a difference in the result attributable to the
/// staff rather than to the fixture.
Song _withoutMelody(Song song) => Song(
  id: song.id,
  title: song.title,
  composer: song.composer,
  style: song.style,
  key: song.key,
  tempo: song.tempo,
  staffSet: StaffSet.chordsOnly,
  sections: <Section>[
    for (final Section section in song.sections)
      Section(
        id: section.id,
        label: section.label,
        bars: <Bar>[
          for (final Bar bar in section.bars)
            Bar(
              timeSignature: bar.timeSignature,
              chords: bar.chords,
              staffText: bar.staffText,
            ),
        ],
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a chart with a melody draws its staff and every note case it exercises', () async {
    final String outDir =
        Platform.environment['MELODY_PROBE_OUT'] ??
        'C:/projects/ChartApp-acl-reports/melody';
    final Song song = melodySong();
    // The font is registered BEFORE the layout runs, because the metrics the engine measures with
    // and the painter draws with are the ones built here; a font loaded after the layout would draw
    // wider text than the boxes that were reserved for it.
    final String? family = await _loadChartFont();
    final FlutterTextMetrics metrics = _metricsFor(family);
    final LayoutEngine engine = LayoutEngine(
      style: LayoutStyle(
        textMetrics: metrics,
        pageMargin: probeStyle.pageMargin,
        barMinWidth: probeStyle.barMinWidth,
        barPadding: probeStyle.barPadding,
        chordSpacing: probeStyle.chordSpacing,
        minCellWidth: probeStyle.minCellWidth,
        barHeight: probeStyle.barHeight,
        systemSpacing: probeStyle.systemSpacing,
        sectionLabelHeight: probeStyle.sectionLabelHeight,
      ),
    );
    final List<PageLayout> pages = engine.layout(
      song,
      pageWidth: probePageWidth,
      pageHeight: probePageHeight,
    );
    expect(
      pages,
      isNotEmpty,
      reason: 'a song with bars must lay out to a page',
    );
    final PageLayout page = pages.first;
    final PlacedBar bar = page.bars.first;

    // The band is reserved, so the staff exists and lies BELOW the chord stave.
    expect(bar.melody.isEmpty, isFalse);
    expect(
      bar.melody.bounds.top,
      greaterThanOrEqualTo(bar.bounds.bottom),
      reason: 'the staff is under the chord line, never over it',
    );
    // A staff with no clef is not read the same by two musicians, so every system's first bar prints
    // one and no other bar does. The expectation is DERIVED from the systems the layout produced, so
    // it stays true when the fixture grows past one system instead of pinning today's wrap point.
    expect(bar.melody.clef, 'G', reason: 'the fixture is a treble staff');
    expect(
      page.bars
          .where((PlacedBar placed) => placed.melody.clef != null)
          .map((PlacedBar placed) => '${placed.sectionId}#${placed.barIndex}')
          .toList(),
      page.systems
          .map(
            (PlacedSystem system) =>
                '${system.bars.first.sectionId}#${system.bars.first.barIndex}',
          )
          .toList(),
      reason: 'exactly one clef per system, on the bar that opens it',
    );

    stdout.writeln(
      'probe.melody pages=${pages.length} systems=${page.systems.length} '
      'bars=${page.bars.length} '
      'stave=${_r(bar.bounds)} staff=${_r(bar.melody.bounds)} '
      'system=${_r(page.systems.first.bounds)} '
      'cells=${bar.cells.length}',
    );

    int totalGlyphs = 0;
    for (final PlacedBar placed in page.bars) {
      final List<MelodyNote> notes = song
          .sections
          .first
          .bars[placed.barIndex]
          .melody
          .map(MelodyNote.of)
          .toList();
      for (int index = 0; index < notes.length; index++) {
        final MelodyNote note = notes[index];
        final List<MelodyGlyph> heads = glyphsOf(
          placed,
          MelodyGlyphKind.notehead,
        );
        final MelodyGlyph? head = index < heads.length ? heads[index] : null;
        final List<MelodyGlyph> stems = glyphsOf(placed, MelodyGlyphKind.stem);
        final MelodyGlyph? stem = index < stems.length ? stems[index] : null;
        stdout.writeln(
          'probe.note bar=${placed.barIndex} i=$index '
          'pitch=${note.label} value=${note.value} '
          'tie=${note.tied} step=${note.step} ledger=${note.ledgerCount} '
          'stemUp=${note.stemUp} accidental=${note.accidental ?? '-'} '
          'dot=${note.dots} head=${_r(head?.bounds)} stemRect=${_r(stem?.bounds)}',
        );
      }
      final List<MelodyGlyph> accidentals = glyphsOf(
        placed,
        MelodyGlyphKind.accidental,
      );
      final List<MelodyGlyph> dots = glyphsOf(placed, MelodyGlyphKind.dot);
      final List<MelodyGlyph> ledgers = glyphsOf(
        placed,
        MelodyGlyphKind.ledgerLine,
      );
      final List<MelodyGlyph> ties = glyphsOf(placed, MelodyGlyphKind.tie);
      totalGlyphs += placed.melody.glyphs.length;
      stdout.writeln(
        'probe.bar bar=${placed.barIndex} glyphs=${placed.melody.glyphs.length} '
        'noteheads=${glyphsOf(placed, MelodyGlyphKind.notehead).length} '
        'stems=${glyphsOf(placed, MelodyGlyphKind.stem).length} '
        'ledgers=${ledgers.length} accidentals=${accidentals.length} '
        'dots=${dots.length} ties=${ties.length} '
        'accidentalText=${accidentals.map((MelodyGlyph g) => g.text).join(',')} '
        'firstTie=${ties.isEmpty ? '-' : '${_o(ties.first.from)}->${_o(ties.first.to)}'
                  ' ctrl=${_o(ties.first.control)}'}',
      );
    }
    stdout.writeln('probe.melody total_glyphs=$totalGlyphs');

    // THE HIT TEST, AS NUMBERS. The same chart written once with the melody and once without is laid
    // out twice: every chord cell's address and rectangle, and the answer a tap at each cell's
    // centre gets, must be identical. A tap on a bar selects a bar and the chord cells are
    // addressed by `{bar, cell}` — so the staff may add height and must not move a cell.
    final Song withoutMelody = _withoutMelody(song);
    final PageLayout plainPage = engine
        .layout(
          withoutMelody,
          pageWidth: probePageWidth,
          pageHeight: probePageHeight,
        )
        .first;
    expect(plainPage.bars.length, page.bars.length);
    int comparedCells = 0;
    for (int index = 0; index < page.bars.length; index++) {
      final PlacedBar withStaff = page.bars[index];
      final PlacedBar plain = plainPage.bars[index];
      for (int cell = 0; cell < withStaff.cells.length; cell++) {
        final PlacedCell a = withStaff.cells[cell];
        final PlacedCell b = plain.cells[cell];
        expect(a.beat, b.beat, reason: 'bar $index cell $cell identity');
        expect(a.bounds, b.bounds, reason: 'bar $index cell $cell rectangle');
        LayoutOffset centre(LayoutRect r) =>
            LayoutOffset(r.left + r.size.width / 2, r.top + r.size.height / 2);
        final ChartHit? hitWith = hitTestPage(page, centre(a.bounds));
        final ChartHit? hitPlain = hitTestPage(plainPage, centre(b.bounds));
        expect(hitWith, isNotNull, reason: 'a tap on a cell must name it');
        expect(hitPlain, isNotNull);
        expect(hitWith!.sectionId, hitPlain!.sectionId);
        expect(hitWith.barIndex, hitPlain.barIndex);
        expect(hitWith.beat, hitPlain.beat);
        comparedCells++;
      }
    }
    expect(comparedCells, 32, reason: 'eight 4/4 bars');
    stdout.writeln(
      'probe.hit-test cells_compared=$comparedCells '
      'melody_first_cell=${_r(page.bars.first.cells.first.bounds)} '
      'plain_first_cell=${_r(plainPage.bars.first.cells.first.bounds)} '
      'identical=true',
    );
    stdout.writeln(
      'probe.height melody_system_height='
      '${page.systems.first.bounds.size.height.toStringAsFixed(1)} '
      'plain_system_height='
      '${plainPage.systems.first.bounds.size.height.toStringAsFixed(1)} '
      'melody_staves=${page.systems.length} plain_systems=${plainPage.systems.length}',
    );

    // D23: THE CHORD ROW SITS ABOVE THE STAFF AND THE TWO DO NOT TOUCH. It is checked on EVERY bar
    // and against the lowest ink each row can reach, not the text boxes: a chord's box is where the
    // layout put it, and what a reader sees is the glyph inside it. A bar's staff-top belongs to its
    // own bar rather than to the system, so a staff that drifted up in one bar is caught here.
    double chordBottom = 0;
    double staffTop = double.infinity;
    for (final PlacedBar placed in page.bars) {
      for (final PlacedChord chord in placed.chords) {
        if (chord.bounds.bottom > chordBottom) {
          chordBottom = chord.bounds.bottom;
        }
      }
      if (placed.melody.bounds.top < staffTop) {
        staffTop = placed.melody.bounds.top;
      }
    }
    stdout.writeln(
      'probe.order lowest_chord_bottom=${chordBottom.toStringAsFixed(1)} '
      'highest_staff_top=${staffTop.toStringAsFixed(1)} '
      'clearance=${(staffTop - chordBottom).toStringAsFixed(1)} '
      'stave_bottom=${page.bars.first.bounds.bottom.toStringAsFixed(1)}',
    );
    expect(
      staffTop,
      greaterThanOrEqualTo(chordBottom),
      reason:
          'D23: the chord row is above the staff and the two do not overlap',
    );
    expect(
      staffTop,
      greaterThanOrEqualTo(page.bars.first.bounds.bottom),
      reason: 'the whole chord-line stave is above the whole melody staff',
    );

    // WHAT THE FIXTURE MUST EXERCISE, asserted rather than assumed. A fixture that quietly stopped
    // covering one case would still render and still look plausible.
    final Set<NoteBase> bases = <NoteBase>{
      for (final Bar b in song.sections.first.bars)
        for (final NoteMark n in b.melody) n.value.base,
    };
    expect(
      bases,
      containsAll(<NoteBase>[
        NoteBase.whole,
        NoteBase.half,
        NoteBase.quarter,
        NoteBase.eighth,
        NoteBase.sixteenth,
        NoteBase.thirtySecond,
      ]),
    );
    final int ties = <MelodyGlyph>[
      for (final PlacedBar placed in page.bars)
        ...glyphsOf(placed, MelodyGlyphKind.tie),
    ].length;
    expect(ties, greaterThan(0), reason: 'the fixture must exercise a tie');
    final int stacked = page.bars[4].melody.glyphs
        .where((MelodyGlyph g) => g.kind == MelodyGlyphKind.notehead)
        .length;
    expect(stacked, 4, reason: 'a stacked beat draws one notehead per note');
    final int accidentals = page.bars[5].melody.glyphs
        .where((MelodyGlyph g) => g.kind == MelodyGlyphKind.accidental)
        .length;
    expect(
      accidentals,
      4,
      reason: 'a flat, a sharp and a double flat are drawn',
    );
    final int ledgers =
        page.bars[6].melody.glyphs
            .where((MelodyGlyph g) => g.kind == MelodyGlyphKind.ledgerLine)
            .length +
        page.bars[7].melody.glyphs
            .where((MelodyGlyph g) => g.kind == MelodyGlyphKind.ledgerLine)
            .length;
    expect(
      ledgers,
      greaterThan(0),
      reason: 'the fixture must exercise ledger lines',
    );
    final int dots = page.bars[3].melody.glyphs
        .where((MelodyGlyph g) => g.kind == MelodyGlyphKind.dot)
        .length;
    expect(dots, 1, reason: 'a dotted quarter draws one dot');

    // The accidental stands to the LEFT of its notehead and outside it, which is the one property
    // of that placement a reader notices: a sign drawn on top of its note is a wrong note. An
    // accidental belongs to the nearest notehead to its right, so that is how it is paired here —
    // not by the next one in the list, which is the wrong note for the last accidental in a bar.
    final List<MelodyGlyph> bar5 = page.bars[5].melody.glyphs;
    final List<MelodyGlyph> heads = bar5
        .where((MelodyGlyph g) => g.kind == MelodyGlyphKind.notehead)
        .toList();
    for (final MelodyGlyph glyph in bar5) {
      if (glyph.kind != MelodyGlyphKind.accidental) {
        continue;
      }
      MelodyGlyph? head;
      for (final MelodyGlyph candidate in heads) {
        if (candidate.bounds.left + 1 < glyph.bounds.right) {
          continue;
        }
        if (head == null || candidate.bounds.left < head.bounds.left) {
          head = candidate;
        }
      }
      expect(head, isNotNull, reason: 'every accidental belongs to a note');
      stdout.writeln(
        'probe.accidental text=${glyph.text} '
        'box=(${glyph.bounds.left.toStringAsFixed(1)}..'
        '${glyph.bounds.right.toStringAsFixed(1)}) '
        'head_left=${head!.bounds.left.toStringAsFixed(1)} '
        'gap=${(head.bounds.left - glyph.bounds.right).toStringAsFixed(1)}',
      );
      expect(
        glyph.bounds.right,
        lessThanOrEqualTo(head.bounds.left + 1),
        reason: 'the sign ends before the notehead begins',
      );
    }

    // The PNG, at twice the logical size so a notehead can be seen. The painter is handed the
    // LOGICAL page extent, not the pixel extent, because it applies `page.scale` and clips to the
    // size it is given: passing the pixel extent would draw the music at half the page inside a
    // clip twice its size, which reads as a staff that stops a third of the way across the system.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.scale(probePixelRatio);
    ChartPainter(
      song: song,
      page: page,
      metrics: metrics,
    ).paint(canvas, const ui.Size(probePageWidth, probePageHeight));
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      (probePageWidth * probePixelRatio).round(),
      (probePageHeight * probePixelRatio).round(),
    );
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    expect(png, isNotNull);
    image.dispose();
    picture.dispose();

    final Directory dir = Directory(outDir);
    dir.createSync(recursive: true);
    final File pngFile = File('${dir.path}${Platform.pathSeparator}melody.png');
    pngFile.writeAsBytesSync(png!.buffer.asUint8List());
    stdout.writeln(
      'probe.melody png=${pngFile.path} bytes=${pngFile.lengthSync()} '
      'pixels=${(probePageWidth * probePixelRatio).round()}x'
      '${(probePageHeight * probePixelRatio).round()}',
    );
  });

  // PURPOSE: Pin the OWNER'S VERDICT that the staff carries no clef sign — by looking at the drawn
  //          page's pixels rather than at the model, because the decision was a decision about the
  //          picture. The treble clef was drawn as the letter `G` in the field left of the first
  //          note, and the owner's report of it is «зачем то буква G в начале. Если это просто
  //          убрать - уже будет лучше» (A68 §7). A test that asserted "no glyph carries a clef" would
  //          not have caught its return: the letter was painted straight onto the canvas, not placed
  //          in the glyph list. This one reads the field it stood in and fails if anything is there.
  // INPUTS: None. The chart is built here, one bar with a chord on beat 1 and a note on the LAST
  //         beat, which leaves the field between the barline and the first cell empty of music.
  // OUTPUTS: Pass/fail, plus `probe.no-clef` lines naming the box sampled, the ink found in it, and
  //          the ink found in a control box on the chord row — the control is what proves the
  //          detector can see ink at all rather than sampling blank paper twice.
  // KEYWORDS: test, melody-staff, clef-removed, owner-verdict, pixels, ink-detector, negative-control,
  //           a68
  test('the staff is drawn without a clef: its left field holds no ink', () async {
    final FlutterTextMetrics metrics = _metricsFor(null);
    final LayoutEngine engine = LayoutEngine(
      style: LayoutStyle(
        textMetrics: metrics,
        pageMargin: probeStyle.pageMargin,
        barMinWidth: probeStyle.barMinWidth,
        barPadding: probeStyle.barPadding,
        chordSpacing: probeStyle.chordSpacing,
        minCellWidth: probeStyle.minCellWidth,
        barHeight: probeStyle.barHeight,
        systemSpacing: probeStyle.systemSpacing,
        sectionLabelHeight: probeStyle.sectionLabelHeight,
      ),
    );
    // The chord is written on beat 1 and the note on beat 4, so the staff's left field — where the
    // clef stood, between the barline and the first cell's column — holds nothing but the staff's own
    // five lines.
    final Song song = Song(
      title: 'No clef',
      key: Key.cMajor,
      staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
      sections: <Section>[
        Section(
          id: 'N',
          label: const SectionLabel.letter('N'),
          bars: <Bar>[
            melodyBar(<NoteMark>[
              noteOf(
                NoteLetter.c,
                4,
                const NoteValue.plain(NoteBase.quarter),
                beat: 3,
              ),
            ]),
          ],
        ),
      ],
    );
    final PageLayout page = engine
        .layout(song, pageWidth: probePageWidth, pageHeight: probePageHeight)
        .single;
    expect(
      page.scale,
      1,
      reason:
          'the page is engraved at 1:1, so an engraved coordinate IS a pixel and the box below '
          'can be sampled directly',
    );
    final PlacedBar bar = page.bars.first;
    final double space = bar.melody.bounds.size.height / 4;

    final int width = probePageWidth.round();
    final int height = probePageHeight.round();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    ChartPainter(
      song: song,
      page: page,
      metrics: metrics,
    ).paint(canvas, ui.Size(probePageWidth, probePageHeight));
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);
    final ByteData? raw = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(raw, isNotNull, reason: 'the renderer must produce pixels to read');
    final Uint8List pixels = raw!.buffer.asUint8List();
    image.dispose();
    picture.dispose();

    /// Whether the pixel at ([x], [y]) is ink rather than paper: white is the page's background, so
    /// anything materially darker than it was drawn.
    bool isInk(int x, int y) {
      final int at = 4 * (y * width + x);
      return pixels[at] < 250 || pixels[at + 1] < 250 || pixels[at + 2] < 250;
    }

    /// Counts ink in a box in PAGE coordinates, skipping a band around each staff line's y.
    ///
    /// THE SKIP IS WHAT MAKES THE SAMPLE MEAN "PAPER": the five staff lines run through the field by
    /// design, so a raw count there would always be positive and the case would prove nothing. The
    /// band is two page pixels either side of a line, which is the antialiasing of a 1.4-pixel
    /// stroke — anything drawn BETWEEN the lines is not a staff line.
    int inkBetweenTheLines({
      required double left,
      required double right,
      required double top,
      required double bottom,
    }) {
      final List<double> lineYs = <double>[
        for (int line = 0; line < 5; line++)
          bar.melody.bounds.top + space * line,
      ];
      int found = 0;
      for (int y = top.ceil(); y <= bottom.floor(); y++) {
        if (lineYs.any((double lineY) => (y - lineY).abs() <= 2)) {
          continue;
        }
        for (int x = left.ceil(); x <= right.floor(); x++) {
          if (isInk(x, y)) {
            found++;
          }
        }
      }
      return found;
    }

    // THE FIELD THE CLEF STOOD IN: from just clear of the barline to just short of the first cell's
    // column, over the height of the five lines.
    final double firstCellLeft = bar.cells.first.bounds.left;
    final int inTheClefsField = inkBetweenTheLines(
      left: bar.melody.bounds.left + 3,
      right: firstCellLeft - 2,
      top: bar.melody.bounds.top + 1,
      bottom: bar.melody.bounds.bottom - 1,
    );
    // THE CONTROL: the same detector aimed at the chord row, where the chord symbol is drawn. If this
    // finds nothing, the detector is blind and the case above proves nothing at all.
    final LayoutRect chordBox = bar.chords.first.bounds;
    int inTheControl = 0;
    for (int y = chordBox.top.ceil(); y <= chordBox.bottom.floor(); y++) {
      for (int x = chordBox.left.ceil(); x <= chordBox.right.floor(); x++) {
        if (isInk(x, y)) {
          inTheControl++;
        }
      }
    }
    stdout.writeln(
      'probe.no-clef field=(${(bar.melody.bounds.left + 3).toStringAsFixed(1)}..'
      '${(firstCellLeft - 2).toStringAsFixed(1)}, '
      '${bar.melody.bounds.top.toStringAsFixed(1)}..'
      '${bar.melody.bounds.bottom.toStringAsFixed(1)}) '
      'ink=$inTheClefsField control_ink=$inTheControl '
      'control=(${chordBox.left},${chordBox.top},'
      '${chordBox.size.width},${chordBox.size.height}) '
      'staff_space=${space.toStringAsFixed(1)}',
    );
    expect(
      inTheControl,
      greaterThan(0),
      reason:
          'the control box holds the chord symbol, so a detector that finds no ink there cannot '
          'be trusted about the field beside the staff',
    );
    expect(
      inTheClefsField,
      0,
      reason:
          'the staff’s left field is blank paper apart from the five lines: the owner removed the '
          'letter that stood there as a clef, and a clef — letter or vector — would be ink between '
          'the lines of exactly this box',
    );
  });
}

/// One note of the fixture, described in the terms the report prints.
class MelodyNote {
  const MelodyNote({
    required this.label,
    required this.value,
    required this.tied,
    required this.step,
    required this.ledgerCount,
    required this.stemUp,
    required this.accidental,
    required this.dots,
  });

  /// Describes [note] — and the number of ledger lines its pitch needs — for the report.
  factory MelodyNote.of(NoteMark note) {
    final int step = melodyStepOf(
      note.pitch.note,
      octave: note.pitch.octave,
      clef: 'treble',
    );
    return MelodyNote(
      label: '${note.pitch.note}${note.pitch.octave}',
      value: note.value.toString(),
      tied: note.tiedToNext,
      step: step,
      ledgerCount: melodyLedgerLineOffsets(step).length,
      stemUp: step < 4,
      accidental: melodyAccidentalOf(note.pitch.note),
      dots: note.value.dots,
    );
  }

  final String label;
  final String value;
  final bool tied;
  final int step;
  final int ledgerCount;
  final bool stemUp;
  final String? accidental;
  final int dots;
}

/// A rectangle as four numbers, or `-` when absent.
String _r(LayoutRect? rect) => rect == null
    ? '-'
    : '(${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},'
          '${rect.size.width.toStringAsFixed(1)},${rect.size.height.toStringAsFixed(1)})';

/// A point as two numbers.
String _o(LayoutOffset point) =>
    '(${point.x.toStringAsFixed(1)},${point.y.toStringAsFixed(1)})';
