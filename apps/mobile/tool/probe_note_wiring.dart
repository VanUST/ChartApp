// PURPOSE: Prove what the NOTE READER DOES WHEN THE APPLICATION DRIVES IT, on this machine, without a
//          tablet and without a window — by driving the SAME path a stylus does: begin a contact,
//          add samples, end it, and read what the layer, the log and the page say afterwards.
//
//          WHAT IT IS NOT, AND THE DISTINCTION IS THE POINT OF THIS PARAGRAPH. It is not a proof that
//          note recognition is switched on in the application, because it is not: the owner removed
//          the quantised shape a recognised note would be written in (`(beat, step, pitch)`), so the
//          call on stroke commit is deferred and recorded at its call site in `ink_layer.dart`. This
//          instrument therefore calls `recogniseMelodyNotes` DIRECTLY, which is exactly what the
//          deferred call site will do, so that the machinery behind the switch is measured now and
//          is two lines from being armed later.
//
//          WHY AN INSTRUMENT AND NOT A TEST. A test says "this passed"; this says WHAT HAPPENED, in
//          the numbers the tablet would print: how many notes the bar holds, which ink the screen
//          has been told to hide, what the rejected note did, and whether the switch being off
//          leaves the document at zero. It is run by hand:
//
//              flutter test tool/probe_note_wiring.dart
//
//          WHAT IT COVERS. (1) RECOGNITION OFF: a notehead drawn on the staff writes ink only, and
//          no note appears. (2) RECOGNITION ON: a pass over that ink becomes ONE STRUCTURED NOTE at
//          the pitch its position names, and the ink it came from is named by
//          `recognisedNoteStrokeIds` so the screen can hide exactly it. (3) THE SAME INK TWICE: a
//          second pass writes nothing. (4) REJECTION: one call deletes the note, gives the ink back,
//          and the next pass does not write it again. (5) A CHORD SYMBOL drawn in the chord row
//          above the staff becomes NO note, which is the false-positive direction the reader was
//          measured on.
//
//          THE INK IS A RING, built here at the head's own size rather than traced from the
//          engraver, because this instrument is about the MACHINERY and not about the reader (whose
//          numbers are `packages/chart_core/tool/probe_note_reader.dart`). The ring is still the
//          figure the shape gates were measured against: an ellipse one notehead wide and tall.
// INPUTS: None. The song is built here with a declared pitched staff, so the page draws one.
// OUTPUTS: `probe.wire.*` lines on stdout and exit code 0. A line whose last field is `ok` is a
//          check that held; `FAILED` names the number that did not.
// KEYWORDS: probe, note-recognition, ink-layer, op-log, rejection, d37, headless, call-site-deferred,
//           not-part-of-the-suite
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ink_layer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// The layout style the application itself lays out with, so the geometry measured here is the
/// geometry a musician is given rather than one invented for the probe.
const LayoutEngine engine = LayoutEngine(
  style: LayoutStyle(
    textMetrics: FlutterTextMetrics(),
    pageMargin: 20,
    barMinWidth: 64,
    barPadding: 8,
    chordSpacing: 12,
    minCellWidth: 18,
    barHeight: 52,
    systemSpacing: 18,
    sectionLabelHeight: 26,
  ),
);

/// The surface the probe draws on, matching the shape of a tablet's chart area.
const double surfaceWidth = 800;
const double surfaceHeight = 700;

/// A one-bar 4/4 song with a declared treble staff (D29), so the page engraves one.
Song probeSong() => Song(
  id: 'probe-note-wiring',
  title: 'wiring',
  composer: '',
  style: '',
  key: Key.cMajor,
  tempo: 120,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'sec-1',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[Bar()],
    ),
  ],
);

/// Counts the notes the document holds, so a check reads as music rather than as a boolean.
int noteCount(EditSession session) {
  int notes = 0;
  for (final Section section in session.song.sections) {
    for (final Bar bar in section.bars) {
      notes += bar.melody.length;
    }
  }
  return notes;
}

/// Every note of the document as `beat.step:pitch`, which is the address a musician would name.
List<String> notesOf(EditSession session) => <String>[
  for (final Section section in session.song.sections)
    for (final Bar bar in section.bars)
      for (final NoteMark note in bar.melody)
        '${note.offsetX.toStringAsFixed(1)}:${note.pitch}',
];

/// The page-space centre of the staff step [step] in column [beat] of the page's first bar.
///
/// The frame the reader itself uses is consulted, so the position drawn here is the position the
/// reader will decode: a mismatch between the two would make this instrument lie about the reader.
LayoutOffset targetOf(PageLayout page, {int beat = 0, int step = 4}) {
  final PlacedBar bar = page.bars.first;
  final MelodyStaffFrame frame = melodyFramesOfPage(
    page,
  )['${bar.sectionId}\u0000${bar.barIndex}']!;
  // THE BAR'S OWN EXTENT, not a column: the frame publishes where the bar reaches, and a touch
  // anywhere between those two x values is on its staff.
  final MelodyStaffFrame column = frame;
  final double middle = frame.middleLineY;
  final double space = frame.staffSpace;
  return LayoutOffset(
    (column.barLeft + column.barRight) / 2,
    middle + (4 - step) * (space / 2),
  );
}

/// Draws one notehead-shaped ring as a REAL stylus contact through the layer, at [pagePoint].
///
/// It goes through [InkCaptureLayer.beginStroke], [InkCaptureLayer.addSample] and
/// [InkCaptureLayer.endStroke] rather than appending an event, because the wiring under test is
/// exactly what happens at the end of that contact: recognition runs there and nowhere else.
void drawRing(
  InkCaptureLayer layer,
  PageLayout page, {
  required LayoutOffset pagePoint,
  required int pointer,
  required double radiusX,
  required double radiusY,
}) {
  final LayoutOffset surface = page.surfacePointOf(pagePoint);
  final bool opened = layer.beginStroke(
    pointer: pointer,
    page: page,
    kind: PointerDeviceKind.stylus,
    position: surface,
    pressure: 1,
    time: 0,
  );
  if (!opened) {
    throw StateError('the layer refused the stroke at $surface');
  }
  for (int index = 1; index <= 24; index++) {
    final double angle = index * math.pi / 12;
    final LayoutOffset point = LayoutOffset(
      pagePoint.x + radiusX * math.cos(angle),
      pagePoint.y + radiusY * math.sin(angle),
    );
    layer.addSample(
      pointer: pointer,
      page: page,
      position: page.surfacePointOf(point),
      pressure: 1,
      time: index.toDouble(),
    );
  }
  layer.endStroke(pointer: pointer, page: page);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the note reader machinery behind the recognition switch', () {
    final Song song = probeSong();
    final EditSession session = EditSession(
      document: DocumentState(song: song),
      docId: song.id,
    );
    final InkCaptureLayer layer = InkCaptureLayer(session: session);
    final List<PageLayout> pages = engine.layout(
      song,
      pageWidth: surfaceWidth,
      pageHeight: surfaceHeight,
    );
    final PageLayout page = pages.first;
    final PlacedBar bar = page.bars.first;
    final MelodyStaffFrame frame = melodyFramesOfPage(
      page,
    )['${bar.sectionId}\u0000${bar.barIndex}']!;
    final double headWidth = frame.headWidth;
    print(
      'probe.wire.frame section=${bar.sectionId} bar=${bar.barIndex} '
      'width=${frame.barRight - frame.barLeft} '
      'space=${frame.staffSpace} head=${headWidth.toStringAsFixed(1)} '
      'window=${frame.headTop.toStringAsFixed(1)}..'
      '${frame.headBottom.toStringAsFixed(1)}',
    );

    // (1) RECOGNITION OFF: the ink is written and nothing is read. This is the state every chart
    // starts in, and the state in which the page must be what it was before the feature existed.
    final LayoutOffset c5 = targetOf(page, beat: 0, step: 5);
    drawRing(
      layer,
      page,
      pagePoint: c5,
      pointer: 1,
      radiusX: headWidth / 2 - 1.1,
      radiusY: frame.headHeight / 2 - 1.1,
    );
    print(
      'probe.wire.off strokes=${session.document.strokes.length} '
      'notes=${noteCount(session)} hidden=${layer.recognisedNoteStrokeIds.length} '
      '${session.document.strokes.length == 1 && noteCount(session) == 0 && layer.recognisedNoteStrokeIds.isEmpty ? 'ok' : 'FAILED'}',
    );

    // (2) RECOGNITION ON, and the SAME ink read by a whole-page pass — which is what the switch
    // does when it is turned on: the musician must not have to write everything again.
    layer.recognitionEnabled = true;
    layer.recogniseMelodyNotes(page);
    print(
      'probe.wire.on notes=${noteCount(session)} ${notesOf(session)} '
      'hidden=${layer.recognisedNoteStrokeIds.length} '
      'strokes=${session.document.strokes.length} seq=${session.seq} '
      '${noteCount(session) == 1 && notesOf(session).first == '0.0:C5' && layer.recognisedNoteStrokeIds.length == 1 ? 'ok' : 'FAILED'}',
    );
    print(
      'probe.wire.hidden ids=${layer.recognisedNoteStrokeIds.join(',')} '
      'document=${session.document.strokes.map((InkStroke stroke) => stroke.id).join(',')} '
      '${layer.recognisedNoteStrokeIds.length == 1 && session.document.strokes.length == 1 ? 'ok — the ink is hidden, not deleted' : 'FAILED'}',
    );

    // (3) THE SAME INK TWICE writes nothing: commit-time recognition runs on every stroke, so a
    // second pass must be a no-op and not a second copy of the music.
    final int seqBefore = session.seq;
    layer.recogniseMelodyNotes(page);
    print(
      'probe.wire.idempotent notes=${noteCount(session)} '
      'seq_before=$seqBefore seq_after=${session.seq} '
      '${noteCount(session) == 1 && session.seq == seqBefore ? 'ok' : 'FAILED'}',
    );

    // (4) REJECTION: one tap on the ink the note came from. The note goes, the handwriting comes
    // back, and a pass over the same ink does not put it back.
    final String? what = layer.rejectRecognisedNoteAt(
      page: page,
      surfacePoint: page.surfacePointOf(c5),
    );
    print(
      'probe.wire.reject what=$what notes=${noteCount(session)} '
      'hidden=${layer.recognisedNoteStrokeIds.length} '
      'strokes=${session.document.strokes.length} '
      '${what == 'rejected' && noteCount(session) == 0 && layer.recognisedNoteStrokeIds.isEmpty && session.document.strokes.length == 1 ? 'ok' : 'FAILED'}',
    );
    layer.recogniseMelodyNotes(page);
    print(
      'probe.wire.reject.again notes=${noteCount(session)} '
      'hidden=${layer.recognisedNoteStrokeIds.length} '
      '${noteCount(session) == 0 ? 'ok — the rejected address is remembered' : 'FAILED'}',
    );
    session.undo();
    print(
      'probe.wire.reject.undo notes=${noteCount(session)} '
      'undoDepth=${session.undoDepth} '
      '${noteCount(session) == 1 ? 'ok — undo puts the recognised note back' : 'FAILED'}',
    );

    // (5) A CHORD SYMBOL ABOVE THE STAFF IS NOT A NOTE. Drawn in the chord row, where the drummer's
    // words and the musician's symbols live, it must yield no note at all: the place gate is the
    // only thing that separates his symbols from noteheads (A78 §6).
    final LayoutOffset chordRow = LayoutOffset(
      targetOf(page, beat: 1, step: 4).x,
      bar.bounds.top + bar.bounds.size.height / 2,
    );
    drawRing(
      layer,
      page,
      pagePoint: chordRow,
      pointer: 2,
      radiusX: headWidth / 2 - 1.1,
      radiusY: frame.headHeight / 2 - 1.1,
    );
    print(
      'probe.wire.chordrow notes=${noteCount(session)} '
      'strokes=${session.document.strokes.length} '
      '${noteCount(session) == 1 ? 'ok — no note from the chord row' : 'FAILED'}',
    );
  });
}
