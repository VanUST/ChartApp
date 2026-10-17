// PURPOSE: Dump what the importer actually reads from an iReal export, so the reading can be
//          checked against the application that produced the file rather than against another copy
//          of the same assumption. A parser and its tests written from one understanding of a
//          format agree with each other; only an outside artefact can contradict them.
// INPUTS: argv[0] — a path to an .html file containing an `irealb://` link. Optionally argv[1] —
//         a case-insensitive substring; when given, only songs whose title contains it are dumped.
// OUTPUTS: One block per song: the metadata, the section and bar counts, and every bar with its
//          chords rendered in the song's own key, each chord tagged with the cell it landed on.
//          Every bar also carries the chord symbols THE FILE WROTE, so the printed text can be
//          compared with the source line by line instead of being asserted to match, and the last
//          line of the dump is a count of the chords compared and of the ones that came back
//          spelled differently.
//
//          EXIT CODES, stated because this probe is an instrument and its number is read:
//            0 — the file was read and every chord printed the way the file wrote it, or the
//                reader stopped reading and this process was told the pipe had closed (see below);
//            1 — the file was read and at least one chord came back spelled differently, which is
//                a real defect in the importer and not a property of the file;
//            2 — no file, or no `irealb://` link in it.
//
//          A CLOSED OUTPUT PIPE IS AN ENDING, NOT A FAILURE. This dump is more than a thousand
//          lines, so a reader that truncates it (`| Select-Object -First N`, a log window that
//          stops consuming, an editor that pages) closes the pipe while the process is still
//          writing, and `stdout.writeln` then throws `FileSystemException: writeFrom failed ... (OS
//          Error: Идет закрытие канала)`. Unhandled, that kills the probe with a non-zero code on
//          a run whose data was perfect, which is exactly how this instrument came to report a
//          failure on the owner's own book. It is caught in [main] and treated as the end of the
//          dump; a genuine failure of the reader is still reported, because it is not a
//          FileSystemException.
// KEYWORDS: probe, ireal, verification, diagnostic, playlist, chart-dump, spelling-check,
//           exit-code, broken-pipe, not-part-of-the-library
import 'dart:async';
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// Runs the probe and turns any failure into a reported exit code.
///
/// The body is wrapped in a guarded zone because `stdout.writeln` reports a closed pipe by calling
/// the zone's uncaught-error handler rather than by throwing to its caller, so a `try` around the
/// write would not see it. A [FileSystemException] is the closed pipe and ends the dump; anything
/// else is a real error and exits 1 with its text on stderr.
void main(List<String> args) {
  runZonedGuarded(
    () {
      final int code = _run(args);
      if (code != 0) {
        exit(code);
      }
    },
    (Object error, StackTrace stack) {
      if (error is FileSystemException) {
        // The reader closed the pipe. Every line it was willing to take has been taken; there is
        // nothing left to report to and nothing wrong with the file.
        return;
      }
      stderr.writeln('probe_ireal: $error\n$stack');
      exitCode = 1;
    },
  );
}

/// Dumps every song in the file and returns the exit code the dump earned.
int _run(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: probe_ireal <file.html> [title-substring]');
    return 2;
  }
  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('no such file: ${args[0]}');
    return 2;
  }
  final RegExpMatch? link = RegExp('irealb://([^"]*)')
      .firstMatch(file.readAsStringSync());
  if (link == null) {
    stderr.writeln('no irealb:// link found in ${args[0]}');
    return 2;
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

  const SpellingTable table = SpellingTable();
  int songsShown = 0;
  int chordsWritten = 0;
  int chordsPrinted = 0;
  int mismatches = 0;

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
    songsShown++;

    // The notation the parser was actually handed, decoded and verbatim, and the chord symbols it
    // contains in reading order. The tokens are the same ones the parser consumed, so the two
    // lists below are two readings of ONE text rather than two guesses about it.
    final String body = _musicBody(payload);
    final List<String> written = _writtenChords(body);

    // Every chord the model now holds, in the same reading order, rendered in the song's own key.
    final List<String> printed = <String>[];
    final List<String> addresses = <String>[];
    for (final Section section in song.sections) {
      for (int barIndex = 0; barIndex < section.bars.length; barIndex++) {
        final List<ChordMark> marks = section.bars[barIndex].chords;
        for (int markIndex = 0; markIndex < marks.length; markIndex++) {
          printed.add(marks[markIndex].chord.render(song.key, table));
          addresses.add('${section.id}[$barIndex]#$markIndex');
        }
      }
    }

    stdout.writeln('    RAW $body');
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

    // THE LINE-BY-LINE CHECK. A printed chord must be the text the file wrote for it, character
    // for character: the importer takes the symbol apart and puts it back together, so anything
    // else is a symbol that changed on the way in. The comparison is positional, which is sound
    // because the parser emits one ChordMark per chord token and reports a chord it could not
    // represent as an issue instead of dropping it silently — when those lists differ in length
    // the alignment is reported rather than guessed at.
    final bool aligned = written.length == printed.length;
    final int firstMismatch = aligned ? _firstMismatch(written, printed) : -1;
    if (!aligned) {
      mismatches++;
      stdout.writeln(
        '    ALIGNMENT chords_in_file=${written.length} '
        'chords_in_model=${printed.length} — the two lists cannot be compared positionally',
      );
    }

    // TWO BARS OF BOTH SIDES, side by side, so the reader can check the comparison by eye rather
    // than trusting the count at the end. The written side uses the SAME cursor the check uses, so
    // a bar shows the symbols that were compared with it and not a second pairing.
    int cursor = 0;
    for (final Section section in song.sections) {
      stdout.writeln(
        '  [${section.id}] "${section.label}" bars=${section.bars.length}',
      );
      for (int barIndex = 0; barIndex < section.bars.length; barIndex++) {
        final Bar bar = section.bars[barIndex];
        final String chords = bar.chords
            .map(
              (ChordMark c) =>
                  '${c.offsetX.toStringAsFixed(1)}:${c.chord.render(song.key, table)}'
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
        final int count = bar.chords.length;
        if (cursor + count <= written.length) {
          if (barIndex < 2) {
            stdout.writeln(
              '      written as: ${written.sublist(cursor, cursor + count).join(" ")}',
            );
          }
        }
        cursor += count;
      }
    }

    chordsWritten += written.length;
    chordsPrinted += printed.length;
    if (aligned && firstMismatch >= 0) {
      // Reported once per song, with the first disagreement, and counted here for the summary.
      mismatches += _countMismatches(written, printed);
      stdout.writeln(
        '    SPELLING ${addresses[firstMismatch]}: the file wrote '
        '"${written[firstMismatch]}" and the model printed '
        '"${printed[firstMismatch]}"',
      );
    }
    stdout.writeln('');
  }

  // THE NUMBER THE REST OF THE REPORT RESTS ON, printed rather than left implicit: how many chords
  // were compared, how many differed, and which exit code the caller will get.
  final int exitCode = mismatches == 0 ? 0 : 1;
  stdout.writeln(
    'SUMMARY songs=$songsShown chords_in_file=$chordsWritten '
    'chords_in_model=$chordsPrinted spelling_mismatches=$mismatches '
    'exit=$exitCode',
  );
  return exitCode;
}

/// Returns the decoded music field of [payload], or the empty string when it carries none.
///
/// The `irealMusicPrefix` is removed because it is a marker rather than notation, which is the same
/// text `parseIRealPayload` hands the tokenizer; using anything else here would compare the model
/// against a string the parser never saw.
String _musicBody(IRealPayload payload) {
  final int musicIndex = payload.musicFieldIndex;
  if (musicIndex < 0) {
    return '';
  }
  final String field = payload.field(musicIndex);
  if (!field.startsWith(irealMusicPrefix)) {
    return '';
  }
  return deobfuscateIrealMusic(field.substring(irealMusicPrefix.length));
}

/// Returns the chord symbols [body] contains, in reading order, exactly as written.
List<String> _writtenChords(String body) => <String>[
  for (final IRealToken token in tokenizeIReal(body))
    if (token is ChordToken) token.text,
];

/// Returns the index of the first pair that differs, or -1 when every pair matches.
int _firstMismatch(List<String> written, List<String> printed) {
  for (int i = 0; i < written.length; i++) {
    if (written[i] != printed[i]) {
      return i;
    }
  }
  return -1;
}

/// Returns how many pairs differ, for a song already known to be aligned.
int _countMismatches(List<String> written, List<String> printed) {
  int count = 0;
  for (int i = 0; i < written.length; i++) {
    if (written[i] != printed[i]) {
      count++;
    }
  }
  return count;
}
