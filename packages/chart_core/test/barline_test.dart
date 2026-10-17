// PURPOSE: Hold the barline detector and the division it produces to the four claims the feature
//          stands on, so that each one is falsifiable rather than argued: a drawn division is found,
//          a tall narrow LETTER is not, a division is a stored structural unit that survives a save
//          and an undo exactly, and ink alone never becomes structure by itself.
//
//          THE FALSE-POSITIVE SIDE IS THE POINT. The owner's own page is five handwritten chord
//          symbols with no bars, and it contains the three marks that look most like a barline in a
//          musician's hand: the `(` of `(b9)`, the `7` and the `/` of `6/9`. Their measurements are
//          transcribed below from that file
//          (`C:\projects\ChartApp-acl-reports\omr-sample\untitled.chart`, strokes 7, 4 and 11 as
//          the codec numbered them) and each is asserted to be REFUSED. A detector that fires on
//          them is worse than no detector, because the musician would have to repair every one.
// INPUTS: None; every stroke is built here, so the file runs under `dart test` with no device.
// OUTPUTS: A passing run prints the test names; a failure names the gate that disagreed.
// KEYWORDS: barline, detector, false-positive, threshold, division, round-trip, undo-exact, d37,
//           handwriting, no-ml
import 'dart:convert';
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The chart's only section id, which [newChartSong] fixes.
const String _section = newChartFirstSectionId;

/// The row height the owner's tablet engravs a chord row at — the unit every threshold is a
/// fraction of, and the number his own ink was measured against in that sample (`barHeight: 52`).
const double _rowHeight = 52;

/// A chart of [bars] bars in C major, 4/4, one section labelled A.
Song _chart({int bars = 4}) => newChartSong(
  key: Key.cMajor,
  timeSignature: TimeSignature.fourFour,
  bars: bars,
);

/// The rectangle of a bar's chord row, in the anchor-local space of a stroke captured on it.
///
/// The origin is zero because a stroke's points are already anchor-local: the row it divides starts
/// at the anchor's own origin, which is what makes the height comparison the row's height and not
/// a page coordinate.
LayoutRect _row() => const LayoutRect(
  origin: LayoutOffset(0, 0),
  size: LayoutSize(88, _rowHeight),
);

/// The frame of a page that engraves one chord row and nothing else.
///
/// It is the shape a chords-only chart has, and it is built through the library's own
/// `BarlineFrame.chordRow` rather than by hand so that the tests below are held to the same rule the
/// application's page is: one row, one band, and the row's height as the page's one barline height.
BarlineFrame _frame() => BarlineFrame.chordRow(_row());

/// A straight stroke from ([x], [y0]) to ([x + lean], [y1]), with [samples] points between them.
///
/// Straight and hand-like in the one respect the detector measures: it travels downward without
/// doubling back, which is what a drawn division does and what a letter's bowl does not.
InkStroke _line({
  required String id,
  required double x,
  required double y0,
  required double y1,
  double lean = 0,
  int samples = 12,
  int bar = 0,
  String sectionId = _section,
}) => InkStroke(
  id: id,
  tool: StrokeTool.pen,
  color: '#102a43',
  size: 3,
  anchor: EventAnchor(sectionId: sectionId, bar: bar),
  points: <InkPoint>[
    for (int index = 0; index < samples; index++)
      InkPoint(
        // A hand is not a ruler: the wobble is one pixel, which is what his own strokes show.
        x: x + lean * index / (samples - 1) + (index.isEven ? 0.4 : -0.4),
        y: y0 + (y1 - y0) * index / (samples - 1),
        w: 0.5,
        t: index * 8,
      ),
  ],
);

/// A curved stroke of the given [height] and [width] starting at ([x], [y0]) — a letter's bowl, or
/// a circle, or the loop of a `6`.
InkStroke _curve({
  required String id,
  required double x,
  required double y0,
  required double width,
  required double height,
  int samples = 24,
}) {
  final List<InkPoint> points = <InkPoint>[];
  for (int index = 0; index < samples; index++) {
    final double t = index / (samples - 1) * 2 * Math.pi;
    points.add(
      InkPoint(
        x: x + width / 2 - width / 2 * math.cos(t),
        y: y0 + height / 2 - height / 2 * math.sin(t),
        w: 0.5,
        t: index * 8,
      ),
    );
  }
  return InkStroke(
    id: id,
    tool: StrokeTool.pen,
    color: '#102a43',
    size: 3,
    anchor: const EventAnchor(sectionId: _section, bar: 0),
    points: points,
  );
}

/// `2 * pi`, because `dart:math` is imported for nothing else in this file.
abstract final class Math {
  /// The full turn in radians.
  static const double pi = 3.1415926535897932;
}

void main() {
  group('a drawn division is found', () {
    test('a stroke across the row becomes a division at its own x', () {
      const BarlineDetector detector = BarlineDetector();
      final InkStroke stroke = _line(id: 'division', x: 40, y0: 4, y1: 50);
      final BarlineVerdict verdict = detector.measure(
        stroke: stroke,
        frame: _frame(),
      );
      expect(verdict.rejection, isNull, reason: 'a full-height line is a line');
      final BarlineCandidate candidate = verdict.candidate!;
      expect(candidate.strokeId, 'division');
      expect(candidate.centreX, closeTo(40, 1));
      // THE OLD ASSERTIONS HERE WERE `expect(candidate.top, closeTo(4, 1))` and
      // `expect(candidate.bottom, closeTo(50, 1))`, and they are replaced because they PINNED THE
      // DEFECT the owner reported and said yes to fixing: a recognised division used to keep the
      // extent of the stroke it was found in, so a line drawn from above the chord line to below it
      // stood taller than every separator the chart draws itself and read as a layout fault. His
      // answer to the proposed clamp is «Да обрезать». The ideal line is now the SPAN — the chord row
      // or the melody staff, which is exactly the rectangle the engraver draws its own separator
      // across — so the recognised line is the same height as the app's own. The ink is not
      // touched: `verdict.measurement.minY`/`maxY` still report 4 and 50, which the next assertion
      // checks, because the division must not be able to lose what he wrote.
      expect(candidate.top, 0);
      expect(candidate.bottom, _rowHeight);
      expect(
        candidate.height,
        _rowHeight,
        reason: 'the chart\'s own separator',
      );
      expect(verdict.measurement.minY, closeTo(4, 1));
      expect(verdict.measurement.maxY, closeTo(50, 1));
      expect(
        verdict.measurement.height,
        greaterThanOrEqualTo(_rowHeight * 0.75),
      );
    });

    test('a lean of three pixels over the row is still a division', () {
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'leaning', x: 40, y0: 2, y1: 52, lean: 3),
        frame: _frame(),
      );
      expect(
        verdict.rejection,
        isNull,
        reason: 'a hand leans, and a leaning line is still a division',
      );
    });
  });

  group('the vertical marks in his chord symbols are refused', () {
    // THE THREE MEASUREMENTS FROM HIS OWN PAGE, and the gate each one dies at. They are not
    // hypotheses: the picture of every bar at 8x shows the `(`, the `7` and the slash, and the
    // numbers below are that file's, rounded to a tenth of a pixel.
    test('the "(" of "(b9)" is too short for the row', () {
      // 5.1 wide, 22.8 tall, in a 52-pixel row: 0.44 of the row, which is his tallest vertical
      // mark anywhere on the page.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'paren', x: 67, y0: 1, y1: 23.8, lean: 5),
        frame: _frame(),
      );
      expect(verdict.rejection, BarlineRejection.tooShort);
      expect(verdict.measurement.height, closeTo(22.8, 0.1));
      expect(verdict.measurement.rowOverlap, lessThan(0.5));
    });

    test('the "7" of "Bb7(b9)" is too short for the row', () {
      // 3.3 wide, 18.7 tall: narrow enough and vertical enough, and still a digit.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'seven', x: 49, y0: 1, y1: 19.7, lean: 3),
        frame: _frame(),
      );
      expect(verdict.rejection, BarlineRejection.tooShort);
    });

    test('the "/" of "6/9" is not narrow enough to be a line', () {
      // 8.3 wide, 17.1 tall: a slash is a diagonal, and its box is wide for its height.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'slash', x: 26, y0: 10, y1: 27.1, lean: 8),
        frame: _frame(),
      );
      expect(verdict.rejection, BarlineRejection.notNarrowEnough);
      expect(
        verdict.measurement.aspect,
        lessThan(BarlineThresholds.standard.minAspect),
      );
    });

    test(
      'a FULL-HEIGHT mark with another mark against it is refused as crowded',
      () {
        // THE `1`, `l`, `I` AND `t`-STEM CASE, and the reason the company gate exists: these letters
        // are as tall as the line beside them and only their company gives them away. A stroke that
        // clears every shape gate is still refused when something stands inside the gap a division
        // needs at its side.
        final InkStroke candidate = _line(id: 'letter', x: 40, y0: 2, y1: 50);
        final InkStroke neighbour = _line(id: 'word', x: 44, y0: 30, y1: 42);
        final BarlineVerdict verdict = const BarlineDetector().measure(
          stroke: candidate,
          frame: _frame(),
          neighbours: <InkStroke>[neighbour],
        );
        expect(verdict.rejection, BarlineRejection.crowded);
        expect(
          verdict.measurement.isolation,
          lessThan(BarlineThresholds.standard.minimumIsolationFor(_rowHeight)),
          reason: 'the gap is 3.2 px where the row allows 7.8',
        );
      },
    );

    test(
      'the same full-height mark is accepted once the neighbour is clear of it',
      () {
        final BarlineVerdict verdict = const BarlineDetector().measure(
          stroke: _line(id: 'division', x: 40, y0: 2, y1: 50),
          frame: _frame(),
          neighbours: <InkStroke>[_line(id: 'chord', x: 54, y0: 30, y1: 42)],
        );
        expect(verdict.rejection, isNull);
        expect(
          verdict.measurement.isolation,
          greaterThanOrEqualTo(
            BarlineThresholds.standard.minimumIsolationFor(_rowHeight),
          ),
          reason: 'the gap is 13.2 px, and the row asks for 7.8',
        );
      },
    );

    test('a circle of the row\'s own height is not a division', () {
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _curve(id: 'circle', x: 20, y0: 0, width: 30, height: 52),
        frame: _frame(),
      );
      expect(verdict.rejection, BarlineRejection.notVerticalEnough);
    });

    test('a tall line written ABOVE the row does not divide it', () {
      // The melody staff and the margin above the chords are both places a musician draws: a note
      // stem there is tall and narrow and has nothing to do with the bar beneath it.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'stem', x: 40, y0: -80, y1: -20),
        frame: _frame(),
      );
      expect(verdict.rejection, BarlineRejection.missesTheRow);
    });
  });

  // THE BUG THE OWNER FOUND BY DRAWING, held here as the four claims the fix stands on: a division
  // drawn across the melody staff is FOUND, it is found for the right reason (it crosses the staff,
  // which is a span the chart draws its own separator across), the line it becomes is the staff's own
  // height, and the marks that are NOT divisions on a staff — a note stem, a ledger line, the staff's
  // own line, and the letters of his chord symbols — are still refused.
  //
  // THE GEOMETRY IS THE APPLICATION'S, NOT AN INVENTED ONE: with `barHeight: 52` and
  // `melodyStaffHeight: 52`, the staff sits at row-local y 70..122 on a chart whose staff carries no
  // note and at 124..176 on one that does. Both numbers are what `LayoutEngine` produces and what
  // `probe_barline_detect.dart` measures; the constant below is the blank-staff case, which is the
  // state his own chart was in when he drew on the staff.
  group('a division drawn across the melody staff is found', () {
    /// The melody staff's rectangle in the chord row's own anchor-local space, for a chart whose
    /// declared staff carries no note: the band is `melodyEmptyBandHeight` = 68, the staff is centred
    /// in it, and the chord row is 52 tall, so the five lines are 70..122 below the row's top.
    const LayoutRect staff = LayoutRect(
      origin: LayoutOffset(0, 70),
      size: LayoutSize(88, 52),
    );

    /// A frame offering BOTH spans of one bar, with the ONE barline height the page measures every
    /// mark against — 52 px, which is the staff's own span and the row's own height on this page.
    BarlineFrame staffFrame() => BarlineFrame(
      referenceHeight: _rowHeight,
      bands: <BarlineBand>[
        BarlineBand(kind: BarlineBandKind.chordStave, bounds: _row()),
        const BarlineBand(kind: BarlineBandKind.melodyStaff, bounds: staff),
      ],
    );

    test('it is accepted on the staff band, not the chord row', () {
      final BarlineVerdict verdict = const BarlineDetector().measure(
        // The stroke overshoots the five lines by two pixels at each end, as a hand does.
        stroke: _line(id: 'staff-division', x: 40, y0: 68, y1: 124),
        frame: staffFrame(),
      );
      expect(
        verdict.rejection,
        isNull,
        reason:
            'the mark the owner drew across the staff must be found; before the page-wide '
            'reference it died at misses-the-row with a row overlap of 0.00',
      );
      expect(verdict.measurement.band?.kind, BarlineBandKind.melodyStaff);
      expect(
        verdict.measurement.rowOverlap,
        0,
        reason:
            'the row is still reported and is still zero: the gate stopped reading it, '
            'it did not start pretending the staff is the row',
      );
      expect(verdict.measurement.bandOverlap, 1.0);
    });

    test(
      'the line it becomes is the staff\'s own height, not the stroke\'s',
      () {
        final BarlineVerdict verdict = const BarlineDetector().measure(
          stroke: _line(id: 'staff-division', x: 40, y0: 68, y1: 124),
          frame: staffFrame(),
        );
        final BarlineCandidate candidate = verdict.candidate!;
        // THE CLAMP (the owner's «Да обрезать»): 56 pixels of ink become the 52-pixel span the chart
        // draws its own separator across, so the recognised line does not stand out as taller than the
        // structure beside it. The ink still reports 56 — the stroke is not lost, only regularised.
        expect(verdict.measurement.height, closeTo(56, 0.5));
        expect(candidate.top, 70);
        expect(candidate.bottom, 122);
        expect(candidate.height, 52);
      },
    );

    test('a note stem next to its notehead is refused as crowded', () {
      // A STEM IS A VERTICAL SEGMENT ATTACHED TO A NOTEHEAD, and that is the whole of what tells it
      // from a division. The notehead is the mark beside it, so the company gate is the gate that
      // separates them — no second rule was added for the staff.
      final InkStroke head = _curve(
        id: 'notehead',
        x: 40,
        y0: 90.2,
        width: 15.6,
        height: 11.7,
      );
      // 3.5 staff spaces of stem — 45.5 px at the application's 13-pixel space — rising from the
      // head's right edge. It clears the shape gates and, at 0.88 of the barline, the size gate too;
      // only its company refuses it, which is the point.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'stem', x: 55, y0: 50.5, y1: 96),
        frame: staffFrame(),
        neighbours: <InkStroke>[head],
      );
      expect(verdict.rejection, BarlineRejection.crowded);
      expect(
        verdict.measurement.isolation,
        lessThan(BarlineThresholds.standard.minimumIsolationFor(52)),
      );
    });

    test('a ledger line is refused: it is horizontal and short', () {
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'ledger', x: 30, y0: 128, y1: 128),
        frame: staffFrame(),
      );
      expect(verdict.rejection, BarlineRejection.notVerticalEnough);
    });

    test(
      'the staff\'s own line is refused: it is horizontal and spans the bar',
      () {
        final BarlineVerdict verdict = const BarlineDetector().measure(
          stroke: _line(id: 'staff-line', x: 1, y0: 70, y1: 70),
          frame: staffFrame(),
        );
        expect(verdict.rejection, BarlineRejection.notVerticalEnough);
      },
    );

    test('the letters of his chord symbols are still refused on the staff', () {
      // A LETTER CAN BE DRAWN IN THE SAME BAND AS A DIVISION, so the size and shape gates are what
      // have to refuse it there: 22.8 px is 0.44 of the 52-pixel barline the page measures against.
      final BarlineVerdict paren = const BarlineDetector().measure(
        stroke: _line(id: 'paren', x: 40, y0: 76, y1: 98.8, lean: 5),
        frame: staffFrame(),
      );
      expect(paren.rejection, BarlineRejection.tooShort);
      final BarlineVerdict slash = const BarlineDetector().measure(
        stroke: _line(id: 'slash', x: 40, y0: 76, y1: 93.1, lean: 8),
        frame: staffFrame(),
      );
      expect(slash.rejection, BarlineRejection.notNarrowEnough);
    });

    test(
      'one height for the page: a frame with one band and one with two agree',
      () {
        // THE ONE-VALUE CLAIM, stated as an equality rather than an adjective. A division in the chord
        // row is judged by the same barline height whether or not the page also engraves a staff, so
        // the same stroke must get the same SIZE verdict from both frames.
        final InkStroke tall = _line(id: 'tall', x: 40, y0: 0, y1: 40);
        expect(
          const BarlineDetector()
              .measure(stroke: tall, frame: _frame())
              .measurement
              .referenceHeight,
          const BarlineDetector()
              .measure(stroke: tall, frame: staffFrame())
              .measurement
              .referenceHeight,
        );
        // And a mark that clears the height gate but crosses NEITHER span is refused, which is what
        // makes the place gate a statement about the page and not about a mark being tall.
        final BarlineVerdict above = const BarlineDetector().measure(
          stroke: _line(id: 'above', x: 40, y0: -60, y1: -8),
          frame: staffFrame(),
        );
        expect(above.rejection, BarlineRejection.missesTheRow);
      },
    );
  });

  group('a division is a structural unit', () {
    test('one round-trips through the event codec unchanged', () {
      const DivisionSetEvent event = DivisionSetEvent(
        docId: 'doc-1',
        seq: 7,
        from: <BarDivision>[],
        to: <BarDivision>[
          BarDivision(
            id: 'division-1',
            place: AnchoredPlace(
              anchor: EventAnchor(sectionId: _section, bar: 2),
              offsetX: 41.5,
              offsetY: 3,
            ),
            height: 50,
            sourceStrokeId: 'ink-1',
          ),
        ],
      );
      final DocumentEvent decoded = EventCodec.decode(
        jsonDecode(EventCodec.encodeLine(event)) as Map<String, Object?>,
      );
      expect(decoded, event);
    });

    test(
      'applying it and its inverse returns the previous document exactly',
      () {
        final DocumentState before = DocumentState(
          song: _chart(),
          strokes: <InkStroke>[_line(id: 'ink-1', x: 40, y0: 2, y1: 50)],
        );
        const BarDivision division = BarDivision(
          id: 'division-1',
          place: AnchoredPlace(
            anchor: EventAnchor(sectionId: _section, bar: 0),
            offsetX: 40,
            offsetY: 2,
          ),
          height: 48,
          sourceStrokeId: 'ink-1',
        );
        final DivisionSetEvent add = DivisionSetEvent(
          docId: 'doc-1',
          seq: 1,
          from: const <BarDivision>[],
          to: const <BarDivision>[division],
        );
        final DocumentState added = DocumentReducer.apply(before, add);
        expect(added.divisions, <BarDivision>[division]);
        final DocumentState undone = DocumentReducer.apply(
          added,
          add.inverse(),
        );
        expect(undone, before);
        expect(
          undone.strokes,
          before.strokes,
          reason: 'the handwriting is never discarded by a division',
        );
      },
    );

    test('a chart saved and reopened keeps its divisions and its ink', () {
      final DocumentState document = DocumentState(
        song: _chart(),
        strokes: <InkStroke>[_line(id: 'ink-1', x: 40, y0: 2, y1: 50)],
        divisions: const <BarDivision>[
          BarDivision(
            id: 'division-1',
            place: AnchoredPlace(
              anchor: EventAnchor(sectionId: _section, bar: 0),
              offsetX: 40,
              offsetY: 2,
            ),
            height: 48,
            sourceStrokeId: 'ink-1',
          ),
        ],
      );
      final ChartFile file = ChartFile(
        metadata: const ChartMetadata(docId: 'doc-1', writer: 'barline-test'),
        snapshot: document,
        events: const <ChartEvent>[
          DivisionSetEvent(
            docId: 'doc-1',
            seq: 1,
            from: <BarDivision>[],
            to: <BarDivision>[
              BarDivision(
                id: 'division-1',
                place: AnchoredPlace(
                  anchor: EventAnchor(sectionId: _section, bar: 0),
                  offsetX: 40,
                  offsetY: 2,
                ),
                height: 48,
                sourceStrokeId: 'ink-1',
              ),
            ],
          ),
        ],
      );
      final ChartFileDecodeResult reopened = ChartFileCodec.decode(
        ChartFileCodec.encode(file).bytes,
      );
      final DocumentState read = reopened.file.reducedDocument;
      expect(read.divisions.length, 1);
      expect(read.divisions.first.id, 'division-1');
      expect(read.divisions.first.source, DivisionSource.recognised);
      expect(read.divisions.first.cameFrom('ink-1'), isTrue);
      expect(
        read.strokes.length,
        1,
        reason: 'the stroke the division came from is still in the file',
      );
    });

    test('ink alone never becomes structure: a stroke event leaves divisions empty', () {
      // THIS IS THE MODEL HALF OF "RECOGNITION IS OFF BY DEFAULT". Nothing in the document adds a
      // division except an explicit `division.set`; committing a stroke — which is what recognition
      // OFF does, and all it does — cannot create one.
      final DocumentState before = DocumentState(song: _chart());
      final DocumentState after = DocumentReducer.apply(
        before,
        InkStrokeAddEvent(
          docId: 'doc-1',
          seq: 1,
          index: 0,
          stroke: _line(id: 'ink-1', x: 40, y0: 2, y1: 50),
        ),
      );
      expect(after.strokes.length, 1);
      expect(after.divisions, isEmpty);
    });
  });
}
