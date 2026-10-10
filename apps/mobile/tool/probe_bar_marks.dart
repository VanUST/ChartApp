// PURPOSE: Report what the owner's real iReal exports carry in `Bar.marks` — the segno, the coda,
//          the fermata and the player's stop — and then take ONE bar of that real corpus that
//          already carries a mark and run the new `mark.set` path over it, so the claim "editing a
//          marked bar does not disturb the signs already there" rests on the owner's own music
//          rather than on a hand-built fixture. The corpus is what decided that marks were worth
//          building (A42 measured 31 of them) and it is what has to show they survive an edit.
//
//          It lives in the app rather than in chart_core because the iReal loader does: the parser
//          returns IRealLibrary, which is an application type.
// INPUTS: The path to an iReal `.html` export, defaulting to the owner's setlist. Read-only; the
//         only document ever changed is the in-memory one an [EditSession] holds, and every change
//         is undone before the probe moves on.
// OUTPUTS: One summary line of counts, a line naming the corpus bar chosen, then the whole mark set
//          of that bar before the edit, after ADDING a sign it did not carry, after UNDOING that
//          edit (compared against the whole document), after CLEARING one of the signs it did carry,
//          and after undoing that too. Nothing is written and no file is modified.
// KEYWORDS: probe, ireal, corpus, bar-mark, segno, coda, fermata, player-ending, mark-set,
//           op-log, undo, exact-restore
//
// Run it from apps/mobile:  dart run tool/probe_bar_marks.dart [path]
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/ireal_library.dart';

/// One bar of the corpus that carries at least one mark, with enough to run the edit path.
class _CorpusMarkedBar {
  /// Creates a reference to the bar at ([sectionId], [barIndex]) of [song].
  const _CorpusMarkedBar({
    required this.song,
    required this.title,
    required this.sectionId,
    required this.barIndex,
  });

  /// The song the bar belongs to, in its written form.
  final Song song;

  /// The song's display title, so a line of output names the tune a reader can find.
  final String title;

  /// The section the bar sits in.
  final String sectionId;

  /// The bar's zero-based index inside that section.
  final int barIndex;

  /// The bar as the corpus wrote it.
  Bar get bar => song.barAt(sectionId, barIndex)!;

  @override
  String toString() =>
      '"$title" $sectionId[$barIndex] marks=${_marks(bar.marks)}';
}

/// The names of [marks] in the order the bar holds them, which is the order the painter draws.
String _marks(Set<BarMark> marks) =>
    '[${marks.map((BarMark mark) => mark.name).join(', ')}]';

/// Reads the export at [path] and runs the mark probe over it.
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

  int bars = 0;
  int barsWithMarks = 0;
  int barsWithSeveral = 0;
  final Map<BarMark, int> byMark = <BarMark, int>{};
  _CorpusMarkedBar? widestMarked;

  for (final IRealSong entry in library.songs) {
    for (final Section section in entry.song.sections) {
      for (int index = 0; index < section.bars.length; index++) {
        bars++;
        final Set<BarMark> marks = section.bars[index].marks;
        if (marks.isEmpty) {
          continue;
        }
        barsWithMarks++;
        if (marks.length > 1) {
          barsWithSeveral++;
        }
        for (final BarMark mark in marks) {
          byMark[mark] = (byMark[mark] ?? 0) + 1;
        }
        // The WIDEST marked bar is chosen rather than the first: an edit over a bar that already
        // carries several signs is the case where "the signs already there survive it" can actually
        // be checked, and a bar with one sign cannot show that.
        if (widestMarked == null ||
            marks.length > widestMarked.bar.marks.length) {
          widestMarked = _CorpusMarkedBar(
            song: entry.song,
            title: entry.title,
            sectionId: section.id,
            barIndex: index,
          );
        }
      }
    }
  }

  final int totalMarks = byMark.values.fold(0, (int a, int b) => a + b);
  final String kinds = BarMark.values
      .map((BarMark mark) => '${mark.name}=${byMark[mark] ?? 0}')
      .join(' ');
  stdout.writeln(
    'songs=${library.songs.length} bars=$bars marks=$totalMarks '
    'barsWithMarks=$barsWithMarks barsWithSeveral=$barsWithSeveral $kinds',
  );

  final _CorpusMarkedBar? chosen = widestMarked;
  if (chosen == null) {
    stdout.writeln('bar_mark.corpus none: the export carries no mark at all');
    return;
  }
  stdout.writeln('bar_mark.corpus chosen=$chosen');
  _editCorpusBar(chosen);
}

// PURPOSE: Run one ADD and one CLEAR over a real marked bar and show, at every step, the whole set
//          of signs the bar carries — because the claim being checked is about what SURVIVES an
//          edit, and a summary count cannot show that a sign was replaced by another.
// INPUTS: chosen — the corpus bar to edit.
// OUTPUTS: Printed evidence only. The whole [DocumentState] is compared after each undo, and the
//          comparison's components are printed rather than a boolean.
// KEYWORDS: corpus-evidence, add, clear, order-preserved, whole-state, undo, exact-restore
void _editCorpusBar(_CorpusMarkedBar chosen) {
  const String docId = 'corpus-mark-probe';
  final EditSession session = EditSession(
    document: DocumentState(song: chosen.song),
    docId: docId,
  );
  String marksNow() =>
      _marks(session.song.barAt(chosen.sectionId, chosen.barIndex)!.marks);

  final Set<BarMark> original = chosen.bar.marks;
  stdout.writeln('bar_mark.before marks=${marksNow()}');

  // ADD the first sign the bar does NOT already carry, so the edit genuinely changes the bar and
  // the signs that were there have to survive it.
  final List<BarMark> missing = BarMark.values
      .where((BarMark mark) => !original.contains(mark))
      .toList();
  final BarMark? toAdd = missing.isEmpty ? null : missing.first;
  if (toAdd != null) {
    final DocumentState before = session.document;
    final bool applied = session.setBarMark(
      sectionId: chosen.sectionId,
      barIndex: chosen.barIndex,
      mark: toAdd,
      present: true,
    );
    final bool changed = session.document != before;
    final Set<BarMark> after = session.song
        .barAt(chosen.sectionId, chosen.barIndex)!
        .marks;
    final bool everyOriginalKept = original.every(after.contains);
    final bool orderKept = _keptRelativeOrder(original, after);
    stdout.writeln(
      'bar_mark.add sign=${toAdd.name} applied=$applied changed=$changed '
      'after=${marksNow()} type=${session.log.last.type} '
      'wire=${EventCodec.encodeLine(session.log.last)} '
      'every_original_kept=$everyOriginalKept order_kept=$orderKept',
    );
    final bool undone = session.undo();
    final DocumentState restored = session.document;
    stdout.writeln(
      'bar_mark.undo.add undone=$undone restored_equal_before=${restored == before} '
      'song_equal=${restored.song == before.song} marks=${marksNow()}',
    );
  } else {
    stdout.writeln(
      'bar_mark.add skipped reason=the bar already carries every sign',
    );
  }

  // CLEAR one of the signs the bar DID carry, which is the direction where a wrong inverse would
  // silently drop a sign the musician never touched. A bar holding only one sign still exercises
  // the empty-set case, which is a real value the event must be able to carry.
  final BarMark? toClear = original.isEmpty ? null : original.first;
  if (toClear != null) {
    final DocumentState before = session.document;
    final bool applied = session.setBarMark(
      sectionId: chosen.sectionId,
      barIndex: chosen.barIndex,
      mark: toClear,
      present: false,
    );
    final Set<BarMark> after = session.song
        .barAt(chosen.sectionId, chosen.barIndex)!
        .marks;
    final Set<BarMark> others = original
        .where((BarMark m) => m != toClear)
        .toSet();
    final bool everyOtherKept = others.every(after.contains);
    stdout.writeln(
      'bar_mark.clear sign=${toClear.name} applied=$applied '
      'after=${marksNow()} other_signs=${others.length} '
      'every_other_kept=$everyOtherKept',
    );
    final bool undone = session.undo();
    final DocumentState restored = session.document;
    stdout.writeln(
      'bar_mark.undo.clear undone=$undone restored_equal_before=${restored == before} '
      'song_equal=${restored.song == before.song} marks=${marksNow()}',
    );
  } else {
    stdout.writeln(
      'bar_mark.clear skipped reason=the chosen bar carries no sign at all',
    );
  }
}

// PURPOSE: Check that the signs an edit did not name kept their RELATIVE order on the bar, which is
//          what "does not disturb what is already there" means for a page that joins the glyphs in
//          the set's iteration order.
// INPUTS: original — the signs before the edit, in the bar's own order. after — the signs after it.
// OUTPUTS: True when the members of [original] appear in [after] in the same relative order.
// KEYWORDS: order-preservation, page-order, relative-order, glyph-line
bool _keptRelativeOrder(Set<BarMark> original, Set<BarMark> after) {
  final List<BarMark> afterList = after.toList();
  int cursor = 0;
  for (final BarMark mark in original) {
    final int found = afterList.indexOf(mark, cursor);
    if (found < 0) {
      return false;
    }
    cursor = found + 1;
  }
  return true;
}
