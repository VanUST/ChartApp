// PURPOSE: Dump what the importer actually reads from an iReal export, so the reading can be
//          checked against the application that produced the file rather than against another copy
//          of the same assumption. A parser and its tests written from one understanding of a
//          format agree with each other; only an outside artefact can contradict them.
// INPUTS: argv[0] — a path to an .html file containing an `irealb://` link. Optionally argv[1] —
//         a case-insensitive substring; when given, only songs whose title contains it are dumped.
// OUTPUTS: One block per song: the metadata, the section and bar counts, and every bar with its
//          chords rendered in the song's own key, each chord tagged with the cell it landed on.
//          Exits 2 when the file or the link is missing, 0 otherwise. Nothing here is part of the
//          library: it is a diagnostic, and it lives in `tool/` so that it can use dart:io without
//          the package taking a dependency on anything.
// KEYWORDS: probe, ireal, verification, diagnostic, playlist, chart-dump, not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: probe_ireal <file.html> [title-substring]');
    exit(2);
  }
  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('no such file: ${args[0]}');
    exit(2);
  }
  final RegExpMatch? link = RegExp('irealb://([^"]*)')
      .firstMatch(file.readAsStringSync());
  if (link == null) {
    stderr.writeln('no irealb:// link found in ${args[0]}');
    exit(2);
  }
  final String decoded = Uri.decodeFull(link.group(1)!);
  final String? filter = args.length > 1 ? args[1].toLowerCase() : null;

  // The payload is itself split on `===` first; the trailing segment is the playlist name. The
  // library reports a multi-song payload rather than silently importing one song, so the probe
  // does the enumeration itself.
  final List<String> segments = decoded.split('===');
  final String? playlistName = segments.length > 1 ? segments.last : null;
  final List<String> songs = segments.length > 1
      ? segments.sublist(0, segments.length - 1)
      : segments;

  stdout.writeln('PLAYLIST=${playlistName ?? '(none)'}');
  stdout.writeln('SONGS=${songs.length}');
  stdout.writeln('');

  for (int index = 0; index < songs.length; index++) {
    final IRealPayload payload = IRealPayload.parse(songs[index]);
    if (filter != null && !payload.title.toLowerCase().contains(filter)) {
      continue;
    }
    final IRealParseResult result = parseIRealPayload(
      songs[index],
      documentId: 'probe-$index',
    );
    final Song song = result.song;
    // The decoded notation, verbatim. When a rendering disagrees with the app that produced the
    // file, this is what settles it: the difference is either in the file or in the reader, and
    // only the raw body can say which.
    final int musicIndex = payload.musicFieldIndex;
    if (musicIndex >= 0) {
      final String field = payload.field(musicIndex);
      if (field.startsWith(irealMusicPrefix)) {
        stdout.writeln(
          '    RAW ${deobfuscateIrealMusic(field.substring(irealMusicPrefix.length))}',
        );
      }
    }
    stdout.writeln('--- [$index] ${song.title}');
    stdout.writeln(
      '    composer="${song.composer}" style="${song.style}" '
      'keyText="${payload.keyText}" transpose=${payload.transposeValue} '
      'bpm=${payload.bpm}',
    );
    stdout.writeln(
      '    sections=${song.sections.length} bars=${song.writtenBarCount} '
      'issues=${result.issues.length}',
    );
    for (final IRealParseIssue issue in result.issues) {
      stdout.writeln('    issue @${issue.offset}: ${issue.message}');
    }
    for (final Section section in song.sections) {
      stdout.writeln(
        '  [${section.id}] "${section.label}" bars=${section.bars.length}',
      );
      for (int barIndex = 0; barIndex < section.bars.length; barIndex++) {
        final Bar bar = section.bars[barIndex];
        final String chords = bar.chords
            .map(
              (ChordMark c) =>
                  '${c.offsetX.toStringAsFixed(1)}:${c.chord.render(song.key, const SpellingTable())}'
                  '${c.size == ChordSize.small ? '(s)' : ''}',
            )
            .join(' ');
        final StringBuffer marks = StringBuffer();
        if (bar.repeatPrevious != RepeatPrevious.none) {
          marks.write(' X=${bar.repeatPrevious.name}');
        }
        if (bar.slashRepeat) {
          marks.write(' slash');
        }
        if (bar.noChord) {
          marks.write(' NC');
        }
        if (bar.volta != null) {
          marks.write(' volta=${bar.volta!.number}');
        }
        if (bar.marks.isNotEmpty) {
          marks.write(
            ' marks=${bar.marks.map((BarMark m) => m.name).join(",")}',
          );
        }
        if (bar.staffText.isNotEmpty) {
          marks.write(' text=${bar.staffText.join("|")}');
        }
        stdout.writeln(
          '    $barIndex ${bar.openingBarline.name}..${bar.closingBarline.name} '
          '[$chords]$marks',
        );
      }
    }
    stdout.writeln('');
  }
}
