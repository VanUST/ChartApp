// PURPOSE: Produce the evidence the `.setlist` container and the chart identity have to stand on: a
//          programme encodes and decodes back to an equal programme, a damaged file fails with the
//          typed failure it should and NEVER arrives as an empty programme, a file written by a
//          newer build is read for what it understands, and the identity is shown to be a fact about
//          the music rather than about the position or the title. A codec and its own round-trip
//          test agree with each other by construction, so this probe prints the values it compared
//          and the exact messages it received rather than a single "ok".
// INPUTS: None. Every fixture is built here; nothing is read from the network or from a device.
// OUTPUTS: One block per check on stdout, then a summary line and an exit code: 0 when every check
//          held, 1 when one did not. A check that is supposed to fail prints the exception TYPE and
//          MESSAGE it caught, so a raw `FormatException` or `RangeError` escaping the codec is
//          visible as exactly that, and a damaged file that decoded to an empty programme is
//          reported as `DID NOT FAIL` rather than passing.
// KEYWORDS: probe, setlist-file, container, identity, round-trip, truncation, corruption,
//           forward-compatibility, evidence, not-part-of-the-library
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

int _failures = 0;
int _checks = 0;

void main() {
  _roundTrips();
  _identityAlgebra();
  _corruptionFailures();
  _newerWriter();
  _crossFormat();
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

// ---------------------------------------------------------------------------------------------
// Round trips
// ---------------------------------------------------------------------------------------------

/// A two-bar chart in D major, the shape an import produces.
Song _song({String title = 'Test Tune'}) => Song(
  id: 'ireal-0',
  title: title,
  composer: 'Test Composer',
  style: 'Medium Swing',
  key: const Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
  tempo: 120,
  sections: <Section>[
    Section(
      id: 's1',
      label: SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          chords: <ChordMark>[
            ChordMark(
              place: cellAt(0),
              chord: Chord(root: ChordRoot(2)),
            ),
          ],
        ),
        Bar(
          chords: <ChordMark>[
            ChordMark(
              place: cellAt(0),
              chord: Chord(root: ChordRoot(9)),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// The setlist fixture every setlist check below starts from.
Setlist _setlist() => Setlist(
  id: 'playlist-Set 1',
  title: 'First set',
  items: <SetlistItem>[
    SetlistItem(
      documentId: 'ireal-0',
      chartIdentity: chartIdentityOf(_song()),
      notes: 'count off',
    ),
    const SetlistItem(documentId: 'ireal-1', transposeSem: -2),
  ],
);

void _roundTrips() {
  _section('round trips');
  const SetlistFile empty = SetlistFile(
    metadata: SetlistMetadata(docId: 'playlist-empty', writer: 'probe'),
    snapshot: Setlist(id: 'playlist-empty'),
  );
  final SetlistFileEncodeResult emptyBytes = SetlistFileCodec.encode(empty);
  stdout.writeln(
    'empty: bytes=${emptyBytes.bytes.length} warnings=${emptyBytes.warnings.length}',
  );
  final SetlistFileDecodeResult emptyBack = SetlistFileCodec.decode(
    emptyBytes.bytes,
  );
  _same('empty: encoded file == decoded file', empty, emptyBack.file);
  _same('empty: no warnings', 0, emptyBack.warnings.length);
  _same(
    'empty: the file begins with the shared magic',
    true,
    _startsWithMagic(emptyBytes.bytes),
  );

  final Setlist programme = _setlist();
  final SetlistFile file = SetlistFile(
    metadata: SetlistMetadata(
      docId: programme.id,
      writer: 'probe',
      createdAt: DateTime.utc(2026, 10, 11, 9),
    ),
    snapshot: programme,
  );
  final SetlistFileDecodeResult decoded = SetlistFileCodec.decode(
    SetlistFileCodec.encode(file).bytes,
  );
  _same('one: encoded file == decoded file', file, decoded.file);
  _same(
    'one: the first entry carries the chart identity',
    chartIdentityOf(_song()),
    decoded.file.snapshot.items.first.chartIdentity,
  );
  stdout.writeln(
    'one: entries=${decoded.file.snapshot.items.length} '
    'identity=${decoded.file.snapshot.items.first.chartIdentity}',
  );

  // The tail a save actually writes: the snapshot is the value BEFORE the operations.
  final SetlistSession session = SetlistSession(setlist: programme);
  _same('tail: the programme was renamed', true, session.rename('Friday'));
  _same(
    'tail: an entry was inserted',
    true,
    session.insertItem(
          SetlistItem(
            documentId: 'ireal-2',
            chartIdentity: chartIdentityOf(_songEdited()),
          ),
        ) !=
        null,
  );
  _same('tail: an entry was moved', true, session.moveItem(2, 0));
  _same(
    'tail: an entry was updated',
    true,
    session.updateItem(0, transposeSem: 3, notes: 'shout'),
  );
  final SetlistFile withTail = SetlistFile(
    metadata: SetlistMetadata(docId: session.docId, writer: 'probe'),
    snapshot: session.baseSetlist,
    events: session.log,
  );
  final SetlistFileDecodeResult tailBack = SetlistFileCodec.decode(
    SetlistFileCodec.encode(withTail).bytes,
  );
  _same('tail: encoded file == decoded file', withTail, tailBack.file);
  _same(
    'tail: the operations are the ones that were made',
    session.log.length,
    tailBack.file.events.length,
  );
  _same('tail: no warnings on a clean file', 0, tailBack.warnings.length);
  final Setlist reopened = tailBack.file.reducedSetlist;
  _same(
    'tail: REOPENED_PROGRAMME_EQUAL the reopened programme is the saved one',
    true,
    reopened == session.setlist,
  );
  stdout.writeln(
    'tail: operations=${tailBack.file.events.length} '
    'types=${tailBack.file.events.map((SetlistEvent e) => e.type).toList()} '
    'reopened_title="${reopened.title}" '
    'reopened_entries=${reopened.items.length} '
    'first=${reopened.items.first}',
  );
}

// ---------------------------------------------------------------------------------------------
// The identity
// ---------------------------------------------------------------------------------------------

void _identityAlgebra() {
  _section('the identity is a fact about the music');
  final Song written = _song();
  final String identity = chartIdentityOf(written);
  stdout.writeln('identity=$identity');
  stdout.writeln('subject=${jsonEncode(canonicalChartContent(written))}');
  _same('stable: the same song twice', identity, chartIdentityOf(_song()));
  _same(
    'stable across POSITION: the same music under another document id',
    identity,
    chartIdentityOf(_songWithId('ireal-7')),
  );
  _same(
    'stable across RENAME: the title is not part of the subject',
    identity,
    chartIdentityOf(_song(title: 'Renamed by the musician')),
  );
  _same(
    'stable across the metadata block: composer, style and tempo too',
    identity,
    chartIdentityOf(_songWithMetadata('Someone Else', 'Ballad', 88)),
  );
  _same(
    'NOT STABLE against an edit: one chord changed is a different identity',
    false,
    chartIdentityOf(_songEdited()) == identity,
  );
  _same('the identity names its algorithm', true, isChartIdentity(identity));
  _same('a session id is not an identity', false, isChartIdentity('ireal-0'));
  stdout.writeln(
    'edited_identity=${chartIdentityOf(_songEdited())} '
    'renamed_identity=${chartIdentityOf(_song(title: 'Renamed by the musician'))}',
  );
}

/// The same music carrying another document id, which is what a different position in an export
/// produces.
Song _songWithId(String id) {
  final Song base = _song();
  return Song(
    id: id,
    title: base.title,
    composer: base.composer,
    style: base.style,
    key: base.key,
    tempo: base.tempo,
    sections: base.sections,
    staffSet: base.staffSet,
  );
}

/// The same music with a different metadata block, which is what a rename or a style change writes.
Song _songWithMetadata(String composer, String style, int tempo) {
  final Song base = _song();
  return Song(
    id: base.id,
    title: base.title,
    composer: composer,
    style: style,
    key: base.key,
    tempo: tempo,
    sections: base.sections,
    staffSet: base.staffSet,
  );
}

/// The same chart with its second bar's chord changed, which is a genuine edit of the music.
Song _songEdited() {
  final Song base = _song();
  return Song(
    id: base.id,
    title: base.title,
    composer: base.composer,
    style: base.style,
    key: base.key,
    tempo: base.tempo,
    sections: <Section>[
      Section(
        id: 's1',
        label: SectionLabel.letter('A'),
        bars: <Bar>[
          base.sections.first.bars[0],
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: cellAt(0),
                chord: Chord(root: ChordRoot(4)),
              ),
            ],
          ),
        ],
      ),
    ],
    staffSet: base.staffSet,
  );
}

// ---------------------------------------------------------------------------------------------
// Corruption
// ---------------------------------------------------------------------------------------------

void _corruptionFailures() {
  _section('corruption');
  final Uint8List valid = SetlistFileCodec.encode(
    SetlistFile(
      metadata: SetlistMetadata(docId: _setlist().id),
      snapshot: _setlist(),
    ),
  ).bytes;
  stdout.writeln('valid bytes=${valid.length}');

  _refuses('truncated to half', valid.sublist(0, valid.length ~/ 2));
  _refuses('truncated to 10 bytes', valid.sublist(0, 10));
  final Uint8List wrongMagic = Uint8List.fromList(valid);
  wrongMagic[3] = 0x00;
  _refuses('magic byte 3 zeroed', wrongMagic);
  final Uint8List wrongVersion = Uint8List.fromList(valid);
  wrongVersion[8] = 0x02;
  _refuses('envelope version 1 -> 2', wrongVersion);
  final Uint8List flipped = Uint8List.fromList(valid);
  flipped[containerPrefixLength + 9] ^= 0xFF;
  _refuses('one header byte flipped', flipped);
  _refuses(
    'two bytes appended',
    Uint8List.fromList(<int>[...valid, 0x00, 0x01]),
  );
  _refuses('nothing at all', Uint8List(0));
}

/// Tries to decode [bytes] as a `.setlist` file and reports the typed failure it produced.
///
/// A decode that RETURNS is the failure this check exists for: a damaged file must not arrive as a
/// programme, and an empty one least of all, because an empty programme looks exactly like a
/// programme somebody had not built yet. The guard prints what came back so the claim can be read
/// off the output rather than trusted.
void _refuses(String what, Uint8List bytes) {
  _checks++;
  try {
    final SetlistFileDecodeResult result = SetlistFileCodec.decode(bytes);
    _failures++;
    stdout.writeln('[$what] DID NOT FAIL');
    stdout.writeln(
      '    returned a programme with ${result.file.snapshot.items.length} '
      'entr(y/ies) and ${result.file.events.length} operation(s)',
    );
  } on ContainerException catch (error) {
    stdout.writeln('[$what] ${error.runtimeType}');
    stdout.writeln('    ${error.message}');
  } catch (error) {
    _failures++;
    stdout.writeln(
      '[$what] UNTYPED ${error.runtimeType}: $error -- a raw failure escaped the codec',
    );
  }
}

// ---------------------------------------------------------------------------------------------
// A newer writer
// ---------------------------------------------------------------------------------------------

void _newerWriter() {
  _section('newer writer');
  final Setlist programme = _setlist();
  const SetlistRenameEvent rename = SetlistRenameEvent(
    docId: 'playlist-Set 1',
    seq: 1,
    fromTitle: 'First set',
    toTitle: 'Encore',
  );
  final Map<String, Object?> future = <String, Object?>{
    'v': 1,
    'docId': programme.id,
    'seq': 0,
    'type': 'setlist.tempo.set',
    'payload': <String, Object?>{'tempo': 120},
  };
  final Map<String, Object?> futureVersion = <String, Object?>{
    'v': 7,
    'docId': programme.id,
    'seq': 0,
    'type': 'setlist.rename',
    'payload': <String, Object?>{'fromTitle': '', 'toTitle': ''},
  };
  final Map<String, Object?> header = <String, Object?>{
    'format': setlistFileFormatTag,
    'version': setlistContainerVersion,
    'docId': programme.id,
    'setlist': programme.toJson(),
    'events': <Object?>[rename.toJson(), future, futureVersion],
  };
  final Uint8List bytes = encodeContainerFrame(
    version: setlistContainerVersion,
    headerBytes: Uint8List.fromList(utf8.encode(jsonEncode(header))),
    payloadBytes: Uint8List(0),
  );
  final SetlistFileDecodeResult decoded = SetlistFileCodec.decode(bytes);
  _same('newer: known operations are kept', 1, decoded.file.events.length);
  _same('newer: two warnings', 2, decoded.warnings.length);
  _same(
    'newer: the first warning names the unknown type',
    SetlistFileWarningCode.unknownEventType,
    decoded.warnings.first.code,
  );
  _same(
    'newer: the programme is the snapshot plus the operations read',
    'Encore',
    decoded.file.reducedSetlist.title,
  );
  for (final SetlistFileWarning warning in decoded.warnings) {
    stdout.writeln('newer: ${warning.code.name}: ${warning.message}');
  }
  stdout.writeln(
    'newer: programme=${decoded.file.reducedSetlist} '
    'entries=${decoded.file.reducedSetlist.items.length}',
  );
}

// ---------------------------------------------------------------------------------------------
// The two formats over one envelope
// ---------------------------------------------------------------------------------------------

void _crossFormat() {
  _section('the two formats share one frame and are told apart by the header');
  final Uint8List chartBytes = ChartFileCodec.encode(
    ChartFile(
      metadata: const ChartMetadata(docId: 'doc-1'),
      snapshot: DocumentState(song: _song()),
    ),
  ).bytes;
  _same(
    'a .chart file begins with the shared magic',
    true,
    _startsWithMagic(chartBytes),
  );
  _refuses('a .chart file handed to the setlist codec', chartBytes);
  final Uint8List setlistBytes = SetlistFileCodec.encode(
    SetlistFile(
      metadata: SetlistMetadata(docId: _setlist().id),
      snapshot: _setlist(),
    ),
  ).bytes;
  _checks++;
  try {
    ChartFileCodec.decode(setlistBytes);
    _failures++;
    stdout.writeln('[a .setlist file handed to the chart codec] DID NOT FAIL');
  } on ChartFileException catch (error) {
    stdout.writeln(
      '[a .setlist file handed to the chart codec] ${error.runtimeType}',
    );
    stdout.writeln('    ${error.message}');
  } catch (error) {
    _failures++;
    stdout.writeln(
      '[a .setlist file handed to the chart codec] UNTYPED ${error.runtimeType}: $error',
    );
  }
}

/// Whether [bytes] begins with the shared container magic.
bool _startsWithMagic(Uint8List bytes) {
  if (bytes.length < containerMagic.length) {
    return false;
  }
  for (int index = 0; index < containerMagic.length; index++) {
    if (bytes[index] != containerMagic[index]) {
      return false;
    }
  }
  return true;
}

/// Prints a section heading.
void _section(String title) {
  stdout.writeln('');
  stdout.writeln('===== $title =====');
}

/// Records one expectation, printing both sides when it fails.
void _same(String what, Object? expected, Object? actual) {
  _checks++;
  final bool ok = expected == actual;
  if (!ok) {
    _failures++;
    stdout.writeln('[FAIL] $what');
    stdout.writeln('    expected: $expected');
    stdout.writeln('    actual:   $actual');
    return;
  }
  stdout.writeln('[ok] $what');
}
