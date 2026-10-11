// PURPOSE: Render written musical notation as the notation it is, in LATIN, whatever language the
//          interface is drawn in — and keep the names of the NOTATION but not the words of the
//          interface in one place, so a duration or a pitch is named the same way by the note palette
//          and by anything that later prints one.
// INPUTS: A `NoteValue` from the model. Nothing else: the strings below take no arguments because
//          they are notation and notation does not inflect.
// OUTPUTS: The terms a musician reads — `Whole`, `Half`, `Quarter`, `Eighth`, `16th`, `32nd`, and the
//          accidental marks — plus a one-line label joining a pitch to its duration.
// KEYWORDS: notation, latin, duration-name, accidental, owner-decision-a53, no-translation
//
// WHY THESE STRINGS ARE NOT IN THE MESSAGE CATALOGUE, and why that is a decision rather than an
// omission. Owner decision A53 puts MUSICAL NOTATION in Latin in every language of the interface, and
// the owner stated the rule again while this palette was being written: a chart is read as `C major`,
// never as `C мажор`, because these are the international terms of the craft. A note value's name is
// notation — a session player in any country reads `Quarter` — so a catalogue entry for it would be an
// entry whose two translations must be IDENTICAL, and an entry that must never be translated is a
// translation waiting to be made. The interface words around the notation (the captions, the actions,
// the hints) are in the catalogue exactly as before, because those ARE interface.
//
// The accidental marks are the marks themselves rather than their names, which is the same rule: `♯`
// and `♭` are what a musician reads on the page, and this surface's whole job is to say what will be
// written.
import 'package:chart_core/chart_core.dart';

/// The mark drawn for each alteration the pitch row offers, indexed by the alteration in semitones.
///
/// The range is the model's own `[-2, 2]`: a double sharp and a double flat are the widest a
/// `WrittenNote` is ever produced with (`shortestAlter` never exceeds two), and an alteration outside
/// it is not offered by any surface here.
const Map<int, String> accidentMarks = <int, String>{
  -2: '♭♭',
  -1: '♭',
  0: '♮',
  1: '♯',
  2: '♯♯',
};

/// The notation's own name for a written duration's base value.
///
/// An augmentation dot is NOT printed. The palette offers no dotted value, so it cannot produce one,
/// and a caller holding a value this function did not write gets the base named rather than a label
/// invented here.
String noteBaseNotation(NoteBase base) => switch (base) {
  NoteBase.whole => 'Whole',
  NoteBase.half => 'Half',
  NoteBase.quarter => 'Quarter',
  NoteBase.eighth => 'Eighth',
  NoteBase.sixteenth => '16th',
  NoteBase.thirtySecond => '32nd',
};

/// The duration a note value is worth, as the fraction of a bar a musician already reads.
///
/// WHY A CHIP CARRIES `1/4` AND NOT ONLY `Quarter`. Owner decision D28 asks for the duration to be
/// held, reused and changed with as few actions as possible, and the action count is decided by
/// what the musician can READ at a glance: a row of five words (`Whole Half Quarter Eighth 16th`)
/// says what each chip is CALLED and not how long it lasts, so a musician changing one note's
/// duration has to translate the word into a length before he can choose, and a musician setting up
/// a run has to hold five words in mind. The fraction is the length itself, it is the same in every
/// language of the interface (owner decision A53: this is notation, not interface), and it is what
/// the bar's own division is measured in — so `1/4` under a bar of four cells needs no translation
/// step. The word is kept BESIDE it, because `Whole` is what a musician says out loud and a fraction
/// alone would make the palette unreadable to a beginner.
String noteBaseFraction(NoteBase base) => switch (base) {
  NoteBase.whole => '1',
  NoteBase.half => '1/2',
  NoteBase.quarter => '1/4',
  NoteBase.eighth => '1/8',
  NoteBase.sixteenth => '1/16',
  NoteBase.thirtySecond => '1/32',
};

/// The label a duration chip shows: the fraction, then the notation's own name for the value.
///
/// `1/4 · Quarter`, and for the 16th `1/16 · 16th` — a repetition, and it is kept because the two
/// halves do different jobs: the fraction is read at a glance while choosing, and the name is what
/// the palette's other line and the note list print.
String noteBaseChipLabel(NoteBase base) =>
    '${noteBaseFraction(base)} · ${noteBaseNotation(base)}';

/// A pitch and its written duration as one line of notation, such as `F#4 · Quarter`.
String noteNotationLabel(PitchedNote pitch, NoteValue value) =>
    '$pitch · ${noteBaseNotation(value.base)}';

/// The mark drawn for [alter], or the natural sign for an alteration no surface offers.
String accidentMark(int alter) => accidentMarks[alter] ?? accidentMarks[0]!;

/// A key named as a musician writes it, such as `C major` or `Bb minor`.
///
/// IT IS DELIBERATELY NOT LOCALIZED, and that is owner decision A53 rather than an oversight: a
/// musician reads `C major` in every language of the interface, and the same rule covers the marks,
/// the roots and the durations above. The mode is printed as the English word rather than translated,
/// so the palette is not the one place a chart's own key is named in words a chart never uses.
String keyNotation(Key key) =>
    '${key.tonic} ${key.mode == Mode.major ? 'major' : 'minor'}';
