// PURPOSE: Produce the evidence the `.chart` container has to stand on: a document encodes and
//          decodes back to an equal document, a truncated file and a corrupted file each fail with
//          the typed failure they should, and a file written by a NEWER build is read for what it
//          understands instead of being refused or turned into an empty document. A codec and its
//          own round-trip test agree with each other by construction, so this probe prints the
//          values it compared and the exact messages it received rather than a single "ok".
// INPUTS: None. Every fixture is built here; nothing is read from the network or from a device.
// OUTPUTS: One block per check on stdout, then a summary line and an exit code: 0 when every check
//          held, 1 when one did not. A check that is supposed to fail prints the exception TYPE and
//          MESSAGE it caught, so a raw `FormatException` or `RangeError` escaping the codec is
//          visible as exactly that.
// KEYWORDS: probe, chart-file, container, round-trip, truncation, corruption, forward-compatibility,
//           d19, evidence, not-part-of-the-library
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

int _failures = 0;
int _checks = 0;

void main() {
  _roundTripEmpty();
  _roundTripOneOperation();
  _roundTripManyOperations();
  _pdfRule();
  _corruptionFailures();
  _newerWriter();
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

// ---------------------------------------------------------------------------------------------
// Round trips
// ---------------------------------------------------------------------------------------------

void _roundTripEmpty() {
  _section('empty document');
  const ChartFile file = ChartFile(
    metadata: ChartMetadata(docId: 'doc-empty', writer: 'probe'),
    snapshot: DocumentState(song: Song(title: '')),
  );
  final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
  stdout.writeln(
    'encoded bytes=${encoded.bytes.length} warnings=${encoded.warnings.length}',
  );
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(encoded.bytes);
  _same('empty: encoded file == decoded file', file, decoded.file);
  _same('empty: no warnings', 0, decoded.warnings.length);
  stdout.writeln('snapshot=${decoded.file.snapshot}');
}

void _roundTripOneOperation() {
  _section('one operation');
  final DocumentState before = DocumentState(song: _baseSong());
  const InkStrokeAddEvent event = InkStrokeAddEvent(
    docId: 'doc-one',
    seq: 1,
    index: 0,
    stroke: InkStroke(
      id: 'ink-1',
      tool: StrokeTool.pen,
      color: '#112233',
      size: 2.5,
      anchor: EventAnchor(sectionId: 's1', bar: 0),
      points: <InkPoint>[
        InkPoint(x: 0, y: 0, w: 0.5, t: 0),
        InkPoint(x: 3.5, y: 1.25, w: 0.75, t: 16),
      ],
    ),
  );
  final DocumentState after = DocumentReducer.apply(before, event);
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'doc-one'),
    snapshot: before,
    events: <ChartEvent>[event],
  );
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(
    ChartFileCodec.encode(file).bytes,
  );
  _same('one: encoded file == decoded file', file, decoded.file);
  _same(
    'one: the operation is the same value',
    event,
    decoded.file.events.single,
  );
  _same(
    'one: the reduced document is the edited one',
    after,
    decoded.file.reducedDocument,
  );
  stdout.writeln('reduced=${decoded.file.reducedDocument}');
}

void _roundTripManyOperations() {
  _section('many mixed operations');
  final DocumentState before = DocumentState(song: _baseSong());
  final List<ChartEvent> events = <ChartEvent>[
    const InkStrokeAddEvent(
      docId: 'doc-many',
      seq: 1,
      index: 0,
      stroke: InkStroke(
        id: 'ink-1',
        tool: StrokeTool.pen,
        color: '#112233',
        size: 2.5,
        anchor: EventAnchor(sectionId: 's1', bar: 0),
        points: <InkPoint>[
          InkPoint(x: 0, y: 0, w: 0.5, t: 0),
          InkPoint(x: 3.5, y: 1.25, w: 0.75, t: 16),
        ],
      ),
    ),
    const TextCueInsertEvent(
      docId: 'doc-many',
      seq: 2,
      index: 0,
      cue: TextCue(
        id: 'cue-1',
        place: AnchoredPlace(anchor: EventAnchor(sectionId: 's1', bar: 0)),
        text: 'to the top',
      ),
    ),
    const BarSizeSetEvent(
      docId: 'doc-many',
      seq: 3,
      sectionId: 's1',
      barIndex: 0,
      from: BarSize.natural,
      to: BarSize(1.25),
    ),
    SongUpdateEvent(
      docId: 'doc-many',
      seq: 4,
      from: SongMetadata(
        title: before.song.title,
        composer: before.song.composer,
        style: before.song.style,
        tempo: before.song.tempo,
      ),
      to: SongMetadata(
        title: 'Renamed By The Log',
        composer: before.song.composer,
        style: before.song.style,
        tempo: before.song.tempo,
      ),
    ),
    const TextCueEditEvent(
      docId: 'doc-many',
      seq: 5,
      id: 'cue-1',
      from: 'to the top',
      to: 'to the top, twice',
    ),
  ];
  // The expected result is built by folding the SAME events the file carries, which is what makes
  // the comparison below a statement about the codec: if the container lost or mangled one field of
  // one operation, the folded document would differ.
  DocumentState expected = before;
  for (final ChartEvent event in events) {
    expected = DocumentReducer.apply(expected, event);
  }
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'doc-many'),
    snapshot: before,
    events: events,
  );
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(
    ChartFileCodec.encode(file).bytes,
  );
  _same('many: encoded file == decoded file', file, decoded.file);
  _same('many: operation count', events.length, decoded.file.events.length);
  _same(
    'many: reduced document equals the fold',
    expected,
    decoded.file.reducedDocument,
  );
  stdout.writeln(
    'types=${decoded.file.events.map((ChartEvent e) => e.type).toList()}',
  );
  stdout.writeln(
    'bars=${decoded.file.reducedDocument.song.writtenBarCount} '
    'strokes=${decoded.file.reducedDocument.strokes.length} '
    'cues=${decoded.file.reducedDocument.textCues.length}',
  );
}

// ---------------------------------------------------------------------------------------------
// D19: inline at most 50 MB per song, otherwise a sidecar reference plus a warning
// ---------------------------------------------------------------------------------------------

void _pdfRule() {
  _section('D19 pdf rule');

  final Uint8List small = Uint8List.fromList(<int>[
    0x25,
    0x50,
    0x44,
    0x46,
    0x2d,
    0x31,
    0x2e,
  ]);
  stdout.writeln(
    'limit=$pdfInlineLimitBytes fits(limit)=${ChartFileCodec.pdfFitsInline(pdfInlineLimitBytes)} '
    'fits(limit+1)=${ChartFileCodec.pdfFitsInline(pdfInlineLimitBytes + 1)}',
  );
  final ChartPdf smallPlacement = ChartFileCodec.applyPdfRule(
    name: 'lead-sheet.pdf',
    bytes: small,
    sidecarReference: 'lead-sheet.pdf',
  );
  _same('d19: small pdf is embedded', true, smallPlacement is EmbeddedPdf);
  final ChartFile withSmall = ChartFile(
    metadata: const ChartMetadata(docId: 'doc-pdf'),
    snapshot: DocumentState(song: _baseSong()),
    attachments: <ChartPdf>[smallPlacement],
  );
  final ChartFileEncodeResult smallEncoded = ChartFileCodec.encode(withSmall);
  stdout.writeln(
    'small: bytes=${smallEncoded.bytes.length} warnings=${smallEncoded.warnings.length}',
  );
  _same('d19: embedding warns about nothing', 0, smallEncoded.warnings.length);
  final ChartFileDecodeResult smallDecoded = ChartFileCodec.decode(
    smallEncoded.bytes,
  );
  _same(
    'd19: the embedded pdf round-trips byte for byte',
    withSmall,
    smallDecoded.file,
  );
  stdout.writeln('small: decoded=${smallDecoded.file.attachments.single}');

  final Uint8List big = Uint8List(pdfInlineLimitBytes + 1);
  final ChartPdf bigPlacement = ChartFileCodec.applyPdfRule(
    name: 'scan.pdf',
    bytes: big,
    sidecarReference: 'scan.pdf',
  );
  _same('d19: over the limit is a sidecar', true, bigPlacement is SidecarPdf);
  final ChartFile withBig = ChartFile(
    metadata: const ChartMetadata(docId: 'doc-pdf'),
    snapshot: DocumentState(song: _baseSong()),
    attachments: <ChartPdf>[bigPlacement],
  );
  final ChartFileEncodeResult bigEncoded = ChartFileCodec.encode(withBig);
  stdout.writeln(
    'big: bytes=${bigEncoded.bytes.length} warnings=${bigEncoded.warnings.length}',
  );
  _same('d19: a sidecar warns', 1, bigEncoded.warnings.length);
  stdout.writeln('big: warning=${bigEncoded.warnings.single}');
  final ChartFileDecodeResult bigDecoded = ChartFileCodec.decode(
    bigEncoded.bytes,
  );
  _same('d19: a sidecar round-trips as a reference', withBig, bigDecoded.file);
  stdout.writeln('big: decoded warning=${bigDecoded.warnings.single}');
}

// ---------------------------------------------------------------------------------------------
// Corruption: every damaged file must fail with its own typed error and return no document
// ---------------------------------------------------------------------------------------------

void _corruptionFailures() {
  _section('corruption');
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'doc-many'),
    snapshot: DocumentState(song: _baseSong()),
    events: <ChartEvent>[
      InkStrokeAddEvent(
        docId: 'doc-many',
        seq: 1,
        index: 0,
        stroke: InkStroke(
          id: 'ink-1',
          tool: StrokeTool.pen,
          color: '#112233',
          size: 2.5,
          anchor: EventAnchor(sectionId: 's1', bar: 0),
          points: <InkPoint>[
            InkPoint(x: 0, y: 0, w: 0.5, t: 0),
            InkPoint(x: 3.5, y: 1.25, w: 0.75, t: 16),
          ],
        ),
      ),
    ],
    attachments: <ChartPdf>[
      EmbeddedPdf(
        name: 'scan.pdf',
        bytes: Uint8List.fromList(List<int>.generate(300, (int i) => i & 0xFF)),
      ),
    ],
  );
  final Uint8List valid = ChartFileCodec.encode(file).bytes;
  stdout.writeln('valid bytes=${valid.length}');

  _garbage(
    'truncated to half',
    Uint8List.sublistView(valid, 0, valid.length ~/ 2),
  );
  _garbage('truncated to 10 bytes', Uint8List.sublistView(valid, 0, 10));

  final Uint8List badMagic = Uint8List.fromList(valid)..[3] = 0x00;
  _garbage('magic byte 3 zeroed', badMagic);

  final Uint8List badVersion = Uint8List.fromList(valid)..[8] = 2;
  _garbage('envelope version 1 -> 2', badVersion);

  final Uint8List badHeader = Uint8List.fromList(valid);
  badHeader[chartFilePrefixLength + 7] ^= 0xFF;
  _garbage('one header byte flipped', badHeader);

  final Uint8List badPayload = Uint8List.fromList(valid);
  badPayload[valid.length - 5] ^= 0xFF;
  _garbage('one embedded-pdf byte flipped', badPayload);

  final Uint8List trailing = Uint8List.fromList(<int>[...valid, 0x00, 0x01]);
  _garbage('two bytes appended', trailing);
}

/// Decodes [bytes], which must fail, and prints the typed failure it produced.
void _garbage(String what, Uint8List bytes) {
  _checks++;
  try {
    final ChartFileDecodeResult result = ChartFileCodec.decode(bytes);
    _failures++;
    stdout.writeln(
      '[$what] DID NOT FAIL: got a document ${result.file} with '
      '${result.warnings.length} warning(s)',
    );
  } on ChartFileException catch (error) {
    stdout.writeln('[$what] ${error.runtimeType}');
    stdout.writeln('    ${error.message}');
  } catch (error) {
    _failures++;
    stdout.writeln(
      '[$what] UNTYPED ${error.runtimeType}: $error -- a raw parse failure '
      'escaped the codec',
    );
  }
}

// ---------------------------------------------------------------------------------------------
// A file from a newer build: read what is understood, report the rest
// ---------------------------------------------------------------------------------------------

void _newerWriter() {
  _section('newer writer');
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'doc-many'),
    snapshot: DocumentState(song: _baseSong()),
    events: <ChartEvent>[
      InkStrokeAddEvent(
        docId: 'doc-many',
        seq: 1,
        index: 0,
        stroke: InkStroke(
          id: 'ink-1',
          tool: StrokeTool.pen,
          color: '#112233',
          size: 2.5,
          anchor: EventAnchor(sectionId: 's1', bar: 0),
          points: <InkPoint>[
            InkPoint(x: 0, y: 0, w: 0.5, t: 0),
            InkPoint(x: 3.5, y: 1.25, w: 0.75, t: 16),
          ],
        ),
      ),
    ],
  );
  final Map<String, Object?> header = _splitHeader(
    ChartFileCodec.encode(file).bytes,
  );

  final Map<String, Object?> unknown = _copyHeader(header);
  (unknown['events']! as List<Object?>).add(<String, Object?>{
    'v': 1,
    'docId': 'doc-many',
    'seq': 2,
    'type': 'tempo.set',
    'payload': <String, Object?>{'tempo': 120},
  });
  final ChartFileDecodeResult unknownResult = ChartFileCodec.decode(
    _craft(unknown),
  );
  _same(
    'newer: known operations are kept',
    1,
    unknownResult.file.events.length,
  );
  _same('newer: one warning', 1, unknownResult.warnings.length);
  _same(
    'newer: the warning names the skip',
    ChartFileWarningCode.unknownEventType,
    unknownResult.warnings.single.code,
  );
  stdout.writeln('newer: warning=${unknownResult.warnings.single}');
  stdout.writeln('newer: document=${unknownResult.file.reducedDocument}');

  final Map<String, Object?> futureVersion = _copyHeader(header);
  final List<Object?> futureEvents = futureVersion['events']! as List<Object?>;
  futureEvents[0] = <String, Object?>{
    ...futureEvents[0]! as Map<String, Object?>,
    'v': 7,
  };
  final ChartFileDecodeResult futureResult = ChartFileCodec.decode(
    _craft(futureVersion),
  );
  _same(
    'newer: a future operation version is skipped',
    0,
    futureResult.file.events.length,
  );
  _same(
    'newer: the warning names the version',
    ChartFileWarningCode.unsupportedEventVersion,
    futureResult.warnings.single.code,
  );
  stdout.writeln('newer: warning=${futureResult.warnings.single}');

  final Map<String, Object?> malformed = _copyHeader(header);
  final List<Object?> malformedEvents = malformed['events']! as List<Object?>;
  malformedEvents[0] = <String, Object?>{
    ...malformedEvents[0]! as Map<String, Object?>,
    'payload': <String, Object?>{
      'sectionId': 's1',
      'bar': 'zero',
      'chord': <String, Object?>{},
    },
  };
  _garbage('a known operation with a malformed field', _craft(malformed));

  final Map<String, Object?> wrongDoc = _copyHeader(header);
  final List<Object?> wrongEvents = wrongDoc['events']! as List<Object?>;
  wrongEvents[0] = <String, Object?>{
    ...wrongEvents[0]! as Map<String, Object?>,
    'docId': 'somewhere-else',
  };
  _garbage('an operation belonging to another document', _craft(wrongDoc));
}

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

void _section(String title) {
  stdout.writeln('');
  stdout.writeln('===== $title =====');
}

/// Records one expectation, printing both sides so a failure is readable.
void _same(String what, Object? expected, Object? actual) {
  _checks++;
  final bool ok = expected == actual;
  if (!ok) {
    _failures++;
  }
  stdout.writeln('[${ok ? 'ok' : 'FAIL'}] $what');
  if (!ok) {
    stdout.writeln('    expected: $expected');
    stdout.writeln('    actual:   $actual');
  }
}

/// The song every document fixture starts from: one section, one empty bar.
Song _baseSong() => Song(
  id: 'doc-many',
  title: 'Probe Tune',
  composer: 'Nobody',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 132,
  sections: <Section>[
    const Section(
      id: 's1',
      label: SectionLabel.letter('A'),
      bars: <Bar>[Bar()],
    ),
  ],
);

/// Reads back the header JSON of an already-encoded container, so a deliberately damaged header can
/// be re-framed with a CORRECT checksum. That is the only way to reach the content checks: a flipped
/// byte is always caught by the CRC first.
Map<String, Object?> _splitHeader(Uint8List container) {
  final int headerLength = _readU32(container, 12);
  final Uint8List headerBytes = Uint8List.sublistView(
    container,
    chartFilePrefixLength,
    chartFilePrefixLength + headerLength,
  );
  return jsonDecode(utf8.decode(headerBytes)) as Map<String, Object?>;
}

Map<String, Object?> _copyHeader(Map<String, Object?> header) =>
    jsonDecode(jsonEncode(header)) as Map<String, Object?>;

/// Frames [header] as a valid container whose checksums are correct.
Uint8List _craft(Map<String, Object?> header) {
  final List<int> headerBytes = utf8.encode(jsonEncode(header));
  final BytesBuilder out = BytesBuilder(copy: false);
  out.add(chartFileMagic);
  _writeU32(out, 1);
  _writeU32(out, headerBytes.length);
  _writeU32(out, 0);
  _writeU32(out, _crc32(headerBytes));
  _writeU32(out, _crc32(const <int>[]));
  out.add(headerBytes);
  return out.takeBytes();
}

void _writeU32(BytesBuilder out, int value) {
  out
    ..addByte(value & 0xFF)
    ..addByte((value >> 8) & 0xFF)
    ..addByte((value >> 16) & 0xFF)
    ..addByte((value >> 24) & 0xFF);
}

int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// An independent CRC-32 (IEEE 802.3), so that a file this probe frames is accepted by the codec
/// only if both implementations agree.
int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte & 0xFF;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
