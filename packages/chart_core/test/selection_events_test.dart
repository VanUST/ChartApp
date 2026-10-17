// PURPOSE: Hold the four things a SELECTION has to do — copy a run of bars, paste it, carry the ink
//          with it, and transpose it without touching the key — to the numbers the owner asked for
//          in his own words (D35, D36). Every assertion here is a fact a musician could check on the
//          tablet, so a failure is a defect and not a taste.
// INPUTS: None; the file builds its own charts with `newChartSong`.
// OUTPUTS: A passing run prints nothing but the test names; a failure names the bar, the chord, the
//          stroke or the undo step that disagreed.
// KEYWORDS: selection, copy, paste, transpose, ink-carried, one-undo, four-step-scenario, d35, d36,
//           d37
//
// WHY THIS FILE EXISTS AND WHAT IT DOES NOT DUPLICATE. The catalogue's event tests already prove an
// event and its inverse; the transposition tests already prove a chord or a note is spelled right.
// What neither can prove is the GESTURE: that a copy of sixteen bars pasted at the end is sixteen
// more bars with their chords, their melody and their ink, that one press of undo takes all sixteen
// away, and that a semitone moves the copy while leaving the key and the rest of the chart alone.
// That is the workflow the owner named, and it is what these tests measure.
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

import '../support/place_fixture.dart';

/// The chart's only section id, which [newChartSong] fixes.
const String _section = newChartFirstSectionId;

/// A chart of [bars] bars in C major, 4/4, one section labelled A.
Song _chart({int bars = 4}) => newChartSong(
  key: Key.cMajor,
  timeSignature: TimeSignature.fourFour,
  bars: bars,
);

/// A document over [song] with the given [strokes].
DocumentState _document(
  Song song, {
  List<InkStroke> strokes = const <InkStroke>[],
}) => DocumentState(song: song, strokes: strokes);

/// A stroke hanging on [bar], drawn at ([x], [y]) from its own bar-local points.
InkStroke _stroke({
  required String id,
  required int bar,
  String sectionId = _section,
  double x = 10,
  double y = 20,
}) => InkStroke(
  id: id,
  tool: StrokeTool.pen,
  color: '#112233',
  size: 2,
  anchor: EventAnchor(sectionId: sectionId, bar: bar),
  points: <InkPoint>[
    InkPoint(x: x, y: y, w: 0.5, t: 0),
    InkPoint(x: x + 30, y: y + 10, w: 0.5, t: 40),
  ],
);

/// A selection of the bars [first]..[last] of the chart's only section.
ChartSelection _bars(int first, int last) =>
    ChartSelection.bars(sectionId: _section, firstBar: first, lastBar: last);

/// Puts a chord and a melody note on every bar of the chart, cycling `Dm7 G7 Cmaj7 A7`, so a
/// transposition has both halves of every bar to move.
void _fillWithMusic(EditSession session, int bars) {
  const List<Chord> cycle = <Chord>[
    Chord(root: ChordRoot(2), quality: ChordQuality.minorSeventh),
    Chord(root: ChordRoot(7), quality: ChordQuality.dominantSeventh),
    Chord(root: ChordRoot(0), quality: ChordQuality.majorSeventh),
    Chord(root: ChordRoot(9), quality: ChordQuality.dominantSeventh),
  ];
  for (int bar = 0; bar < bars; bar++) {
    fixtureChord(
      session,
      sectionId: _section,
      barIndex: bar,
      slot: 0,
      chord: cycle[bar % cycle.length],
    );
    fixtureInsertNote(
      session,
      sectionId: _section,
      barIndex: bar,
      slot: 0,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.d, 0), octave: 4),
      value: const NoteValue.plain(NoteBase.quarter),
    );
  }
}

/// Renders the chord on [beat] of [bar] in the chart's own key, the way a musician reads it.
String _chordText(Song song, int bar, int beat) => song
    .sections
    .first
    .bars[bar]
    .chords
    .firstWhere((ChordMark placed) => placed.offsetX == fixtureX(beat))
    .chord
    .render(song.key, const SpellingTable());

void main() {
  group('the four-step scenario the owner described', () {
    test('16 bars are copied, pasted at the end, and the pasted 16 move up a '
        'semitone while the key stays', () {
      final EditSession session = EditSession(
        document: _document(_chart(bars: 16)),
      );
      _fillWithMusic(session, 16);
      final int undoBefore = session.undoDepth;

      // 1. SELECT sixteen bars.
      final SelectionReport report = selectionReportOf(
        song: session.song,
        strokes: session.document.strokes,
        selection: _bars(0, 15),
      );
      expect(report.barCount, 16, reason: 'the selection covers sixteen bars');
      expect(
        report.structuredBars,
        16,
        reason:
            'every bar carries a chord and a note, so all sixteen transpose',
      );

      // 2. COPY: no event, no undo step.
      final ChartClip? clip = session.copySelection(_bars(0, 15));
      expect(clip, isNotNull);
      expect(clip!.barCount, 16);
      expect(
        session.undoDepth,
        undoBefore,
        reason: 'copying changes nothing, so it offers nothing to undo',
      );

      // 3. PASTE at the end: bar index 15 is the section's last bar, so the run lands after it.
      expect(
        session.pasteClip(at: _bars(15, 15), clip: clip),
        ClipPasteOutcome.pasted,
      );
      expect(
        session.document.song.sectionById(_section)!.bars.length,
        32,
        reason: 'sixteen copied bars pasted at the end make thirty-two',
      );
      expect(
        session.undoDepth,
        undoBefore + 1,
        reason: 'the whole paste is ONE undo step, not sixteen',
      );
      expect(
        _chordText(session.song, 16, 0),
        'Dm7',
        reason: 'the pasted bar is a copy of the first bar of the selection',
      );

      // 4. TRANSPOSE the pasted sixteen up a semitone.
      final SelectionTransposition moved = session.transposeSelection(
        selection: _bars(16, 31),
        semitones: 1,
      );
      expect(moved.outcome, SelectionTransposeOutcome.applied);
      expect(moved.barsChanged, 16);
      expect(moved.barsTotal, 16);
      expect(
        session.undoDepth,
        undoBefore + 2,
        reason: 'the transposition is the SECOND step, not a sixteen-step run',
      );

      expect(session.document.song.sections.first.bars.length, 32);
      expect(
        _chordText(session.song, 0, 0),
        'Dm7',
        reason: 'the source is untouched',
      );
      expect(_chordText(session.song, 16, 0), 'Ebm7');
      expect(_chordText(session.song, 17, 0), 'Ab7');
      expect(_chordText(session.song, 18, 0), 'Dbmaj7');
      expect(_chordText(session.song, 19, 0), 'Bb7');
      expect(
        session.song.key,
        Key.cMajor,
        reason:
            'a selection transposition is not a modulation: the key is '
            'what the chart is filed under, not a property of one run',
      );
      // The melody moved with the chords, which is the rule transposeSong states for the whole
      // chart and which a selection must follow or the two halves of a bar would disagree.
      expect(
        session
            .song
            .sections
            .first
            .bars[16]
            .melody
            .single
            .pitch
            .note
            .pitchClass,
        session
                .song
                .sections
                .first
                .bars[0]
                .melody
                .single
                .pitch
                .note
                .pitchClass +
            1,
        reason:
            'the pasted bar has its melody moved by the same semitone as '
            'its chord',
      );
      expect(
        session.song.sections.first.bars[1].melody.single.pitch.note.pitchClass,
        session.song.sections.first.bars[0].melody.single.pitch.note.pitchClass,
        reason: 'the source bar has its melody where it was',
      );

      // 5. THE UNDO COST, COUNTED: two presses take the chart back where it started.
      expect(session.undo(), isTrue);
      expect(
        _chordText(session.song, 16, 0),
        'Dm7',
        reason: 'one undo puts the pasted run back before the transposition',
      );
      expect(session.undo(), isTrue);
      expect(
        session.document.song.sections.first.bars.length,
        16,
        reason: 'the second undo takes the whole pasted run away',
      );
    });
  });

  group('the handwriting travels with its bars', () {
    test('a copied bar carries its strokes, and the paste gives them their OWN '
        'anchors and identities', () {
      final EditSession session = EditSession(
        document: _document(
          _chart(bars: 4),
          strokes: <InkStroke>[
            _stroke(id: 'ink-a-0', bar: 0, x: 12, y: 30),
            _stroke(id: 'ink-a-0-b2', bar: 0),
            _stroke(id: 'ink-a-2', bar: 2),
          ],
        ),
      );
      final ChartClip clip = session.copySelection(_bars(0, 1))!;
      expect(
        clip.strokes.length,
        2,
        reason: 'both strokes of bar 0 travel; bar 2 is outside the selection',
      );
      expect(
        clip.strokes.every((InkStroke stroke) => stroke.anchor.bar == 0),
        isTrue,
        reason: 'the clip rebases its anchors onto the fragment',
      );

      expect(
        session.pasteClip(at: _bars(1, 1), clip: clip),
        ClipPasteOutcome.pasted,
      );

      final List<InkStroke> strokes = session.document.strokes;
      expect(
        strokes.length,
        5,
        reason: 'three original strokes and two pasted ones',
      );
      final List<InkStroke> pasted = strokes
          .where((InkStroke stroke) => stroke.anchor.bar == 2)
          .toList();
      expect(
        pasted.length,
        2,
        reason:
            'the pasted strokes hang on the pasted bar (index 2), not on '
            'bar 0 where they came from',
      );
      expect(
        pasted.map((InkStroke stroke) => stroke.id).toSet(),
        <String>{'ink-a-0~copy-1', 'ink-a-0-b2~copy-1'},
        reason: 'a copy needs its own identity, or the eraser would take both',
      );
      // REWRITTEN. The assertion this replaces was
      //   expect(pasted.firstWhere((InkStroke stroke) => stroke.id.startsWith('ink-a-0-b2'))
      //       .anchor.beat, 2,
      //       reason: 'a stroke that hung on a CELL keeps its cell');
      // and it pinned the cell a stroke was anchored to. A stroke is anchored to its BAR now and its
      // position along that bar is in its own points, so "it keeps its cell" survives as "it keeps
      // its points": the copy's first sample is where the original's was measured from the same bar,
      // which is the only fact the cell number ever stood for.
      expect(
        pasted
            .firstWhere(
              (InkStroke stroke) => stroke.id.startsWith('ink-a-0-b2'),
            )
            .anchor,
        EventAnchor(sectionId: _section, bar: 2),
        reason: 'a stroke pasted with the bars keeps its bar and its own ink',
      );
      expect(
        strokes.where((InkStroke stroke) => stroke.anchor.bar == 0).length,
        2,
        reason: 'the originals stay on their own bar',
      );
      expect(
        pasted.first.points,
        clip.strokes.first.points,
        reason: 'the copy carries the same geometry, re-anchored',
      );

      // ONE UNDO TAKES THE INK WITH THE BARS.
      expect(session.undo(), isTrue);
      expect(
        session.document.strokes.length,
        3,
        reason:
            'undo removes the pasted bars AND the strokes that came with '
            'them',
      );
      expect(
        session.document.strokes.map((InkStroke stroke) => stroke.id),
        <String>['ink-a-0', 'ink-a-0-b2', 'ink-a-2'],
      );
    });

    test('a paste in the MIDDLE moves the ink of the bars it pushes along, and '
        'one undo puts it back', () {
      final EditSession session = EditSession(
        document: _document(
          _chart(bars: 4),
          strokes: <InkStroke>[
            _stroke(id: 'ink-b2', bar: 2),
            _stroke(id: 'ink-b3', bar: 3),
          ],
        ),
      );
      final DocumentState original = session.document;
      final ChartClip clip = session.copySelection(_bars(0, 0))!;

      // Paste after bar 0: the original bars 2 and 3 become bars 3 and 4, and their ink must
      // follow them. Leaving the strokes on bar 2 would draw the musician's ink over the PASTED
      // bar, which is the silent failure this whole feature exists to prevent.
      expect(
        session.pasteClip(at: _bars(1, 1), clip: clip),
        ClipPasteOutcome.pasted,
      );
      expect(
        <String, int>{
          for (final InkStroke stroke in session.document.strokes)
            stroke.id: stroke.anchor.bar,
        },
        <String, int>{'ink-b2': 3, 'ink-b3': 4},
        reason: 'the ink moved with the music it was written on',
      );
      expect(
        session.document.song.sectionById(_section)!.bars.length,
        5,
        reason: 'one bar pasted',
      );

      expect(session.undo(), isTrue);
      expect(
        session.document.strokes.map((InkStroke stroke) => stroke.anchor.bar),
        <int>[2, 3],
        reason: 'undo re-addresses the ink back onto the bars it came from',
      );
      expect(
        session.document,
        original,
        reason: 'the whole document, ink included, is exactly what it was',
      );
    });
  });

  group('a fragment nothing recognised is still copyable', () {
    test('sixteen bars of pure handwriting report as minimal, copy and paste '
        'with their ink, and their extent is measured', () {
      final EditSession session = EditSession(
        document: _document(
          _chart(bars: 16),
          strokes: <InkStroke>[
            for (int bar = 0; bar < 16; bar++)
              _stroke(id: 'ink-hand-$bar', bar: bar, x: 4, y: 6),
          ],
        ),
      );
      final SelectionReport report = selectionReportOf(
        song: session.song,
        strokes: session.document.strokes,
        selection: _bars(0, 15),
      );
      expect(
        report.structuredBars,
        0,
        reason: 'nothing on these bars was ever recognised as music',
      );
      expect(report.minimalBars, 16);
      expect(
        report.inkOnlyBars,
        16,
        reason:
            'every one of the sixteen carries handwriting, so all sixteen '
            'are worth carrying even though none of them transposes',
      );
      expect(
        report.emptyBars,
        0,
        reason: 'none of them is a bar with nothing on it at all',
      );
      expect(
        report.strokeCount,
        16,
        reason: 'every handwritten mark hangs on its own bar',
      );
      expect(report.hasStructuredContent, isFalse);
      // THE MINIMUM STRUCTURE, AS A NUMBER: a centre and an area, derived from the points.
      final InkFragment fragment = report.fragments.first;
      expect(fragment.strokeCount, 1);
      expect(
        fragment.centreX,
        4 + 15,
        reason: 'the centre is the middle of the drawn extent',
      );
      expect(
        fragment.width,
        30 + 2,
        reason: 'the extent includes the whole nib',
      );
      expect(fragment.height, 10 + 2);
      expect(
        fragment.anchor.bar,
        0,
        reason: 'the fragment is measured from the bar it hangs on',
      );

      // COPY AND PASTE IT ANYWAY. This is the owner's own example: bars of handwriting copied to
      // another place with no recognition anywhere in the path.
      final ChartClip clip = session.copySelection(_bars(0, 15))!;
      expect(clip.bars.length, 16);
      expect(clip.strokes.length, 16);
      expect(
        session.pasteClip(at: _bars(15, 15), clip: clip),
        ClipPasteOutcome.pasted,
      );
      expect(session.document.song.sectionById(_section)!.bars.length, 32);
      expect(
        session.document.strokes.length,
        32,
        reason: 'the pasted sixteen bars carry sixteen strokes of their own',
      );
      for (int bar = 16; bar < 32; bar++) {
        expect(
          session.document.strokes.any(
            (InkStroke stroke) => stroke.anchor.bar == bar,
          ),
          isTrue,
          reason: 'pasted bar $bar carries its own ink',
        );
      }
      expect(
        session.undo(),
        isTrue,
        reason: 'and the whole thing is one undo step, ink included',
      );
      expect(session.document.strokes.length, 16);
    });

    test('a transposition leaves the ink exactly where it was drawn and says '
        'how many strokes it kept', () {
      final EditSession session = EditSession(
        document: _document(
          _chart(bars: 2),
          strokes: <InkStroke>[
            _stroke(id: 'ink-1', bar: 0),
            _stroke(id: 'ink-2', bar: 1),
          ],
        ),
      );
      fixtureChord(
        session,
        sectionId: _section,
        barIndex: 0,
        slot: 0,
        chord: const Chord(root: ChordRoot(2)),
      );
      final List<InkStroke> inkBefore = session.document.strokes;
      final SelectionTransposition moved = session.transposeSelection(
        selection: _bars(0, 1),
        semitones: 1,
      );
      expect(moved.outcome, SelectionTransposeOutcome.applied);
      expect(moved.barsChanged, 1, reason: 'only bar 0 has anything to move');
      expect(
        moved.barsTotal,
        2,
        reason: 'bar 1 carries no chord and no note, and is reported as such',
      );
      expect(
        moved.strokesKept,
        2,
        reason:
            'the two strokes were counted so the surface can say they '
            'stayed',
      );
      expect(
        session.document.strokes,
        inkBefore,
        reason: 'handwriting is a picture: a semitone moves no pixel of it',
      );
      expect(
        session.document.song.sectionById(_section)!.bars[1],
        _chart(bars: 2).sections.first.bars[1],
        reason: 'a bar with nothing in it is left exactly as it was',
      );
    });
  });

  group('a window of beats inside one bar', () {
    test('copies the cells of the window, pastes them into another bar, and one '
        'undo puts the target bar back', () {
      final EditSession session = EditSession(
        document: _document(_chart(bars: 2)),
      );
      for (int beat = 0; beat < 4; beat++) {
        fixtureChord(
          session,
          sectionId: _section,
          barIndex: 0,
          slot: beat,
          chord: Chord(root: ChordRoot(beat)),
        );
      }
      // A WINDOW IS A STRETCH OF THE BAR BETWEEN TWO X VALUES, so its width is a DISTANCE and not
      // a count of beats. THE OLD ASSERTION, QUOTED: expect(window.windowWidth, 2); — two beats,
      // because a window used to be a run of cells and its width was how many of them it held.
      // What a paste needs from the width is a length in pixels, because a paste translates a clip
      // by the distance between two windows' left ends. This window runs from x=26 to x=45: it is
      // 19 wide, and it holds the chords written at 26 and 44 and nothing else.
      final ChartSelection window = ChartSelection.window(
        sectionId: _section,
        barIndex: 0,
        firstX: 26,
        lastX: 45,
      );
      expect(window.barCount, 1);
      expect(window.windowWidth, 19);
      final ChartClip clip = session.copySelection(window)!;
      expect(clip.depth, SelectionDepth.window);

      final Bar targetBefore = session.document.song.sections.first.bars[1];
      final ClipPasteOutcome outcome = session.pasteClip(
        at: ChartSelection.window(
          sectionId: _section,
          barIndex: 1,
          firstX: 70,
          lastX: 89,
        ),
        clip: clip,
      );
      expect(outcome, ClipPasteOutcome.pasted);
      final Bar target = session.document.song.sections.first.bars[1];
      // THE WINDOW LANDED WHERE IT WAS PUT. Two old expectations are quoted here because the
      // migration had already rewritten one of them. The original read the two chords' beats as
      // `<int>[2, 3]` — the columns the metre gave them in the target bar. The migrated form read
      // the two places as `<double>[fixtureX(2), fixtureX(3)]`, which was the right unit and the
      // wrong numbers: the source window it named held no chord at all, so it pinned a paste of
      // nothing. A paste is a TRANSLATION, so what is asserted is the two places it produced: the
      // source window's chords (26 and 44) moved by the 44 pixels between the two windows' left
      // ends, which is 70 and 88.
      expect(
        target.chords.map((ChordMark placed) => placed.offsetX),
        <double>[70, 88],
        reason:
            'each chord of the copied window moved by the distance between the windows, which is '
            'the whole of what a window paste is',
      );
      expect(
        target.chords.map((ChordMark placed) => placed.chord.root.pitchClass),
        <int>[1, 2],
        reason: 'the chords of the source window are the ones at x=26 and x=44, roots 1 and 2',
      );
      expect(
        session.document.song.sections.first.bars[0].chords.length,
        4,
        reason: 'the source bar was copied, not moved',
      );
      expect(session.undo(), isTrue);
      expect(
        session.document.song.sections.first.bars[1],
        targetBefore,
        reason: 'ONE undo puts the whole target bar back as it was',
      );
    });

    test(
      'a window past the old metre is pasted and widens the bar, not refused',
      () {
        // THE OLD ASSERTION, QUOTED, and its removal is the point of this case:
        //   expect(session.pasteClip(...), ClipPasteOutcome.windowDoesNotFit,
        //       reason: 'a two-beat window at beat 4 of a 4/4 bar does not fit, and spilling past the
        //                barline would be the application composing');
        // — with `expect(session.undoDepth, undoBefore)` and the target bar unchanged after it. A
        // window that ran past the last beat of the metre was refused, because the metre decided how
        // much room a bar had and a paste could not be allowed to exceed it.
        //
        // THERE IS NO ROOM TO EXCEED. A bar's width follows its content, so a mark past where the
        // fourth beat used to end makes the bar wider instead of spilling off it, and a paste is a
        // translation whose destination is a coordinate like any other. What has to remain true — and
        // is asserted here instead of the refusal — is that the paste lands exactly where it was put,
        // is ONE event, and loses nothing.
        final EditSession session = EditSession(
          document: _document(_chart(bars: 2)),
        );
        fixtureChord(
          session,
          sectionId: _section,
          barIndex: 0,
          slot: 3,
          chord: const Chord(root: ChordRoot(0)),
        );
        final int undoBefore = session.undoDepth;
        final ChartClip clip = session.copySelection(
          ChartSelection.window(
            sectionId: _section,
            barIndex: 0,
            firstX: 62,
            lastX: 63,
          ),
        )!;
        expect(
          clip.bars.single.chords,
          hasLength(1),
          reason: 'the copied window holds the chord written at x=62, which is the old beat 4',
        );
        expect(
          session.pasteClip(
            at: ChartSelection.window(
              sectionId: _section,
              barIndex: 1,
              firstX: 100,
              lastX: 101,
            ),
            clip: clip,
          ),
          ClipPasteOutcome.pasted,
          reason:
              'a place further along the bar than the metre ever reached is a place like any other: '
              'the bar widens to hold it rather than the application refusing the musician',
        );
        expect(
          session.undoDepth,
          undoBefore + 1,
          reason: 'a paste is one event, so one undo is enough to take it back',
        );
        expect(
          session.document.song.sections.first.bars[1].chords.map(
            (ChordMark placed) => placed.offsetX,
          ),
          <double>[100],
          reason: 'the chord landed exactly where the target window began',
        );
        expect(session.undo(), isTrue);
        expect(
          session.document.song.sections.first.bars[1],
          _chart(bars: 2).sections.first.bars[1],
          reason: 'and the undo left the target bar exactly as it was',
        );
      },
    );

    test('a window cannot be transposed, and says so instead of writing '
        'something', () {
      final EditSession session = EditSession(
        document: _document(_chart(bars: 1)),
      );
      fixtureChord(
        session,
        sectionId: _section,
        barIndex: 0,
        slot: 1,
        chord: const Chord(root: ChordRoot(2)),
      );
      final SelectionTransposition refused = session.transposeSelection(
        selection: ChartSelection.window(
          sectionId: _section,
          barIndex: 0,
          firstX: 0,
          lastX: 1,
        ),
        semitones: 1,
      );
      expect(refused.outcome, SelectionTransposeOutcome.beatsOnly);
      expect(refused.applied, isFalse);
      expect(
        session
            .document
            .song
            .sections
            .first
            .bars[0]
            .chords
            .single
            .chord
            .root
            .pitchClass,
        2,
        reason:
            'nothing moved: a bar is the smallest fragment that holds a key',
      );
    });
  });

  group(
    'the events replay, which is what makes a save and a reopen keep the ink',
    () {
      test(
        'a paste encoded into a log tail and decoded again rebuilds the same '
        'document, strokes included',
        () {
          final EditSession session = EditSession(
            document: _document(
              _chart(bars: 4),
              strokes: <InkStroke>[_stroke(id: 'ink-a0', bar: 0)],
            ),
          );
          fixtureChord(
            session,
            sectionId: _section,
            barIndex: 0,
            slot: 0,
            chord: const Chord(
              root: ChordRoot(2),
              quality: ChordQuality.minorSeventh,
            ),
          );
          final ChartClip clip = session.copySelection(_bars(0, 1))!;
          session.pasteClip(at: _bars(3, 3), clip: clip);
          session.transposeSelection(selection: _bars(4, 5), semitones: 1);

          // A SAVE WRITES THE SNAPSHOT AND THE TAIL; A REOPEN APPLIES THE TAIL. The tail is what
          // must carry the pasted ink, so the round trip goes through the codec that writes
          // `events.jsonl`.
          final String tail = session.log
              .map((ChartEvent event) => EventCodec.encodeLine(event))
              .join('\n');
          final List<DocumentEvent> decodedEvents = EventCodec.decodeLines(
            tail.split('\n'),
          );
          final List<ChartEvent> decoded = decodedEvents.cast<ChartEvent>();
          expect(decoded.length, session.log.length);
          expect(
            decoded,
            session.log,
            reason: 'every event round-trips unchanged',
          );

          final EditSession reopened = EditSession(
            document: session.baseDocument,
            docId: session.docId,
            seq: session.seq,
            restored: decoded,
          );
          expect(
            reopened.document,
            session.document,
            reason:
                'the reopened session is the same document: bars, chords, '
                'melody and the two copies of the stroke',
          );
          expect(reopened.document.strokes.length, 2);
          expect(
            reopened.document.strokes.map(
              (InkStroke stroke) => stroke.anchor.bar,
            ),
            <int>[0, 4],
            reason:
                'after a save and a reopen both copies still carry their own '
                'strokes on their own bars',
          );
        },
      );

      test('a bars.insert with its moves survives the codec', () {
        const BarsInsertEvent event = BarsInsertEvent(
          docId: 'doc-1',
          seq: 4,
          sectionId: 'A',
          index: 1,
          bars: <Bar>[Bar(timeSignature: TimeSignature.threeFour)],
          moves: <AnchorMove>[
            AnchorMove(
              kind: AnchorMoveKind.stroke,
              id: 'ink-1',
              from: EventAnchor(sectionId: 'A', bar: 1),
              to: EventAnchor(sectionId: 'A', bar: 2),
            ),
          ],
        );
        final DocumentEvent decoded = EventCodec.decodeLine(
          EventCodec.encodeLine(event),
        );
        expect(decoded, event);
        expect(
          (decoded as ChartEvent).inverse(),
          isA<BarsRemoveEvent>(),
          reason: 'the inverse is the removal, carrying the same run',
        );
      });
    },
  );

  group('the selection is an address and not an entity', () {
    test('two touches make a run, a backwards pair is normalised, and a window '
        'that spans bars becomes the run of bars', () {
      final ChartSelection run = ChartSelection.span(
        sectionId: 'A',
        firstBar: 12,
        lastBar: 5,
      );
      expect(run.firstBar, 5);
      expect(run.lastBar, 12);
      expect(run.barCount, 8);
      expect(run.isWindow, isFalse);

      final ChartSelection window = ChartSelection.span(
        sectionId: 'A',
        firstBar: 4,
        firstX: 3,
        lastBar: 4,
        lastX: 1,
      );
      expect(window.isWindow, isTrue);
      expect(window.firstX, 1);
      expect(window.lastX, 3);
      // A WINDOW'S WIDTH IS THE DISTANCE BETWEEN ITS ENDS. THE OLD ASSERTION, QUOTED:
      // expect(window.windowWidth, 3); — three beats, because a window was a run of cells and the
      // span from x=1 to x=3 covered three of them. The two ends are one pixel apart per pixel now:
      // 3 − 1 = 2.
      expect(window.windowWidth, 2);

      final ChartSelection flattened = ChartSelection.span(
        sectionId: 'A',
        firstBar: 4,
        firstX: 3,
        lastBar: 6,
        lastX: 1,
      );
      expect(
        flattened.isWindow,
        isFalse,
        reason:
            'a window cannot span bars, so extending onto another bar '
            'selects the bars between them',
      );
      expect(flattened.barCount, 3);
    });

    test('the two depths of a single touch are a whole bar and one beat', () {
      expect(
        ChartSelection.span(sectionId: 'A', firstBar: 7, lastBar: 7).depth,
        SelectionDepth.bars,
      );
      expect(
        ChartSelection.span(
          sectionId: 'A',
          firstBar: 7,
          firstX: 2,
          lastBar: 7,
          lastX: 2,
        ).depth,
        SelectionDepth.window,
      );
    });
  });
}
