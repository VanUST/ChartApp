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
  int? beat,
  String sectionId = _section,
}) => InkStroke(
  id: id,
  tool: StrokeTool.pen,
  color: '#102a43',
  size: 3,
  anchor: EventAnchor(sectionId: sectionId, bar: bar, beat: beat),
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
        row: _row(),
      );
      expect(verdict.rejection, isNull, reason: 'a full-height line is a line');
      final BarlineCandidate candidate = verdict.candidate!;
      expect(candidate.strokeId, 'division');
      expect(candidate.centreX, closeTo(40, 1));
      expect(candidate.top, closeTo(4, 1));
      expect(candidate.bottom, closeTo(50, 1));
      expect(candidate.height, greaterThanOrEqualTo(_rowHeight * 0.75));
    });

    test('a lean of three pixels over the row is still a division', () {
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'leaning', x: 40, y0: 2, y1: 52, lean: 3),
        row: _row(),
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
        row: _row(),
      );
      expect(verdict.rejection, BarlineRejection.tooShort);
      expect(verdict.measurement.height, closeTo(22.8, 0.1));
      expect(verdict.measurement.rowOverlap, lessThan(0.5));
    });

    test('the "7" of "Bb7(b9)" is too short for the row', () {
      // 3.3 wide, 18.7 tall: narrow enough and vertical enough, and still a digit.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'seven', x: 49, y0: 1, y1: 19.7, lean: 3),
        row: _row(),
      );
      expect(verdict.rejection, BarlineRejection.tooShort);
    });

    test('the "/" of "6/9" is not narrow enough to be a line', () {
      // 8.3 wide, 17.1 tall: a slash is a diagonal, and its box is wide for its height.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'slash', x: 26, y0: 10, y1: 27.1, lean: 8),
        row: _row(),
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
          row: _row(),
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
          row: _row(),
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
        row: _row(),
      );
      expect(verdict.rejection, BarlineRejection.notVerticalEnough);
    });

    test('a tall line written ABOVE the row does not divide it', () {
      // The melody staff and the margin above the chords are both places a musician draws: a note
      // stem there is tall and narrow and has nothing to do with the bar beneath it.
      final BarlineVerdict verdict = const BarlineDetector().measure(
        stroke: _line(id: 'stem', x: 40, y0: -80, y1: -20),
        row: _row(),
      );
      expect(verdict.rejection, BarlineRejection.missesTheRow);
    });
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
