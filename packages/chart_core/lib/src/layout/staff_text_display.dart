// PURPOSE: Turn a stored `Bar.staffText` entry into the words a reader should see. The model keeps
//          the `*NN` vertical-position prefix and the exporter's padding so that the stored text is
//          exactly what the chart wrote; a reader must not be shown a layout instruction as if it
//          were part of a phrase. This file is the ONE place that decides what the display form is,
//          so the layout engine — which measures the words and reserves room for them — and the
//          painter, which draws the box the engine published, cannot disagree about the string they
//          are sizing and rendering.
// INPUTS: A stored staff-text string from `Bar.staffText`, exactly as the model carries it: with or
//         without a `*NN` prefix, with or without surrounding whitespace, and possibly empty.
// OUTPUTS: The display string. Never null, never a throw. The prefix and any leading and trailing
//          whitespace are removed; the stored value itself is never modified, because display is a
//          projection and not an edit, and nothing in this file has side effects.
// KEYWORDS: staff-text, display-form, prefix-stripping, layout-render-agreement, pure-function
//
// WHAT "THE DISPLAY TEXT" IS, AND WHY EACH PART.
//
// `*NN` — REMOVED. `parser.dart` records that the `*NN` prefix of `<*72Solo>` is a written layout
// instruction (a vertical position) rather than part of the words, and stores it back verbatim so
// that the stored text is exactly what the chart wrote and a re-parse cannot read a position out of
// a word by accident. That decision stands. It does mean, however, that the stored string is not the
// string to print: `*69Куплет` must read `Куплет`. The prefix is removed wherever it appears as `*`
// followed by digits at the very start.
//
// A DIFFERENT DIGIT COUNT — REMOVED TOO. The tokenizer recognises exactly two digits and the parser
// writes them back padded to two, so on the imported path the prefix is always two digits (`*69`,
// `*07`). The display rule accepts ONE OR MORE digits rather than exactly two, because the model
// lets a `Bar` built by hand or read from a future format carry `*7` or `*007`, and a prefix whose
// digit count is not two would otherwise reach the page. `*` not followed by a digit is NOT a
// prefix and stays, because the format writes words as well as digits into that run.
//
// LEADING AND TRAILING WHITESPACE — REMOVED. iReal pads the text inside `<>`, and the owner's own
// corpus carries runs such as `*69          проигрыш` and `  8+8x`. Those spaces are exporter
// padding rather than a written indent: the words' horizontal home is the cell the `<...>` occupies
// and their vertical home is the `*NN`, so the spaces add nothing the musician asked for and arrive
// on the page as a phrase starting in the middle of its own bar. Trailing spaces (`*72Припев `) are
// invisible but are still measured, so removing them keeps the width the engine reserves equal to
// the width the reader can actually see. The trim happens AFTER the prefix is removed, so the spaces
// the prefix exposed are taken with it.
//
// AN ENTRY THAT IS ONLY A PREFIX DISPLAYS AS EMPTY. `*69` with no words carries a position and
// nothing to say, so it draws nothing and reserves nothing. The engine skips an empty display line
// rather than placing a zero-width one, and the painter draws nothing for an empty string, so no
// separate "is there anything to say" test is needed anywhere else.
//
// THE OWNER'S OWN TEXTS ARE WHY THIS MATTERS, named so that the rule is not read as housekeeping:
// the book this renderer is judged against carries `*69Куплет` (verse), `*72Припев` (chorus),
// `*74         проигрыш` (instrumental), `*69      х4` (four times), `*72кода` (coda) and
// `*36брейк  бараьанов 4 т`. Three of those six carry padding and one carries a position prefix
// that would print as `74` in front of the words.

/// The written position prefix at the start of a stored staff text, `*` plus one or more digits.
///
/// Anchored at the start on purpose: `x*69` is a phrase that happens to contain the characters, not
/// an instruction, and only a prefix at the very beginning is one. The run is one-or-more rather
/// than exactly-two so that a hand-built or future chart's `*7`/`*007` is also understood.
final RegExp _positionPrefix = RegExp(r'^\*[0-9]+');

// PURPOSE: Report the words a stored staff-text entry should show, with the written position and
//          the exporter's padding removed, so a layout instruction never reaches the page as if it
//          were part of a phrase.
// INPUTS: stored — one `Bar.staffText` entry exactly as the model carries it; may be empty, may be
//         whitespace alone, may be a bare `*NN` prefix with no words.
// OUTPUTS: The words to draw. The empty string for an entry that carries only a position prefix or
//          only whitespace, which every caller treats as nothing to draw; otherwise the stored text
//          with its leading `*` plus digits and its surrounding whitespace removed, and nothing else
//          changed — inner spacing, capitalisation and punctuation are the musician's.
//          NEVER THROWS and never returns null, on any string.
// KEYWORDS: staff-text, display-form, prefix-strip, trim, total-function, layout-render-agreement
/// Returns the words a stored staff-text entry should show.
String displayStaffText(String stored) =>
    stored.replaceFirst(_positionPrefix, '').trim();
