// PURPOSE: Assemble the token stream of a decoded iReal music body into the project's Song model,
//          collecting every symbol the model cannot carry into a list of issues instead of
//          aborting the import. One bad symbol must not cost a musician the other thirty bars, so
//          this file's entry point is a total function: no input makes it throw, and a chart it
//          cannot fully represent still produces every bar it could read.
// INPUTS: The decoded music body — what `deobfuscateIrealMusic` returns, with the magic prefix
//         already removed — plus an identity the caller wants the resulting Song to carry. The
//         body does not contain the title, composer, style, key or tempo; those are sibling
//         fields of an export, not notation, and this parser deliberately does not invent them.
// OUTPUTS: An [IRealParseResult]: a Song built from the sections and bars the notation describes,
//          and a list of [IRealParseIssue]s, each holding a message and the character offset it
//          arose at. An empty body yields a song with no sections and no issues. Unrepresentable
//          chords and unrecognised characters are reported, never silently dropped.
// KEYWORDS: ireal, parser, assembler, song-model, cell-model, diagnostics, total-function
//
// THE CELL MODEL. A chord occupies a cell and advances. A space, `p`, `x`, `r` or `n` occupies a
// cell and advances. A COMMA DOES NOTHING AT ALL: it consumes no cell and stacks nothing.
//
// The comma rule is not inferred from prose — it is what the reference implementation does:
//
//     if (!found) {
//         // ignore the comma separator
//         if (text[0] !== ',') arr.push(text[0]);
//         text = text.substr(1);
//     }
//     ...
//     if (token && i < arr.length - 1) { prevObj = obj; obj = this.newToken(out); }
//
// A comma is skipped before it can ever become a token, and every token that survives starts a new
// cell. Its only effect is therefore to REMOVE the empty cell a space would have inserted: `A B`
// puts two chords two cells apart, `A,B` puts them one cell apart, and neither stacks them. The
// format's only stacking construct is the alternate chord in parentheses, which this model carries
// as a nested Chord on one ChordMark rather than as a second placement.
//
// Check the document's cases against that reading. `C7ppF7` gives C7(0) p(1) p(2) F7(3) — four
// cells. `D- D-/C` gives D-(0) and D-/C(2), because the space took cell 1. `A7,p,p,p,` gives
// A7(0) p(1) p(2) p(3), four cells, with the commas contributing nothing. And `sEh,A7,` gives
// Eh(0) and A7(1) — ADJACENT cells.
//
// An earlier version of this file read the comma the other way round, as pulling the next chord
// back onto the cell the previous chord already occupied. That is the reverse of the reference and
// it silently merged two written chords into a single beat, which no test caught because every
// example in the protocol document happens to be consistent with both readings. It was found by
// reading the reference parser rather than by reasoning about the prose.
//
// WHY A BAR THAT RECEIVED ONLY SPACES DISAPPEARS. iReal pads a line to its cell count with runs
// of spaces that belong to no measure, and it writes a genuinely empty measure as `n` (N.C.) or
// `x`. A bar whose only tokens were cell advances is therefore padding by construction, and
// emitting it would add phantom measures to every chart that ends a line unevenly. The rule is
// stated over TOKENS, not over emptiness: a bar survives if it received any token that places or
// describes something — a chord, a mark, an ending, staff text, a repeat or no-chord symbol, an
// unrecognised character — and is dropped when everything it received was a space, a comma, a
// meter or chord-size marker, a system break or a barline. The last two are persistent state or a
// layout hint, so they describe the reading position rather than the bar and must not conjure a
// measure out of padding; an unrecognised character is kept as content precisely because losing a
// measure is worse than keeping an empty one, and the issue names the character either way.
//
// STAFF TEXT KEEPS ITS POSITION NUMBER. `Bar.staffText` is a list of plain strings, and the `*NN`
// prefix of `<*72Solo>` is a written layout instruction rather than part of the words. It is
// stored back as a two-digit prefix (`*72Solo`, `*07Solo`) so that the stored text is exactly the
// text the chart wrote; dropping the number would lose an instruction the musician gave, and
// keeping it without a rule for the leading zero would not round-trip.
//
// A SYSTEM BREAK IS REPORTED RATHER THAN DROPPED. `Y` asks for vertical space before a system.
// The Song model has no field for it, so keeping it would mean inventing one and dropping it
// silently would lose a written layout choice. It becomes an issue — a note, not a defect — with
// the offset of the `Y`, and callers that want only defects can filter issues by message.
//
// SECTION AND BAR IDENTITY. A section id is `sec-<key>-<occurrence>`, where the key is the label
// as written (`A`, `V`, `i`, a custom label, or `implicit` for a body that opens with music and
// no marker) and the occurrence counts how many sections with that key came before. So `sec-A-0`
// is the first A section and `sec-A-1` the second, and inserting a bar inside the first A does
// not rename either. A bar carries no id field in the model, so its stable identity is the
// address `Song.barAt` already takes: the section id plus the bar's zero-based index within that
// section, which is a counter that restarts at every section and therefore does not change when a
// bar is inserted into some other section.
import '../anchored_place.dart';
import '../chord.dart';
import '../layout/layout_style.dart';
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';
import '../song/time_signature.dart';
import 'chord_parser.dart';
import 'tokenizer.dart';

/// One problem met while assembling a decoded music body.
///
/// The offset is carried next to the message, rather than being folded into the message text,
/// because a caller that wants to underline the character in the original chart needs a number,
/// and a caller that wants to log a sentence needs the sentence. Parsing them back apart would be
/// the same mistake the tokenizer avoids for staff text.
class IRealParseIssue {
  /// Creates an issue with [message], which arose at [offset] in the decoded body.
  const IRealParseIssue(this.message, this.offset);

  /// What was wrong, phrased so a log reader can act on it.
  final String message;

  /// Character offset into the decoded body of the symbol the issue is about.
  ///
  /// Never negative: it is a real index into the string that was parsed, because the tokenizer
  /// consumes every character exactly once and the parser only ever passes a token's own offset.
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is IRealParseIssue &&
      other.message == message &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(message, offset);

  @override
  String toString() => 'IRealParseIssue($offset: $message)';
}

/// The outcome of parsing a decoded music body: what could be built, and what could not.
///
/// Both halves are always present. A result with issues still carries a song, because a partial
/// chart is more useful than none, and a result with no issues still carries the empty list
/// rather than null, so a caller never has to branch on the absence of a list.
class IRealParseResult {
  /// Creates a result pairing [song] with the [issues] met while building it.
  const IRealParseResult({
    required this.song,
    this.issues = const <IRealParseIssue>[],
  });

  /// The song assembled from the notation. Never null; an unparseable body yields an empty song.
  final Song song;

  /// Everything that could not be represented, in the order it was met. Empty when the body was
  /// read completely.
  final List<IRealParseIssue> issues;

  @override
  String toString() => 'IRealParseResult($song, ${issues.length} issue(s))';
}

// PURPOSE: Turn a decoded iReal music body into a Song, reporting rather than throwing on
//          anything the model cannot hold, so a malformed symbol costs one chord instead of the
//          whole chart.
// INPUTS: decodedNotation — the music body decoded by `deobfuscateIrealMusic`, without the ten
//         character `irealMusicPrefix` and without the field list around it. It may be empty, and
//         it may contain characters the grammar does not define. documentId — the identifier the
//         resulting Song should carry, or the empty string when the caller has not assigned one.
// OUTPUTS: An [IRealParseResult]. The song's sections and bars describe the notation; its title,
//          composer, style, key and tempo keep their defaults, because the music body does not
//          carry them. The issues list is empty for a body that parsed completely, and otherwise
//          holds one entry per unrepresentable chord, unrecognised character or dropped layout
//          hint, in reading order.
//
//          Behaviour at the edges: an empty body yields no sections and no issues; a body of only
//          spaces yields no sections, because padding that belongs to no measure is not a
//          measure; a body with no section marker puts its bars in a single implicit section; and
//          a bar that was never closed by a barline is still emitted, with a single closing
//          barline, because iReal omits the final barline of a chart.
// KEYWORDS: parse, assemble, ireal, song-builder, total-function, diagnostics, cell-model
/// Parses decoded iReal notation into a Song, collecting problems as issues.
IRealParseResult parseIRealNotation(
  String decodedNotation, {
  String documentId = '',
}) {
  final List<IRealParseIssue> issues = <IRealParseIssue>[];
  final _ChartAssembler assembler = _ChartAssembler(issues);
  for (final IRealToken token in tokenizeIReal(decodedNotation)) {
    assembler.accept(token);
  }
  return IRealParseResult(
    song: Song(id: documentId, title: '', sections: assembler.finish()),
    issues: issues,
  );
}

/// A section under construction, before its bars are known to be complete.
class _SectionBuilder {
  _SectionBuilder({required this.id, required this.label});

  final String id;
  final SectionLabel label;
  final List<Bar> bars = <Bar>[];
}

// PURPOSE: Convert one beat of the SOURCE's grid into the x a chord is written at. This is the only
//          place in the application where a beat becomes a coordinate, and it exists because an
//          iReal chart REALLY HAS a grid: its bars and its cells are in the source, so the importer
//          is the one component allowed to translate them.
// INPUTS: beat — the zero-based cell the source wrote the chord on.
// OUTPUTS: The horizontal offset from the bar's left edge, in bar-local logical pixels, that the
//          chord is stored at. Cell 0 is written where the engraver starts a bar's content
//          (`LayoutStyle.barPadding`), and each further cell is one chord slot further along, the
//          slot being the narrowest one the engraver ever gives a chord (`LayoutStyle.minCellWidth`).
//
//          WHY THE SLOT IS THE MINIMUM AND NOT A MEASURED WIDTH. A chord's own text decides how much
//          room it needs, and that measurement needs a font, which this parser does not have and must
//          not have: a chart imported on a device with a different font would store different x
//          values for the same `.irealb` text, and the same source would produce two different
//          documents. A fixed slot stores one chart. The cost is named rather than hidden: a bar of
//          wide chord symbols is engraved slightly tighter than the old cell-per-measured-width
//          layout drew it, and the bar itself is narrower because its width follows its content.
//
//          WHY THIS IS A GRID THE IMPORTER OWNS AND THE MODEL DOES NOT. iReal's own notation IS a
//          grid: a chord sits in cell k of a bar and the format says so. This function is the one
//          place that grid becomes a coordinate, and it runs ONCE, on the way in — nothing reads it
//          back, and no part of the model or the engraving inverts it. The adapter that used to
//          invert this arithmetic for the whole application was deleted with its last caller, so
//          the numbers now agree with nothing but the source format, which is what they are FOR.
// KEYWORDS: ireal, beat-to-coordinate, grid-conversion, import, cell-pitch, no-quantisation
/// Returns the x a chord on [beat] of an imported bar is written at.
double irealChordX(int beat) =>
    const LayoutStyle().barPadding + beat * const LayoutStyle().minCellWidth;

/// A bar under construction, holding the same facts a [Bar] does plus the cell cursor the
/// assembler needs while the bar is still being read.
class _BarBuilder {
  _BarBuilder({required this.timeSignature});

  TimeSignature timeSignature;
  Barline openingBarline = Barline.single;
  Barline closingBarline = Barline.single;

  /// The chord symbols read so far, each with the BEAT the source wrote it on.
  ///
  /// The beat is the SOURCE's own grid and it stops here: the bar is not yet built and does not know
  /// its section or its index, which an [AnchoredPlace] needs, so the cell is carried until [build]
  /// can turn it into a coordinate. This is the only place in the application where a beat survives
  /// the change that removed the grid, and it survives because an iReal chart really has one.
  final List<({int cell, Chord chord, ChordSize size})> chords =
      <({int cell, Chord chord, ChordSize size})>[];
  final Set<BarMark> marks = <BarMark>{};
  final List<String> staffText = <String>[];
  Volta? volta;
  RepeatPrevious repeatPrevious = RepeatPrevious.none;
  bool slashRepeat = false;
  bool noChord = false;

  /// Whether any token arrived that places or describes something in this bar. A bar in which
  /// this stayed false received only padding and is not emitted.
  bool receivedContent = false;

  /// The cell the next symbol will occupy, zero-based.
  int cell = 0;

  /// Occupies the current cell with a cell-consuming symbol and moves past it.
  void advanceCell() {
    cell++;
  }

  /// Freezes this builder into an immutable [Bar] placed at ([sectionId], [barIndex]).
  ///
  /// The two arguments are what turn every beat into a place: a chord at cell k is written k
  /// cell-pitches from the bar's left edge, and from then on the chart carries a coordinate and no
  /// grid. See [irealChordX] for the number and why it is this one.
  Bar build({required String sectionId, required int barIndex}) => Bar(
    timeSignature: timeSignature,
    chords: List<ChordMark>.unmodifiable(<ChordMark>[
      for (final (:int cell, :Chord chord, :ChordSize size) in chords)
        ChordMark(
          place: AnchoredPlace(
            anchor: EventAnchor(sectionId: sectionId, bar: barIndex),
            offsetX: irealChordX(cell),
          ),
          chord: chord,
          size: size,
        ),
    ]),
    openingBarline: openingBarline,
    closingBarline: closingBarline,
    volta: volta,
    repeatPrevious: repeatPrevious,
    slashRepeat: slashRepeat,
    noChord: noChord,
    marks: Set<BarMark>.unmodifiable(marks),
    staffText: List<String>.unmodifiable(staffText),
  );
}

/// Accumulates bars into sections as tokens arrive.
///
/// It owns the state the notation makes persistent across bar boundaries — the meter and the
/// chord size — because that state belongs to the reading position rather than to any one bar,
/// and keeping it on a bar would force every consumer of the model to search backwards for the
/// last change.
class _ChartAssembler {
  _ChartAssembler(this._issues);

  final List<IRealParseIssue> _issues;
  final List<Section> _sections = <Section>[];
  final Map<String, int> _sectionOccurrences = <String, int>{};
  _SectionBuilder? _openSection;
  _BarBuilder? _openBar;
  TimeSignature _timeSignature = TimeSignature.fourFour;
  ChordSize _chordSize = ChordSize.normal;

  /// Reads one token, updating the section and bar under construction.
  void accept(IRealToken token) {
    switch (token) {
      case SectionToken():
        _onSection(token);
      case BarlineToken():
        if (token.role == BarlineRole.opening) {
          _onOpeningBarline(token);
        } else {
          final _BarBuilder bar = _bar();
          bar.closingBarline = token.kind;
          _closeBar();
        }
      case TimeSignatureToken():
        _timeSignature = token.value;
        // A bar that already holds music keeps the meter it was begun in: the model gives a bar
        // one meter, so honouring the change by rewriting it would misdate every chord already
        // read. The change is persistent, so the next bar starts in the new meter either way.
        final _BarBuilder? open = _openBar;
        if (open != null && !open.receivedContent) {
          open.timeSignature = token.value;
        }
      case ChordSizeToken():
        _chordSize = token.size;
      case EndingToken():
        final _BarBuilder bar = _bar();
        bar.volta = Volta(token.number);
        bar.receivedContent = true;
      case RepeatPreviousToken():
        final _BarBuilder bar = _bar();
        bar.repeatPrevious = token.kind;
        bar.receivedContent = true;
        bar.advanceCell();
      case SlashRepeatToken():
        final _BarBuilder bar = _bar();
        bar.slashRepeat = true;
        bar.receivedContent = true;
        bar.advanceCell();
      case NoChordToken():
        final _BarBuilder bar = _bar();
        bar.noChord = true;
        bar.receivedContent = true;
        bar.advanceCell();
      case MarkToken():
        final _BarBuilder bar = _bar();
        bar.marks.add(token.mark);
        bar.receivedContent = true;
      case StaffTextToken():
        final _BarBuilder bar = _bar();
        bar.staffText.add(_staffTextOf(token));
        bar.receivedContent = true;
      case SystemBreakToken():
        // Reported, not stored: there is no field for it. See the note at the top of this file.
        _issues.add(
          IRealParseIssue(
            'System break of ${token.amount} line(s) is a layout hint the bar model '
            'cannot carry; it was not stored.',
            token.offset,
          ),
        );
      case CellToken():
        _bar().advanceCell();
      case ChordSeparatorToken():
        // Deliberately nothing. The reference implementation drops a comma before it can become a
        // token, so it neither consumes a cell nor joins two chords: the cell pointer simply stays
        // where the preceding chord or space left it, and the next chord takes that next cell.
        // Treating this as a no-op is what makes `A,B` two chords one cell apart rather than two
        // chords on one beat.
        break;
      case ChordToken():
        _onChord(token);
      case UnknownToken():
        // The bar survives so that the bars after a stray character keep their addresses; the
        // character itself is reported rather than guessed at.
        _bar().receivedContent = true;
        _issues.add(
          IRealParseIssue(
            'Unrecognised character "${token.character}".',
            token.offset,
          ),
        );
    }
  }

  /// Closes the last bar and the last section and returns every section that has bars.
  List<Section> finish() {
    _closeBar();
    _closeSection();
    return List<Section>.unmodifiable(_sections);
  }

  /// Starts a section, giving the open bar to whichever side of the boundary it belongs on.
  void _onSection(SectionToken token) {
    final _BarBuilder? open = _openBar;
    if (open != null && open.receivedContent) {
      // The bar already holds music, so it belongs to the section that was current.
      _closeBar();
    }
    // Otherwise the bar is empty — typically the one an opening barline just created — and it is
    // the first bar of the new section, which is what makes `[*iB-` keep its `[`.
    _closeSection();
    final SectionLabel label = _labelOf(token.label);
    final String key = _sectionKey(label);
    final int occurrence = _sectionOccurrences[key] ?? 0;
    _sectionOccurrences[key] = occurrence + 1;
    _openSection = _SectionBuilder(id: 'sec-$key-$occurrence', label: label);
  }

  /// Reads an opening barline onto the bar about to be built.
  void _onOpeningBarline(BarlineToken token) {
    final _BarBuilder? open = _openBar;
    if (open != null && open.receivedContent) {
      // An opening barline decorates the NEXT bar. A bar that already holds music is closed
      // first, with the closing barline last written for it, because the alternatives are losing
      // the bar or losing the bracket.
      _closeBar();
    }
    _bar().openingBarline = token.kind;
  }

  /// Places a chord on the cell in force and moves past it.
  ///
  /// The step is always zero. Under the reference cell model no two chords can share a cell — a
  /// comma removes an empty cell rather than joining two chords — so a non-zero step would only ever
  /// be produced by a bug. What is recorded here is the SOURCE's cell, not a position in this
  /// project's model: [build] turns it into the x the chord is stored at, in one place, so that the
  /// importer is the only component that has to know a beat at all.
  void _onChord(ChordToken token) {
    final _BarBuilder bar = _bar();
    bar.receivedContent = true;
    final int cell = bar.cell;

    final Chord? chord = parseIRealChord(token.text);
    if (chord == null) {
      _issues.add(
        IRealParseIssue(
          'The chord "${token.text}" cannot be represented; it was skipped.',
          token.offset,
        ),
      );
    } else {
      bar.chords.add((cell: cell, chord: chord, size: _chordSize));
    }

    // The written position is consumed even when the symbol was skipped, so a later chord keeps
    // the cell it was written on instead of sliding left into the gap.
    bar.advanceCell();
  }

  /// Emits the open bar into the open section unless it received only padding.
  void _closeBar() {
    final _BarBuilder? bar = _openBar;
    _openBar = null;
    if (bar == null || !bar.receivedContent) {
      return;
    }
    final _SectionBuilder section = _section();
    section.bars.add(
      bar.build(sectionId: section.id, barIndex: section.bars.length),
    );
  }

  /// Emits the open section unless it ended up with no bars.
  void _closeSection() {
    final _SectionBuilder? section = _openSection;
    if (section == null) {
      return;
    }
    _openSection = null;
    if (section.bars.isNotEmpty) {
      _sections.add(
        Section(
          id: section.id,
          label: section.label,
          bars: List<Bar>.unmodifiable(section.bars),
        ),
      );
    }
  }

  /// Returns the bar under construction, creating it — in the meter in force — when a barline
  /// or a section marker left none open.
  _BarBuilder _bar() {
    final _BarBuilder? open = _openBar;
    if (open != null) {
      return open;
    }
    final _BarBuilder created = _BarBuilder(timeSignature: _timeSignature);
    _openBar = created;
    return created;
  }

  /// Returns the section bars are being added to, creating an implicit one for a body that
  /// starts with music and carries no section marker.
  _SectionBuilder _section() {
    final _SectionBuilder? open = _openSection;
    if (open != null) {
      return open;
    }
    const String key = 'implicit';
    final int occurrence = _sectionOccurrences[key] ?? 0;
    _sectionOccurrences[key] = occurrence + 1;
    final _SectionBuilder created = _SectionBuilder(
      id: 'sec-$key-$occurrence',
      label: const SectionLabel.custom(''),
    );
    _openSection = created;
    return created;
  }

  /// Classifies a one-character section label.
  SectionLabel _labelOf(String label) {
    if (label == 'i') {
      return const SectionLabel.intro();
    }
    if (label == 'V') {
      return const SectionLabel.verse();
    }
    if (label.length == 1 && _isUppercaseLetter(label)) {
      return SectionLabel.letter(label);
    }
    return SectionLabel.custom(label);
  }

  /// The stable text a section id is built from, so that the id does not depend on position.
  String _sectionKey(SectionLabel label) {
    switch (label.kind) {
      case SectionKind.intro:
        return 'i';
      case SectionKind.verse:
        return 'V';
      case SectionKind.letter:
      case SectionKind.custom:
        return label.text.isEmpty ? 'untitled' : label.text;
    }
  }

  /// Restores the `*NN` vertical-position prefix the tokenizer separated off.
  ///
  /// Padded to two digits because the prefix is exactly two characters in the notation; a bare
  /// `*7Solo` would not be the text the chart wrote, and re-parsing it would read position 7 out
  /// of `*7S` only by accident.
  String _staffTextOf(StaffTextToken token) {
    final int? position = token.verticalPosition;
    if (position == null) {
      return token.text;
    }
    return '*${position.toString().padLeft(2, '0')}${token.text}';
  }
}

/// Whether [character] is an ASCII uppercase letter, the only kind a rehearsal letter is.
bool _isUppercaseLetter(String character) {
  final int code = character.codeUnitAt(0);
  return code >= 0x41 && code <= 0x5A;
}
