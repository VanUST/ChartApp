// PURPOSE: Measure the SHAPE of the owner's real iReal exports so that the starting shape of a
//          chart written from scratch is decided from what his music actually looks like rather
//          than from taste. The question it answers is narrow: when a musician opens a blank chart,
//          how many bars, how many sections, which meter, which key and which style should be
//          there before he writes anything?
//
//          It lives in the app rather than in chart_core because the iReal loader does: the parser
//          returns IRealLibrary, which is an application type.
// INPUTS: The path to an iReal `.html` export, defaulting to the owner's setlist. Read-only.
// OUTPUTS: One line of totals, then histograms for song length, sections per song, bars per
//          section, meter, key (by tonic and mode) and style, the tempo statistics, and — the
//          figure the per-bar meter requirement is judged on — WHERE the meter changes inside each
//          song: how many songs change it, what each change is, and on which written bar it lands.
//          Nothing is written and no document is modified.
// KEYWORDS: probe, ireal, corpus, default-shape, new-chart, sections, bars, meter, meter-change,
//           key, tempo
//
// WHY THE METER-CHANGE COUNT EXISTS AND WHAT IT DOES NOT DECIDE. Owner decision D22 requires a
// meter a musician sets by hand on any bar. The count below says how many of the charts he ALREADY
// has would be rendered wrongly today for want of a meter sign — which is the defect, not the
// requirement: the requirement is about what he writes next. A count of zero would therefore NOT
// retire the requirement, and it is reported plainly either way rather than being used to argue
// the feature down.
//
// Run it from apps/mobile:  dart run tool/probe_corpus_shape.dart [path]
import 'dart:convert';
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/ireal_library.dart';

// PURPOSE: Count how often each value occurs, so every histogram below is written the same way.
// INPUTS: values — the observations, in any order.
// OUTPUTS: A map from value to count. An empty input gives an empty map.
// KEYWORDS: histogram, tally, counting
Map<T, int> _tally<T>(Iterable<T> values) {
  final Map<T, int> counts = <T, int>{};
  for (final T value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}

// PURPOSE: Print a histogram sorted by descending count, as "value xN".
// INPUTS: label — what is being counted. counts — the tally.
// OUTPUTS: Nothing; writes lines to stdout.
// KEYWORDS: report, histogram, sorted
void _report<T>(String label, Map<T, int> counts) {
  final List<MapEntry<T, int>> sorted = counts.entries.toList()
    ..sort(
      (MapEntry<T, int> a, MapEntry<T, int> b) => b.value.compareTo(a.value),
    );
  stdout.writeln('--- $label ---');
  for (final MapEntry<T, int> entry in sorted) {
    stdout.writeln('  ${entry.key} x${entry.value}');
  }
}

/// Reads the export at [path] and prints the shape of its songs.
void main(List<String> args) {
  // The export carries Russian song titles and this host's ANSI code page is windows-1251, so the
  // report is written in UTF-8 explicitly: without this a redirected run mangles every Cyrillic
  // title into replacement bytes, which is the trap that has corrupted output here before.
  stdout.encoding = utf8;
  final String path = args.isNotEmpty
      ? args.first
      : r'C:\Users\1\Downloads\Ракета Русское.html';
  final File file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('no such export: $path');
    return;
  }
  final IRealLibrary library = parseIRealExport(
    file.readAsStringSync(),
    source: path,
  );

  final List<int> songBars = <int>[];
  final List<int> sectionsPerSong = <int>[];
  final List<int> barsPerSection = <int>[];
  final List<String> meters = <String>[];
  final List<String> keys = <String>[];
  final List<String> styles = <String>[];
  final List<int> tempos = <int>[];
  int songsWithTempo = 0;
  int songsWithStyle = 0;

  for (final IRealSong entry in library.songs) {
    final Song song = entry.song;
    songBars.add(song.writtenBarCount);
    sectionsPerSong.add(song.sections.length);
    for (final Section section in song.sections) {
      barsPerSection.add(section.bars.length);
      for (final Bar bar in section.bars) {
        meters.add(bar.timeSignature.toString());
      }
    }
    keys.add('${song.key}');
    if (song.style.trim().isNotEmpty) {
      songsWithStyle++;
      styles.add(song.style.trim());
    }
    if (song.tempo > 0) {
      songsWithTempo++;
    }
    tempos.add(song.tempo);
  }

  final int totalBars = songBars.fold<int>(0, (int a, int b) => a + b);
  final int totalSections = sectionsPerSong.fold<int>(
    0,
    (int a, int b) => a + b,
  );
  final List<int> sortedSongBars = List<int>.of(songBars)..sort();
  final List<int> sortedSections = List<int>.of(barsPerSection)..sort();

  String median(List<int> sorted) =>
      sorted.isEmpty ? 'n/a' : '${sorted[sorted.length ~/ 2]}';

  stdout.writeln(
    'songs=${library.songs.length} bars=$totalBars '
    'avgBars=${(totalBars / library.songs.length).toStringAsFixed(1)} '
    'minBars=${sortedSongBars.first} medianBars=${median(sortedSongBars)} '
    'maxBars=${sortedSongBars.last}',
  );
  stdout.writeln(
    'sections=$totalSections '
    'avgSectionsPerSong=${(totalSections / library.songs.length).toStringAsFixed(2)} '
    'medianBarsPerSection=${median(sortedSections)} '
    'minBarsPerSection=${sortedSections.first} maxBarsPerSection=${sortedSections.last}',
  );
  stdout.writeln(
    'songsWithStyle=$songsWithStyle songsWithTempo=$songsWithTempo '
    'tempoZero=${tempos.where((int t) => t == 0).length}',
  );

  _report<int>('bars per section', _tally<int>(barsPerSection));
  _report<int>('sections per song', _tally<int>(sectionsPerSong));
  _report<String>('meter', _tally<String>(meters));
  _report<String>('key', _tally<String>(keys));
  _report<String>('style', _tally<String>(styles));
  _report<int>('song bar count', _tally<int>(songBars));

  // --- where the meter changes, per song -------------------------------------------------------
  //
  // A "change" is a written bar whose meter differs from the bar before it in reading order, across
  // section boundaries. The FIRST bar of a song is not a change: there is nothing before it to
  // change from, and a 3/4 chart that opens in 3/4 is counted separately as an unusual opening,
  // because that is the case the renderer must still sign at the start of every system.
  int songsWithChange = 0;
  int songsOpeningNon44 = 0;
  int changeBars = 0;
  final Map<String, int> transitions = <String, int>{};
  final List<String> meterRows = <String>[];
  for (final IRealSong entry in library.songs) {
    final Song song = entry.song;
    final List<TimeSignature> written = <TimeSignature>[
      for (final Section section in song.sections)
        for (final Bar bar in section.bars) bar.timeSignature,
    ];
    if (written.isEmpty) {
      continue;
    }
    final List<String> changes = <String>[];
    for (int index = 1; index < written.length; index++) {
      if (written[index] == written[index - 1]) {
        continue;
      }
      final String transition = '${written[index - 1]}->${written[index]}';
      changes.add('$transition@${index + 1}');
      transitions[transition] = (transitions[transition] ?? 0) + 1;
      changeBars++;
    }
    if (changes.isNotEmpty) {
      songsWithChange++;
    }
    if (written.first != TimeSignature.fourFour) {
      songsOpeningNon44++;
    }
    final Map<TimeSignature, int> counts = _tally<TimeSignature>(written);
    meterRows.add(
      '  "${song.title}" bars=${written.length} opens=${written.first} '
      'meters=${counts.entries.map((MapEntry<TimeSignature, int> e) => '${e.key}x${e.value}').join(' ')} '
      'changes=${changes.isEmpty ? 'none' : changes.join(',')}',
    );
  }
  stdout.writeln('--- meter changes ---');
  stdout.writeln(
    '  songsWithChange=$songsWithChange of ${library.songs.length} '
    'songsOpeningNon44=$songsOpeningNon44 changeBars=$changeBars '
    'totalBars=$totalBars',
  );
  _report<String>('meter transitions', transitions);
  for (final String row in meterRows) {
    stdout.writeln(row);
  }

  // Melody and percussion, counted once more here so the new-chart debt has a number beside it.
  int melodyBars = 0;
  int percussionBars = 0;
  int pitchedStaffSongs = 0;
  for (final IRealSong entry in library.songs) {
    if (entry.song.staffSet.pitched != null) {
      pitchedStaffSongs++;
    }
    for (final Section section in entry.song.sections) {
      for (final Bar bar in section.bars) {
        if (bar.melody.isNotEmpty) {
          melodyBars++;
        }
        if (bar.percussion.isNotEmpty) {
          percussionBars++;
        }
      }
    }
  }
  stdout.writeln(
    'staves: pitchedStaffSongs=$pitchedStaffSongs melodyBars=$melodyBars '
    'percussionBars=$percussionBars',
  );
}
