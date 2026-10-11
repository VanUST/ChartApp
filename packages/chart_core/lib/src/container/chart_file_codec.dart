// PURPOSE: Read a `.chart` file's HEADER and write one, turning every way the document part can be
//          wrong into one typed failure instead of a raw parse exception or, worse, an empty
//          document that looks like a real one. It also applies D19's inline-or-sidecar rule to a
//          PDF, because that rule is about what goes into this container. The ENVELOPE around the
//          header — magic, version, lengths, CRC-32 and every way those can disagree — is not
//          implemented here: it is `container_frame.dart`, shared with the `.setlist` container, so
//          the two formats cannot come to classify the same damage differently.
// INPUTS: A [ChartFile] on the way out; the container's bytes on the way in.
// OUTPUTS: [ChartFileEncodeResult] carrying the bytes and any warning D19 forced, and
//          [ChartFileDecodeResult] carrying the file and any warning a newer build forced.
//          [ChartFileSignatureException], [ChartFileTruncatedException],
//          [ChartFileCorruptException] and [ChartFileVersionException] are thrown for a file that
//          is not a readable container; [ChartFileWriteException] for a value that is not a legal
//          file. Nothing throws a bare `FormatException` or `RangeError`: the header JSON, the
//          operation payloads, the UTF-8 decoding and the byte ranges are all caught and
//          re-reported.
// KEYWORDS: codec, container, header, encode, decode, truncation, corruption,
//           forward-compatibility, d19, pdf, no-silent-default, typed-failure, shared-frame
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
    // The frame is written by the shared implementation, so a `.chart` and a `.setlist` file are
    // the same bytes up to the end of the header. The size check lives there too.
    return ChartFileEncodeResult(
      bytes: encodeContainerFrame(
        version: chartContainerVersion,
        headerBytes: headerBytes,
        payloadBytes: payloadBytes,
      ),
      warnings: warnings,
    );
  }

  /// Reads [bytes] as a container.
  ///
  /// Throws a [ChartFileException] for every way the bytes can fail to be a readable `.chart` file,
  /// and never returns a document that is not exactly what the file says. An operation this build
  /// does not understand is the one thing that is skipped rather than refused, and it is reported
  /// in the result's warnings together with what the document is without it.
  static ChartFileDecodeResult decode(Uint8List bytes) {
    // THE FRAME IS READ BY THE SHARED IMPLEMENTATION. Every way the envelope can be wrong — short
    // of its prefix, wrong magic, an envelope version this build does not read, shorter or longer
    // than its own lengths declare, a header or payload whose CRC-32 disagrees — is classified
    // there, once, with the typed failure the frame family declares. This function reads only what
    // is INSIDE the frame, so a `.chart` and a `.setlist` file cannot disagree about what
    // "truncated" or "corrupt" means.
    final ContainerFrame frame = decodeContainerFrame(
      bytes,
      version: chartContainerVersion,
      extension: chartFileExtension,
    );
    final Uint8List headerBytes = frame.header;
    final Uint8List payloadBytes = frame.payload;
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
