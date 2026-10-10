// PURPOSE: Describe which staves a song carries and what each one means, so that a melody and a
//          drum part can coexist with the chord line under one document model instead of three
//          incompatible ones. The decision this implements (owner decision D16) is that the
//          pitched melodic staff is first-class for every user including drummers, and that a
//          percussion staff is added ALONGSIDE it rather than replacing it.
// INPUTS: A StaffKind, an optional drum map, and a clef name.
// OUTPUTS: Immutable StaffSpec values and a StaffSet that can hold at most one pitched and at
//          most one percussion staff. An empty StaffSet means the song is chords only, which is
//          the state every imported chart starts in.
// KEYWORDS: staff, staff-set, percussion, drum-map, melody, clef, transpose-scope
//
// WHY StaffSet IS A TYPE AND NOT A List<StaffSpec>.
//
// The decision states an invariant: zero or one pitched staff, zero or one percussion staff. A
// list cannot express it — nothing stops a caller appending a second pitched staff, and the
// failure would surface later as two melodies laid out on top of each other. Naming the two slots
// makes that state unrepresentable, and it also makes the transpose rule readable: only the
// pitched staff transposes, and it is the only one that CAN, so `StaffSet.pitched` being null is
// exactly the condition under which a PDF or a drum-only chart must disable transposition.

/// What a staff carries.
enum StaffKind {
  /// Pitched notation: a melody, a bass line, anything read as notes.
  ///
  /// This staff transposes. It is the only one that does.
  pitched,

  /// Unpitched percussion, read through a drum map rather than at a pitch.
  ///
  /// A drum part does not transpose: a kick drum is not a whole tone higher because the chart
  /// moved up a tone. This is why the kind is part of the model rather than a flag on a staff.
  percussion,
}

/// One staff of a song.
class StaffSpec {
  /// Creates a staff of [kind].
  ///
  /// Prefer [StaffSpec.pitched] and [StaffSpec.percussion], which cannot be built in a
  /// self-contradictory state. This constructor exists so the two named ones can share a body,
  /// and it asserts the same rules in debug builds: a pitched staff must carry no drum map, and a
  /// percussion staff must carry one.
  const StaffSpec({required this.kind, this.drumMap, this.clef = 'treble'})
    : assert(
        kind != StaffKind.pitched || drumMap == null,
        'a pitched staff reads notes, not a drum map',
      ),
      assert(
        kind != StaffKind.percussion || drumMap != null,
        'a percussion staff without a drum map has no way to name what is struck',
      );

  /// Creates a pitched staff, optionally naming its [clef].
  const StaffSpec.pitched({String clef = 'treble'})
    : this(kind: StaffKind.pitched, clef: clef);

  /// Creates a percussion staff reading through [drumMap].
  const StaffSpec.percussion({
    required Map<int, String> drumMap,
    String clef = 'percussion',
  }) : this(kind: StaffKind.percussion, drumMap: drumMap, clef: clef);

  /// What this staff carries.
  final StaffKind kind;

  /// Instrument number to the label shown when a note is placed on this staff.
  ///
  /// The numbers are MIDI percussion note numbers, which is the one vocabulary every drum source
  /// in this domain already speaks, and the labels are what the editor shows as a tooltip. Null
  /// for a pitched staff. The map is data rather than code: a real chart's kit is whatever its
  /// author used, so this model names no instruments of its own.
  final Map<int, String>? drumMap;

  /// The clef the staff is engraved in, as a name the renderer understands.
  ///
  /// A string rather than an enum because the set of clefs is a rendering concern that will grow
  /// (octave transpositions, percussion, tablature), and a closed enum here would mean a model
  /// change for every engravable detail.
  final String clef;

  @override
  bool operator ==(Object other) {
    if (other is! StaffSpec || other.kind != kind || other.clef != clef) {
      return false;
    }
    final Map<int, String>? mine = drumMap;
    final Map<int, String>? theirs = other.drumMap;
    if (mine == null || theirs == null) {
      return mine == null && theirs == null;
    }
    if (mine.length != theirs.length) {
      return false;
    }
    for (final MapEntry<int, String> entry in mine.entries) {
      if (theirs[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    clef,
    drumMap == null ? null : Object.hashAllUnordered(drumMap!.entries),
  );

  @override
  String toString() =>
      'StaffSpec(${kind.name}, $clef${drumMap == null ? '' : ', ${drumMap!.length} instrument(s)'})';
}

/// The staves of a song: the chord line is implicit and always present, plus at most one pitched
/// staff and at most one percussion staff.
class StaffSet {
  /// Creates a staff set from an optional [pitched] staff and an optional [percussion] staff,
  /// trusting the caller that each slot holds the right kind.
  ///
  /// Prefer [StaffSet.of], which checks. This constructor is the one the named factories and
  /// [chordsOnly] go through, and it cannot validate: a const constructor's assertions may only
  /// use potentially constant expressions, and reading `pitched.kind` is a getter call. That rule
  /// was measured the hard way once already (see the `const` entry in the decision journal) — the
  /// asserts below are deliberately restricted to comparing parameters and constants.
  const StaffSet({this.pitched, this.percussion});

  // PURPOSE: Build a staff set with the slots checked, which is the path callers should take and
  //          the only one that rejects a percussion staff placed in the pitched slot.
  // INPUTS: pitched — a pitched staff or null. percussion — a percussion staff or null.
  // OUTPUTS: A StaffSet with both slots filled. Throws ArgumentError naming the offending
  //          argument when a staff is in the wrong slot, because that is a programming error and
  //          a layout that quietly drew two melodies on top of each other would be far harder to
  //          diagnose than an exception at the call site.
  // KEYWORDS: factory, validation, slot-kind, fail-fast
  /// Creates a staff set, validating that each slot holds the right kind.
  factory StaffSet.of({StaffSpec? pitched, StaffSpec? percussion}) {
    if (pitched != null && pitched.kind != StaffKind.pitched) {
      throw ArgumentError.value(
        pitched,
        'pitched',
        'the pitched slot takes a staff of kind pitched',
      );
    }
    if (percussion != null && percussion.kind != StaffKind.percussion) {
      throw ArgumentError.value(
        percussion,
        'percussion',
        'the percussion slot takes a staff of kind percussion',
      );
    }
    return StaffSet(pitched: pitched, percussion: percussion);
  }

  /// A song with a chord line and nothing else, which is every imported chart and every song that
  /// never opened the melody editor.
  static const StaffSet chordsOnly = StaffSet();

  /// The pitched staff, or null when the song has no melody line.
  final StaffSpec? pitched;

  /// The percussion staff, or null when the song has no drum part.
  final StaffSpec? percussion;

  /// Whether the song has staves beyond the implicit chord line.
  bool get isEmpty => pitched == null && percussion == null;

  /// Whether anything in this song responds to transposition.
  ///
  /// False for a drum-only or PDF-backed song, which is the condition the editor uses to disable
  /// the transpose control and show the hint that the design calls for. Returning this from the
  /// model rather than letting each screen decide means the rule is stated once.
  bool get hasTransposableContent => pitched != null;

  @override
  bool operator ==(Object other) =>
      other is StaffSet &&
      other.pitched == pitched &&
      other.percussion == percussion;

  @override
  int get hashCode => Object.hash(pitched, percussion);

  @override
  String toString() {
    if (isEmpty) {
      return 'StaffSet(chords only)';
    }
    return 'StaffSet(${<String>['chords', if (pitched != null) 'pitched', if (percussion != null) 'percussion'].join(' + ')})';
  }
}
