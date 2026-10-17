// PURPOSE: Print what a row of UNEQUAL bars is engraved into — each bar's rectangle, its cell
//          columns, its chords' x positions, its melody notes' x positions — before and after one
//          bar is given a size, and then print what a tap and a stroke on that resized bar resolve
//          to, plus the save/undo/redo round trip of the stored value. It exists because the width
//          of a bar is the number the whole coordinate system hangs on (A33, A47): a claim that the
//          engraving honours a per-bar size is worth nothing unless the numbers that derive from it
//          are shown to move together.
// INPUTS: An optional page width in logical pixels (default 1269, one of the tablet's measured
//         content widths), and an optional ladder rung to apply (default 1.5).
// OUTPUTS: Lines on stdout, each naming what it measured. Nothing is written to disk and nothing
//          needs a device or a Flutter binding: the engraver, the hit test and the ink anchor are
//          all pure `chart_core`, which is the reason this instrument can be re-run by anyone.
//          It prints a `probe.verdict` line at the end whose `ok` field is the conjunction of the
//          claims the report rests on, so a reader does not have to compare the numbers by eye.
// KEYWORDS: probe, bar-size, width, cell-column, chord-x, notehead-x, hit-test, ink-anchor,
//           undo, redo, save-reopen, identity, not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// The section every bar of the fixture sits in, so an address can be written without a lookup.
const String _section = 'A';

/// The index of the BUSY bar: the one holding six chords, a run of eighths and a flat.
const int _busyBar = 1;

void main(List<String> args) {
  final double pageWidth = args.isNotEmpty ? double.parse(args.first) : 1269;
  final double rung = args.length > 1
      ? double.parse(args[1])
      : const BarSize(1.5).factor;

  final Song written = _unequalChart();
  final EditSession session = EditSession(
    document: DocumentState(song: written),
  );
  stdout.writeln(
    'probe.chart title="${written.title}" page_width=$pageWidth '
    'rung=$rung bars=${written.writtenBarCount}',
  );

  _report('before', session, pageWidth);
  final bool applied = session.setBarSize(
    sectionId: _section,
    barIndex: _busyBar,
    size: BarSize(rung),
  );
  stdout.writeln(
    'probe.size.set applied=$applied section=$_section bar=$_busyBar '
    'from=1.0 to=$rung seq=${session.log.length}',
  );
  _report('after', session, pageWidth);

  _reportAnchors(session, pageWidth);

  final bool undoes = session.undo();
  final Bar? afterUndo = session.song.barAt(_section, _busyBar);
  stdout.writeln(
    'probe.undo done=$undoes stored=${afterUndo?.size.factor} '
    'undo_depth=${session.undoDepth} redo_depth=${session.redoDepth}',
  );
  final bool redoes = session.redo();
  final Bar? afterRedo = session.song.barAt(_section, _busyBar);
  stdout.writeln(
    'probe.redo done=$redoes stored=${afterRedo?.size.factor} '
    'undo_depth=${session.undoDepth} redo_depth=${session.redoDepth}',
  );

  _reportRoundTrip(session, written, rung);

  final bool ok =
      applied &&
      undoes &&
      afterUndo?.size.factor == 1 &&
      redoes &&
      afterRedo?.size.factor == rung;
  stdout.writeln('probe.verdict ok=$ok');
  if (!ok) {
    exitCode = 1;
  }
}

// PURPOSE: Print one engraving of the session's chart: every bar's rectangle, and for the busy bar
//          the cell columns, the chords' x positions and the melody noteheads' x positions relative
//          to that bar's own left edge — which is the same number the hit test and the ink anchor
//          read.
// INPUTS: label — the word printed on every line so two runs can be told apart. session — the
//         document as it stands. pageWidth — the page to engrave at.
// OUTPUTS: Nothing; it writes to stdout. One line per bar, and a second line for the busy bar's
//          columns. A chart with no bars prints no bar line, and the caller sees that rather than
//          an exception.
// KEYWORDS: probe-report, bar-rect, cell-column, chord-x, notehead-x, before-after
void _report(String label, EditSession session, double pageWidth) {
  final Song song = session.song;
  // A tall page, so the whole fixture stays on one system and the measurement is about the row's
  // horizontal arithmetic rather than about pagination.
  final LayoutEngine engine = const LayoutEngine();
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: pageWidth,
    pageHeight: 20000,
  );
  stdout.writeln(
    'probe.layout $label pages=${pages.length} '
    'systems=${pages.isEmpty ? 0 : pages.first.systems.length}',
  );
  if (pages.isEmpty) {
    return;
  }
  for (final PlacedBar bar in pages.first.bars) {
    final Bar? model = song.barAt(bar.sectionId, bar.barIndex);
    stdout.writeln(
      'probe.bar $label ${bar.sectionId}#${bar.barIndex} '
      'x=${_n(bar.bounds.left)} y=${_n(bar.bounds.top)} '
      'w=${_n(bar.bounds.size.width)} h=${_n(bar.bounds.size.height)} '
      'size=${model?.size.factor} cells=${bar.cells.length} '
      'chords=${bar.chords.length}',
    );
    final StringBuffer columns = StringBuffer();
    for (final PlacedCell cell in bar.cells) {
      columns.write(
        ' ${cell.beat}:${_n(cell.bounds.left - bar.bounds.left)}'
        '+${_n(cell.bounds.size.width)}',
      );
    }
    stdout.writeln(
      'probe.cells $label ${bar.sectionId}#${bar.barIndex}$columns',
    );
    final StringBuffer chords = StringBuffer();
    for (final PlacedChord chord in bar.chords) {
      chords.write(
        ' ${chord.beat}.${chord.step}@${_n(chord.bounds.left - bar.bounds.left)}'
        '(${chord.bounds.size.width.toStringAsFixed(1)})',
      );
    }
    stdout.writeln(
      'probe.chords $label ${bar.sectionId}#${bar.barIndex}$chords',
    );
    final StringBuffer heads = StringBuffer();
    for (final MelodyGlyph glyph in bar.melody.glyphs) {
      if (glyph.kind != MelodyGlyphKind.notehead) {
        continue;
      }
      heads.write(' @${_n(glyph.bounds.left - bar.bounds.left)}');
    }
    stdout.writeln(
      'probe.noteheads $label ${bar.sectionId}#${bar.barIndex}$heads',
    );
  }
}

// PURPOSE: Print what a touch and a stroke on the RESIZED bar resolve to — the bar the hit test
//          names and the anchor an ink stroke is stored against — because a green engraving proves
//          nothing about either, and the previous change to this file's subject failed exactly here.
// INPUTS: session — the document with the busy bar resized. pageWidth — the page to engrave at.
// OUTPUTS: Nothing; writes to stdout. The probe aims at three points of the resized bar: its centre,
//          its first cell's centre, and one point inside its LAST column, and prints the address each
//          one names. A point that names a different bar than the one it was aimed at would be
//          printed as such rather than raising, so a failure is read rather than thrown.
// KEYWORDS: probe-report, hit-test, tap, ink-anchor, resized-bar, address-agreement
void _reportAnchors(EditSession session, double pageWidth) {
  final List<PageLayout> pages = const LayoutEngine().layout(
    session.song,
    pageWidth: pageWidth,
    pageHeight: 20000,
  );
  if (pages.isEmpty) {
    return;
  }
  final PageLayout page = pages.first;
  final PlacedBar? resized = _barOf(page, _busyBar);
  if (resized == null) {
    return;
  }
  final List<LayoutOffset> aims = <LayoutOffset>[
    LayoutOffset(
      resized.bounds.left + resized.bounds.size.width / 2,
      resized.bounds.top + resized.bounds.size.height / 2,
    ),
    LayoutOffset(
      resized.cells.first.bounds.left +
          resized.cells.first.bounds.size.width / 2,
      resized.bounds.top + resized.bounds.size.height / 2,
    ),
    LayoutOffset(
      resized.cells.last.bounds.left + resized.cells.last.bounds.size.width / 2,
      resized.bounds.top + resized.bounds.size.height / 2,
    ),
  ];
  for (final LayoutOffset aim in aims) {
    final ChartHit? hit = hitTestPage(page, aim);
    final InkAnchorChoice? choice = resolveInkAnchor(page, aim);
    stdout.writeln(
      'probe.tap aim=(${_n(aim.x)},${_n(aim.y)}) '
      'hit=${hit == null ? 'none' : '${hit.sectionId}#${hit.barIndex}'} '
      'beat=${hit?.beat} '
      'ink=${choice == null ? 'none' : '${choice.placement.anchor.sectionId}'
                '#${choice.placement.anchor.bar}/${choice.basis.name}'}',
    );
  }
  // The staff is a SECOND surface over the same bar, and its columns come from the same cell
  // rectangles, so the busiest bar is aimed at there too: a column that moved on the chord line and
  // not on the staff would put a note in a different beat from the chord above it.
  final LayoutRect staff = resized.melody.bounds;
  if (!resized.melody.isEmpty) {
    for (final PlacedCell cell in resized.cells) {
      final LayoutOffset aim = LayoutOffset(
        cell.bounds.left + cell.bounds.size.width / 2,
        staff.top + staff.size.height / 2,
      );
      final ChartHit? staffHit = hitTestMelodyStaff(page, aim);
      stdout.writeln(
        'probe.staff aim=(${_n(aim.x)},${_n(aim.y)}) '
        'hit=${staffHit == null ? 'none' : '${staffHit.sectionId}'
                  '#${staffHit.barIndex}'} '
        'beat=${staffHit?.beat}',
      );
    }
  }
}

// PURPOSE: Print the round trip the requirement names: the value survives a save and a reopen, its
//          event survives the JSON codec, and the identity of the chart does NOT move when a bar is
//          resized — because a layout change must not detach a chart from the programme that names it.
// INPUTS: session — the document with the busy bar resized. written — the same chart before the
//         edit, for the identity comparison. rung — the factor the bar now carries.
// OUTPUTS: Nothing; writes to stdout. The stored factor is read from `ModelJson`/`EventCodec` and
//          from the document, never from the picture, which is the whole point of the check.
// KEYWORDS: probe-report, save-reopen, codec, identity, stored-value, not-the-picture
void _reportRoundTrip(EditSession session, Song written, double rung) {
  final Bar? stored = session.song.barAt(_section, _busyBar);
  final Map<String, Object?> barJson = ModelJson.bar(stored!);
  final Bar reopened = ModelJson.decodeBar(barJson);
  final ChartEvent forward = BarSizeSetEvent(
    docId: session.docId,
    seq: 1,
    sectionId: _section,
    barIndex: _busyBar,
    from: BarSize.natural,
    to: BarSize(rung),
  );
  final DocumentEvent decoded = EventCodec.decode(
    EventJson.decodeObject(EventCodec.encodeLine(forward)),
  );
  stdout.writeln(
    'probe.save stored=${stored.size.factor} json=${barJson['size']} '
    'reopened=${reopened.size.factor} '
    'equal=${reopened == stored}',
  );
  stdout.writeln(
    'probe.codec type=${decoded.type} '
    'from=${decoded is BarSizeSetEvent ? decoded.from.factor : 'n/a'} '
    'to=${decoded is BarSizeSetEvent ? decoded.to.factor : 'n/a'} '
    'inverse=${decoded.inverse() is BarSizeSetEvent ? (decoded.inverse() as BarSizeSetEvent).to.factor : 'n/a'} '
    'equal=${decoded == forward}',
  );
  stdout.writeln(
    'probe.identity before=${chartIdentityOf(written)} '
    'after=${chartIdentityOf(session.song)} '
    'same=${chartIdentityOf(written) == chartIdentityOf(session.song)}',
  );
  // A bar that never carries a size must produce exactly the bytes it produced before the property
  // existed, which is what keeps every identity already written into a setlist resolving.
  stdout.writeln(
    'probe.identity.natural json_has_size='
    '${ModelJson.bar(written.sections.first.bars.first).containsKey('size')} '
    'canonical_has_size=${canonicalChartContent(written).toString().contains('size')}',
  );
}

/// Returns the placed bar at [barIndex] of section [_section], or null when the page has none.
///
/// A linear walk over one page's bars, because the probe holds one short fixture and a page has one
/// row of it: an index would have to be kept in step with a layout the probe is measuring.
PlacedBar? _barOf(PageLayout page, int barIndex) {
  for (final PlacedBar bar in page.bars) {
    if (bar.sectionId == _section && bar.barIndex == barIndex) {
      return bar;
    }
  }
  return null;
}

/// Formats [value] to one decimal place, which is the resolution every engraved coordinate is read
/// at: a tenth of a logical pixel is a number a reader can compare against another run.
String _n(double value) => value.toStringAsFixed(1);

// PURPOSE: Build the fixture the whole probe reasons about — a row of bars whose contents are as
//          unequal as a jazz chart's are, so the difference between "every bar gets the same width"
//          and "the width follows the music" is visible in the numbers.
// INPUTS: None.
// OUTPUTS: A one-section chart of four bars in C major with a declared pitched staff: an empty bar,
//          a bar holding six chords including a flat and a run of eighths in the melody, a bar with
//          one chord, and a bar with one chord on beat 3. The result is a const-like literal with no
//          clock, no file and no random seed, so two runs print the same numbers.
// KEYWORDS: fixture, unequal-bars, busy-bar, empty-bar, chords, melody, deterministic
Song _unequalChart() {
  const WrittenNote eFlat = WrittenNote(NoteLetter.e, -1);
  const WrittenNote g = WrittenNote(NoteLetter.g, 0);
  const WrittenNote bFlat = WrittenNote(NoteLetter.b, -1);
  const WrittenNote d = WrittenNote(NoteLetter.d, 0);
  const WrittenNote fSharp = WrittenNote(NoteLetter.f, 1);
  const WrittenNote a = WrittenNote(NoteLetter.a, 0);
  const NoteValue quarter = NoteValue.plain(NoteBase.quarter);
  const NoteValue eighth = NoteValue.plain(NoteBase.eighth);

  Bar chord(String token, int rootSemitones, int beat, {int step = 0}) => Bar(
    chords: <ChordMark>[
      ChordMark(
        place: cellAt(beat, step),
        chord: Chord(
          root: ChordRoot(rootSemitones),
          quality: ChordQuality(token),
        ),
      ),
    ],
  );

  return Song(
    id: 'probe-bar-size',
    title: 'Unequal Bars',
    key: Key.cMajor,
    staffSet: const StaffSet(pitched: StaffSpec.pitched()),
    sections: <Section>[
      Section(
        id: _section,
        label: SectionLabel.letter('A'),
        bars: <Bar>[
          // An EMPTY bar: nothing but four cells' worth of room.
          const Bar(),
          // THE BUSY BAR: six chords packed into four cells, a flat, and four eighths on the staff.
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: cellAt(0),
                chord: Chord(root: ChordRoot(0), quality: ChordQuality('maj7')),
              ),
              ChordMark(
                place: cellAt(0, 1),
                chord: Chord(root: ChordRoot(9), quality: ChordQuality('m7')),
              ),
              ChordMark(
                place: cellAt(1),
                chord: Chord(root: ChordRoot(2), quality: ChordQuality('m7b5')),
              ),
              ChordMark(
                place: cellAt(2),
                chord: Chord(root: ChordRoot(7), quality: ChordQuality('7')),
              ),
              ChordMark(
                place: cellAt(3),
                chord: Chord(root: ChordRoot(5), quality: ChordQuality('maj7')),
              ),
              ChordMark(
                place: cellAt(3, 1),
                chord: Chord(root: ChordRoot(10), quality: ChordQuality('7')),
              ),
            ],
            melody: <NoteMark>[
              NoteMark(
                place: cellAt(0),
                pitch: PitchedNote(note: eFlat, octave: 4),
                value: eighth,
              ),
              NoteMark(
                place: cellAt(0, 1),
                pitch: PitchedNote(note: g, octave: 4),
                value: eighth,
              ),
              NoteMark(
                place: cellAt(1),
                pitch: PitchedNote(note: bFlat, octave: 4),
                value: eighth,
              ),
              NoteMark(
                place: cellAt(1, 1),
                pitch: PitchedNote(note: d, octave: 5),
                value: eighth,
              ),
              NoteMark(
                place: cellAt(2),
                pitch: PitchedNote(note: fSharp, octave: 5),
                value: quarter,
              ),
              NoteMark(
                place: cellAt(3),
                pitch: PitchedNote(note: a, octave: 5),
                value: quarter,
              ),
            ],
          ),
          // A bar with one chord: the ordinary bar this feature must leave alone.
          chord('maj7', 5, 0),
          // A bar whose only chord is on beat 3, so a column that is not the first is exercised.
          chord('7', 7, 2),
        ],
      ),
    ],
  );
}
