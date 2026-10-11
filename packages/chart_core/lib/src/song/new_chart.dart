// PURPOSE: Define the chart a musician writes from nothing — the one value this application could
//          not produce before, because music arrived only by importing an iReal export. It answers
//          one question: what is on the page at the moment the musician decides to write a new
//          tune, before they have typed a note of it?
// INPUTS: The key the chart is to be written in, the meter its bars are in, and how many bars its
//         first section holds. Every input has a default, so a caller that has no opinion still
//         gets a musically sensible chart.
// OUTPUTS: A [Song] carrying ONE section, labelled A, of nothing but empty bars in the given meter
//          and key, with no title, no composer, no style and no tempo. It is an ordinary Song: the
//          same editing session, the same event catalogue, the same `.chart` container and the same
//          identity function handle it as any imported chart, and nothing downstream can tell that
//          it was not imported.
// KEYWORDS: new-chart, blank-chart, from-scratch, default-shape, starting-point, song-factory,
//           d21, authoring
//
// WHY THIS EXISTS AT ALL, AND WHY IT IS IN `chart_core`.
//
// The whole application is built around a Song: the editor edits one, the container stores one, the
// identity is derived from one. A chart written from scratch is therefore not a second kind of
// document — it is the same document with a beginning. Putting the beginning here, with the model
// it produces, keeps it checkable by `dart test` and `dart run` on a machine with no device, which
// is the rule this package exists under (no Flutter, no `dart:io`, no clock). The app layer decides
// only WHEN a musician wants one and WHICH key and meter they asked for; what a new chart IS lives
// beside the model.
//
// WHY ONE SECTION OF EIGHT BARS, AND WHERE THE NUMBER COMES FROM.
//
// Measured from the owner's own export (`apps/mobile/tool/probe_corpus_shape.dart`, 22 songs, 1045
// bars, 90 sections): the most common section length is EIGHT bars, twenty-two sections of ninety,
// with sixteen second at thirteen; the average song is 47.5 bars over four sections, and the
// section lengths fall on the powers of two a working musician counts in. Eight is therefore not a
// taste: it is the module the owner's own form is built from, it is four bars of a plausible
// chord progression plus its answer, and it is small enough that a musician who wanted twelve is
// four taps from it while one who got forty would have to delete thirty-two.
//
// WHY ONE SECTION RATHER THAN THREE. A new chart's sections are added by the form sheet, one at a
// time, and a new section is born with one bar (owner decision D17 and `EditSession`). Seeding
// three empty sections would put two names on the page that mean nothing yet, and the corpus's
// three-sections-per-song average describes FINISHED tunes, not tunes being started.
//
// WHY THE METER AND THE KEY ARE ARGUMENTS RATHER THAN CONSTANTS INTERNAL TO THIS FILE.
//
// Both are facts a chart cannot be changed out of afterwards, and that is a real gap rather than a
// design: nothing in the event catalogue rewrites a bar's meter, and nothing in the interface
// changes a song's written key (the key grid moves what is SHOWN — owner decision D14's editor
// meaning — and a save writes the written chart). So the two properties are offered at the moment
// of creation, where the musician still has the choice, and 4/4 and C major stand as the defaults:
// 1032 of the owner's 1045 bars are 4/4, and no key dominates his corpus (fourteen minor songs
// across seven tonics, eight major across six), which leaves C major as the model's own reference
// key (`Key.cMajor`) and the one every spelling rule is described against.
//
// WHAT IS DELIBERATELY NOT HERE. No title. `Song.title` is empty until the musician names the
// tune through `song.update`, which is the same door a rename goes through — so there is exactly
// one way a chart is named, whether it was made or imported. No tempo and no style either: 17 of
// the owner's 22 charts carry no tempo at all, and the model already defines 0 as "this chart sets
// none", so an invented tempo would assert a fact about the music that nobody has decided yet.
import '../key.dart';
import 'bar.dart';
import 'section.dart';
import 'song.dart';
import 'time_signature.dart';

/// How many bars the first section of a chart written from scratch holds.
///
/// Eight, measured from the owner's own corpus: it is the most common section length there (22 of
/// 90) and the module his form is built from. See the file header for the numbers.
const int newChartBarCount = 8;

/// The label the first section of a chart written from scratch carries.
///
/// A rehearsal letter rather than a name, because a new tune has no sections whose meaning is
/// known yet: `A` asserts nothing about the music, while `Куплет` would claim the first eight bars
/// are a verse before the musician has written one. The form sheet renames it.
const SectionLabel newChartFirstSectionLabel = SectionLabel.letter('A');

/// The id the first section of a chart written from scratch carries.
///
/// An address, not music — `chartIdentityOf` excludes section ids, and an anchor resolves through
/// one — so a fixed id is correct here: it is unique within the song it is the only section of.
/// It matches what `EditSession.insertSectionAfter` mints next (`sec-2`), because that method
/// numbers new sections from the session's sequence counter, which starts at one.
const String newChartFirstSectionId = 'sec-1';

// PURPOSE: Produce the chart a musician starts writing on: one section of empty bars in the meter
//          and key they asked for, with nothing else decided for them.
// INPUTS: key — the key the chart is written in; defaults to C major, the model's reference key.
//         timeSignature — the meter every bar of the first section carries; defaults to 4/4.
//         bars — how many bars that section holds; defaults to [newChartBarCount] and is a whole
//         number of at least one.
// OUTPUTS: A [Song] with one section of [bars] empty bars, an empty title, composer, style and
//          tempo, and the given key. The song's `id` is left EMPTY on purpose: the id belongs to a
//          store that has not assigned one, and `EditSession` already defines what a document with
//          no id is written under (see `EditSession.untitledDocumentId`), so inventing one here
//          would be a second answer to a question that has one.
//
//          Throws [ArgumentError] when [bars] is below one. It is not clamped: a section with no
//          bars cannot be seen, tapped or selected, so it is a state the editor cannot leave, and
//          `EditSession.deleteBar` refuses to create one for the same reason. A caller asking for
//          zero has a bug, and a silently repaired chart would hide it behind a page that looks
//          empty for a different reason.
// KEYWORDS: new-chart, blank-bars, meter, key, one-section, empty-metadata, fail-loud, d21
/// Returns a chart of [bars] empty bars in [timeSignature], written in [key].
Song newChartSong({
  Key key = Key.cMajor,
  TimeSignature timeSignature = TimeSignature.fourFour,
  int bars = newChartBarCount,
}) {
  if (bars < 1) {
    throw ArgumentError.value(
      bars,
      'bars',
      'a section of a chart needs at least one bar, or it can be neither seen nor selected',
    );
  }
  return Song(
    // Empty and not a placeholder word: "no title" is a value this model holds, the interface has
    // its own word for drawing it (`l10n.untitled`), and a chart typed from scratch is named
    // through `song.update` exactly as an imported one is renamed.
    title: '',
    key: key,
    sections: <Section>[
      Section(
        id: newChartFirstSectionId,
        label: newChartFirstSectionLabel,
        bars: <Bar>[
          for (int index = 0; index < bars; index++)
            Bar(timeSignature: timeSignature),
        ],
      ),
    ],
  );
}
