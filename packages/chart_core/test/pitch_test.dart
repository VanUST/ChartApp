// PURPOSE: Pin the arithmetic that everything else in the pitch layer assumes — that a written
//          note reduces to a correct pitch class including for negative input, that the letter
//          sequence wraps, and that a key reports its signature from its spelled tonic rather
//          than from a stored field that could contradict it.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation. Every expected value below was derived from the
//          documented rule, not read off a run.
// KEYWORDS: test, pitch-class, note-letter, key-signature, circle-of-fifths, hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

void main() {
  group('normalizePitchClass', () {
    test('leaves values already in range untouched', () {
      expect(normalizePitchClass(0), 0);
      expect(normalizePitchClass(11), 11);
    });

    test('wraps octaves upward and downward', () {
      expect(normalizePitchClass(12), 0);
      expect(normalizePitchClass(13), 1);
      expect(normalizePitchClass(-1), 11);
      expect(normalizePitchClass(-12), 0);
      expect(normalizePitchClass(-13), 11);
    });
  });

  group('NoteLetter', () {
    test('carries the natural pitch class of each letter', () {
      expect(NoteLetter.c.naturalPitchClass, 0);
      expect(NoteLetter.d.naturalPitchClass, 2);
      expect(NoteLetter.e.naturalPitchClass, 4);
      expect(NoteLetter.f.naturalPitchClass, 5);
      expect(NoteLetter.g.naturalPitchClass, 7);
      expect(NoteLetter.a.naturalPitchClass, 9);
      expect(NoteLetter.b.naturalPitchClass, 11);
    });

    test('step walks the letter sequence and wraps within seven letters', () {
      expect(NoteLetter.c.step(1), NoteLetter.d);
      expect(NoteLetter.c.step(4), NoteLetter.g);
      expect(NoteLetter.b.step(1), NoteLetter.c);
      expect(NoteLetter.c.step(7), NoteLetter.c);
      expect(NoteLetter.c.step(0), NoteLetter.c);
    });

    test('step walks downward for negative steps', () {
      expect(NoteLetter.c.step(-1), NoteLetter.b);
      expect(NoteLetter.c.step(-2), NoteLetter.a);
      // -8 letters is the same position as -1, because the sequence has period 7.
      expect(NoteLetter.c.step(-8), NoteLetter.b);
    });
  });

  group('WrittenNote', () {
    test('reduces letter and alteration to a pitch class', () {
      expect(const WrittenNote(NoteLetter.c, 0).pitchClass, 0);
      expect(const WrittenNote(NoteLetter.a, -1).pitchClass, 8);
      expect(const WrittenNote(NoteLetter.g, 1).pitchClass, 8);
      expect(const WrittenNote(NoteLetter.b, 1).pitchClass, 0);
      expect(const WrittenNote(NoteLetter.c, -1).pitchClass, 11);
    });

    test('keeps enharmonic spellings distinct under equality', () {
      // The distinction the whole pitch layer exists to preserve: Ab and G# sound identical and
      // are not the same instruction to a musician.
      const WrittenNote aFlat = WrittenNote(NoteLetter.a, -1);
      const WrittenNote gSharp = WrittenNote(NoteLetter.g, 1);
      expect(aFlat.pitchClass, gSharp.pitchClass);
      expect(aFlat == gSharp, isFalse);
      expect(aFlat, const WrittenNote(NoteLetter.a, -1));
    });

    test('renders accidentals the way a chart writes them', () {
      expect(const WrittenNote(NoteLetter.c, 0).toString(), 'C');
      expect(const WrittenNote(NoteLetter.f, 1).toString(), 'F#');
      expect(const WrittenNote(NoteLetter.b, -1).toString(), 'Bb');
      expect(const WrittenNote(NoteLetter.d, -2).toString(), 'Dbb');
    });
  });

  group('shortestAlter', () {
    test('picks the alteration closest to natural', () {
      expect(shortestAlter(1, NoteLetter.c), 1);
      expect(shortestAlter(1, NoteLetter.d), -1);
      expect(shortestAlter(0, NoteLetter.c), 0);
      // C is the nearest spelling of pitch class 0 on the letter B, not a double sharp.
      expect(shortestAlter(0, NoteLetter.b), 1);
    });
  });

  group('Key.signatureFifths', () {
    test('is zero for C major and A minor', () {
      expect(Key.cMajor.signatureFifths, 0);
      expect(Key.aMinor.signatureFifths, 0);
    });

    test('counts sharps upward through the circle', () {
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.g, 0),
          mode: Mode.major,
        ).signatureFifths,
        1,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.d, 0),
          mode: Mode.major,
        ).signatureFifths,
        2,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.a, 0),
          mode: Mode.major,
        ).signatureFifths,
        3,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.e, 0),
          mode: Mode.major,
        ).signatureFifths,
        4,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.b, 0),
          mode: Mode.major,
        ).signatureFifths,
        5,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.f, 1),
          mode: Mode.major,
        ).signatureFifths,
        6,
      );
    });

    test('counts flats downward through the circle', () {
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.f, 0),
          mode: Mode.major,
        ).signatureFifths,
        -1,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.b, -1),
          mode: Mode.major,
        ).signatureFifths,
        -2,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.e, -1),
          mode: Mode.major,
        ).signatureFifths,
        -3,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.a, -1),
          mode: Mode.major,
        ).signatureFifths,
        -4,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.d, -1),
          mode: Mode.major,
        ).signatureFifths,
        -5,
      );
    });

    test('derives a minor key signature from its relative major', () {
      // A minor and C major share a signature; E minor and G major; D minor and F major.
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.e, 0),
          mode: Mode.minor,
        ).signatureFifths,
        1,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.d, 0),
          mode: Mode.minor,
        ).signatureFifths,
        -1,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.b, 0),
          mode: Mode.minor,
        ).signatureFifths,
        2,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.f, 1),
          mode: Mode.minor,
        ).signatureFifths,
        3,
      );
    });

    test('separates enharmonic keys that share a pitch class', () {
      // The reason a Key stores a spelled tonic rather than a pitch class: both of these sound
      // on pitch class 1 and they have opposite signatures.
      const Key dFlatMajor = Key(
        tonic: WrittenNote(NoteLetter.d, -1),
        mode: Mode.major,
      );
      const Key cSharpMajor = Key(
        tonic: WrittenNote(NoteLetter.c, 1),
        mode: Mode.major,
      );
      expect(dFlatMajor.tonicPitchClass, cSharpMajor.tonicPitchClass);
      expect(dFlatMajor.signatureFifths, -5);
      expect(cSharpMajor.signatureFifths, 7);
    });
  });

  group('Key.prefersSharps', () {
    test('is true only for keys with a sharp signature', () {
      expect(Key.cMajor.prefersSharps, isFalse);
      expect(Key.aMinor.prefersSharps, isFalse);
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.g, 0),
          mode: Mode.major,
        ).prefersSharps,
        isTrue,
      );
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.f, 0),
          mode: Mode.major,
        ).prefersSharps,
        isFalse,
      );
      // Documented simplification: a key with no signature reports flats.
      expect(
        const Key(
          tonic: WrittenNote(NoteLetter.d, -1),
          mode: Mode.major,
        ).prefersSharps,
        isFalse,
      );
    });
  });
}
