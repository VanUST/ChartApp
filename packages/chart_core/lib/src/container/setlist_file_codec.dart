// PURPOSE: Write a [SetlistFile] as a `.setlist` container and read one back, so a programme a
//          musician built survives the session it was built in — and so that a malformed file is
//          refused with a typed reason rather than arriving as an empty programme that looks
//          exactly like a programme somebody had not built yet.
// INPUTS: A [SetlistFile] on the way out; the container's bytes on the way in.
// OUTPUTS: [SetlistFileEncodeResult] carrying the bytes, and [SetlistFileDecodeResult] carrying the
//          file and any warning a newer build forced. The failures are the shared container family:
//          [ContainerSignatureException], [ContainerTruncatedException], [ContainerVersionException]
//          and [ContainerCorruptException] for a file that is not a readable setlist container, and
//          [ContainerWriteException] for a value that is not a legal one. Nothing throws a bare
//          `FormatException` or `RangeError`.
// KEYWORDS: setlist-file, codec, encode, decode, snapshot, op-log, typed-failure,
//           no-silent-empty, shared-frame
part of 'setlist_file.dart';

/// The header keys, named once so the writer and the reader cannot drift apart.
abstract final class _S {
  static const String format = 'format';
  static const String version = 'version';
  static const String docId = 'docId';
  static const String writer = 'writer';
  static const String createdAt = 'createdAt';
  static const String modifiedAt = 'modifiedAt';
  static const String setlist = 'setlist';
  static const String events = 'events';
}

/// The `.setlist` container codec.
abstract final class SetlistFileCodec {
  /// Writes [file] as a container.
  ///
  /// Throws [ContainerWriteException] when [file] does not describe a legal `.setlist` file: an
  /// empty document id, or an operation belonging to another document. There is no attachment rule
  /// here and no payload region: a programme carries no bytes besides its own header.
  static SetlistFileEncodeResult encode(SetlistFile file) {
    _checkWritable(file);
    final SetlistMetadata metadata = file.metadata;
    final DateTime? created = metadata.createdAt;
    final DateTime? modified = metadata.modifiedAt;
    final Map<String, Object?> header = <String, Object?>{
      _S.format: setlistFileFormatTag,
      _S.version: setlistContainerVersion,
      _S.docId: metadata.docId,
      if (metadata.writer.isNotEmpty) _S.writer: metadata.writer,
      if (created != null) _S.createdAt: created.toUtc().toIso8601String(),
      if (modified != null) _S.modifiedAt: modified.toUtc().toIso8601String(),
      _S.setlist: file.snapshot.toJson(),
      _S.events: <Object?>[
        for (final SetlistEvent event in file.events) event.toJson(),
      ],
    };
    final Uint8List headerBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(header)),
    );
    return SetlistFileEncodeResult(
      bytes: encodeContainerFrame(
        version: setlistContainerVersion,
        headerBytes: headerBytes,
        payloadBytes: Uint8List(0),
      ),
    );
  }

  /// Reads [bytes] as a container.
  ///
  /// Throws a [ContainerException] for every way the bytes can fail to be a readable `.setlist`
  /// file, and never returns a programme that is not exactly what the file says. An operation this
  /// build does not understand is the one thing that is skipped rather than refused, and it is
  /// reported in the result's warnings together with what the programme is without it.
  static SetlistFileDecodeResult decode(Uint8List bytes) {
    final ContainerFrame frame = decodeContainerFrame(
      bytes,
      version: setlistContainerVersion,
      extension: setlistFileExtension,
    );
    final Map<String, Object?> header;
    try {
      final Object? decoded = jsonDecode(utf8.decode(frame.header));
      if (decoded is! Map<String, Object?>) {
        throw ContainerCorruptException(
          'the header is ${decoded == null ? 'null' : decoded.runtimeType}, '
          'not a JSON object',
        );
      }
      header = decoded;
    } on FormatException catch (error) {
      throw ContainerCorruptException(
        'the header is not readable as UTF-8 JSON: ${error.message}',
      );
    }
    try {
      return _readBody(header);
    } on EventFormatException catch (error) {
      throw ContainerCorruptException(
        'the header is not a readable container: ${error.message}',
      );
    }
  }

  /// Reads the header object into a file, reporting a warning for each part it cannot read.
  static SetlistFileDecodeResult _readBody(Map<String, Object?> header) {
    final String format = EventJson.string(header, _S.format);
    if (format != setlistFileFormatTag) {
      throw ContainerCorruptException(
        'the header calls itself "$format", not "$setlistFileFormatTag"; a '
        '`.chart` file is a different kind of document',
      );
    }
    final int headerVersion = EventJson.integer(header, _S.version);
    if (headerVersion != setlistContainerVersion) {
      throw ContainerCorruptException(
        'the frame is version $setlistContainerVersion but the header inside '
        'it says $headerVersion',
      );
    }
    final String docId = EventJson.string(header, _S.docId);
    if (docId.isEmpty) {
      throw const ContainerCorruptException(
        'the document id is empty, so no operation in this container can be '
        'checked against the document it belongs to',
      );
    }
    final List<SetlistFileWarning> warnings = <SetlistFileWarning>[];
    final SetlistMetadata metadata = SetlistMetadata(
      docId: docId,
      writer: EventJson.optionalString(header, _S.writer) ?? '',
      createdAt: _readInstant(header, _S.createdAt),
      modifiedAt: _readInstant(header, _S.modifiedAt),
    );
    final Setlist snapshot = Setlist.fromJson(
      EventJson.object(header, _S.setlist),
    );
    final List<SetlistEvent> events = <SetlistEvent>[];
    final List<Object?> rawEvents = EventJson.array(header, _S.events);
    for (int index = 0; index < rawEvents.length; index++) {
      final Object? entry = rawEvents[index];
      if (entry is! Map<String, Object?>) {
        throw ContainerCorruptException('events[$index] is not a JSON object');
      }
      final DocumentEvent decoded;
      try {
        decoded = EventCodec.decode(entry);
      } on UnknownEventTypeException catch (error) {
        warnings.add(
          SetlistFileWarning(
            code: SetlistFileWarningCode.unknownEventType,
            message: _skippedMessage(index, error.message),
          ),
        );
        continue;
      } on UnsupportedEventVersionException catch (error) {
        warnings.add(
          SetlistFileWarning(
            code: SetlistFileWarningCode.unsupportedEventVersion,
            message: _skippedMessage(index, error.message),
          ),
        );
        continue;
      }
      if (decoded is! SetlistEvent) {
        throw ContainerCorruptException(
          'events[$index] is a "${decoded.type}" operation, which edits a '
          'chart; a setlist document cannot contain it',
        );
      }
      if (decoded.docId != docId) {
        throw ContainerCorruptException(
          'events[$index] belongs to document "${decoded.docId}" but this '
          'container is document "$docId"',
        );
      }
      events.add(decoded);
    }
    return SetlistFileDecodeResult(
      file: SetlistFile(metadata: metadata, snapshot: snapshot, events: events),
      warnings: warnings,
    );
  }

  /// The one wording every skipped operation uses, so a caller knows a skip means the snapshot plus
  /// the operations that were read, not an empty programme.
  static String _skippedMessage(int index, String message) =>
      'events[$index]: $message. The operation was skipped; the programme is '
      'the snapshot plus the operations this build did read.';

  /// Reads an optional ISO-8601 instant, reporting text that is not one.
  static DateTime? _readInstant(Map<String, Object?> json, String key) {
    final String? text = EventJson.optionalString(json, key);
    if (text == null) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw ContainerCorruptException(
        'field "$key" is "$text", which is not an ISO-8601 instant',
      );
    }
    return parsed.toUtc();
  }

  /// Reports a value that cannot be written as a legal container.
  static void _checkWritable(SetlistFile file) {
    if (file.metadata.docId.isEmpty) {
      throw const ContainerWriteException(
        'the metadata document id is empty; an operation log needs a document '
        'to belong to',
      );
    }
    for (int index = 0; index < file.events.length; index++) {
      final SetlistEvent event = file.events[index];
      if (event.docId != file.metadata.docId) {
        throw ContainerWriteException(
          'events[$index] belongs to document "${event.docId}" but the file is '
          'document "${file.metadata.docId}"',
        );
      }
    }
  }
}
