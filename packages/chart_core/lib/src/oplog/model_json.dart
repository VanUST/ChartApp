// PURPOSE: Turn the song-model values an event payload carries into JSON and back — and, at the
//          top of that ladder, a whole song and a whole document, which is the snapshot a
//          `.chart` container stores. One place decides how a chord, a note, a bar, a section, a
//          staff set or a song is written and read; every event family and the container reuse
//          that decision. A second encoder per caller would be a second chance to write a bar
//          without its volta or a note without its tie.
// INPUTS: Immutable model values from the chart domain, or the decoded JSON object a previous
//         call produced.
// OUTPUTS: A JSON object per value, and the value rebuilt from one. Decoding is strict: every
//          field is required unless the model itself can hold null (a slash bass, a volta
//          bracket, a tuplet, a staff slot), and a wrong or missing field throws
//          [EventFormatException] rather than producing a value with an invented default. A list
//          read back is a fresh, mutable list, so a caller mutating it cannot reach the decoded
//          object's siblings.
// KEYWORDS: json, model-mapping, event-payload, chord, note, bar, section, key, song, staff-set, strict-decode
part of 'oplog.dart';

/// The JSON mapping of the chart model's value types.
///
/// Every method that writes a value has a matching method that reads it, and the two are kept
/// next to each other so a field added to the model is a visible edit in one file rather than a
/// hunt through the catalogue.
abstract final class ModelJson {
  /// Writes a [WrittenNote] as its letter and alteration.
  static Map<String, Object?> writtenNote(WrittenNote note) =>
      <String, Object?>{'letter': note.letter.name, 'alter': note.alter};

  /// Rebuilds a [WrittenNote] from [json].
  static WrittenNote decodeWrittenNote(Map<String, Object?> json) =>
      WrittenNote(
        EventJson.enumeration(
          NoteLetter.values,
          EventJson.string(json, 'letter'),
          'letter',
        ),
        EventJson.integer(json, 'alter'),
      );

  /// Writes a [ChordRoot] as its unreduced semitone count and spelling preference.
  ///
  /// The semitones are written as stored, not reduced to a pitch class: reducing them would make
  /// a root of 12 indistinguishable from one of 0, and the model deliberately keeps the
  /// transposition arithmetic visible on the value.
  static Map<String, Object?> chordRoot(ChordRoot root) => <String, Object?>{
    'semitones': root.semitones,
    'preference': root.preference.name,
  };

  /// Rebuilds a [ChordRoot] from [json].
  static ChordRoot decodeChordRoot(Map<String, Object?> json) => ChordRoot(
    EventJson.integer(json, 'semitones'),
    preference: EventJson.enumeration(
      SpellingPreference.values,
      EventJson.string(json, 'preference'),
      'preference',
    ),
  );

  /// Writes a [Chord] as root, quality token, optional slash bass and optional alternate.
  static Map<String, Object?> chord(Chord chord) {
    final ChordRoot? bass = chord.bass;
    final Chord? alternate = chord.alternate;
    return <String, Object?>{
      'root': chordRoot(chord.root),
      'quality': chord.quality.token,
      'bass': bass == null ? null : chordRoot(bass),
      'alternate': alternate == null ? null : ModelJson.chord(alternate),
    };
  }

  /// Rebuilds a [Chord] from [json].
  static Chord decodeChord(Map<String, Object?> json) {
    final Map<String, Object?>? bass = EventJson.optionalObject(json, 'bass');
    final Map<String, Object?>? alternate = EventJson.optionalObject(
      json,
      'alternate',
    );
    return Chord(
      root: decodeChordRoot(EventJson.object(json, 'root')),
      quality: ChordQuality(EventJson.string(json, 'quality')),
      bass: bass == null ? null : decodeChordRoot(bass),
      alternate: alternate == null ? null : decodeChord(alternate),
    );
  }

  /// Writes a [TimeSignature] as its two written figures.
  static Map<String, Object?> timeSignature(TimeSignature time) =>
      <String, Object?>{
        'numerator': time.numerator,
        'denominator': time.denominator,
      };

  /// Rebuilds a [TimeSignature] from [json].
  static TimeSignature decodeTimeSignature(Map<String, Object?> json) =>
      TimeSignature(
        numerator: EventJson.integer(json, 'numerator'),
        denominator: EventJson.integer(json, 'denominator'),
      );

  /// Writes a [NoteValue] as its base, dot count and optional tuplet ratio.
  static Map<String, Object?> noteValue(NoteValue value) {
    final Tuplet? tuplet = value.tuplet;
    return <String, Object?>{
      'base': value.base.name,
      'dots': value.dots,
      'tuplet': tuplet == null
          ? null
          : <String, Object?>{'actual': tuplet.actual, 'normal': tuplet.normal},
    };
  }

  /// Rebuilds a [NoteValue] from [json].
  static NoteValue decodeNoteValue(Map<String, Object?> json) {
    final Map<String, Object?>? tuplet = EventJson.optionalObject(
      json,
      'tuplet',
    );
    return NoteValue(
      base: EventJson.enumeration(
        NoteBase.values,
        EventJson.string(json, 'base'),
        'base',
      ),
      dots: EventJson.integer(json, 'dots'),
      tuplet: tuplet == null
          ? null
          : Tuplet(
              actual: EventJson.integer(tuplet, 'actual'),
              normal: EventJson.integer(tuplet, 'normal'),
            ),
    );
  }

  /// Writes a [PitchedNote] as its written pitch and octave.
  static Map<String, Object?> pitchedNote(PitchedNote pitch) =>
      <String, Object?>{
        'note': writtenNote(pitch.note),
        'octave': pitch.octave,
      };

  /// Rebuilds a [PitchedNote] from [json].
  static PitchedNote decodePitchedNote(Map<String, Object?> json) =>
      PitchedNote(
        note: decodeWrittenNote(EventJson.object(json, 'note')),
        octave: EventJson.integer(json, 'octave'),
      );

  /// Writes a [BeatChord] as the chord plus its address and engraving size.
  static Map<String, Object?> beatChord(BeatChord placed) => <String, Object?>{
    'chord': chord(placed.chord),
    'beat': placed.beat,
    'step': placed.step,
    'size': placed.size.name,
  };

  /// Rebuilds a [BeatChord] from [json].
  static BeatChord decodeBeatChord(Map<String, Object?> json) => BeatChord(
    chord: decodeChord(EventJson.object(json, 'chord')),
    beat: EventJson.integer(json, 'beat'),
    step: EventJson.integer(json, 'step'),
    size: EventJson.enumeration(
      ChordSize.values,
      EventJson.string(json, 'size'),
      'size',
    ),
  );

  /// Writes a [BeatNote] as its pitch, written duration, address and tie.
  static Map<String, Object?> beatNote(BeatNote note) => <String, Object?>{
    'pitch': pitchedNote(note.pitch),
    'value': noteValue(note.value),
    'beat': note.beat,
    'step': note.step,
    'tiedToNext': note.tiedToNext,
  };

  /// Rebuilds a [BeatNote] from [json].
  static BeatNote decodeBeatNote(Map<String, Object?> json) => BeatNote(
    pitch: decodePitchedNote(EventJson.object(json, 'pitch')),
    value: decodeNoteValue(EventJson.object(json, 'value')),
    beat: EventJson.integer(json, 'beat'),
    step: EventJson.integer(json, 'step'),
    tiedToNext: EventJson.boolean(json, 'tiedToNext'),
  );

  /// Writes a [PercussionHit] as its instrument, written duration and address.
  static Map<String, Object?> percussionHit(PercussionHit hit) =>
      <String, Object?>{
        'instrument': hit.instrument,
        'value': noteValue(hit.value),
        'beat': hit.beat,
        'step': hit.step,
      };

  /// Rebuilds a [PercussionHit] from [json].
  static PercussionHit decodePercussionHit(Map<String, Object?> json) =>
      PercussionHit(
        instrument: EventJson.integer(json, 'instrument'),
        value: decodeNoteValue(EventJson.object(json, 'value')),
        beat: EventJson.integer(json, 'beat'),
        step: EventJson.integer(json, 'step'),
      );

  /// Writes a [Bar] with every field the model carries, including the structural signs.
  ///
  /// All of them are written because a `measure.*` event carries a whole bar and carries it for
  /// the inverse alone: a bar restored without its volta would be a silently different bar. The
  /// same argument covers [BarSize]: a bar restored at the wrong size is a bar the musician did not
  /// set, and because a `measure.delete` undo re-inserts the bar it removed, the size has to travel
  /// with it or an undo would silently reset a width he chose.
  static Map<String, Object?> bar(Bar bar) => <String, Object?>{
    'timeSignature': timeSignature(bar.timeSignature),
    'size': bar.size.factor,
    'chords': <Object?>[for (final BeatChord c in bar.chords) beatChord(c)],
    'melody': <Object?>[for (final BeatNote n in bar.melody) beatNote(n)],
    'percussion': <Object?>[
      for (final PercussionHit h in bar.percussion) percussionHit(h),
    ],
    'openingBarline': bar.openingBarline.name,
    'closingBarline': bar.closingBarline.name,
    'volta': bar.volta?.number,
    'repeatPrevious': bar.repeatPrevious.name,
    'slashRepeat': bar.slashRepeat,
    'noChord': bar.noChord,
    'marks': barMarks(bar.marks),
    'staffText': <Object?>[for (final String text in bar.staffText) text],
  };

  /// Rebuilds a [Bar] from [json].
  ///
  /// `size` IS READ TOLERANTLY, AND IT IS THE ONLY FIELD THAT IS. Every other field of a bar is
  /// required, because a missing one means a truncated event and a default would make the damage
  /// look like an edit that cleared something. A missing `size` is not that case: no build before
  /// this field existed could express any value other than [BarSize.natural], so absence names
  /// exactly one value rather than an unknown one, and refusing the file would make every chart and
  /// every operation tail written by the previous build unreadable. What is NOT tolerated is a
  /// factor the engraver cannot honour — see [decodeBarSize], which reports it rather than
  /// defaulting it.
  static Bar decodeBar(Map<String, Object?> json) {
    final int? volta = EventJson.optionalInteger(json, 'volta');
    return Bar(
      timeSignature: decodeTimeSignature(
        EventJson.object(json, 'timeSignature'),
      ),
      size: decodeBarSize(EventJson.optionalNumber(json, 'size'), 'size'),
      chords: <BeatChord>[
        for (final Object? entry in EventJson.array(json, 'chords'))
          decodeBeatChord(_asObject(entry, 'chords')),
      ],
      melody: <BeatNote>[
        for (final Object? entry in EventJson.array(json, 'melody'))
          decodeBeatNote(_asObject(entry, 'melody')),
      ],
      percussion: <PercussionHit>[
        for (final Object? entry in EventJson.array(json, 'percussion'))
          decodePercussionHit(_asObject(entry, 'percussion')),
      ],
      openingBarline: EventJson.enumeration(
        Barline.values,
        EventJson.string(json, 'openingBarline'),
        'openingBarline',
      ),
      closingBarline: EventJson.enumeration(
        Barline.values,
        EventJson.string(json, 'closingBarline'),
        'closingBarline',
      ),
      volta: volta == null ? null : Volta(volta),
      repeatPrevious: EventJson.enumeration(
        RepeatPrevious.values,
        EventJson.string(json, 'repeatPrevious'),
        'repeatPrevious',
      ),
      slashRepeat: EventJson.boolean(json, 'slashRepeat'),
      noChord: EventJson.boolean(json, 'noChord'),
      marks: decodeBarMarks(EventJson.array(json, 'marks'), 'marks'),
      staffText: <String>[
        for (final Object? entry in EventJson.array(json, 'staffText'))
          _asString(entry, 'staffText'),
      ],
    );
  }

  /// Rebuilds a [BarSize] from the factor a bar or an event carries, naming [field] in a failure.
  ///
  /// A NULL FACTOR IS THE NATURAL BAR, because a bar that was never resized writes nothing anywhere
  /// in this format and an older file carries no `size` at all: absence can only mean the one value
  /// every bar had before the property existed. Every other shape of the value is a reported
  /// failure and never a default —
  ///
  ///   * a non-finite factor would put a bar's rectangle at infinity or at NaN, and a bar drawn at
  ///     NaN is invisible rather than visibly wrong;
  ///   * a factor below 1 asks the engraver to squeeze the bar's cells, and the surplus it would
  ///     have to give back is shared out over EVERY cell, including the ones holding chords — so a
  ///     chord would be drawn over its neighbour on the chord line, which is the one thing the
  ///     width of a bar may never do. The model's own constructor asserts this, and the reader
  ///     checks it here as well because a decode path must not depend on asserts being enabled.
  ///
  /// A factor ABOVE the top of [BarSize.ladder] is deliberately accepted. That is the `meter.set`
  /// rule: refusing a value already written into a saved file would make the file unopenable rather
  /// than merely unusual, and a future build that offers a wider ladder must stay readable by this
  /// one.
  static BarSize decodeBarSize(double? factor, String field) {
    if (factor == null) {
      return BarSize.natural;
    }
    if (!factor.isFinite) {
      throw EventFormatException(
        'field "$field" names a bar size of $factor, which is not a width',
      );
    }
    if (factor < BarSize.natural.factor) {
      throw EventFormatException(
        'field "$field" names a bar size of $factor, and a bar may not be drawn '
        'narrower than ${BarSize.natural.factor} times its own content',
      );
    }
    return BarSize(factor);
  }

  /// Writes a set of [BarMark]s as the list of their names.
  ///
  /// The SET'S OWN ITERATION ORDER is what is written, because that is the order the painter joins
  /// the glyphs in and the order a `mark.set` carries on both sides. Writing it sorted would be a
  /// second opinion about the order, and a bar round-tripped through JSON would then draw its signs
  /// in a different order than the bar that was written.
  static List<Object?> barMarks(Set<BarMark> marks) => <Object?>[
    for (final BarMark mark in marks) mark.name,
  ];

  /// Rebuilds a set of [BarMark]s from the array [entries], naming [field] in a failure.
  ///
  /// Throws [EventFormatException] when an entry is not a string, or names a mark this build does
  /// not have, rather than dropping it: a dropped sign is a sign the musician put on the bar and the
  /// page no longer shows. A name repeated in [entries] collapses, because the model stores a set —
  /// that is the model's own shape and not a default invented here.
  static Set<BarMark> decodeBarMarks(List<Object?> entries, String field) =>
      <BarMark>{
        for (final Object? entry in entries)
          EventJson.enumeration(BarMark.values, _asString(entry, field), field),
      };

  /// Writes a [SectionLabel] as its kind and text.
  static Map<String, Object?> sectionLabel(SectionLabel label) =>
      <String, Object?>{'kind': label.kind.name, 'text': label.text};

  /// Rebuilds a [SectionLabel] from [json].
  static SectionLabel decodeSectionLabel(Map<String, Object?> json) =>
      SectionLabel(
        kind: EventJson.enumeration(
          SectionKind.values,
          EventJson.string(json, 'kind'),
          'kind',
        ),
        text: EventJson.string(json, 'text'),
      );

  /// Writes a [Section] as its stable id, label and bars in order.
  static Map<String, Object?> section(Section section) => <String, Object?>{
    'id': section.id,
    'label': sectionLabel(section.label),
    'bars': <Object?>[for (final Bar bar in section.bars) ModelJson.bar(bar)],
  };

  /// Rebuilds a [Section] from [json].
  static Section decodeSection(Map<String, Object?> json) => Section(
    id: EventJson.string(json, 'id'),
    label: decodeSectionLabel(EventJson.object(json, 'label')),
    bars: <Bar>[
      for (final Object? entry in EventJson.array(json, 'bars'))
        decodeBar(_asObject(entry, 'bars')),
    ],
  );

  /// Writes a [Key] as its spelled tonic and mode.
  static Map<String, Object?> key(Key key) => <String, Object?>{
    'tonic': writtenNote(key.tonic),
    'mode': key.mode.name,
  };

  /// Rebuilds a [Key] from [json].
  static Key decodeKey(Map<String, Object?> json) => Key(
    tonic: decodeWrittenNote(EventJson.object(json, 'tonic')),
    mode: EventJson.enumeration(
      Mode.values,
      EventJson.string(json, 'mode'),
      'mode',
    ),
  );

  /// Writes a [StaffSpec] as its kind, clef and — for a percussion staff — its drum map.
  ///
  /// The drum map's instrument numbers are written as JSON object keys, which JSON forces to be
  /// strings. That is the only reason the reader has to parse them back, and the reader reports a
  /// key that is not a number rather than dropping the instrument.
  static Map<String, Object?> staffSpec(StaffSpec spec) {
    final Map<int, String>? drumMap = spec.drumMap;
    return <String, Object?>{
      'kind': spec.kind.name,
      'clef': spec.clef,
      'drumMap': drumMap == null
          ? null
          : <String, Object?>{
              for (final MapEntry<int, String> entry in drumMap.entries)
                '${entry.key}': entry.value,
            },
    };
  }

  /// Rebuilds a [StaffSpec] from [json], enforcing the rule the model's own constructor asserts.
  ///
  /// The two states the model forbids — a pitched staff carrying a drum map, and a percussion
  /// staff without one — are reported as [EventFormatException] rather than reaching the assert,
  /// because a decode path must not depend on asserts being enabled.
  static StaffSpec decodeStaffSpec(Map<String, Object?> json) {
    final StaffKind kind = EventJson.enumeration(
      StaffKind.values,
      EventJson.string(json, 'kind'),
      'kind',
    );
    final Map<String, Object?>? rawMap = EventJson.optionalObject(
      json,
      'drumMap',
    );
    final Map<int, String>? drumMap = rawMap == null
        ? null
        : _decodeDrumMap(rawMap);
    if (kind == StaffKind.pitched && drumMap != null) {
      throw const EventFormatException(
        'field "drumMap" is present on a pitched staff, which reads notes, '
        'not a drum map',
      );
    }
    if (kind == StaffKind.percussion && drumMap == null) {
      throw const EventFormatException(
        'a percussion staff without field "drumMap" has no way to name what '
        'is struck',
      );
    }
    return StaffSpec(
      kind: kind,
      drumMap: drumMap,
      clef: EventJson.string(json, 'clef'),
    );
  }

  /// Rebuilds a drum map from its JSON object, reporting an instrument key that is not a number.
  static Map<int, String> _decodeDrumMap(Map<String, Object?> json) {
    final Map<int, String> drumMap = <int, String>{};
    for (final MapEntry<String, Object?> entry in json.entries) {
      final int? instrument = int.tryParse(entry.key);
      if (instrument == null) {
        throw EventFormatException(
          'an entry of "drumMap" has key "${entry.key}", which is not an '
          'instrument number',
        );
      }
      final Object? label = entry.value;
      if (label is! String) {
        throw EventFormatException(
          'the label of drum-map instrument $instrument is not a string',
        );
      }
      drumMap[instrument] = label;
    }
    return drumMap;
  }

  /// Writes a [StaffSet] as its optional pitched and percussion slots.
  static Map<String, Object?> staffSet(StaffSet set) {
    final StaffSpec? pitched = set.pitched;
    final StaffSpec? percussion = set.percussion;
    return <String, Object?>{
      'pitched': pitched == null ? null : staffSpec(pitched),
      'percussion': percussion == null ? null : staffSpec(percussion),
    };
  }

  /// Rebuilds a [StaffSet] from [json], reporting a staff placed in the wrong slot.
  static StaffSet decodeStaffSet(Map<String, Object?> json) {
    final Map<String, Object?>? pitched = EventJson.optionalObject(
      json,
      'pitched',
    );
    final Map<String, Object?>? percussion = EventJson.optionalObject(
      json,
      'percussion',
    );
    return StaffSet(
      pitched: pitched == null
          ? null
          : _staffOfKind(pitched, StaffKind.pitched, 'pitched'),
      percussion: percussion == null
          ? null
          : _staffOfKind(percussion, StaffKind.percussion, 'percussion'),
    );
  }

  /// Rebuilds the staff at [field] and reports it when its kind is not [kind].
  static StaffSpec _staffOfKind(
    Map<String, Object?> json,
    StaffKind kind,
    String field,
  ) {
    final StaffSpec spec = decodeStaffSpec(json);
    if (spec.kind != kind) {
      throw EventFormatException(
        'field "$field" holds a ${spec.kind.name} staff where a ${kind.name} '
        'one belongs',
      );
    }
    return spec;
  }

  /// Writes a [SongMetadata] as the four fields it carries.
  ///
  /// All four are written every time, including an empty title and a zero tempo, so that a reader
  /// never has to decide what an absent field means. The reader below enforces the other half of
  /// that rule: a missing field is a typed failure rather than a default, because a default would
  /// make a truncated event look like an edit that cleared a title.
  static Map<String, Object?> songMetadata(SongMetadata metadata) =>
      <String, Object?>{
        'title': metadata.title,
        'composer': metadata.composer,
        'style': metadata.style,
        'tempo': metadata.tempo,
      };

  /// Rebuilds a [SongMetadata] from [json].
  ///
  /// Throws [EventFormatException] when any of the four fields is absent or of the wrong type. A
  /// PARTIAL update is therefore not expressible on the wire, which is deliberate: the event's
  /// inverse is the same four fields swapped, so a payload that carried only the field being
  /// changed would leave the inverse unable to name the values it must restore. A caller that
  /// wants to change one field fills the other three from the document it is editing.
  static SongMetadata decodeSongMetadata(Map<String, Object?> json) =>
      SongMetadata(
        title: EventJson.string(json, 'title'),
        composer: EventJson.string(json, 'composer'),
        style: EventJson.string(json, 'style'),
        tempo: EventJson.integer(json, 'tempo'),
      );

  /// Writes a [Song] as its identity, its metadata and its sections in order.
  ///
  /// The whole song is written, including the empty strings and the zero tempo, because this
  /// mapping is what a `.chart` container stores as the document the log starts from: a reader
  /// that cannot understand the newest operation still has the song the writer saw.
  static Map<String, Object?> song(Song song) => <String, Object?>{
    'id': song.id,
    'title': song.title,
    'composer': song.composer,
    'style': song.style,
    'key': key(song.key),
    'tempo': song.tempo,
    'staffSet': staffSet(song.staffSet),
    'sections': <Object?>[
      for (final Section section in song.sections) ModelJson.section(section),
    ],
  };

  /// Rebuilds a [Song] from [json].
  static Song decodeSong(Map<String, Object?> json) => Song(
    id: EventJson.string(json, 'id'),
    title: EventJson.string(json, 'title'),
    composer: EventJson.string(json, 'composer'),
    style: EventJson.string(json, 'style'),
    key: decodeKey(EventJson.object(json, 'key')),
    tempo: EventJson.integer(json, 'tempo'),
    sections: <Section>[
      for (final Object? entry in EventJson.array(json, 'sections'))
        decodeSection(_asObject(entry, 'sections')),
    ],
    staffSet: decodeStaffSet(EventJson.object(json, 'staffSet')),
  );

  /// Writes a [DocumentState] as the song plus the three anchored collections.
  ///
  /// This is the materialised snapshot a container stores so that opening a document does not
  /// depend on replaying every operation, and so that a reader which cannot understand a newer
  /// operation still recovers the document as of the snapshot.
  static Map<String, Object?> documentState(DocumentState state) =>
      <String, Object?>{
        'song': song(state.song),
        'strokes': <Object?>[
          for (final InkStroke stroke in state.strokes) stroke.toJson(),
        ],
        'annotations': <Object?>[
          for (final Annotation annotation in state.annotations)
            annotation.toJson(),
        ],
        'textCues': <Object?>[
          for (final TextCue cue in state.textCues) cue.toJson(),
        ],
      };

  /// Rebuilds a [DocumentState] from [json].
  static DocumentState decodeDocumentState(Map<String, Object?> json) =>
      DocumentState(
        song: decodeSong(EventJson.object(json, 'song')),
        strokes: <InkStroke>[
          for (final Object? entry in EventJson.array(json, 'strokes'))
            InkStroke.fromJson(_asObject(entry, 'strokes')),
        ],
        annotations: <Annotation>[
          for (final Object? entry in EventJson.array(json, 'annotations'))
            Annotation.fromJson(_asObject(entry, 'annotations')),
        ],
        textCues: <TextCue>[
          for (final Object? entry in EventJson.array(json, 'textCues'))
            TextCue.fromJson(_asObject(entry, 'textCues')),
        ],
      );

  /// Rebuilds a JSON object from an array entry of [field], reporting the field when it is not one.
  static Map<String, Object?> _asObject(Object? entry, String field) {
    if (entry is! Map<String, Object?>) {
      throw EventFormatException('an entry of "$field" is not a JSON object');
    }
    return entry;
  }

  /// Rebuilds a JSON string from an array entry of [field], reporting the field when it is not one.
  static String _asString(Object? entry, String field) {
    if (entry is! String) {
      throw EventFormatException('an entry of "$field" is not a string');
    }
    return entry;
  }
}
