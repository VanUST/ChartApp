// PURPOSE: Report what VERBAL TEXT the owner's real iReal exports actually carry on their bars, so
//          that work on interpreting musical navigation ("D.C. al Coda", "D.S. al Fine", coda,
//          fine) rests on what the corpus contains rather than on what a standard implies. A13
//          deferred navigation for want of a corpus; this is how the corpus answers.
//
//          It lives in the app rather than in chart_core because the iReal loader does: the parser
//          returns IRealLibrary, which is an application type. chart_core owns the model, the app
//          owns reading a file into it.
// INPUTS: The path to an iReal `.html` export, defaulting to the owner's setlist. Read-only.
// OUTPUTS: One line of counts, then the distinct staff texts by frequency, then the leading words.
//          Nothing is written and no document is modified.
// KEYWORDS: probe, ireal, staff-text, navigation, dc-al-coda, ds-al-fine, corpus
//
// Run it from apps/mobile:  dart run tool/probe_staff_text.dart [path]
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/ireal_library.dart';

/// The words that would make navigation interpretation matter at all.
const List<String> _navWords = <String>[
  'd.c',
  'dc',
  'd.s',
  'ds',
  'coda',
  'fine',
  'segno',
];

/// Reads the export at [path] and prints what it carries.
void main(List<String> args) {
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

  final Map<String, int> texts = <String, int>{};
  final Map<String, int> leadingWords = <String, int>{};
  int bars = 0;
  int barsWithText = 0;
  int navBars = 0;

  for (final IRealSong entry in library.songs) {
    for (final Section section in entry.song.sections) {
      for (final Bar bar in section.bars) {
        bars++;
        if (bar.staffText.isEmpty) {
          continue;
        }
        barsWithText++;
        var navHere = false;
        for (final String text in bar.staffText) {
          texts[text] = (texts[text] ?? 0) + 1;
          final String lower = text.toLowerCase();
          if (_navWords.any(lower.contains)) {
            navHere = true;
          }
          final String stripped = lower
              .replaceAll(RegExp(r'[^a-z. ]'), ' ')
              .trim();
          final List<String> parts = stripped
              .split(RegExp(r'\s+'))
              .where((String p) => p.isNotEmpty)
              .toList();
          if (parts.isNotEmpty) {
            leadingWords[parts.first] = (leadingWords[parts.first] ?? 0) + 1;
          }
        }
        if (navHere) {
          navBars++;
        }
      }
    }
  }

  stdout.writeln(
    'songs=${library.songs.length} bars=$bars barsWithAnyText=$barsWithText '
    'distinctTexts=${texts.length} barsWithNavigationWords=$navBars',
  );

  final List<MapEntry<String, int>> sorted = texts.entries.toList()
    ..sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value),
    );
  stdout.writeln('--- distinct staff texts (top 30) ---');
  for (final MapEntry<String, int> e in sorted.take(30)) {
    stdout.writeln('  x${e.value}\t"${e.key}"');
  }

  final List<MapEntry<String, int>> words = leadingWords.entries.toList()
    ..sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value),
    );
  stdout.writeln('--- leading words (top 15) ---');
  for (final MapEntry<String, int> e in words.take(15)) {
    stdout.writeln('  ${e.key} x${e.value}');
  }
}
