// PURPOSE: Encode every document event as one JSON object with a `type` discriminator, and read
//          one back, so that a `.chart` file's `events.jsonl` tail is the whole record and a
//          reader can rebuild the catalogue without the writer having agreed on anything else.
//          Reading an unknown type is a REPORTED FAILURE and never a skip: an event that was not
//          understood is an edit that would disappear from the document.
// INPUTS: An event, or the JSON object / JSON text a previous call produced, or the lines of an
//         `events.jsonl` tail.
// OUTPUTS: A stable JSON object per event, JSON text, and the event rebuilt from either. The
//          version field must be present and must be [documentEventFormatVersion]; a missing
//          field, a field of the wrong type, an unknown enum token and an unknown `type` all
//          raise [EventFormatException]. Blank lines in a tail are skipped because a trailing
//          newline is not an event; a malformed line is not blank and therefore fails.
// KEYWORDS: codec, events-jsonl, event-type, discriminator, strict-decode, unknown-type, version
part of 'oplog.dart';

/// The JSON codec for the document event catalogue.
abstract final class EventCodec {
  /// Writes [event] as its stable JSON object.
  static Map<String, Object?> encode(DocumentEvent event) => event.toJson();

  /// Writes [event] as one JSON text line, the unit an `events.jsonl` tail is made of.
  static String encodeLine(DocumentEvent event) => jsonEncode(event.toJson());

  /// Rebuilds an event from the JSON object [json].
  ///
  /// Throws [EventFormatException] when the object is not an event of a known type or is missing
  /// a field the type requires. The enum and number readers throw the same exception for a field
  /// of the wrong type, so a caller has exactly one failure to handle. An unknown `type` is thrown
  /// as [UnknownEventTypeException] and an unknown `v` as [UnsupportedEventVersionException], both
  /// of which are [EventFormatException]; a container that can keep reading a file written by a
  /// newer build uses those two subtypes to tell "this build does not know this event" apart from
  /// "this event is malformed".
  static DocumentEvent decode(Map<String, Object?> json) {
    final String type = EventJson.string(json, 'type');
    final String docId = EventJson.string(json, 'docId');
    final int seq = EventJson.integer(json, 'seq');
    _checkVersion(json, type);
    final Map<String, Object?> payload = EventJson.object(json, 'payload');
    return _decodePayload(type, docId, seq, payload);
  }

  /// Rebuilds an event from the JSON text [line].
  static DocumentEvent decodeLine(String line) =>
      decode(EventJson.decodeObject(line));

  /// Rebuilds every event in [lines], which is the content of an `events.jsonl` tail.
  ///
  /// Blank and whitespace-only lines are skipped, because a file that ends in a newline has a
  /// final empty line that is not an event. Anything else that cannot be read throws, with the
  /// one-based line number added to the message: a tail that cannot be read whole is reported
  /// rather than partially applied, because silently applying the readable prefix would produce
  /// a document that is neither the old one nor the new one.
  static List<DocumentEvent> decodeLines(Iterable<String> lines) {
    final List<DocumentEvent> events = <DocumentEvent>[];
    int lineNumber = 0;
    for (final String line in lines) {
      lineNumber++;
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        events.add(decodeLine(line));
      } on EventFormatException catch (error) {
        throw EventFormatException(
          'events.jsonl line $lineNumber: ${error.message}',
          type: error.type,
        );
      }
    }
    return events;
  }

  /// Checks the encoded format version, reporting a missing or unsupported one.
  static void _checkVersion(Map<String, Object?> json, String type) {
    final int? version = EventJson.optionalInteger(json, 'v');
    if (version == null) {
      throw EventFormatException('missing format version "v"', type: type);
    }
    if (version != documentEventFormatVersion) {
      throw UnsupportedEventVersionException(
        'unsupported format version $version, this build writes '
        '$documentEventFormatVersion',
        type: type,
      );
    }
  }

  /// Builds the event named by [type] from [payload].
  static DocumentEvent _decodePayload(
    String type,
    String docId,
    int seq,
    Map<String, Object?> payload,
  ) {
    switch (type) {
      case 'size.set':
        return BarSizeSetEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: ModelJson.decodeBarSize(
            EventJson.number(payload, 'from'),
            'from',
          ),
          to: ModelJson.decodeBarSize(EventJson.number(payload, 'to'), 'to'),
        );
      case 'song.update':
        return SongUpdateEvent(
          docId: docId,
          seq: seq,
          from: ModelJson.decodeSongMetadata(EventJson.object(payload, 'from')),
          to: ModelJson.decodeSongMetadata(EventJson.object(payload, 'to')),
        );
      case 'ink.stroke.add':
        return InkStrokeAddEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          stroke: InkStroke.fromJson(EventJson.object(payload, 'stroke')),
        );
      case 'ink.stroke.delete':
        return InkStrokeDeleteEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          stroke: InkStroke.fromJson(EventJson.object(payload, 'stroke')),
        );
      case 'textcue.insert':
        return TextCueInsertEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          cue: TextCue.fromJson(EventJson.object(payload, 'cue')),
        );
      case 'textcue.delete':
        return TextCueDeleteEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          removed: TextCue.fromJson(EventJson.object(payload, 'cue')),
        );
      case 'textcue.edit':
        return TextCueEditEvent(
          docId: docId,
          seq: seq,
          id: EventJson.string(payload, 'id'),
          from: EventJson.string(payload, 'from'),
          to: EventJson.string(payload, 'to'),
        );
      case 'textcue.move':
        return TextCueMoveEvent(
          docId: docId,
          seq: seq,
          id: EventJson.string(payload, 'id'),
          from: EventJson.anchoredPlace(payload, 'from'),
          to: EventJson.anchoredPlace(payload, 'to'),
        );
      case 'setlist.rename':
        return SetlistRenameEvent(
          docId: docId,
          seq: seq,
          fromTitle: EventJson.string(payload, 'fromTitle'),
          toTitle: EventJson.string(payload, 'toTitle'),
        );
      case 'setlist.item.insert':
        return SetlistItemInsertEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          item: SetlistItem.fromJson(EventJson.object(payload, 'item')),
        );
      case 'setlist.item.delete':
        return SetlistItemDeleteEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          removed: SetlistItem.fromJson(EventJson.object(payload, 'item')),
        );
      case 'setlist.item.move':
        return SetlistItemMoveEvent(
          docId: docId,
          seq: seq,
          fromIndex: EventJson.integer(payload, 'fromIndex'),
          toIndex: EventJson.integer(payload, 'toIndex'),
        );
      case 'setlist.item.update':
        return SetlistItemUpdateEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          from: SetlistItem.fromJson(EventJson.object(payload, 'from')),
          to: SetlistItem.fromJson(EventJson.object(payload, 'to')),
        );
      default:
        throw UnknownEventTypeException(
          'unknown event type "$type"; refusing to skip it because a lost event '
          'is a lost edit',
          type: type,
        );
    }
  }
  // PURPOSE: Read one side of a `bars.*` event as a list of whole bars, so the three events that
  //          carry a run of bars cannot decode it differently.
  // INPUTS: json — the event payload. key — which list it is (`bars`, `from` or `to`), so a failure
  //         names the field.
  // OUTPUTS: The decoded bars, in order. An entry that is not an object is refused with the key and
  //          the position, because a run whose third bar could not be read is not a run this build
  //          can apply, and skipping it would paste fewer bars than were copied.
  // KEYWORDS: bars-decode, array-of-objects, named-field, strict, no-partial-run
  // PURPOSE: Read the strokes a `bars.*` event carries, as whole canonical strokes.
  // INPUTS: json — the event payload. key — which list it is, so a failure names the field.
  // OUTPUTS: The decoded strokes, in order. [InkStroke.fromJson] is the one reader of a stroke's
  //          shape, so a stroke that arrived through a `bars.insert` is read by exactly the code that
  //          reads one that arrived through `ink.stroke.add`.
  // KEYWORDS: stroke-decode, whole-value, one-reader, named-field, strict
  // PURPOSE: Read the re-addressing a `bars.insert` causes, so a log replayed on another device
  //          produces the same document as the device that made it.
  // INPUTS: json — the event payload. key — the field name.
  // OUTPUTS: The decoded moves, in order. An entry that is not an object is refused with the key and
  //          the position: a move that could not be read is a mark that would stay on the wrong bar.
  // KEYWORDS: anchor-move-decode, deterministic-replay, named-field, strict
  // PURPOSE: Read one side of a `division.set`, so that a division survives the file exactly as the
  //          document held it.
  // INPUTS: json — the event payload. key — the field name, `from` or `to`.
  // OUTPUTS: The decoded [BarDivision] values, in order. [BarDivision.fromJson] is the one reader
  //          of a division's shape and refuses a non-positive height, which is the state the
  //          display rule could not draw; an entry that is not an object is refused here with the
  //          key and the position rather than skipped, because a skipped division is a line the
  //          musician sees missing from a chart that saved without complaint.
  // KEYWORDS: division-decode, whole-value, one-reader, named-field, strict
  // PURPOSE: Read one side of a `meter.set`, refusing a meter the model cannot hold.
  // INPUTS: json — the `from` or `to` object. side — which side it is, so a failure names it.
  // OUTPUTS: The decoded [TimeSignature]. The two figures are read with the same strict integer
  //          reader every other numeric field uses, so a missing figure, a figure of the wrong type
  //          and a fractional figure are all [EventFormatException]s; on top of that, a figure
  //          below one is refused here rather than stored.
  //
  //          WHY POSITIVITY IS CHECKED HERE AND NOT ONLY AT THE INPUT SURFACE. A bar of zero beats
  //          is not a state the layout can be asked to draw, and this event is the only path by
  //          which a meter is written after import. A file carrying one would otherwise put the
  //          document into a state no surface can repair, because every surface that could set a
  //          meter would refuse to write the zero it would have to read first.
  //
  //          WHY THE UPPER BOUND IS NOT CHECKED HERE. `maxMeterFigure` bounds what a musician can
  //          TYPE; refusing a figure already written into a saved file would make the file
  //          unopenable rather than merely odd, which is a worse failure than loading it.
  // KEYWORDS: meter-decode, strict, positivity, typed-failure, no-silent-default
}
