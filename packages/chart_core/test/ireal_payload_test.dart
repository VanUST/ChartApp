// PURPOSE: Pin the payload layer's reading of a decoded `irealb://` string: which field is which,
//          how the key field spells a mode, that the transpose field moves the key the way the
//          reference does, that an unreadable or missing field becomes an issue rather than a
//          crash, and that the two descriptions of a playlist are handled as far as they can be and
//          reported where they cannot. Every expectation is derived by hand and the derivation is
//          written next to it, so a failure names a rule rather than a number.
// INPUTS: None. The last test reads a real iReal export from the path in the IREAL_FIXTURE
//         environment variable and is skipped when it is unset.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, ireal, payload, field-list, key, transpose, composer, playlist, hand-derived
import 'dart:io';

import 'package:chart_core/src/ireal/obfuscation.dart';
import 'package:chart_core/src/ireal/parser.dart';
import 'package:chart_core/src/ireal/payload.dart';
import 'package:chart_core/src/key.dart';
import 'package:chart_core/src/pitch.dart';
import 'package:test/test.dart';

/// A music field carrying [notation], obfuscated and prefixed the way a payload stores it.
///
/// Built through `obfuscateIrealMusic` rather than pasted as a literal so that the tests below
/// exercise the real inverse: a hand-written field could agree with a wrong decoder.
String musicField(String notation) =>
    '$irealMusicPrefix${obfuscateIrealMusic(notation)}';

/// A complete ten-field payload, with only the named fields varied.
///
/// The layout is title, composer, undocumented, style, key, transpose, music, groove, bpm,
/// repeats, so field 2 is written as the empty run between two `=` signs.
String completePayload({
  String title = 'T',
  String composer = 'C',
  String style = 'S',
  String key = 'C',
  String transpose = '0',
  String notation = '*AC7|F7|',
  String groove = 'G',
  String bpm = '120',
  String repeats = '0',
}) =>
    '$title=$composer==$style=$key=$transpose=${musicField(notation)}=$groove=$bpm=$repeats';

void main() {
  group('the field list', () {
    test('reads ten fields into typed accessors', () {
      // Derivation: the payload is written field by field in the documented order, so each accessor
      // must return the text that was placed at its index and nothing else. Field 2 is deliberately
      // non-empty here even though real exports leave it empty, to prove it is preserved rather
      // than skipped.
      final String music = musicField('*AC7|F7|');
      final String decoded =
          'My Tune=Miller Bob=Ignored=Ballad=F=0=$music=Medium Swing=120=2';
      final IRealPayload payload = IRealPayload.parse(decoded);

      expect(payload.fields, hasLength(10));
      expect(payload.title, 'My Tune');
      expect(payload.composer, 'Miller Bob');
      expect(payload.field(2), 'Ignored');
      expect(payload.style, 'Ballad');
      expect(payload.keyText, 'F');
      expect(payload.transposeValue, 0);
      expect(payload.musicField, music);
      expect(payload.musicFieldIndex, 6);
      expect(payload.groove, 'Medium Swing');
      expect(payload.bpm, 120);
      expect(payload.repeatsValue, 2);
      expect(payload.isPlaylist, isFalse);
      expect(payload.songSegmentCount, 1);
      expect(payload.playlistName, '');
    });

    test('a field past the end is empty, not an error', () {
      // Derivation: the payload has three fields, so index 9 addresses nothing. An accessor that
      // threw or returned null would force every caller to bounds-check; the empty string is the
      // documented "not written" value, and the missing fields themselves are reported by
      // parseIRealPayload.
      final IRealPayload payload = IRealPayload.parse('A=B=C');

      expect(payload.fields, hasLength(3));
      expect(payload.field(9), '');
      expect(payload.bpmText, '');
      expect(payload.bpmValue, isNull);
      expect(payload.bpm, 0);
    });

    test('the composer is stored as written and reversed only for display', () {
      // Derivation: field 1 is the library's sort key, `LastName FirstName`. The model stores it
      // verbatim so sorting still works, and composerDisplayName swaps the first and last tokens
      // for a reader. `Bach Johann Sebastian` has a multi-token given name, which must stay in
      // order, so only the first and last tokens move.
      expect(
        IRealPayload.parse('T=Bach Johann Sebastian==S=C=0=x=G=0=0').composer,
        'Bach Johann Sebastian',
      );
      expect(
        IRealPayload.parse('T=Bach Johann Sebastian==S=C=0=x=G=0=0')
            .composerDisplayName,
        'Johann Sebastian Bach',
      );
      // One token: there is no surname to move.
      expect(
        IRealPayload.parse('T=Prince==S=C=0=x=G=0=0').composerDisplayName,
        'Prince',
      );
      // Nothing written at all.
      expect(IRealPayload.parse('T=  ==S=C=0=x=G=0=0').composerDisplayName, '');
    });

    test('the key field spells major and minor', () {
      // Derivation: the field is a letter, an optional accidental, and `-` for minor. Each case
      // below names the exact WrittenNote the model must hold, because the letter is what the
      // spelling layer later depends on: `Bb` and `A#` sound alike and are different keys.
      expect(
        IRealPayload.parse(completePayload(key: 'C')).writtenKey,
        const Key(tonic: WrittenNote(NoteLetter.c, 0), mode: Mode.major),
      );
      expect(
        IRealPayload.parse(completePayload(key: 'Bb')).writtenKey,
        const Key(tonic: WrittenNote(NoteLetter.b, -1), mode: Mode.major),
      );
      expect(
        IRealPayload.parse(completePayload(key: 'F#')).writtenKey,
        const Key(tonic: WrittenNote(NoteLetter.f, 1), mode: Mode.major),
      );
      expect(
        IRealPayload.parse(completePayload(key: 'A-')).writtenKey,
        const Key(tonic: WrittenNote(NoteLetter.a, 0), mode: Mode.minor),
      );
      expect(
        IRealPayload.parse(completePayload(key: 'C#-')).writtenKey,
        const Key(tonic: WrittenNote(NoteLetter.c, 1), mode: Mode.minor),
      );
      // An absent key is the ordinary unset case, not a defect; a letter the model does not know is
      // not a key at all.
      expect(IRealPayload.parse(completePayload(key: '')).writtenKey, isNull);
      expect(IRealPayload.parse(completePayload(key: 'H')).writtenKey, isNull);
    });
  });

  group('the transpose field', () {
    test('is REPORTED, and the key stays the written key', () {
      // Derivation and the reason for the expectation. The reference applies the payload's
      // transpose to the written key before it renders, so a naive port would put B minor + 5 here
      // and call the song E minor. That was tried and was WRONG: only the key label moved, the
      // chords stayed exactly as written, and the song ended up claiming E minor while holding
      // B-minor chords — internally inconsistent under either reading of what the key means.
      //
      // `Song.key` is documented as "the key the chart is WRITTEN in", and the imported chords are
      // the written ones, so the key is B minor (tonic pitch class 11, minor). The transpose is
      // not silently dropped either: it is reported as an issue and still readable as
      // `transposeValue`, so a caller can apply it as an explicit, reversible action.
      final String decoded = completePayload(key: 'B-', transpose: '5');
      final IRealPayload payload = IRealPayload.parse(decoded);
      expect(
        payload.writtenKey,
        const Key(tonic: WrittenNote(NoteLetter.b, 0), mode: Mode.minor),
      );
      expect(payload.transposeValue, 5);

      final IRealParseResult result = parseIRealPayload(decoded);
      expect(result.song.key.tonicPitchClass, 11);
      expect(result.song.key.mode, Mode.minor);
      expect(
        result.issues.single.message,
        allOf(contains('5 semitone'), contains('B-')),
      );
    });

    test('a transpose of zero leaves the key exactly as written', () {
      // Derivation: F major plus no semitones is F major, and the key must be the written key by
      // equality, not merely by pitch class, so the spelling is preserved too.
      final IRealParseResult result = parseIRealPayload(
        completePayload(key: 'F', transpose: '0'),
      );

      expect(result.issues, isEmpty);
      expect(
        result.song.key,
        const Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
      );
    });

    test(
      'a negative transpose is reported too, and the key still does not move',
      () {
        // Derivation: C major is pitch class 0. The old behaviour moved it by -3 to pitch class 9 (A
        // major) while leaving the chords in C, which is the inconsistency this expectation exists
        // to prevent. The key is therefore C major by EQUALITY — spelling included — and the -3 is
        // reported.
        final IRealParseResult result = parseIRealPayload(
          completePayload(key: 'C', transpose: '-3'),
        );

        expect(
          result.song.key,
          const Key(tonic: WrittenNote(NoteLetter.c, 0), mode: Mode.major),
        );
        expect(
          result.issues.single.message,
          allOf(contains('-3 semitone'), contains('C')),
        );
      },
    );
  });

  group('problems become issues, never exceptions', () {
    test(
      'fewer fields than a song carries is reported and the rest is used',
      () {
        // Derivation: two fields means the style, key, transpose, music, groove, bpm and repeats
        // fields are all absent, so exactly two issues are due: the field count, and the absence of a
        // music field. The title and composer that ARE present must still come through.
        final IRealParseResult result = parseIRealPayload(
          'Only Title=Only Composer',
        );

        expect(result.issues, hasLength(2));
        expect(result.issues[0].message, contains('2 field(s)'));
        expect(result.issues[1].message, contains('music prefix'));
        expect(result.song.title, 'Only Title');
        expect(result.song.composer, 'Only Composer');
        expect(result.song.sections, isEmpty);
      },
    );

    test('a missing music field is reported and the metadata survives', () {
      // Derivation: the field list is complete, so one issue is due. The field at index 6 is not a
      // music field because it does not carry the prefix, and the song must still be built.
      final IRealParseResult result = parseIRealPayload(
        'T=C==S=C=0=not-music=G=0=0',
      );

      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('music prefix'));
      expect(result.song.title, 'T');
      expect(result.song.sections, isEmpty);
    });

    test(
      'an unreadable key is reported at its own offset and C major is assumed',
      () {
        // Derivation: `H` is not one of the seven letters, so no Key can be built. The offset must
        // point at the character in the decoded payload that the issue is about, which is where the
        // key field begins: `T=C==S=` is seven characters, so `H` is at index 7. Computing the index
        // in the test from the text itself keeps that derivation honest rather than hard-coding it.
        final String decoded = completePayload(key: 'H');
        final IRealParseResult result = parseIRealPayload(decoded);
        final int expectedOffset = decoded.indexOf('=H=') + 1;

        expect(expectedOffset, 7);
        expect(result.issues, hasLength(1));
        expect(result.issues.single.message, contains('"H"'));
        expect(result.issues.single.offset, expectedOffset);
        expect(decoded[result.issues.single.offset], 'H');
        expect(result.song.key, Key.cMajor);
      },
    );

    test('an unreadable transpose is reported and nothing is moved', () {
      // Derivation: `lots` is not an integer, so there is no interval to apply; the key must be
      // exactly the written F major rather than a guess at what `lots` meant.
      final IRealParseResult result = parseIRealPayload(
        completePayload(key: 'F', transpose: 'lots'),
      );

      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('"lots"'));
      expect(
        result.song.key,
        const Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
      );
    });

    test('an unreadable bpm is reported, an absent one is not', () {
      // Derivation: `fast` is a written tempo this model cannot read, so it is reported and the
      // tempo stays at 0. An empty field is the ordinary "no tempo written" case, which the model
      // documents as 0 and which must NOT be reported, or every chart without a tempo would look
      // defective.
      final IRealParseResult unreadable = parseIRealPayload(
        completePayload(bpm: 'fast'),
      );
      expect(unreadable.issues, hasLength(1));
      expect(unreadable.issues.single.message, contains('"fast"'));
      expect(unreadable.song.tempo, 0);

      final IRealParseResult absent = parseIRealPayload(
        completePayload(bpm: ''),
      );
      expect(absent.issues, isEmpty);
      expect(absent.song.tempo, 0);
    });
  });

  group('playlists, and the form that cannot be decided', () {
    test('a `===` playlist parses its first song and reports the others', () {
      // Derivation: the reference splits on `===` first and treats the final segment as the
      // playlist's name. Three segments therefore mean two songs, and the one result this API can
      // return is the first song — with an issue saying the other was not parsed.
      final String first = completePayload(title: 'First');
      final String second = completePayload(title: 'Second');
      final String playlist = '$first===$second===My Playlist';
      final IRealPayload payload = IRealPayload.parse(playlist);

      expect(payload.isPlaylist, isTrue);
      expect(payload.songSegmentCount, 2);
      expect(payload.playlistName, 'My Playlist');
      expect(payload.title, 'First');
      expect(payload.musicFieldIndex, 6);

      final IRealParseResult result = parseIRealPayload(playlist);
      expect(result.song.title, 'First');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('2 songs'));
    });

    test('the single-`=` multi-song form is reported, not guessed', () {
      // Derivation: no `===` appears, so the split produces one long field list instead of songs.
      // Two complete songs joined by `=` give twenty fields and two music-prefix fields, both of
      // which a single song cannot have. Where the second song begins cannot be decided from the
      // text alone, so the first is parsed and the ambiguity is reported rather than a second title
      // silently overwriting the first. Twenty fields do not trigger the too-few-fields issue, and
      // the first song's key, transpose and bpm are all valid, so exactly one issue is due.
      final String first = completePayload(title: 'First');
      final String second = completePayload(title: 'Second');
      final String joined = '$first=$second';
      final IRealPayload payload = IRealPayload.parse(joined);

      expect(payload.fields, hasLength(20));
      expect(payload.musicFieldCount, 2);

      final IRealParseResult result = parseIRealPayload(joined);
      expect(result.song.title, 'First');
      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('cannot be decided'));
    });
  });

  group('issue offsets', () {
    test(
      'a notation issue points at the character it is about in the payload',
      () {
        // Derivation: `W/A` has an invisible root, so the notation parser reports it at the offset of
        // the `W` in the DECODED music body. The payload holds that body OBFUSCATED, so the payload
        // position is not the body position; the payload layer must invert the block permutation.
        // The body is made longer than 51 characters so that at least one full block really is
        // permuted, and `W/A` is placed near the start so it falls inside that block — with a short
        // body nothing is permuted and the test would pass on a broken translation.
        final String body = '*AW/A|${'*AC7|F7|' * 7}';
        // A precondition, not a convenience: if obfuscating and decoding did not return the body
        // unchanged, the index the issue carries would mean something other than `W`.
        final IRealPayload payload = IRealPayload.parse(
          completePayload(notation: body),
        );
        expect(
          deobfuscateIrealMusic(
            payload.musicField!.substring(irealMusicPrefix.length),
          ),
          body,
        );
        expect(body.length, greaterThan(52));

        final String decoded = completePayload(notation: body);
        final IRealParseResult result = parseIRealPayload(decoded);
        expect(result.issues, hasLength(1));
        final int offset = result.issues.single.offset;

        // The issue is about the `W` of `W/A`, which sits at body index 2; the translated offset
        // must be the payload position of that same character.
        expect(body.indexOf('W/A'), 2);
        expect(decoded[offset], 'W');

        // An offset points at a CHARACTER, not at a run: the permutation moves each character
        // independently, so the payload positions of the three characters of `W/A` are not
        // adjacent. The translation is therefore checked character by character — every character
        // of the decoded body must be found at the payload position its body index maps to, and a
        // permutation cannot change a character, so a wrong mapping shows up as a mismatch.
        for (int index = 0; index < body.length; index++) {
          expect(
            decoded[payload.payloadIndexForMusicIndex(index)],
            body[index],
            reason: 'body index $index',
          );
        }
      },
    );

    test('the music body start is the payload offset of its first decoded character', () {
      // Derivation: fields 0-5 are `T`, `C`, an EMPTY field, `S`, `C` and `0`, so the music field
      // begins after five characters and six `=` signs, at index 11; the ten-character prefix
      // follows, so decoded body offset 0 is payload index 21.
      final IRealPayload payload = IRealPayload.parse(completePayload());

      expect(payload.fieldOffset(6), 11);
      expect(payload.payloadIndexForMusicIndex(0), 21);
    });
  });

  group('a real export', () {
    // The only case that proves the layer against a payload iReal Pro wrote rather than one this
    // file's author assembled. Guarded by an environment variable because the chart is a third
    // party's work and the repository is public. Run locally with
    //
    //   IREAL_FIXTURE=<path to an iReal .html export> dart test test/ireal_payload_test.dart
    final String? fixture = Platform.environment['IREAL_FIXTURE'];

    test(
      'yields the metadata, and reports the transposition without applying it',
      () {
        final String html = File(fixture!).readAsStringSync();
        final RegExpMatch? url = RegExp('irealb://([^"]*)').firstMatch(html);
        expect(url, isNotNull, reason: 'no irealb:// link found in $fixture');
        final String decoded = Uri.decodeFull(url!.group(1)!);
        final IRealPayload payload = IRealPayload.parse(decoded);

        // The field list this export actually has, measured: title, composer, empty, style, key,
        // transpose 5, music, groove empty, bpm 0, repeats 0.
        expect(payload.fields, hasLength(10));
        expect(payload.title, 'Три белых коня (правильный)');
        expect(payload.composer, 'кинофильмов из');
        expect(payload.composerDisplayName, 'из кинофильмов');
        expect(payload.style, 'Russian Retro');
        expect(payload.keyText, 'B-');
        expect(
          payload.writtenKey,
          const Key(tonic: WrittenNote(NoteLetter.b, 0), mode: Mode.minor),
        );
        expect(payload.transposeValue, 5);
        expect(payload.musicFieldIndex, 6);
        expect(payload.bpm, 0);
        expect(payload.isPlaylist, isFalse);

        final IRealParseResult result = parseIRealPayload(
          decoded,
          documentId: 'tri-belyh-konya',
        );

        // This payload is readable and its notation carries no unrecognised symbol, so the ONLY
        // issue is the transposition, which is reported rather than applied. Asserting the exact
        // count and the exact text is what makes "nothing else went wrong" a measurement.
        expect(result.issues, hasLength(1));
        expect(
          result.issues.single.message,
          allOf(contains('5 semitone'), contains('B-')),
        );
        expect(result.song.id, 'tri-belyh-konya');
        expect(result.song.title, 'Три белых коня (правильный)');
        expect(result.song.composer, 'кинофильмов из');
        expect(result.song.style, 'Russian Retro');
        expect(result.song.tempo, 0);
        expect(result.song.writtenBarCount, 49);
        expect(result.song.sections, hasLength(3));
        // The written key, not the transposed one. B minor's tonic is pitch class 11; the payload's
        // transpose field says 5, which WOULD be pitch class 4 (E), and that is deliberately not
        // applied — see the header. The chords are the written chords, so the key has to match them.
        expect(result.song.key.tonicPitchClass, 11);
        expect(result.song.key.mode, Mode.minor);

        // Offsets. Fields 0-5 of this payload are 27, 14, 0, 13, 2 and 1 characters long, so field 6
        // begins after 57 characters and six `=` signs, at payload index 63; the ten-character prefix
        // follows, so the decoded body starts at 73. Body offset 0 does NOT map to 73: the body is 269
        // characters, so five 50-character blocks are permuted, and the character that decodes to body
        // offset 0 sits at offset 49 of the first block — the mirror of 0. 73 + 49 = 122.
        expect(payload.fieldOffset(6), 63);
        final String body = deobfuscateIrealMusic(
          payload.musicField!.substring(irealMusicPrefix.length),
        );
        expect(body.length, 269);
        expect(payload.payloadIndexForMusicIndex(0), 122);

        // The translation is a bijection onto the music field's payload span: every one of the body's
        // characters maps to a different payload position, and the outermost body offsets reach the
        // two ends of the span. This is checkable even where a substitution token expanded, because
        // the POSITION is exact in that case and only the character differs.
        final Set<int> mapped = <int>{
          for (int index = 0; index < body.length; index++)
            payload.payloadIndexForMusicIndex(index),
        };
        expect(mapped, hasLength(body.length));
        expect(mapped.reduce((int a, int b) => a < b ? a : b), 73);
        expect(
          mapped.reduce((int a, int b) => a > b ? a : b),
          73 + body.length - 1,
        );
      },
      skip: fixture == null ? 'set IREAL_FIXTURE' : null,
    );
  });
}
