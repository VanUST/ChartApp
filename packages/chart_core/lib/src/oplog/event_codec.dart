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
      case 'chord.insert':
        return ChordInsertEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          chord: ModelJson.decodeBeatChord(EventJson.object(payload, 'chord')),
        );
      case 'chord.update':
        return ChordUpdateEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: ModelJson.decodeBeatChord(EventJson.object(payload, 'from')),
          to: ModelJson.decodeBeatChord(EventJson.object(payload, 'to')),
        );
      case 'chord.delete':
        return ChordDeleteEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          removed: ModelJson.decodeBeatChord(
            EventJson.object(payload, 'chord'),
          ),
        );
      case 'note.insert':
        return NoteInsertEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          note: ModelJson.decodeBeatNote(EventJson.object(payload, 'note')),
        );
      case 'note.update':
        return NoteUpdateEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: ModelJson.decodeBeatNote(EventJson.object(payload, 'from')),
          to: ModelJson.decodeBeatNote(EventJson.object(payload, 'to')),
        );
      case 'note.delete':
        return NoteDeleteEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          removed: ModelJson.decodeBeatNote(EventJson.object(payload, 'note')),
        );
      case 'measure.insert':
        return MeasureInsertEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          index: EventJson.integer(payload, 'index'),
          bar: ModelJson.decodeBar(EventJson.object(payload, 'bar')),
        );
      case 'measure.delete':
        return MeasureDeleteEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          index: EventJson.integer(payload, 'index'),
          removed: ModelJson.decodeBar(EventJson.object(payload, 'bar')),
        );
      case 'measure.duplicate':
        return MeasureDuplicateEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          index: EventJson.integer(payload, 'index'),
          duplicate: ModelJson.decodeBar(EventJson.object(payload, 'bar')),
        );
      case 'section.insert':
        return SectionInsertEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          section: ModelJson.decodeSection(
            EventJson.object(payload, 'section'),
          ),
        );
      case 'section.delete':
        return SectionDeleteEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          removed: ModelJson.decodeSection(
            EventJson.object(payload, 'section'),
          ),
        );
      case 'section.update':
        return SectionUpdateEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          from: ModelJson.decodeSectionLabel(EventJson.object(payload, 'from')),
          to: ModelJson.decodeSectionLabel(EventJson.object(payload, 'to')),
        );
      case 'section.duplicate':
        return SectionDuplicateEvent(
          docId: docId,
          seq: seq,
          sourceId: EventJson.string(payload, 'sectionId'),
          index: EventJson.integer(payload, 'index'),
          duplicate: ModelJson.decodeSection(
            EventJson.object(payload, 'section'),
          ),
        );
      case 'section.reorder':
        return SectionReorderEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          fromIndex: EventJson.integer(payload, 'fromIndex'),
          toIndex: EventJson.integer(payload, 'toIndex'),
        );
      case 'repeat.set':
        return RepeatSetEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: RepeatSigns.fromJson(EventJson.object(payload, 'from')),
          to: RepeatSigns.fromJson(EventJson.object(payload, 'to')),
        );
      case 'volta.set':
        return VoltaSetEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: _volta(EventJson.optionalInteger(payload, 'from')),
          to: _volta(EventJson.optionalInteger(payload, 'to')),
        );
      case 'mark.set':
        return BarMarkSetEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: ModelJson.decodeBarMarks(
            EventJson.array(payload, 'from'),
            'from',
          ),
          to: ModelJson.decodeBarMarks(EventJson.array(payload, 'to'), 'to'),
        );
      case 'meter.set':
        return MeterSetEvent(
          docId: docId,
          seq: seq,
          sectionId: EventJson.string(payload, 'sectionId'),
          barIndex: EventJson.integer(payload, 'bar'),
          from: _meter(EventJson.object(payload, 'from'), 'from'),
          to: _meter(EventJson.object(payload, 'to'), 'to'),
        );
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
      case 'key.transpose':
        return KeyTransposeEvent(
          docId: docId,
          seq: seq,
          semitones: EventJson.integer(payload, 'semitones'),
          fromKey: ModelJson.decodeKey(EventJson.object(payload, 'fromKey')),
          toKey: ModelJson.decodeKey(EventJson.object(payload, 'toKey')),
        );
      case 'song.update':
        return SongUpdateEvent(
          docId: docId,
          seq: seq,
          from: ModelJson.decodeSongMetadata(EventJson.object(payload, 'from')),
          to: ModelJson.decodeSongMetadata(EventJson.object(payload, 'to')),
        );
      case 'staff.set':
        return StaffSetEvent(
          docId: docId,
          seq: seq,
          from: ModelJson.decodeStaffSet(EventJson.object(payload, 'from')),
          to: ModelJson.decodeStaffSet(EventJson.object(payload, 'to')),
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
      case 'annotation.insert':
        return AnnotationInsertEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          annotation: Annotation.fromJson(
            EventJson.object(payload, 'annotation'),
          ),
        );
      case 'annotation.delete':
        return AnnotationDeleteEvent(
          docId: docId,
          seq: seq,
          index: EventJson.integer(payload, 'index'),
          removed: Annotation.fromJson(EventJson.object(payload, 'annotation')),
        );
      case 'annotation.move':
        return AnnotationMoveEvent(
          docId: docId,
          seq: seq,
          id: EventJson.string(payload, 'id'),
          from: AnchoredPlace.fromJson(EventJson.object(payload, 'from')),
          to: AnchoredPlace.fromJson(EventJson.object(payload, 'to')),
        );
      case 'annotation.duplicate':
        return AnnotationDuplicateEvent(
          docId: docId,
          seq: seq,
          sourceId: EventJson.string(payload, 'sourceId'),
          index: EventJson.integer(payload, 'index'),
          duplicate: Annotation.fromJson(
            EventJson.object(payload, 'annotation'),
          ),
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
          from: AnchoredPlace.fromJson(EventJson.object(payload, 'from')),
          to: AnchoredPlace.fromJson(EventJson.object(payload, 'to')),
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

  /// Wraps a decoded bracket number back into a [Volta], or null when the bar has none.
  static Volta? _volta(int? number) => number == null ? null : Volta(number);

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
  static TimeSignature _meter(Map<String, Object?> json, String side) {
    final TimeSignature meter = ModelJson.decodeTimeSignature(json);
    if (meter.numerator < 1 || meter.denominator < 1) {
      throw EventFormatException(
        'field "$side" names the meter $meter, whose figures must both be '
        'positive',
      );
    }
    return meter;
  }
}
