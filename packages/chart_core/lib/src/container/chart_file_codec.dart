// PURPOSE: Write a [ChartFile] as a `.chart` container and read one back, turning every way a file
//          can be wrong into one typed failure instead of a raw parse exception or, worse, an empty
//          document that looks like a real one. It also applies D19's inline-or-sidecar rule to a
//          PDF, because that rule is about what goes into this container.
// INPUTS: A [ChartFile] on the way out; the container's bytes on the way in.
// OUTPUTS: [ChartFileEncodeResult] carrying the bytes and any warning D19 forced, and
//          [ChartFileDecodeResult] carrying the file and any warning a newer build forced.
//          [ChartFileSignatureException], [ChartFileTruncatedException],
//          [ChartFileCorruptException] and [ChartFileVersionException] are thrown for a file that
//          is not a readable container; [ChartFileWriteException] for a value that is not a legal
//          file. Nothing throws a bare `FormatException` or `RangeError`: the header JSON, the
//          operation payloads, the UTF-8 decoding and the byte ranges are all caught and
//          re-reported.
// KEYWORDS: codec, container, encode, decode, crc32, truncation, corruption, forward-compatibility,
//           d19, pdf, no-silent-default, typed-failure
part of 'chart_file.dart';

/// The header keys, named once so the writer and the reader cannot drift apart.
abstract final class _H {
  static const String format = 'format';
  static const String version = 'version';
  static const String docId = 'docId';
  static const String writer = 'writer';
  static const String createdAt = 'createdAt';
  static const String modifiedAt = 'modifiedAt';
  static const String document = 'document';
  static const String events = 'events';
  static const String attachments = 'attachments';
  static const String kind = 'kind';
  static const String name = 'name';
  static const String mediaType = 'mediaType';
  static const String offset = 'offset';
  static const String length = 'length';
  static const String reference = 'reference';
  static const String byteLength = 'byteLength';
  static const String kindEmbedded = 'embedded';
  static const String kindSidecar = 'sidecar';
}

/// The `.chart` container codec.
abstract final class ChartFileCodec {
  /// Applies D19 to one song's PDF: embed it when it is at most [pdfInlineLimitBytes], otherwise
  /// leave it on disk and name [sidecarReference].
  ///
  /// [name] is the PDF's own file name; [sidecarReference] is where the PDF can be found from the
  /// `.chart` file, normally just the same name beside it. A caller that already knows the PDF is
  /// too big can test [pdfFitsInline] and build a [SidecarPdf] directly, which avoids reading the
  /// bytes at all — which is the point of the rule.
  ///
  /// The returned [SidecarPdf] carries no bytes. The writer records the size it was given and emits
  /// the warning D19 requires when the file is encoded.
  static ChartPdf applyPdfRule({
    required String name,
    required Uint8List bytes,
    required String sidecarReference,
  }) {
    if (bytes.length <= pdfInlineLimitBytes) {
      return EmbeddedPdf(name: name, bytes: bytes);
    }
    return SidecarPdf(
      name: name,
      reference: sidecarReference.isEmpty ? name : sidecarReference,
      byteLength: bytes.length,
    );
  }

  /// Whether D19 embeds a PDF of [byteLength] bytes rather than referencing it.
  static bool pdfFitsInline(int byteLength) =>
      byteLength <= pdfInlineLimitBytes;

  /// Writes [file] as a container.
  ///
  /// Throws [ChartFileWriteException] when [file] does not describe a legal chart file: an empty
  /// metadata document id, an operation belonging to another document, an attachment with no name,
  /// two attachments sharing a name, or content too large for the frame's 32-bit length fields.
  /// Warnings in the result are what D19 left out, never a failure.
  static ChartFileEncodeResult encode(ChartFile file) {
    _checkWritable(file);
    final List<ChartFileWarning> warnings = <ChartFileWarning>[];
    final BytesBuilder payload = BytesBuilder(copy: false);
    final List<Object?> attachments = <Object?>[];
    for (final ChartPdf attachment in file.attachments) {
      switch (attachment) {
        case final EmbeddedPdf embedded:
          attachments.add(<String, Object?>{
            _H.kind: _H.kindEmbedded,
            _H.name: embedded.name,
            _H.mediaType: pdfMediaType,
            _H.offset: payload.length,
            _H.length: embedded.bytes.length,
          });
          payload.add(embedded.bytes);
        case final SidecarPdf sidecar:
          attachments.add(<String, Object?>{
            _H.kind: _H.kindSidecar,
            _H.name: sidecar.name,
            _H.mediaType: pdfMediaType,
            _H.reference: sidecar.reference,
            _H.byteLength: sidecar.byteLength,
          });
          warnings.add(
            ChartFileWarning(
              code: ChartFileWarningCode.pdfSidecar,
              message:
                  'the PDF "${sidecar.name}" is ${sidecar.byteLength} bytes, '
                  'over D19\'s $pdfInlineLimitBytes-byte inline limit, so it was '
                  'NOT embedded and is named as "${sidecar.reference}" beside '
                  'the chart; move the two files together. The chart itself is '
                  'complete.',
            ),
          );
      }
    }
    final ChartMetadata metadata = file.metadata;
    final DateTime? created = metadata.createdAt;
    final DateTime? modified = metadata.modifiedAt;
    final Map<String, Object?> header = <String, Object?>{
      _H.format: chartFileFormatTag,
      _H.version: chartContainerVersion,
      _H.docId: metadata.docId,
      if (metadata.writer.isNotEmpty) _H.writer: metadata.writer,
      if (created != null) _H.createdAt: created.toUtc().toIso8601String(),
      if (modified != null) _H.modifiedAt: modified.toUtc().toIso8601String(),
      _H.document: ModelJson.documentState(file.snapshot),
      _H.events: <Object?>[
        for (final ChartEvent event in file.events) event.toJson(),
      ],
      _H.attachments: attachments,
    };

    final Uint8List headerBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(header)),
    );
    final Uint8List payloadBytes = payload.takeBytes();
    if (headerBytes.length > _maxU32 || payloadBytes.length > _maxU32) {
      throw const ChartFileWriteException(
        'the container is too large for its own frame: the header and the '
        'payload region each hold at most 4294967295 bytes',
      );
    }

    final BytesBuilder out = BytesBuilder(copy: false);
    out.add(chartFileMagic);
    _writeU32(out, chartContainerVersion);
    _writeU32(out, headerBytes.length);
    _writeU32(out, payloadBytes.length);
    _writeU32(out, _crc32(headerBytes));
    _writeU32(out, _crc32(payloadBytes));
    out
      ..add(headerBytes)
      ..add(payloadBytes);
    return ChartFileEncodeResult(bytes: out.takeBytes(), warnings: warnings);
  }

  /// Reads [bytes] as a container.
  ///
  /// Throws a [ChartFileException] for every way the bytes can fail to be a readable `.chart` file,
  /// and never returns a document that is not exactly what the file says. An operation this build
  /// does not understand is the one thing that is skipped rather than refused, and it is reported
  /// in the result's warnings together with what the document is without it.
  static ChartFileDecodeResult decode(Uint8List bytes) {
    if (bytes.length < chartFilePrefixLength) {
      throw ChartFileTruncatedException(
        'a .chart container is at least $chartFilePrefixLength bytes; this '
        'file is ${bytes.length}',
        found: bytes.length,
        expected: chartFilePrefixLength,
      );
    }
    for (int index = 0; index < chartFileMagic.length; index++) {
      if (bytes[index] != chartFileMagic[index]) {
        throw const ChartFileSignatureException(
          'these bytes do not begin with the .chart magic, so this is not a '
          '.chart container',
        );
      }
    }
    final int version = _readU32(bytes, 8);
    if (version != chartContainerVersion) {
      throw ChartFileVersionException(
        'this is a version $version .chart container; this build reads version '
        '$chartContainerVersion and refuses the rest rather than reading a '
        'frame it does not know',
        found: version,
        supported: chartContainerVersion,
      );
    }
    final int headerLength = _readU32(bytes, 12);
    final int payloadLength = _readU32(bytes, 16);
    final int headerCrc = _readU32(bytes, 20);
    final int payloadCrc = _readU32(bytes, 24);
    final int declared = chartFilePrefixLength + headerLength + payloadLength;
    if (bytes.length < declared) {
      throw ChartFileTruncatedException(
        'the container declares $declared bytes but this file ends at '
        '${bytes.length}',
        found: bytes.length,
        expected: declared,
      );
    }
    if (bytes.length > declared) {
      throw ChartFileCorruptException(
        'the container declares $declared bytes but this file holds '
        '${bytes.length}; the ${bytes.length - declared} trailing byte(s) '
        'belong to nothing',
      );
    }
    final Uint8List headerBytes = Uint8List.sublistView(
      bytes,
      chartFilePrefixLength,
      chartFilePrefixLength + headerLength,
    );
    final Uint8List payloadBytes = Uint8List.sublistView(
      bytes,
      chartFilePrefixLength + headerLength,
      declared,
    );
    final int actualHeaderCrc = _crc32(headerBytes);
    if (actualHeaderCrc != headerCrc) {
      throw ChartFileCorruptException(
        'the header does not match its CRC-32: recorded $headerCrc, computed '
        '$actualHeaderCrc. The bytes have changed since the file was written.',
      );
    }
    if (payloadLength > 0) {
      final int actualPayloadCrc = _crc32(payloadBytes);
      if (actualPayloadCrc != payloadCrc) {
        throw ChartFileCorruptException(
          'the embedded bytes do not match their CRC-32: recorded $payloadCrc, '
          'computed $actualPayloadCrc.',
        );
      }
    }
    final Map<String, Object?> header;
    try {
      final Object? decoded = jsonDecode(utf8.decode(headerBytes));
      if (decoded is! Map<String, Object?>) {
        throw ChartFileCorruptException(
          'the header is ${decoded == null ? 'null' : decoded.runtimeType}, '
          'not a JSON object',
        );
      }
      header = decoded;
    } on FormatException catch (error) {
      throw ChartFileCorruptException(
        'the header is not readable as UTF-8 JSON: ${error.message}',
      );
    }
    try {
      return _readBody(header, payloadBytes);
    } on EventFormatException catch (error) {
      throw ChartFileCorruptException(
        'the header is not a readable container: ${error.message}',
      );
    }
  }

  /// Reads the header object into a file, reporting a warning for each part it cannot read.
  static ChartFileDecodeResult _readBody(
    Map<String, Object?> header,
    Uint8List payload,
  ) {
    final String format = EventJson.string(header, _H.format);
    if (format != chartFileFormatTag) {
      throw ChartFileCorruptException(
        'the header calls itself "$format", not "$chartFileFormatTag"',
      );
    }
    final int headerVersion = EventJson.integer(header, _H.version);
    if (headerVersion != chartContainerVersion) {
      throw ChartFileCorruptException(
        'the frame is version $chartContainerVersion but the header inside it '
        'says $headerVersion',
      );
    }
    final String docId = EventJson.string(header, _H.docId);
    if (docId.isEmpty) {
      throw const ChartFileCorruptException(
        'the document id is empty, so no operation in this container can be '
        'checked against the document it belongs to',
      );
    }
    final List<ChartFileWarning> warnings = <ChartFileWarning>[];
    final ChartMetadata metadata = ChartMetadata(
      docId: docId,
      writer: EventJson.optionalString(header, _H.writer) ?? '',
      createdAt: _readInstant(header, _H.createdAt),
      modifiedAt: _readInstant(header, _H.modifiedAt),
    );
    final DocumentState snapshot = ModelJson.decodeDocumentState(
      EventJson.object(header, _H.document),
    );
    final List<ChartEvent> events = <ChartEvent>[];
    final List<Object?> rawEvents = EventJson.array(header, _H.events);
    for (int index = 0; index < rawEvents.length; index++) {
      final Object? entry = rawEvents[index];
      if (entry is! Map<String, Object?>) {
        throw ChartFileCorruptException('events[$index] is not a JSON object');
      }
      final DocumentEvent decoded;
      try {
        decoded = EventCodec.decode(entry);
      } on UnknownEventTypeException catch (error) {
        warnings.add(_skipped(index, error.message));
        continue;
      } on UnsupportedEventVersionException catch (error) {
        warnings.add(
          ChartFileWarning(
            code: ChartFileWarningCode.unsupportedEventVersion,
            message: _skippedMessage(index, error.message),
          ),
        );
        continue;
      }
      if (decoded is! ChartEvent) {
        throw ChartFileCorruptException(
          'events[$index] is a "${decoded.type}" operation, which edits a '
          'setlist; a chart document cannot contain it',
        );
      }
      if (decoded.docId != docId) {
        throw ChartFileCorruptException(
          'events[$index] belongs to document "${decoded.docId}" but this '
          'container is document "$docId"',
        );
      }
      events.add(decoded);
    }
    final List<ChartPdf> attachments = _readAttachments(
      EventJson.array(header, _H.attachments),
      payload,
      warnings,
    );
    return ChartFileDecodeResult(
      file: ChartFile(
        metadata: metadata,
        snapshot: snapshot,
        events: events,
        attachments: attachments,
      ),
      warnings: warnings,
    );
  }

  /// Reads the attachment array, slicing embedded bytes out of [payload].
  static List<ChartPdf> _readAttachments(
    List<Object?> raw,
    Uint8List payload,
    List<ChartFileWarning> warnings,
  ) {
    final List<ChartPdf> attachments = <ChartPdf>[];
    for (int index = 0; index < raw.length; index++) {
      final Object? entry = raw[index];
      if (entry is! Map<String, Object?>) {
        throw ChartFileCorruptException(
          'attachments[$index] is not a JSON object',
        );
      }
      final String kind = EventJson.string(entry, _H.kind);
      final String mediaType =
          EventJson.optionalString(entry, _H.mediaType) ?? pdfMediaType;
      if (mediaType != pdfMediaType) {
        warnings.add(
          ChartFileWarning(
            code: ChartFileWarningCode.unknownAttachment,
            message:
                'attachments[$index] is a "$mediaType" attachment, which this '
                'build does not read. It was skipped and whatever it holds is '
                'NOT available; re-saving this document will not carry it '
                'forward.',
          ),
        );
        continue;
      }
      switch (kind) {
        case _H.kindEmbedded:
          final String name = _readName(entry, index);
          final int offset = EventJson.integer(entry, _H.offset);
          final int length = EventJson.integer(entry, _H.length);
          if (offset < 0 || length < 0 || offset + length > payload.length) {
            throw ChartFileCorruptException(
              'attachments[$index] claims bytes $offset..${offset + length} of '
              'a ${payload.length}-byte payload',
            );
          }
          attachments.add(
            EmbeddedPdf(
              name: name,
              bytes: Uint8List.fromList(
                Uint8List.sublistView(payload, offset, offset + length),
              ),
            ),
          );
        case _H.kindSidecar:
          final String name = _readName(entry, index);
          final String reference = EventJson.string(entry, _H.reference);
          final int byteLength = EventJson.integer(entry, _H.byteLength);
          if (byteLength < 0) {
            throw ChartFileCorruptException(
              'attachments[$index] records a negative size $byteLength',
            );
          }
          attachments.add(
            SidecarPdf(
              name: name,
              reference: reference,
              byteLength: byteLength,
            ),
          );
          warnings.add(
            ChartFileWarning(
              code: ChartFileWarningCode.pdfSidecar,
              message:
                  'the PDF "$name" is not inside this container; it is '
                  'referenced as "$reference" beside it and is '
                  '$byteLength bytes. The chart is complete; the PDF is not '
                  'part of the file and will not move with it.',
            ),
          );
        default:
          warnings.add(
            ChartFileWarning(
              code: ChartFileWarningCode.unknownAttachment,
              message:
                  'attachments[$index] is of kind "$kind", which this build '
                  'does not read. It was skipped and whatever it holds is NOT '
                  'available; re-saving this document will not carry it '
                  'forward.',
            ),
          );
      }
    }
    return attachments;
  }

  /// Reads an attachment name, reporting an empty one.
  static String _readName(Map<String, Object?> entry, int index) {
    final String name = EventJson.string(entry, _H.name);
    if (name.isEmpty) {
      throw ChartFileCorruptException('attachments[$index] has no name');
    }
    return name;
  }

  /// Reports a skipped operation with the code that says what kind of skip it was.
  static ChartFileWarning _skipped(int index, String message) =>
      ChartFileWarning(
        code: ChartFileWarningCode.unknownEventType,
        message: _skippedMessage(index, message),
      );

  /// The one wording every skipped operation uses, so a caller knows a skip means the snapshot plus
  /// the operations that were read, not an empty document.
  static String _skippedMessage(int index, String message) =>
      'events[$index]: $message. The operation was skipped; the document is '
      'the snapshot plus the operations this build did read.';

  /// Reads an optional ISO-8601 instant, reporting text that is not one.
  static DateTime? _readInstant(Map<String, Object?> json, String key) {
    final String? text = EventJson.optionalString(json, key);
    if (text == null) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw ChartFileCorruptException(
        'field "$key" is "$text", which is not an ISO-8601 instant',
      );
    }
    return parsed.toUtc();
  }

  /// Reports a value that cannot be written as a legal container.
  static void _checkWritable(ChartFile file) {
    if (file.metadata.docId.isEmpty) {
      throw const ChartFileWriteException(
        'the metadata document id is empty; an operation log needs a document '
        'to belong to',
      );
    }
    for (int index = 0; index < file.events.length; index++) {
      final ChartEvent event = file.events[index];
      if (event.docId != file.metadata.docId) {
        throw ChartFileWriteException(
          'events[$index] belongs to document "${event.docId}" but the file is '
          'document "${file.metadata.docId}"',
        );
      }
    }
    final Set<String> names = <String>{};
    for (int index = 0; index < file.attachments.length; index++) {
      final ChartPdf attachment = file.attachments[index];
      if (attachment.name.isEmpty) {
        throw ChartFileWriteException('attachments[$index] has no name');
      }
      if (!names.add(attachment.name)) {
        throw ChartFileWriteException(
          'two attachments are both called "${attachment.name}"; a sidecar '
          'reference by name would be ambiguous',
        );
      }
    }
  }
}

/// The largest value the frame's 32-bit length fields can hold.
const int _maxU32 = 0xFFFFFFFF;

/// Writes [value] as four little-endian bytes.
void _writeU32(BytesBuilder out, int value) {
  out
    ..addByte(value & 0xFF)
    ..addByte((value >> 8) & 0xFF)
    ..addByte((value >> 16) & 0xFF)
    ..addByte((value >> 24) & 0xFF);
}

/// Reads four little-endian bytes at [offset].
int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// The CRC-32 (IEEE 802.3) of [bytes]: reflected polynomial `0xEDB88320`, initial value all ones,
/// final value inverted.
///
/// A checksum is what makes a single flipped byte in the header a REPORTED corruption rather than a
/// slightly different chart: header JSON with one character changed still parses, so nothing else
/// in this codec would notice it.
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
