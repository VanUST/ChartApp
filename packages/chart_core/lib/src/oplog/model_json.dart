// PURPOSE: Turn the song-model values an event payload carries into JSON and back, so that one
//          place decides how a chord, a note, a bar or a section is written inside `events.jsonl`
//          and every event family reuses that decision. A second encoder per event would be a
//          second chance to write a bar without its volta or a note without its tie.
// INPUTS: Immutable model values from the chart domain, or the decoded JSON object a previous
//         call produced.
// OUTPUTS: A JSON object per value, and the value rebuilt from one. Decoding is strict: every
//          field is required unless the model itself can hold null (a slash bass, a volta
//          bracket, a tuplet), and a wrong or missing field throws [EventFormatException] rather
//          than producing a value with an invented default. A list read back is a fresh, mutable
//          list, so a caller mutating it cannot reach the decoded object's siblings.
// KEYWORDS: json, model-mapping, event-payload, chord, note, bar, section, key, strict-decode
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
  /// the inverse alone: a bar restored without its volta would be a silently different bar.
  static Map<String, Object?> bar(Bar bar) => <String, Object?>{
    'timeSignature': timeSignature(bar.timeSignature),
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
    'marks': <Object?>[for (final BarMark m in bar.marks) m.name],
    'staffText': <Object?>[for (final String text in bar.staffText) text],
  };

  /// Rebuilds a [Bar] from [json].
  static Bar decodeBar(Map<String, Object?> json) {
    final int? volta = EventJson.optionalInteger(json, 'volta');
    return Bar(
      timeSignature: decodeTimeSignature(
        EventJson.object(json, 'timeSignature'),
      ),
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
      marks: <BarMark>{
        for (final Object? entry in EventJson.array(json, 'marks'))
          EventJson.enumeration(
            BarMark.values,
            _asString(entry, 'marks'),
            'marks',
          ),
      },
      staffText: <String>[
        for (final Object? entry in EventJson.array(json, 'staffText'))
          _asString(entry, 'staffText'),
      ],
    );
  }

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
