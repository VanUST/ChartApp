// PURPOSE: Answer the two claims this feature rests on, as measurements rather than as assertions
//          inside the code that makes them: that an entry's interval is a SCENE offset which moves
//          what the chart shows while leaving the chart's own written key alone, and that every
//          setlist operation is exactly undone by its own inverse. It uses the library's real
//          import, spelling and reduction paths, and prints the whole value each time, because
//          "the setlist came back" is a claim only the complete JSON can settle.
// INPUTS: None. The chart is a synthetic iReal payload written in this file, so the probe never
//         reads the owner's export and never opens a window.
// OUTPUTS: Chord renderings for the written and the shown chart, the written key before and after
//          the setlist edits, and, per setlist operation, the whole setlist before, after and after
//          the undo, with the verdict of the comparison. Exits 1 when a claim fails, 0 otherwise.
// KEYWORDS: probe, setlist, scene-transposition, D14, undo, inverse, whole-value, verification
import 'dart:convert';
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// The musical key the synthetic chart is written in, which is what the scene interval is measured
/// from.
const Key _dMajor = Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major);

/// The written chords of the synthetic chart, in reading order, so a transposition can be checked
/// chord by chord rather than only by its key label.
const List<String> _writtenChords = <String>['D^', 'E7', 'D^', 'E7'];

/// The chords the same chart shows under the scene interval this file checks.
const List<String> _shownChords = <String>['E^', 'F#7', 'E^', 'F#7'];

/// The scene interval the entry carries: two semitones up, which is D major to E major.
const int _sceneSemitones = 2;

/// The failures this run found, printed with their detail and used as the exit code.
final List<String> _failures = <String>[];

// PURPOSE: Build the one-song iReal payload this probe transposes, in the export's own ten-field
//          layout, so the chart goes through the same import path the application uses.
// INPUTS: None.
// OUTPUTS: A decoded payload string whose one song is `D^ | E7 | D^ | E7` in D major.
// KEYWORDS: fixture, synthetic-payload, d-major, obfuscation, ten-field-layout
String _syntheticPayload() {
  const String notation = '*AT44D^ |E7 |D^ |E7 Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Test Tune=Test Composer==Medium Swing=D=0=$music=Medium Swing=120=1';
}

// PURPOSE: Read the chord of every bar of [song], in the song's own key, so two charts can be
//          compared by what a musician reads rather than only by the key label.
// INPUTS: song — the chart. key — the key to spell the chords in.
// OUTPUTS: One string per bar, `-` for a bar with no chord.
// KEYWORDS: chord-list, render, comparison, reading-order
List<String> _chordsOf(Song song, Key key) {
  const SpellingTable table = SpellingTable();
  return <String>[
    for (final Bar bar in song.barsInReadingOrder)
      bar.chords.isEmpty ? '-' : bar.chords.first.chord.render(key, table),
  ];
}

// PURPOSE: Record a claim that failed, so the run reports every failure rather than stopping at the
//          first, and the exit code reflects all of them.
// INPUTS: claim — what was being checked. expected and actual — the two values that disagreed.
// OUTPUTS: Nothing.
// KEYWORDS: failure, reporting, all-failures, exit-code
void _fail(String claim, Object? expected, Object? actual) {
  _failures.add(claim);
  stdout.writeln('FAIL $claim\n  expected: $expected\n  actual:   $actual');
}

// PURPOSE: Compare two values the way this probe reports them: scalars by equality, and lists or
//          maps by their JSON, because two Dart Lists are not `==` even when they hold the same
//          elements and a claim stated on the reading would fail on the container.
// INPUTS: expected and actual — the values to compare.
// OUTPUTS: True when they encode the same.
// KEYWORDS: deep-equality, json-compare, list-equality
bool _sameValue(Object? expected, Object? actual) {
  if (expected is List || expected is Map) {
    return jsonEncode(expected) == jsonEncode(actual);
  }
  return expected == actual;
}

// PURPOSE: Check one claim and print it, changing nothing when it holds.
// INPUTS: claim — the words. expected and actual — the values.
// OUTPUTS: Nothing. A mismatch is recorded in [_failures].
// KEYWORDS: check, print, verdict
void _check(String claim, Object? expected, Object? actual) {
  final bool held = _sameValue(expected, actual);
  stdout.writeln(
    'CHECK $claim ${held ? 'OK' : 'FAILED'} expected=$expected actual=$actual',
  );
  if (!held) {
    _fail(claim, expected, actual);
  }
}

// PURPOSE: Prove the SCENE meaning of owner decision D14: the interval on a setlist entry moves what
//          the chart shows and does not touch the chart document's written key.
// INPUTS: None.
// OUTPUTS: Nothing but printed measurements and recorded failures.
// KEYWORDS: scene-transposition, written-key-preserved, setlist-entry, D14
void _probeSceneMeaning() {
  stdout.writeln(
    '=== SCENE MEANING (D14): an entry interval moves what is shown ===',
  );
  final IRealParseResult result = parseIRealPayload(
    _syntheticPayload(),
    documentId: 'chart-d',
  );
  final Song written = result.song;
  _check('the imported chart is written in D major', _dMajor, written.key);
  _check(
    'the written chart reads D^ E7 D^ E7',
    _writtenChords,
    _chordsOf(written, written.key),
  );

  // The entry names the chart by the id the import gave it. The setlist below carries one entry, and
  // its interval is the only transposition in play.
  final Setlist setlist = Setlist(
    id: 'programme-1',
    title: 'Test programme',
    items: <SetlistItem>[
      SetlistItem(documentId: written.id, transposeSem: _sceneSemitones),
    ],
  );
  final SetlistSession session = SetlistSession(setlist: setlist);
  final SetlistScene scene = setlistSceneFor(
    entry: session.setlist.items.single,
    written: written,
  );

  stdout.writeln(
    'scene written=${scene.written.key} shown=${scene.shownKey} '
    'semitones=${scene.semitones} transposed=${scene.isTransposed}',
  );
  stdout.writeln(
    'scene written_chords=${_chordsOf(scene.written, scene.written.key)}',
  );
  stdout.writeln(
    'scene shown_chords=${_chordsOf(scene.shown, scene.shownKey)}',
  );
  // The chart document is `written` itself; nothing about the setlist session touched it. The
  // comparison is against the same value read after the setlist was built, not a copy.
  _check(
    'the chart document still says its written key after the setlist exists',
    _dMajor,
    written.key,
  );
  _check(
    'the shown chart is in E major, two semitones up',
    'E major',
    scene.shownKey.toString(),
  );
  _check(
    'the shown chart reads E^ F#7 E^ F#7',
    _shownChords,
    _chordsOf(scene.shown, scene.shownKey),
  );
  _check(
    'the written chart still reads D^ E7 D^ E7',
    _writtenChords,
    _chordsOf(written, written.key),
  );
  _check(
    'the entry carries the interval as stored',
    _sceneSemitones,
    scene.semitones,
  );
  stdout.writeln('');
}

// PURPOSE: Prove that every setlist operation is undone exactly, by applying one operation to a
//          fresh baseline, undoing it, and comparing the WHOLE setlist value before and after.
// INPUTS: None.
// OUTPUTS: Nothing but printed measurements and recorded failures.
// KEYWORDS: undo, inverse, whole-value, setlist-session, rename, insert, delete, move, update
void _probeUndoPerOperation() {
  stdout.writeln('=== UNDO PER SETLIST OPERATION (whole value compared) ===');
  final Setlist baseline = Setlist(
    id: 'programme-1',
    title: '',
    items: <SetlistItem>[
      const SetlistItem(documentId: 'chart-a', notes: 'count off'),
      const SetlistItem(documentId: 'chart-b', transposeSem: -2),
      const SetlistItem(
        documentId: 'chart-c',
        transposeSem: 3,
        notes: 'ballad',
      ),
    ],
  );

  final List<(String, bool Function(SetlistSession))> operations =
      <(String, bool Function(SetlistSession))>[
        ('rename', (SetlistSession s) => s.rename('Friday night')),
        (
          'insert',
          (SetlistSession s) =>
              s.insertItem(
                const SetlistItem(
                  documentId: 'chart-d',
                  transposeSem: 1,
                  notes: 'encore',
                ),
                index: 1,
              ) !=
              null,
        ),
        ('delete', (SetlistSession s) => s.deleteItem(1)),
        ('move', (SetlistSession s) => s.moveItem(0, 2)),
        (
          'update-transposition-and-notes',
          (SetlistSession s) =>
              s.updateItem(0, transposeSem: -3, notes: 'slower'),
        ),
      ];

  for (final (String name, bool Function(SetlistSession) run) in operations) {
    final SetlistSession session = SetlistSession(setlist: baseline);
    final Setlist before = session.setlist;
    final String beforeJson = jsonEncode(before.toJson());
    final bool applied = run(session);
    final Setlist after = session.setlist;
    final String afterJson = jsonEncode(after.toJson());
    stdout.writeln('--- $name ---');
    if (!applied) {
      _fail('$name applied', true, false);
    }
    stdout.writeln('before $beforeJson');
    stdout.writeln('after  $afterJson');
    if (after == before) {
      _fail('$name must change the setlist', 'a different setlist', afterJson);
    }
    final String undoLogBefore = jsonEncode(
      session.log.map((SetlistEvent e) => e.type).toList(),
    );
    final bool undone = session.undo();
    final Setlist restored = session.setlist;
    final String restoredJson = jsonEncode(restored.toJson());
    stdout.writeln('undone $restoredJson');
    stdout.writeln(
      'log=${jsonEncode(session.log.map((SetlistEvent e) => e.type).toList())} '
      'undo=$undone depth_undo=${session.undoDepth} depth_redo=${session.redoDepth}',
    );
    _check('$name undo reports an edit was undone', true, undone);
    _check(
      '$name undo restores the whole setlist value',
      true,
      restored == before,
    );
    if (restoredJson != beforeJson) {
      _fail(
        '$name undo restores the whole setlist value',
        beforeJson,
        restoredJson,
      );
    }
    // Redo must put the edited value back, which is the other half of the same claim.
    final bool redone = session.redo();
    _check(
      '$name redo re-applies the edit',
      true,
      redone && session.setlist == after,
    );
    stdout.writeln(
      'redo_log_added=${jsonEncode(session.log.map((SetlistEvent e) => e.type).toList())} '
      'jsonl_tail=${session.log.length} (before this op: $undoLogBefore)',
    );
  }
  stdout.writeln('');
}

void main() {
  _probeSceneMeaning();
  _probeUndoPerOperation();
  if (_failures.isEmpty) {
    stdout.writeln('SUMMARY claims_failed=0');
    exit(0);
  }
  stdout.writeln('SUMMARY claims_failed=${_failures.length}');
  for (final String failure in _failures) {
    stdout.writeln('FAILED: $failure');
  }
  exit(1);
}
