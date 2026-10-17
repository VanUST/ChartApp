// PURPOSE: Give the reducer a way to build a new song, section or bar with one field changed,
//          without restating every other field at each call site and without touching the model
//          classes themselves. The reducer's whole job is "the same value with one thing
//          different", and a clone written by hand in twenty places is twenty chances to drop a
//          bar's volta or a song's staff set.
// INPUTS: The value to copy and the fields to replace. A null argument means "leave this field
//         alone"; an empty collection must be passed explicitly to clear one.
// OUTPUTS: A new immutable value of the same type. `Bar.copyWith` is the one case where leaving a
//          field alone and clearing it cannot both be spelled by a null — the bracket is itself
//          nullable — so clearing it takes the explicit [Bar] `clearVolta` flag rather than a
//          nullable parameter that would silently mean two things.
// KEYWORDS: copy-with, immutable-update, extension, nullable-field, clear-flag, reducer-support
part of 'oplog.dart';

/// Field-replacing copies of a [Bar].
extension BarEditing on Bar {
  /// Returns a copy of this bar with the named fields replaced.
  ///
  /// See the extension contract for the null-versus-clear rule; the bracket is cleared with
  /// [clearVolta], not by passing a null `volta`.
  Bar copyWith({
    TimeSignature? timeSignature,
    BarSize? size,
    List<BeatChord>? chords,
    List<BeatNote>? melody,
    List<PercussionHit>? percussion,
    Barline? openingBarline,
    Barline? closingBarline,
    Volta? volta,
    bool clearVolta = false,
    RepeatPrevious? repeatPrevious,
    bool? slashRepeat,
    bool? noChord,
    Set<BarMark>? marks,
    List<String>? staffText,
  }) => Bar(
    timeSignature: timeSignature ?? this.timeSignature,
    size: size ?? this.size,
    chords: chords ?? this.chords,
    melody: melody ?? this.melody,
    percussion: percussion ?? this.percussion,
    openingBarline: openingBarline ?? this.openingBarline,
    closingBarline: closingBarline ?? this.closingBarline,
    volta: clearVolta ? null : (volta ?? this.volta),
    repeatPrevious: repeatPrevious ?? this.repeatPrevious,
    slashRepeat: slashRepeat ?? this.slashRepeat,
    noChord: noChord ?? this.noChord,
    marks: marks ?? this.marks,
    staffText: staffText ?? this.staffText,
  );
}

/// Field-replacing copies of a [Section].
extension SectionEditing on Section {
  /// Returns a copy of this section with the named fields replaced.
  Section copyWith({String? id, SectionLabel? label, List<Bar>? bars}) =>
      Section(
        id: id ?? this.id,
        label: label ?? this.label,
        bars: bars ?? this.bars,
      );
}

/// Field-replacing copies of a [Song].
extension SongEditing on Song {
  /// Returns a copy of this song with the named fields replaced.
  Song copyWith({
    String? id,
    String? title,
    String? composer,
    String? style,
    Key? key,
    int? tempo,
    List<Section>? sections,
    StaffSet? staffSet,
  }) => Song(
    id: id ?? this.id,
    title: title ?? this.title,
    composer: composer ?? this.composer,
    style: style ?? this.style,
    key: key ?? this.key,
    tempo: tempo ?? this.tempo,
    sections: sections ?? this.sections,
    staffSet: staffSet ?? this.staffSet,
  );

  /// Returns a copy of this song carrying [metadata]'s four fields.
  ///
  /// The identity, the key, the sections and the staves are left alone: a `song.update` says what
  /// the tune is CALLED and how it is played, not where it sits or what is written in it. Passing
  /// an empty title or a zero tempo is therefore meaningful — they are the values the model uses
  /// for "unnamed" and "no tempo" — which is why this takes a whole [SongMetadata] rather than
  /// nullable fields that would have to mean two things.
  Song withMetadata(SongMetadata metadata) => copyWith(
    title: metadata.title,
    composer: metadata.composer,
    style: metadata.style,
    tempo: metadata.tempo,
  );
}
