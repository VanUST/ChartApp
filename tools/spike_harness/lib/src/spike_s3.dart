// PURPOSE: Answer spike S3's question with a measurement rather than an opinion: does
//          transposing a chart through all twelve keys return the spelling it started with? The
//          answer decides whether the chord model in chart_core is fit to build the iReal import
//          and the layout engine on, so it is measured over many chords and many starting keys
//          instead of over the handful of examples a person would think to try.
// INPUTS: None. The chord set and the key cycle are declared in this file so that a change to
//         what is measured is visible in the diff.
// OUTPUTS: A SpikeOutcome carrying one SpikeClaim per measured property, each with the ratio it
//          observed and the threshold it was held to. [SpikeOutcome.report] writes the claims as
//          JSON Lines. No claim is reported as passing on a vacuous sample: a run that measured
//          nothing fails rather than passes.
// KEYWORDS: spike, s3, transposition, round-trip, spelling, measurement, verifiable-claim
import 'dart:convert';

import 'package:chart_core/chart_core.dart';

/// One measured property and whether it held.
class SpikeClaim {
  /// Creates a claim named [name] that [passed], with [detail] describing what was observed.
  const SpikeClaim({
    required this.name,
    required this.passed,
    required this.detail,
  });

  /// Stable identifier of the property, suitable for grouping in a log analyser.
  final String name;

  /// Whether the property held at every sample.
  final bool passed;

  /// Human-readable measurement, stating the sample size as well as the result.
  final String detail;
}

/// The result of running one spike.
class SpikeOutcome {
  /// Creates an outcome for spike [id] answering [question] with [claims].
  const SpikeOutcome({
    required this.id,
    required this.question,
    required this.claims,
  });

  /// The spike id, matching the command line argument.
  final String id;

  /// The question this spike exists to answer, copied from the design document.
  final String question;

  /// One entry per measured property.
  final List<SpikeClaim> claims;

  /// True only when every claim held and at least one claim was measured.
  bool get passed =>
      claims.isNotEmpty && claims.every((SpikeClaim c) => c.passed);

  // PURPOSE: Write the outcome as JSON Lines so that a spike run is analysable after the fact by
  //          tools/logview, the same way a device bench run is.
  // INPUTS: out — the sink to write to.
  // OUTPUTS: Nothing. One line per claim plus a final verdict line, all valid JSON objects.
  // KEYWORDS: reporting, jsonl, structured-logging, verdict
  /// Writes the outcome to [out] as JSON Lines.
  void report(StringSink out) {
    out.writeln(
      jsonEncode(<String, Object?>{
        'name': 'spike.start',
        'spike': id,
        'question': question,
        'claims': claims.length,
      }),
    );
    for (final SpikeClaim claim in claims) {
      out.writeln(
        jsonEncode(<String, Object?>{
          'name': 'spike.claim',
          'spike': id,
          'claim': claim.name,
          'passed': claim.passed,
          'detail': claim.detail,
        }),
      );
    }
    out.writeln(
      jsonEncode(<String, Object?>{
        'name': 'spike.verdict',
        'spike': id,
        'passed': passed,
      }),
    );
  }
}

/// The spelled major keys of the chromatic scale, in pitch-class order from C.
///
/// Declared rather than generated so that the cycle the measurement runs against is readable in
/// the source: a bug in key naming would otherwise silently change what is being measured.
const List<Key> _chromaticKeys = <Key>[
  Key(tonic: WrittenNote(NoteLetter.c, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.d, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.e, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.e, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.f, 1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.g, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.a, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.a, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.b, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.b, 0), mode: Mode.major),
];

/// The chords the measurement runs over: every triad, then sevenths, tensions, a slash bass and
/// a parenthesised marking, so that a property which held only for bare triads is not reported
/// as holding for chords.
const List<Chord> _probeChords = <Chord>[
  Chord(root: ChordRoot(0)),
  Chord(root: ChordRoot(1)),
  Chord(root: ChordRoot(2)),
  Chord(root: ChordRoot(3)),
  Chord(root: ChordRoot(4)),
  Chord(root: ChordRoot(5)),
  Chord(root: ChordRoot(6)),
  Chord(root: ChordRoot(7)),
  Chord(root: ChordRoot(8)),
  Chord(root: ChordRoot(9)),
  Chord(root: ChordRoot(10)),
  Chord(root: ChordRoot(11)),
  Chord(root: ChordRoot(0), quality: ChordQuality.minorTriad),
  Chord(root: ChordRoot(2), quality: ChordQuality.minorSeventh),
  Chord(
    root: ChordRoot(7),
    quality: ChordQuality.dominantSeventh,
    alterations: <String>['b9'],
  ),
  Chord(root: ChordRoot(0), bass: ChordRoot(4)),
  Chord(
    root: ChordRoot(5),
    quality: ChordQuality.majorSeventh,
    parenthesised: true,
  ),
];

// PURPOSE: Run spike S3 and return its measured claims.
// INPUTS: None.
// OUTPUTS: A SpikeOutcome for spike `s3` carrying three claims:
//
//            1. `round_trip_12_keys` — transposing every probe chord through all twelve keys,
//               one semitone at a time while the key advances with it, returns the identical
//               rendered chart. Threshold: every sample, with no exception for the awkward
//               enharmonic keys. A single mismatch fails the claim.
//            2. `octave_identity` — moving a chord by twelve semitones and reading it in the key
//               it started in changes nothing. This is the weaker property, measured separately
//               so that a failure distinguishes "the model lost the spelling" from "the key
//               cycle lost the spelling".
//            3. `spelling_is_total` — every chord, moved by every interval from -12 to +12 in
//               every key, produces a written note that sounds at the chord's pitch class. A
//               spelling that changed the sounding pitch would be a wrong chord, not a wrong
//               label, and this is the claim that catches it.
//
//          The outcome is reported as passing only if all three hold over their full sample.
// KEYWORDS: round-trip, twelve-keys, spelling-preservation, measurement, threshold
/// Runs spike S3 and returns its measured claims.
SpikeOutcome runSpikeS3() {
  const SpellingTable table = SpellingTable();
  const Transposer transposer = Transposer();

  int roundTripSamples = 0;
  int roundTripFailures = 0;
  String firstFailure = '';

  int octaveSamples = 0;
  int octaveFailures = 0;

  int spellingSamples = 0;
  int spellingFailures = 0;

  for (final Chord chord in _probeChords) {
    // Claim 1: the full twelve-key cycle from every starting key.
    for (int startIndex = 0; startIndex < _chromaticKeys.length; startIndex++) {
      Chord current = chord;
      int keyIndex = startIndex;
      for (int step = 0; step < _chromaticKeys.length; step++) {
        current = transposer.transposeChord(current, 1);
        keyIndex = (keyIndex + 1) % _chromaticKeys.length;
      }
      roundTripSamples++;
      final String before = chord.render(_chromaticKeys[startIndex], table);
      final String after = current.render(_chromaticKeys[keyIndex], table);
      if (before != after) {
        roundTripFailures++;
        if (firstFailure.isEmpty) {
          firstFailure =
              '${chord.root} in ${_chromaticKeys[startIndex]}: expected $before, got $after';
        }
      }
    }

    // Claim 2: twelve semitones in one move is the identity.
    for (final Key key in _chromaticKeys) {
      octaveSamples++;
      if (transposer.transposeChord(chord, 12).render(key, table) !=
          chord.render(key, table)) {
        octaveFailures++;
      }
    }

    // Claim 3: spelling never changes what the chord sounds like.
    for (int semitones = -12; semitones <= 12; semitones++) {
      final Chord moved = transposer.transposeChord(chord, semitones);
      for (final Key key in _chromaticKeys) {
        spellingSamples++;
        if (moved.root.spellIn(key, table).pitchClass !=
            moved.root.pitchClass) {
          spellingFailures++;
        }
      }
    }
  }

  return SpikeOutcome(
    id: 's3',
    question:
        'Transposer: does a 12-key round-trip return the original spelling?',
    claims: <SpikeClaim>[
      SpikeClaim(
        name: 'round_trip_12_keys',
        passed: roundTripSamples > 0 && roundTripFailures == 0,
        detail:
            '$roundTripSamples samples, $roundTripFailures mismatches'
            '${firstFailure.isEmpty ? '' : '; first: $firstFailure'}',
      ),
      SpikeClaim(
        name: 'octave_identity',
        passed: octaveSamples > 0 && octaveFailures == 0,
        detail: '$octaveSamples samples, $octaveFailures mismatches',
      ),
      SpikeClaim(
        name: 'spelling_is_total',
        passed: spellingSamples > 0 && spellingFailures == 0,
        detail:
            '$spellingSamples samples, $spellingFailures spelling/pitch disagreements',
      ),
    ],
  );
}
