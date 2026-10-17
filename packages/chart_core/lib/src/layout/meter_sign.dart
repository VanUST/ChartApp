// PURPOSE: Decide WHERE the meter is drawn on a page, which is the whole of owner decision D22's
//          rendering half: a chart that changes meter must SAY SO at the bar where it changes, and
//          a chart that spends a whole line in an unusual meter must say so again at the start of
//          that line, where a musician's eye returns. The rule lives here rather than in the
//          painter so that the page, a probe and a test all read the same decision instead of three
//          copies of it drifting apart.
// INPUTS: A song, a laid-out page, and — for the rule itself — a bar's meter, the meter of the bar
//         before it in reading order, and whether the bar opens a system.
// OUTPUTS: Booleans and the `sectionId#barIndex` keys of the bars a page signs, with the text each
//          sign carries. Nothing here draws: a caller decides what a sign looks like.
// KEYWORDS: meter, time-signature, meter-sign, engraving-rule, change-bar, system-start,
//           byte-identity, pure-function
//
// THE RULE, WRITTEN OUT, BECAUSE IT IS A DECISION AND NOT AN IMPLEMENTATION DETAIL:
//
//   1. A bar whose meter differs from the bar BEFORE it in reading order is signed. That is the bar
//      where the meter CHANGES, and the one place a musician is looking for the sign.
//   2. A bar that OPENS A SYSTEM is signed when its meter is not 4/4. 4/4 is the meter a musician
//      assumes when nothing is written — it is the one `Bar.timeSignature` defaults to, and the
//      meter of 1032 of the owner's 1045 written bars — so writing it at the start of every line
//      would be a column of identical symbols saying nothing. This rule is also why a chart that
//      never changes meter renders BYTE-IDENTICALLY to the page the painter produced before a sign
//      existed: every bar of such a chart is 4/4, neither rule matches, and nothing is drawn.
//   3. The chart's FIRST bar is treated as opening a system, so a chart that opens in 3/4 or 15/8
//      is signed from its first bar; one that opens in 4/4 is not. Since the chart's own header line
//      states the opening meter on the page where the music begins, the first bar of a chart that
//      HAS a header is not signed at all — the statement has been made one line above it, and
//      printing it twice would be one fact in two places. Header and no header therefore differ in
//      exactly one bar of a chart that does not open in 4/4, and the painter and this file read that
//      fact from the page rather than from a second rule.
//
// WHAT THE RULE DELIBERATELY DOES NOT DO. It does not sign every bar of a chart that is 3/4
// throughout, except at the start of each system — which is the convention a jazz chart follows,
// and the reason a UNIFORM NON-4/4 chart is the one case where the page changes even though the
// meter never does. Returning to 4/4 mid-system IS signed, by rule 1: a meter change is written
// whichever way it goes.
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';
import '../song/time_signature.dart';
import 'page_layout.dart';

/// The meter a musician assumes when the page writes nothing, and therefore the one the sign is
/// omitted for at the start of every system.
///
/// 4/4, and deliberately nothing else: 2/4, 3/4 and 6/8 are unusual enough in this repertoire to be
/// worth a sign, and this model has no cut-time value.
const TimeSignature assumedMeter = TimeSignature.fourFour;

// PURPOSE: Answer whether one bar's meter must be DRAWN, from the three things that decide it.
// INPUTS: meter — the bar's own meter. preceding — the meter of the bar before it in reading order,
//         or null when this is the chart's first bar. opensSystem — whether this bar begins a line.
//         headerStatesOpeningMeter — whether the chart's own header line has already printed this
//         bar's meter as the meter the music opens in.
// OUTPUTS: True when the sign is drawn; false otherwise, and false for EVERY bar of a 4/4 chart,
//          which is what keeps such a page byte-identical to the one drawn before signs existed.
//          Never throws: a bar is signed or it is not, and there is no third answer.
//
//          WHY THE HEADER SUPPRESSES THE FIRST BAR'S SIGN, AND WHY THAT IS A RULE RATHER THAN A
//          DUPLICATE TOLERANCE. The chart's first bar is the one place where the meter has already
//          been stated — the header says `C major · 3/4` one line above it — and printing `3/4`
//          again in the bar's own corner would state the same fact twice within a centimetre. A
//          printed chart signs the opening meter once, where the music begins; the header IS that
//          statement now, so the bar does not repeat it. Every LATER system keeps its sign, because
//          the header is on the first page only and a reader returning to the music needs the meter
//          where the line begins — which is the other half of the convention the rule already
//          followed.
//
//          THE PARAMETER DEFAULTS TO FALSE, and both call sites in this tree pass it from the page
//          they are drawing: the rule belongs here, but whether a header has already spoken is a
//          fact about the PAGE, and a function given only a bar cannot know it. A caller that
//          forgets it draws the duplicate in the one case it can occur — a chart that does not open
//          in 4/4 — and draws nothing wrongly anywhere else.
// KEYWORDS: meter-sign, decision, change, system-start, 4/4-default, header-suppression,
//           total-function
/// Returns whether the meter of a bar is engraved on the page.
bool showsMeterSign({
  required TimeSignature meter,
  required TimeSignature? preceding,
  required bool opensSystem,
  bool headerStatesOpeningMeter = false,
}) {
  // The chart's first bar has nothing before it to change from, so it is answered by the
  // system-start rule: signed unless the meter is the assumed one, exactly like every other system
  // start. A 4/4 opening therefore draws nothing — and a 3/4 opening draws nothing either when the
  // header has just said 3/4, because the statement has been made.
  if (preceding == null) {
    return !headerStatesOpeningMeter && meter != assumedMeter;
  }
  // A change is signed whichever way it goes: into 3/4 and back out of it are both things the
  // musician has to read at the bar they happen on.
  if (meter != preceding) {
    return true;
  }
  return opensSystem && meter != assumedMeter;
}

// PURPOSE: Read the meter of the bar that comes BEFORE ([sectionId], [barIndex]) in reading order,
//          which is what [showsMeterSign] compares against.
// INPUTS: song — the chart. sectionId and barIndex — the address in the model's own terms, with the
//         bar index zero-based inside its section.
// OUTPUTS: The previous bar's meter, or null when the address is the chart's first bar OR names no
//          bar in the song. The two cases deliberately share one value: a caller asking about a bar
//          the song does not contain is asking about nothing.
//
//          WHY IT WALKS THE WHOLE SONG. The painter draws one page at a time and therefore has no
//          earlier page to look back at, so a change that lands on the first bar of a NEW PAGE
//          would go unsigned if the comparison read only the preceding bar of the same page. A
//          sign silently missing at a page turn is precisely the wrongness the sign exists to
//          remove, so the predecessor is read from the song, which survives pagination.
// KEYWORDS: preceding-meter, reading-order, page-turn, cross-page, null-safe
/// Returns the meter of the bar before this address in reading order, or null.
TimeSignature? precedingMeter(Song song, String sectionId, int barIndex) {
  TimeSignature? previous;
  for (final Section section in song.sections) {
    for (int index = 0; index < section.bars.length; index++) {
      if (section.id == sectionId && index == barIndex) {
        return previous;
      }
      previous = section.bars[index].timeSignature;
    }
  }
  return null;
}

// PURPOSE: Apply the rule to a whole laid-out page, so a probe, a test or another renderer can ask
//          what a page signs without rasterising it and without copying the rule.
// INPUTS: song — the chart the page was laid out from. page — the page.
// OUTPUTS: One entry per signed bar, keyed `sectionId#barIndex`, whose value is the meter's text
//          (`3/4`, `15/8`) exactly as the page draws it. A bar the song does not contain — a page
//          and a song from different states — is skipped rather than guessed at. An empty map means
//          the page shows no meter at all, which is every 4/4 chart and every chart whose opening
//          meter the page's own header states.
//
//          THE HEADER'S PRESENCE IS READ FROM THE PAGE, not passed in, because it is the page that
//          publishes it: `page.header != null` means this page has already printed the opening meter
//          one line above the first bar, and the first bar therefore does not repeat it. That keeps
//          this function and `ChartPainter` answering the same question from the same fact instead
//          of each deciding when a header exists.
// KEYWORDS: page-signs, probe-support, painter-contract, reading-order, header-suppression
/// Returns the meter signs a page shows, keyed by bar address.
Map<String, String> meterSignsOnPage(Song song, PageLayout page) {
  final Map<String, String> signs = <String, String>{};
  for (final PlacedSystem system in page.systems) {
    for (int index = 0; index < system.bars.length; index++) {
      final PlacedBar placed = system.bars[index];
      final Bar? bar = song.barAt(placed.sectionId, placed.barIndex);
      if (bar == null) {
        continue;
      }
      final TimeSignature meter = bar.timeSignature;
      if (showsMeterSign(
        meter: meter,
        preceding: precedingMeter(song, placed.sectionId, placed.barIndex),
        opensSystem: index == 0,
        headerStatesOpeningMeter: page.header != null,
      )) {
        signs['${placed.sectionId}#${placed.barIndex}'] = meter.toString();
      }
    }
  }
  return signs;
}
