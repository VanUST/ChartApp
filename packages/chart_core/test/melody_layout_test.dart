// PURPOSE: Pin what a melody staff costs a page, and prove the cost is bounded and reported rather
//          than discovered later. It answers three numbers the decision record owes the owner: how
//          much taller a system becomes, how many fewer systems fit a page, and what scale FIT has
//          to reach to put a melody chart on one page — together with the legibility floor it must
//          not cross.
// INPUTS: None. The chart is built here so the probe never depends on the owner's export.
// OUTPUTS: Pass/fail per claim, plus `melody.fit ...` lines on stdout naming every scale and system
//          count it measured.
// KEYWORDS: test, melody-staff, system-height, pagination, fit-to-page, legibility-floor, numbers
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The chart every claim below is measured on: one section, [bars] bars, one chord and one quarter
/// note per bar. A chord is `C` and a note is `G4`, which is inside the staff and needs no ledger
/// line, so the height the melody costs is the BAND and not a ledger line's excursion.
Song melodyChart(int bars) => Song(
  title: 'Melody pagination',
  key: Key.cMajor,
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < bars; index++)
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: cellAt(0),
                chord: Chord(root: ChordRoot(0)),
              ),
            ],
            melody: <NoteMark>[
              NoteMark(
                place: cellAt(0),
                pitch: const PitchedNote(
                  note: WrittenNote(NoteLetter.g, 0),
                  octave: 4,
                ),
                value: const NoteValue.plain(NoteBase.quarter),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// [chart] with every melody removed, for the same reason the render probe has one: the two layouts
/// differ only in the staff, so a difference is attributable to the staff.
Song withoutMelody(Song chart) => Song(
  title: chart.title,
  key: chart.key,
  staffSet: StaffSet.chordsOnly,
  sections: <Section>[
    for (final Section section in chart.sections)
      Section(
        id: section.id,
        label: section.label,
        bars: <Bar>[
          for (final Bar bar in section.bars)
            Bar(timeSignature: bar.timeSignature, chords: bar.chords),
        ],
      ),
  ],
);

void main() {
  const LayoutEngine engine = LayoutEngine();

  test('the melody band is what makes a system taller, and it is a constant', () {
    final Song withStaff = melodyChart(8);
    final Song plain = withoutMelody(withStaff);
    final List<PageLayout> staffPages = engine.layout(
      withStaff,
      pageWidth: 1200,
      pageHeight: 3000,
    );
    final List<PageLayout> plainPages = engine.layout(
      plain,
      pageWidth: 1200,
      pageHeight: 3000,
    );

    final double staffSystemHeight =
        staffPages.first.systems.first.bounds.size.height;
    final double plainSystemHeight =
        plainPages.first.systems.first.bounds.size.height;
    final PlacedBar staffBar = staffPages.first.bars.first;
    stdout.writeln(
      'melody.fit system_height=$staffSystemHeight '
      'without_staff=$plainSystemHeight '
      'delta=${staffSystemHeight - plainSystemHeight} '
      'staff_height=${staffBar.melody.bounds.size.height} '
      'stave_height=${staffBar.bounds.size.height} '
      'band=${const LayoutStyle().melodyBandHeight}',
    );
    expect(
      staffSystemHeight - plainSystemHeight,
      const LayoutStyle().melodyBandHeight,
      reason: 'the whole cost of the staff is its band',
    );
    // A system's height does not depend on which notes are on it: a tune that climbs and falls must
    // not make its systems different heights, or the columns would not line up.
    final Set<double> heights = <double>{
      for (final PageLayout page in staffPages)
        for (final PlacedSystem system in page.systems)
          system.bounds.size.height,
    };
    expect(heights.length, 1, reason: 'every system is the same height');
  });

  test('a melody staff costs pages, and the numbers say how many', () {
    final Song withStaff = melodyChart(80);
    final Song plain = withoutMelody(withStaff);
    // An 8.5-inch-tall sheet at 96 logical pixels per inch, which is the tablet's own scale.
    const double pageWidth = 816;
    const double pageHeight = 1056;
    final List<PageLayout> staffPages = engine.layout(
      withStaff,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
    final List<PageLayout> plainPages = engine.layout(
      plain,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
    stdout.writeln(
      'melody.fit page=816x1056 '
      'systems_on_page1_with_staff=${staffPages.first.systems.length} '
      'systems_on_page1_without=${plainPages.first.systems.length} '
      'pages_with_staff=${staffPages.length} pages_without=${plainPages.length} '
      'bars=${withStaff.writtenBarCount}',
    );
    // What the staff costs is PAGES: a taller system fits a page fewer times, so the same music
    // needs more of them. The claim is deliberately NOT "one fewer system on page one" — whether a
    // particular page loses a system depends on where the bars happen to break — so the measurement
    // is the page count, which is what the musician feels.
    expect(
      staffPages.first.systems.length,
      lessThanOrEqualTo(plainPages.first.systems.length),
    );
    expect(
      staffPages.length,
      greaterThan(plainPages.length),
      reason: 'the taller systems must push the chart onto more pages',
    );
    // Nothing is lost by the reflow: every written bar is still on a page exactly once.
    final List<String> addresses = <String>[
      for (final PageLayout page in staffPages)
        for (final PlacedBar bar in page.bars)
          '${bar.sectionId}#${bar.barIndex}',
    ];
    expect(addresses.length, withStaff.writtenBarCount);
    expect(addresses.toSet().length, withStaff.writtenBarCount);

    // And every bar on every page really carries a staff, so a page cannot be half engraved.
    for (final PageLayout page in staffPages) {
      for (final PlacedBar bar in page.bars) {
        expect(bar.melody.isEmpty, isFalse, reason: 'bar ${bar.barIndex}');
        expect(
          bar.melody.bounds.top,
          greaterThanOrEqualTo(bar.bounds.bottom),
          reason: 'D23: the staff is below the chord line',
        );
      }
    }
  });

  test('FIT reports a scale at or above the floor, or says it does not fit', () {
    // A surface small enough that FIT must genuinely shrink: at this size the same chart needs more
    // than one page at full size, so the outcome is a scale below 1 rather than a chart that already
    // fitted.
    final Song withStaff = melodyChart(40);
    final Song plain = withoutMelody(withStaff);
    const double pageWidth = 600;
    const double pageHeight = 800;
    final FitOutcome withStaffFit = engine.fitToPage(
      withStaff,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
    final FitOutcome plainFit = engine.fitToPage(
      plain,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
    stdout.writeln(
      'melody.fit fit_with_staff=${withStaffFit.fits} '
      'scale_with_staff=${withStaffFit.scale} '
      'systems_with_staff=${withStaffFit.page?.systems.length} '
      'fit_without=${plainFit.fits} scale_without=${plainFit.scale} '
      'systems_without=${plainFit.page?.systems.length} '
      'floor=${LayoutEngine.minLegibleScale}',
    );
    expect(withStaffFit.fits, isTrue);
    expect(
      withStaffFit.scale,
      lessThanOrEqualTo(plainFit.scale),
      reason: 'the staff cannot make a chart need LESS shrinking',
    );
    expect(
      withStaffFit.scale,
      greaterThanOrEqualTo(LayoutEngine.minLegibleScale),
    );
    expect(
      withStaffFit.scale < 1,
      isTrue,
      reason: 'a fitted page must actually be scaled, or it proves nothing',
    );
    // The page must land inside the surface it was fitted to: every system's bottom edge, times the
    // scale, is inside the surface because the page was engraved on one page of the enlarged virtual
    // surface. This is the arithmetic behind "a fitted page does not overflow".
    final PageLayout page = withStaffFit.page!;
    final double surfaceBottom = page.systems.last.bounds.bottom * page.scale;
    stdout.writeln(
      'melody.fit surface=${pageWidth}x$pageHeight '
      'engraved_page=${page.size} '
      'last_system_bottom=${page.systems.last.bounds.bottom.toStringAsFixed(2)} '
      'surface_bottom=${surfaceBottom.toStringAsFixed(2)} '
      'inside_surface=${surfaceBottom <= pageHeight}',
    );
    expect(surfaceBottom, lessThanOrEqualTo(pageHeight));

    // A surface so short that no scale can help: the answer must be the floor and no page, not a
    // page shrunk into illegibility.
    final FitOutcome impossible = engine.fitToPage(
      withStaff,
      pageWidth: 320,
      pageHeight: 294,
    );
    stdout.writeln(
      'melody.fit tiny=320x294 fits=${impossible.fits} '
      'scale=${impossible.scale} '
      'system_height_with_staff='
      '${engine.layout(withStaff, pageWidth: 320, pageHeight: 294).first.systems.first.bounds.size.height}',
    );
    expect(impossible.fits, isFalse);
    expect(impossible.scale, LayoutEngine.minLegibleScale);
    expect(impossible.page, isNull);
  });
}
