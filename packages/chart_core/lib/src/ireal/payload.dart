// PURPOSE: Turn a whole decoded `irealb://` payload — the field list around the music body — into
//          a Song that carries its metadata, and expose that field list through typed accessors so
//          a caller that needs a field the model has no home for does not have to split on `=`
//          itself. `parseIRealNotation` deliberately reads notation only and produces an untitled
//          song; this layer is what an import a musician can actually use goes through.
// INPUTS: A decoded payload: the text after `irealb://` and after `Uri.decodeFull`, i.e. the
//         percent-decoding has happened but the music field is still obfuscated. It may be short,
//         malformed, or carry several songs.
// OUTPUTS: An [IRealPayload] (the field list plus typed accessors) and, from
//          [parseIRealPayload], an [IRealParseResult] whose song has the title, composer, style,
//          key, transposed key and tempo the payload describes. Nothing throws; every field that
//          is missing, unparsable or impossible to place in the model becomes an
//          [IRealParseIssue].
// KEYWORDS: ireal, payload, url, field-list, metadata, composer, key, transpose, tempo, playlist
//
// THE FIELD LAYOUT. The old protocol page documents fields 0-5; a real export has ten. The order
// is the same as far as both go, and this file uses the ten-field shape:
//
//     0 title    1 composer   2 undocumented, empty in every export seen   3 style   4 key
//     5 transpose   6 music   7 groove   8 bpm   9 repeats
//
// Fields 2, 7 and 9 have no home in the Song model. They are exposed by [IRealPayload] rather than
// dropped, because a caller can hold them; what the Song does not carry is stated here so that a
// later reader does not assume the import silently lost them.
//
// WHY THE KEY IS THE WRITTEN KEY, AND THE TRANSPOSE IS REPORTED INSTEAD OF APPLIED.
//
// The reference applies the payload's transpose on top of the written key
// (`options.transpose += song.transpose`) before it plays or prints the chart, so a chart written
// in B minor with transpose 5 is shown in E minor. An earlier version of this file copied that and
// moved `Song.key` — but it moved ONLY the key, leaving the chords exactly as written. The result
// was a song whose label said E minor while its chords were B-minor chords: internally
// inconsistent, and wrong under either reading of what the key field means.
//
// [Song.key] is documented as "the key the chart is WRITTEN in", and the imported chords are the
// written ones, so the key stays the written key. The transpose is REPORTED as an issue and
// exposed as [IRealPayload.transposeValue], so nothing is lost silently and nothing is destroyed
// at import. Applying it is a reversible action the editor can offer; baking it in here would
// rewrite every chord and make a re-export differ from the file it came from.
//
// Whether an imported chart should instead arrive already transposed is a PRODUCT decision rather
// than a parsing one — it belongs to whoever owns the rule that the editor's transposition is the
// song's key. Until that is settled, the import preserves what the file says and says so.
//
// WHY THE COMPOSER IS STORED AS WRITTEN. Field 1 holds `LastName FirstName` because the field is
// the library's sort key; the reference reverses it for display only. Storing the reversed form in
// the model would silently sort the library by first name, so `composer` keeps the raw field and
// [IRealPayload.composerDisplayName] is the explicit, opt-in reversal.
//
// THE PLAYLIST AMBIGUITY, RECORDED RATHER THAN RESOLVED. Two descriptions of the format disagree.
// The reference implementation splits a multi-song payload on `===` before splitting each song on
// `=`, and treats the last segment as the playlist name; the protocol page instead shows songs
// joined by a single `=`. Those cannot both be right, and a one-song payload is a special case of
// both, so the text alone cannot decide. This file handles the `===` form, and when a payload has
// no `===` but does carry more fields or more music prefix fields than one song can have, it
// parses the first song and REPORTS the ambiguity instead of guessing where the next song starts.
//
// OFFSETS. The issue list of [parseIRealPayload] uses one coordinate system: the decoded payload
// the caller passed in. That includes the issues raised by the notation parser, whose offsets
// index the decoded music body; they are translated back through the obfuscation permutation by
// [IRealPayload.payloadIndexForMusicIndex]. The translation is exact because both steps of the
// codec are length preserving — the three substitutions replace a string with another of the same
// length, and the block permutation only reorders — so a music-body index and the payload index it
// came from are related by the permutation and nothing else.
import '../key.dart';
import '../pitch.dart';
import '../song/section.dart';
import '../song/song.dart';
import '../song/staff.dart';
import 'obfuscation.dart';
import 'parser.dart';

/// A decoded `irealb://` payload read as a field list, with typed accessors for the fields this
/// project knows about.
///
/// The accessors are total: a payload shorter than the field an accessor names yields the empty
/// string, zero or null rather than throwing, because a truncated payload is reported as an issue
/// by [parseIRealPayload] and the reading of whatever fields it does have should still work.
class IRealPayload {
  /// Reads [decoded] as a payload: `===` separates songs and `=` separates fields.
  ///
  /// The `===` split happens FIRST, which is what makes it possible to read a multi-song payload at
  /// all: a music field contains no `=` or `===`, so splitting a whole payload on `=` before
  /// splitting on `===` would merge two songs into one field list. Only the first song's fields are
  /// exposed; [songSegmentCount], [playlistName] and [isPlaylist] describe the rest.
  factory IRealPayload.parse(String decoded) {
    final List<String> segments = decoded.split('===');
    return IRealPayload._(segments.first.split('='), segments);
  }

  /// Wraps an already-split field list. Private because [IRealPayload.parse] is the only way to
  /// build one: the split order (`===` before `=`) is part of the format, not a caller's choice.
  const IRealPayload._(this.fields, this._segments);

  /// The fields of the first song, in payload order.
  ///
  /// Exposed raw so that a caller can read a field this class has no accessor for. Reading a field
  /// by index through [field] is safer than indexing this list directly, because the list is only
  /// as long as the payload was.
  final List<String> fields;

  final List<String> _segments;

  /// The field at [index], or the empty string when [index] is negative or past the end.
  String field(int index) =>
      index >= 0 && index < fields.length ? fields[index] : '';

  /// Field 0: the title, as written.
  String get title => field(0);

  /// Field 1: the composer, VERBATIM, in the sort order the format stores.
  String get composer => field(1);

  /// Field 3: the style or feel, free text such as `Russian Retro`.
  String get style => field(3);

  /// Field 4: the key as written, such as `C`, `Bb`, `F#`, `A-` or `C#-`.
  String get keyText => field(4);

  /// Field 5: the transpose as written, or the empty string when the payload is shorter.
  String get transposeText => field(5);

  /// Field 7: the groove, which this model does not store.
  String get groove => field(7);

  /// Field 8: the tempo as written, or the empty string when it is absent.
  String get bpmText => field(8);

  /// Field 9: the reference implementation's "repeats" field, which this model does not store.
  String get repeatsText => field(9);

  /// Whether the payload was split on `===`, i.e. whether it is a playlist rather than one song.
  bool get isPlaylist => _segments.length > 1;

  /// How many `===` segments the payload claims are songs.
  ///
  /// One for a payload with no separator. For a playlist it is the segment count minus the last
  /// segment, because the reference treats the final segment as the playlist's name rather than a
  /// song. Never negative.
  int get songSegmentCount => isPlaylist ? _segments.length - 1 : 1;

  /// The final `===` segment when the payload is a playlist, otherwise the empty string.
  ///
  /// Read as the playlist's name, following the reference; a caller that disagrees can read
  /// [fields] of the song it wants instead, since this class exposes only the first song.
  String get playlistName => isPlaylist ? _segments.last : '';

  /// Index of the field carrying the obfuscated music body, or -1 when there is none.
  ///
  /// Found by scanning for [irealMusicPrefix] rather than by assuming index 6, because the field
  /// list is not always exactly ten long and a shifted list must not turn into a chart with no
  /// music. A complete payload still puts it at 6.
  int get musicFieldIndex {
    for (int index = 0; index < fields.length; index++) {
      if (fields[index].startsWith(irealMusicPrefix)) {
        return index;
      }
    }
    return -1;
  }

  /// The music field itself, or null when no field carries the prefix.
  String? get musicField {
    final int index = musicFieldIndex;
    return index < 0 ? null : fields[index];
  }

  /// How many fields carry the music prefix.
  ///
  /// More than one is the strongest available evidence that a payload with no `===` is really
  /// several songs joined by `=`, which is the ambiguity [parseIRealPayload] reports.
  int get musicFieldCount =>
      fields.where((String value) => value.startsWith(irealMusicPrefix)).length;

  /// Where field [index] begins in the decoded payload, or the payload's length when the index is
  /// past the end.
  ///
  /// Computed by summing the fields before it plus one `=` each, which is exact for the first song
  /// and therefore for a single-song payload. It is also exact for the first song of a `===`
  /// playlist, because that song starts at offset 0.
  int fieldOffset(int index) {
    int offset = 0;
    for (int i = 0; i < index && i < fields.length; i++) {
      offset += fields[i].length + 1;
    }
    return offset;
  }

  // PURPOSE: Report which key the chart was written in, without applying the transpose field, so
  //          that a caller can tell the written key from the key the reference would play.
  // INPUTS: None. Reads field 4.
  // OUTPUTS: A Key when the field is a note letter, an optional accidental and an optional
  //          trailing `-` for minor; null when the field is empty or is not a name this model can
  //          read (an empty field is the ordinary "no key written" case, not a defect). A trailing
  //          `-` is the format's minor marker, so `A-` is A minor and `A` is A major.
  // KEYWORDS: key, mode, minor, accidental, payload-field
  /// Returns the written key from field 4, or null when it cannot be read.
  Key? get writtenKey {
    String text = keyText;
    if (text.isEmpty) {
      return null;
    }
    bool minor = false;
    if (text.endsWith('-')) {
      minor = true;
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) {
      return null;
    }
    final NoteLetter? letter = _letterOf(text[0]);
    if (letter == null) {
      return null;
    }
    int alter = 0;
    for (int i = 1; i < text.length; i++) {
      final String character = text[i];
      if (character == '#') {
        alter += 1;
      } else if (character == 'b') {
        alter -= 1;
      } else {
        return null;
      }
    }
    return Key(
      tonic: WrittenNote(letter, alter),
      mode: minor ? Mode.minor : Mode.major,
    );
  }

  /// Field 5 read as an integer, or null when it is absent or is not a number.
  ///
  /// Null rather than 0 so that [parseIRealPayload] can report a value that was written and not
  /// understood while staying silent about one that was never there.
  int? get transposeValue => int.tryParse(transposeText);

  /// Field 8 read as an integer, or null when it is absent or is not a number.
  int? get bpmValue => int.tryParse(bpmText);

  /// Field 8 as the model wants it: the tempo, or 0 for "unset".
  ///
  /// Zero rather than null because [Song.tempo] documents 0 as the format's unset value.
  int get bpm => bpmValue ?? 0;

  /// Field 9 read as an integer, or null when it is absent or is not a number.
  int? get repeatsValue => int.tryParse(repeatsText);

  // PURPOSE: Give the composer in the order a person reads it, without changing what the model
  //          stores, so that a display layer and the sort order do not have to agree on one string.
  // INPUTS: None. Reads [composer], which is stored as `LastName FirstName`.
  // OUTPUTS: The stored text with its first and last tokens exchanged — `Miller Bob` becomes
  //          `Bob Miller`, `Bach Johann Sebastian` becomes `Johann Sebastian Bach` — so that a
  //          multi-token given name stays in its written order. A single token, an empty field or a
  //          field with whitespace only is returned trimmed and otherwise unchanged, because there
  //          is no surname to move. Never null.
  // KEYWORDS: composer, display-name, sort-key, presentation, reversal
  /// Returns the composer as `FirstName LastName`, or the stored text when there is only one token.
  String get composerDisplayName {
    final String stored = composer.trim();
    final int space = stored.indexOf(' ');
    if (space < 0) {
      return stored;
    }
    final String last = stored.substring(0, space);
    final String rest = stored.substring(space + 1).trim();
    if (rest.isEmpty) {
      return last;
    }
    return '$rest $last';
  }

  // PURPOSE: Translate an offset in the decoded music body back to the character position it came
  //          from in the decoded payload, so that every issue [parseIRealPayload] reports can be
  //          pointed at the one string the caller holds.
  // INPUTS: musicIndex — a character offset into the string `deobfuscateIrealMusic` returns. It may
  //         be negative or past the end of the body.
  // OUTPUTS: The offset in the decoded payload of the character that produced [musicIndex]. The
  //          mapping is the codec's block permutation and nothing else, because both the
  //          substitutions and the permutation preserve length: a substitution replaces a run with
  //          another run of the same length, and the permutation only reorders. A negative index
  //          maps to the start of the music body, and an index at or past the end maps to the end
  //          of the body, so the result is always a real position inside the payload rather than
  //          something the caller has to bounds-check.
  // KEYWORDS: offset, diagnostics, permutation, obfuscation, coordinate-translation
  /// Returns the payload offset of the character that decoding placed at [musicIndex].
  int payloadIndexForMusicIndex(int musicIndex) {
    final int bodyField = musicFieldIndex;
    if (bodyField < 0) {
      return 0;
    }
    final int bodyStart = fieldOffset(bodyField) + irealMusicPrefix.length;
    final String raw = fields[bodyField].substring(irealMusicPrefix.length);
    if (musicIndex < 0) {
      return bodyStart;
    }
    if (musicIndex >= raw.length) {
      return bodyStart + raw.length;
    }

    // Exactly the trailing-block rule `deobfuscateIrealMusic` applies: only whole blocks that have
    // more than one character after them are permuted, so the final short remainder is untouched.
    int permutedBlocks = 0;
    int remaining = raw.length;
    while (remaining > irealObfuscationBlockSize + 1) {
      permutedBlocks++;
      remaining -= irealObfuscationBlockSize;
    }
    final int permutedLength = permutedBlocks * irealObfuscationBlockSize;
    if (musicIndex >= permutedLength) {
      return bodyStart + musicIndex;
    }
    final int block = musicIndex ~/ irealObfuscationBlockSize;
    final int within = musicIndex % irealObfuscationBlockSize;
    return bodyStart +
        block * irealObfuscationBlockSize +
        _mirrorSourceIndex(within);
  }

  @override
  String toString() =>
      'IRealPayload(${fields.length} field(s)'
      '${isPlaylist ? ', playlist of $songSegmentCount song(s)' : ''})';
}

// PURPOSE: Build a Song from a whole decoded payload, so that an import carries the identity a
//          musician recognises — title, composer, style, key, tempo — and not just the notation.
// INPUTS: decoded — the text after `irealb://` with `Uri.decodeFull` already applied. Its music
//         field is still obfuscated; this function strips `irealMusicPrefix` and decodes it.
//         documentId — the identifier the Song should carry, or the empty string.
// OUTPUTS: An [IRealParseResult] whose song carries the payload's metadata and the sections and
//          bars of its notation. The key is the written key moved by the transpose field, because
//          that is what the reference plays; the composer is field 1 verbatim.
//
//          Issues are reported, never thrown: a payload shorter than ten fields, a payload with no
//          music field, a key or transpose or bpm that cannot be read, a playlist with more than
//          one song, and the `=`-joined multi-song ambiguity all produce an issue while everything
//          readable is still returned. Offsets index the decoded payload, including those inherited
//          from the notation parser, which are translated by
//          [IRealPayload.payloadIndexForMusicIndex].
// KEYWORDS: parse, payload, import, metadata, transpose, playlist, issues, total-function
/// Parses a whole decoded iReal payload into a Song with its metadata.
IRealParseResult parseIRealPayload(String decoded, {String documentId = ''}) {
  final List<IRealParseIssue> issues = <IRealParseIssue>[];
  final IRealPayload payload = IRealPayload.parse(decoded);

  if (payload.songSegmentCount > 1) {
    issues.add(
      IRealParseIssue(
        'The payload carries ${payload.songSegmentCount} songs separated by `===` and only the '
        'first was parsed; the final segment was read as the playlist name.',
        0,
      ),
    );
  } else if (payload.musicFieldCount > 1 || payload.fields.length > 10) {
    // No `===`, yet the field list is longer than one song's or holds more than one music field.
    // Guessing where the next song begins would put one chart's chords under another's title, so
    // the first song is read and the rest is reported.
    issues.add(
      IRealParseIssue(
        'The payload has no `===` separator but carries ${payload.fields.length} fields and '
        '${payload.musicFieldCount} field(s) starting with `$irealMusicPrefix`. A single song has '
        'ten fields and one music field, so this is most likely the protocol page\'s `=`-joined '
        'multi-song form, and where one song ends and the next begins cannot be decided from the '
        'text; only the first music field was parsed.',
        0,
      ),
    );
  }

  if (payload.fields.length < 10) {
    issues.add(
      IRealParseIssue(
        'The payload has ${payload.fields.length} field(s); a complete song carries ten (title, '
        'composer, undocumented, style, key, transpose, music, groove, bpm, repeats). The fields '
        'that are present were used.',
        0,
      ),
    );
  }

  final Key? writtenKey = payload.writtenKey;
  if (writtenKey == null && payload.keyText.isNotEmpty) {
    issues.add(
      IRealParseIssue(
        'The key field "${payload.keyText}" is not a key this model can name; C major was assumed.',
        payload.fieldOffset(4),
      ),
    );
  }

  final int? transpose = payload.transposeValue;
  if (transpose == null && payload.transposeText.isNotEmpty) {
    issues.add(
      IRealParseIssue(
        'The transpose field "${payload.transposeText}" is not an integer; no transposition was '
        'applied.',
        payload.fieldOffset(5),
      ),
    );
  }

  final int? bpm = payload.bpmValue;
  if (bpm == null && payload.bpmText.isNotEmpty) {
    issues.add(
      IRealParseIssue(
        'The bpm field "${payload.bpmText}" is not an integer; the tempo was left at 0 (unset).',
        payload.fieldOffset(8),
      ),
    );
  }

  List<Section> sections = const <Section>[];
  StaffSet staffSet = StaffSet.chordsOnly;
  final String? music = payload.musicField;
  if (music == null) {
    issues.add(
      IRealParseIssue(
        'No field starts with the music prefix `$irealMusicPrefix`, so the payload carries no '
        'chart; the song was built from the metadata alone.',
        payload.musicFieldIndex < 0
            ? 0
            : payload.fieldOffset(payload.musicFieldIndex),
      ),
    );
  } else {
    final IRealParseResult notation = parseIRealNotation(
      deobfuscateIrealMusic(music.substring(irealMusicPrefix.length)),
      documentId: documentId,
    );
    for (final IRealParseIssue issue in notation.issues) {
      issues.add(
        IRealParseIssue(
          issue.message,
          payload.payloadIndexForMusicIndex(issue.offset),
        ),
      );
    }
    sections = notation.song.sections;
    staffSet = notation.song.staffSet;
  }

  final Key baseKey = writtenKey ?? Key.cMajor;
  final int semitones = transpose ?? 0;
  if (semitones != 0) {
    // Reported rather than applied. The alternative — moving the key label and leaving the chords
    // — was tried and produced a song that contradicted itself, so the choice is between being
    // faithful to the file and being wrong in one of two directions, and this is the one that
    // destroys nothing.
    issues.add(
      IRealParseIssue(
        'The payload asks for a transposition of $semitones semitone(s). The chart was imported in '
        'its written key (${payload.keyText}) with its written chords, because the song model has '
        'no field for a transposition and applying it would rewrite every chord.',
        payload.fieldOffset(5),
      ),
    );
  }
  return IRealParseResult(
    song: Song(
      id: documentId,
      title: payload.title,
      composer: payload.composer,
      style: payload.style,
      key: baseKey,
      tempo: bpm ?? 0,
      sections: sections,
      staffSet: staffSet,
    ),
    issues: issues,
  );
}

/// The source index, within a 50-character block, of the character that decoding places at
/// [index].
///
/// Derived from the exported [mirrorIrealBlock] instead of restating its ranges: a probe block of
/// 50 distinct characters is mirrored once, and the code unit found at [index] in the result is the
/// probe index that arrived there, because the permutation is its own inverse. Deriving it keeps
/// this mapping from drifting away from the permutation the decoder actually applies, which is the
/// one thing that would make every translated offset silently wrong.
int _mirrorSourceIndex(int index) {
  final String probe = String.fromCharCodes(
    List<int>.generate(irealObfuscationBlockSize, (int i) => i),
  );
  return mirrorIrealBlock(probe).codeUnitAt(index);
}

/// Maps an uppercase letter character to a [NoteLetter], or null when it is not one.
///
/// A local copy of the chord parser's private helper. It is duplicated rather than shared because
/// the chord parser's is library-private by design and this package has no dependency to put a
/// shared table in; the seven letters are format constants and cannot drift.
NoteLetter? _letterOf(String character) {
  switch (character) {
    case 'C':
      return NoteLetter.c;
    case 'D':
      return NoteLetter.d;
    case 'E':
      return NoteLetter.e;
    case 'F':
      return NoteLetter.f;
    case 'G':
      return NoteLetter.g;
    case 'A':
      return NoteLetter.a;
    case 'B':
      return NoteLetter.b;
    default:
      return null;
  }
}
