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

  /// Writes a [ChordRoot] as its unreduced semitone count, its spelling preference and the note it
  /// was written as.
  ///
  /// The semitones are written as stored, not reduced to a pitch class: reducing them would make
  /// a root of 12 indistinguishable from one of 0, and the model deliberately keeps the
  /// transposition arithmetic visible on the value.
  ///
  /// `written` IS WRITTEN WHEN IT EXISTS, because it is the field that decides the spelling a
  /// musician reads. A save that dropped it would reopen the chart respelled by the key, which is
  /// the defect this field exists to close: the document would survive and the notation would not.
  static Map<String, Object?> chordRoot(ChordRoot root) {
    final WrittenNote? written = root.written;
    return <String, Object?>{
      'semitones': root.semitones,
      'preference': root.preference.name,
      'written': written == null ? null : writtenNote(written),
    };
  }

  /// Rebuilds a [ChordRoot] from [json].
  ///
  /// `written` IS READ TOLERANTLY, for the reason `Bar.size` is: no build before this field existed
  /// could write one, so its absence names exactly one state — a root whose spelling the key
  /// decides — rather than an unknown one. Every other field stays required, because a missing
  /// semitone or preference means a truncated event and a default there would make the damage look
  /// like an edit.
  static ChordRoot decodeChordRoot(Map<String, Object?> json) {
    final Map<String, Object?>? written = EventJson.optionalObject(
      json,
      'written',
    );
    return ChordRoot(
      EventJson.integer(json, 'semitones'),
      preference: EventJson.enumeration(
        SpellingPreference.values,
        EventJson.string(json, 'preference'),
        'preference',
      ),
      written: written == null ? null : decodeWrittenNote(written),
    );
  }

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

  /// Writes a [ChordMark] as the chord plus its place and engraving size.
  ///
  /// THE PLACE CARRIES THE BAR, so this payload has one address and not two: the mark's place is
  /// where it is, and a reader that finds it in a bar's list can check that the two agree. `beat`
  /// and `step` are gone with the grid; a file written before this change has no `place` and is
  /// refused by name rather than being guessed at — which is the owner's "old files do not matter,
  /// except iReal" taken literally, and a refusal a musician can read instead of a silent
  /// re-interpretation of his music.
  static Map<String, Object?> chordMark(ChordMark placed) => <String, Object?>{
    'place': placed.place.toJson(),
    'chord': chord(placed.chord),
    'size': placed.size.name,
  };

  /// Rebuilds a [ChordMark] from [json].
  static ChordMark decodeChordMark(Map<String, Object?> json) => ChordMark(
    place: EventJson.anchoredPlace(json, 'place'),
    chord: decodeChord(EventJson.object(json, 'chord')),
    size: EventJson.enumeration(
      ChordSize.values,
      EventJson.string(json, 'size'),
      'size',
    ),
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
    'chords': <Object?>[for (final ChordMark c in bar.chords) chordMark(c)],
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
      chords: <ChordMark>[
        for (final Object? entry in EventJson.array(json, 'chords'))
          decodeChordMark(_asObject(entry, 'chords')),
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
  );

  /// Writes a [DocumentState] as the song plus the two anchored collections.
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
