// PURPOSE: Derive the order a chart is actually played in — the written bars unrolled through
//          repeat barlines, alternative-ending brackets and the `%` repeat-previous symbol — as a
//          pure function of the written form, so that a playhead, a printed order and any future
//          exporter read one answer instead of each re-deciding what a repeat means.
// INPUTS: A Song. Nothing else: no configuration, no clock, no device, no dependency.
// OUTPUTS: A [PlayOrder] holding one [PlayedBar] per bar the musician plays, in order, each naming
//          the written bar it came from, the written bar whose music sounds, and the pass it
//          belongs to; the repeat passages the song contains with their pass counts; and the
//          structural problems the derivation had to decide around. A song of zero bars yields an
//          empty order rather than an error.
// KEYWORDS: play-order, performance-order, repeat, volta, ending, repeat-previous, percent-bar,
//           derivation, written-form, playhead, pure-function, ambiguity-decisions
//
// THE RULES THIS FILE DECIDES.
//
// The written model deliberately stores no performance order (A13), and it deliberately stores no
// repeat COUNT: the iReal `repeats` field is not part of a Song. That absence is the source of
// most of the decisions below, and every one of them is visible in the returned value rather than
// left for the reader.
//
// R1. A repeat is a repeatEnd barline closed by the nearest still-open repeatStart barline before
//     it, matched with a stack, so nesting works: an inner passage expands in full on each pass of
//     the outer one, which is the reading a musician applies to nested repeat signs. A repeatEnd
//     with no open repeatStart is an ordinary barline and is reported. A repeatStart with no
//     repeatEnd repeats nothing and is reported: an unmatched start does not say how far back to
//     jump, and repeating to the end of the song would invent a passage the chart never wrote.
//
// R2. Passes. The model stores no count, so a passage is played TWICE unless a numbered bracket
//     demands more: the pass count is the highest numbered bracket in the passage or in the
//     brackets that follow it, floored at two. [RepeatPassage.passCountBasis] says which of the
//     two happened, so a caller that wants to warn about an assumed count can see it. A lone
//     first-ending bracket does not reduce the count below two — a bracket that says "first time"
//     implies a second time, and the second pass simply takes whatever follows the closing barline.
//
// R3. Brackets. A numbered bracket is selected by pass: a bar whose bracket number is n is played
//     on pass n only, whether it sits before the closing barline or in the bracketed run after it.
//     A bar written with no bracket of its own inherits the bracket of the last bracketed bar
//     before it INSIDE the same passage, which is what puts the repeatEnd bar into the first ending
//     rather than playing it on every pass; the inheritance stops at the closing barline, so it
//     cannot leak into what follows. An UNNUMBERED bracket (Volta(0)) cannot select a pass, so it is
//     played on every pass it is reached on. A bracket that no repeat passage can resolve is
//     reported and otherwise ignored.
//
// R4. `%` — the repeat-previous symbol, written `x` (one bar) or `r` (two bars). It names WRITTEN
//     bars, not played ones: `x` sounds the bar one back on the page, and when that bar is itself
//     a `%` the chain is followed back to the first bar that writes music. A `%` at the very start
//     of the song has nothing to repeat: the position is still played — the bar is written into the
//     chart — its source is itself, and the anomaly is reported. `r` yields TWO played positions,
//     because it is two bars of music; both name the same written bar (that is where the symbol is
//     drawn) and their sources are the two bars it refers to. References always point backwards,
//     so the chain terminates and cannot cycle. `p`, the slash repeat, repeats the previous CHORD
//     inside the same bar and therefore changes what sounds in a bar, never which bar is played;
//     it is deliberately not a play-order concern here.
//
// R5. Navigation — `D.C. al Coda`, `D.S. al Fine`, coda and fine — is preserved verbatim in
//     `Bar.staffText` and is NOT interpreted by this function. A13 records why: the readings differ
//     between implementations and there is no corpus to check against. A staff text that says "go
//     to the coda" therefore does not change this order, and a caller that assumes it does would be
//     wrong. This is the largest known gap in the derivation, and it is named rather than hidden.
//
// R6. Empty inputs are ordinary. A song of zero sections or zero bars plays nothing and reports
//     nothing; a section of zero bars contributes nothing and is not reported either, because an
//     empty section is a normal state while a chart is being edited, not a structural defect.
//
// R7. A passage may cross a section boundary. Sections are rehearsal labels on a linear written
//     stream, not walls, so the match and the `%` chain both run across them; a passage that does
//     cross is flagged with [RepeatPassage.crossesSection] because it is unusual enough to be worth
//     seeing rather than inferring.
import 'bar.dart';
import 'section.dart';
import 'song.dart';

/// A place in the written chart: the section it belongs to and its zero-based index there.
///
/// This is the address `Song.barAt` resolves and the address an annotation anchor holds, named as
/// a value so that a played position can point at a written bar without carrying the bar itself.
class WrittenBarAddress {
  /// Creates the address of bar [barIndex] in section [sectionId].
  const WrittenBarAddress({required this.sectionId, required this.barIndex});

  /// The id of the section the bar belongs to.
  final String sectionId;

  /// The zero-based index of the bar within its section.
  final int barIndex;

  @override
  bool operator ==(Object other) =>
      other is WrittenBarAddress &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex;

  @override
  int get hashCode => Object.hash(sectionId, barIndex);

  @override
  String toString() => '$sectionId[$barIndex]';
}

/// One passage a played bar is inside, with the pass being taken through it.
class PlayedPass {
  /// Creates the record of a played bar being on [pass] of the passage at [repeatStart].
  const PlayedPass({
    required this.repeatStart,
    required this.pass,
    required this.passCount,
  });

  /// The repeat-start bar of the passage.
  final WrittenBarAddress repeatStart;

  /// Which pass through that passage is being played, one-based.
  final int pass;

  /// How many passes that passage has.
  final int passCount;

  @override
  bool operator ==(Object other) =>
      other is PlayedPass &&
      other.repeatStart == repeatStart &&
      other.pass == pass &&
      other.passCount == passCount;

  @override
  int get hashCode => Object.hash(repeatStart, pass, passCount);

  @override
  String toString() => 'PlayedPass($repeatStart, $pass/$passCount)';
}

/// One bar of the performance order: a place on the page and the music that sounds there.
class PlayedBar {
  /// Creates the played position at [position] with its written and sounding addresses and the
  /// passages it is inside, outermost first.
  PlayedBar({
    required this.position,
    required this.written,
    required this.source,
    required List<PlayedPass> passes,
  }) : passes = List<PlayedPass>.unmodifiable(passes);

  /// Zero-based index of this played bar in the order, counting from the first bar played.
  final int position;

  /// The bar as written at this point of the page — the bar a playhead highlights.
  ///
  /// A `%` bar is named here even though its music comes from elsewhere, because the symbol is
  /// what the musician is looking at.
  final WrittenBarAddress written;

  /// The written bar whose music sounds at this position.
  ///
  /// Equal to [written] unless the bar is a repeat-previous symbol, in which case it names the bar
  /// the symbol refers to after any chain of `%` bars has been followed back.
  final WrittenBarAddress source;

  /// Every passage this position lies inside, outermost first, and empty when it lies inside none.
  ///
  /// One entry per enclosing repeat, so a position inside a repeat nested in another repeat records
  /// both: the outer passage's pass and the inner passage's pass are both answers to "which pass
  /// is this", and neither alone is the whole answer.
  final List<PlayedPass> passes;

  /// Whether this position lies inside a repeated passage.
  bool get isInRepeat => passes.isNotEmpty;

  /// The repeat-start bar of the INNERMOST passage this position is inside, or null.
  WrittenBarAddress? get repeatStart =>
      passes.isEmpty ? null : passes.last.repeatStart;

  /// Which pass through the innermost passage this position is, or 1 outside every passage.
  int get pass => passes.isEmpty ? 1 : passes.last.pass;

  /// How many passes the innermost passage has, or 1 outside every passage.
  int get passCount => passes.isEmpty ? 1 : passes.last.passCount;

  /// Whether the music at this position comes from another written bar.
  bool get repeatsPreviousBar => source != written;

  @override
  bool operator ==(Object other) =>
      other is PlayedBar &&
      other.position == position &&
      other.written == written &&
      other.source == source &&
      _samePasses(other.passes, passes);

  @override
  int get hashCode =>
      Object.hash(position, written, source, Object.hashAll(passes));

  @override
  String toString() =>
      'PlayedBar($position, written=$written, source=$source, pass=$pass/$passCount'
      '${repeatStart == null ? '' : ', repeat=$repeatStart'})';
}

/// Whether two pass chains are equal position by position.
bool _samePasses(List<PlayedPass> left, List<PlayedPass> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

/// Where a passage's pass count came from, so that an assumed count is visible as an assumption.
enum PassCountBasis {
  /// Two passes, assumed: the model stores no repeat count, and no numbered bracket asked for
  /// more. Two is the smallest reading a single repeat barline can carry.
  assumedTwoPasses,

  /// A numbered bracket required this many passes. A bracket numbered 3 makes a three-pass
  /// passage, which is how a chart expresses more than one repetition at all.
  voltaRequired,
}

/// A repeated passage the derivation found, with the extent it was taken to have.
class RepeatPassage {
  /// Creates a passage from [start] to [end] with [passCount] and its [passCountBasis].
  const RepeatPassage({
    required this.start,
    required this.end,
    required this.passCount,
    required this.passCountBasis,
    required this.crossesSection,
  });

  /// The bar carrying the repeat-start barline.
  final WrittenBarAddress start;

  /// The bar carrying the matching repeat-end barline.
  final WrittenBarAddress end;

  /// How many times the passage is played.
  final int passCount;

  /// How [passCount] was decided; see [PassCountBasis].
  final PassCountBasis passCountBasis;

  /// Whether the passage spans more than one section.
  final bool crossesSection;

  @override
  bool operator ==(Object other) =>
      other is RepeatPassage &&
      other.start == start &&
      other.end == end &&
      other.passCount == passCount &&
      other.passCountBasis == passCountBasis &&
      other.crossesSection == crossesSection;

  @override
  int get hashCode =>
      Object.hash(start, end, passCount, passCountBasis, crossesSection);

  @override
  String toString() =>
      'RepeatPassage($start..$end, $passCount pass(es), $passCountBasis'
      '${crossesSection ? ', crosses a section' : ''})';
}

/// A structural problem the derivation met and had to decide around.
enum PlayOrderIssueKind {
  /// A repeat-end barline with no repeat-start barline open before it. The barline plays as an
  /// ordinary one.
  repeatEndWithoutStart,

  /// A repeat-start barline with no matching repeat-end barline. The passage plays once.
  repeatStartWithoutEnd,

  /// A repeat-previous bar with no bar before it to repeat. The bar plays as itself.
  percentWithoutPreviousBar,

  /// An alternative-ending bracket that no repeat passage contains. It selects no pass, so it is
  /// ignored as a bracket and the bar plays on every pass it is reached on.
  voltaOutsideRepeat,

  /// A repeat-start barline inside an alternative-ending run after a closing barline. The run
  /// stops there, so the nested passage is expanded as a separate sibling rather than inside the
  /// ending.
  repeatNestedInAlternativeEnding,

  /// A pass whose brackets select no bar at all, so it plays nothing.
  ///
  /// This is the consequence of a numbered bracket that covers the whole passage: the bracket says
  /// "first time only", and the second pass the repeat sign demands then has no bar to play.
  passPlaysNothing,
}

/// One problem the derivation met, reported rather than thrown.
class PlayOrderIssue {
  /// Creates an issue of [kind], arising at [at] when the problem names a bar.
  const PlayOrderIssue({required this.kind, this.at});

  /// What kind of problem this is.
  final PlayOrderIssueKind kind;

  /// The written bar the problem is about, or null when it is about the song as a whole.
  final WrittenBarAddress? at;

  /// A sentence a log reader can act on.
  String get message => switch (kind) {
    PlayOrderIssueKind.repeatEndWithoutStart =>
      'A repeat-end barline at ${at ?? 'the song'} has no repeat-start barline before it; '
          'the barline was played as an ordinary one.',
    PlayOrderIssueKind.repeatStartWithoutEnd =>
      'A repeat-start barline at ${at ?? 'the song'} has no repeat-end barline after it; '
          'the passage was played once.',
    PlayOrderIssueKind.percentWithoutPreviousBar =>
      'A repeat-previous bar at ${at ?? 'the song'} has no bar before it to repeat; '
          'the position was kept and its own (unrepeated) content was used.',
    PlayOrderIssueKind.voltaOutsideRepeat =>
      'An alternative-ending bracket at ${at ?? 'the song'} is inside no repeated passage; '
          'it selects no pass and was ignored as a bracket.',
    PlayOrderIssueKind.repeatNestedInAlternativeEnding =>
      'A repeat-start barline at ${at ?? 'the song'} opens inside an alternative-ending run; '
          'that passage was expanded as a separate sibling, not inside the ending.',
    PlayOrderIssueKind.passPlaysNothing =>
      'A pass of the passage at ${at ?? 'the song'} selects no bar, so it plays nothing; '
          'the brackets that cover the passage never allow that pass.',
  };

  @override
  bool operator ==(Object other) =>
      other is PlayOrderIssue && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => 'PlayOrderIssue(${kind.name}, $at)';
}

/// The order a chart is played in, with the evidence a caller needs to inspect it.
class PlayOrder {
  /// Creates an order from its played positions, the passages found and the problems met.
  ///
  /// The three lists are copied into unmodifiable views, so a caller cannot mutate an order that
  /// another caller is reading.
  PlayOrder({
    required List<PlayedBar> played,
    required List<RepeatPassage> passages,
    required List<PlayOrderIssue> issues,
  }) : played = List<PlayedBar>.unmodifiable(played),
       passages = List<RepeatPassage>.unmodifiable(passages),
       issues = List<PlayOrderIssue>.unmodifiable(issues);

  /// Every bar played, in order, one entry per bar the musician plays.
  ///
  /// A written `r` bar contributes two entries here, because it is two bars of music.
  final List<PlayedBar> played;

  /// The repeated passages found, in written order.
  final List<RepeatPassage> passages;

  /// The structural problems met, each with the decision that was taken.
  final List<PlayOrderIssue> issues;

  /// How many bars are played.
  int get length => played.length;

  /// Whether nothing is played.
  bool get isEmpty => played.isEmpty;

  /// The written bar whose music sounds at each position, in order.
  List<WrittenBarAddress> get sources => <WrittenBarAddress>[
    for (final PlayedBar bar in played) bar.source,
  ];

  /// The written bar each position is reached through, in order.
  List<WrittenBarAddress> get writtenBars => <WrittenBarAddress>[
    for (final PlayedBar bar in played) bar.written,
  ];

  @override
  String toString() =>
      'PlayOrder(${played.length} played, ${passages.length} passage(s), '
      '${issues.length} issue(s))';
}

// PURPOSE: Produce the order a song is played in from the song as written, expanding repeats,
//          alternative endings and repeat-previous bars, so that every consumer of the play order
//          derives it the same way instead of each writing its own reading of a repeat.
// INPUTS: song — the chart as written. The value is not modified and nothing else is read.
// OUTPUTS: A [PlayOrder]. Its `played` list has one entry per bar the musician plays; each entry
//          names the written bar it was reached through, the written bar whose music sounds, and
//          the pass it belongs to. Its `passages` list makes every repeat's pass count explicit,
//          together with whether that count was assumed. Its `issues` list names every structural
//          problem the chart forced a decision about, with the decision taken.
//
//          Edge cases, each decided rather than left undefined:
//            - a song of zero bars, or a section of zero bars: an empty order, no issues;
//            - a `%` at the first bar of the song: the position is played, its source is itself,
//              and [PlayOrderIssueKind.percentWithoutPreviousBar] is reported;
//            - a `%` chain: each `%` is followed back to the first bar that writes music, so
//              `%`-after-`%` sounds the concrete bar rather than the symbol;
//            - an unmatched repeat end: the barline is ordinary, and it is reported;
//            - an unmatched repeat start: the passage plays once, and it is reported;
//            - a passage with no bracket: two passes, and the basis says the count was assumed;
//            - a bracket that no passage contains: ignored as a bracket, and reported;
//            - a bracket numbered 1 that covers the whole passage: the repeat sign still demands a
//              second pass, that pass selects no bar, plays nothing, and is reported;
//            - nested passages: the inner one is expanded in full on every pass of the outer, and
//              each played bar records both passes, outermost first.
// KEYWORDS: derive, play-order, repeat-expansion, volta, percent, total-function, pure
/// Returns the performance order of [song], derived from its written form.
PlayOrder derivePlayOrder(Song song) => _Expander(song).expand();

/// One bar of the flattened written form, held with the address it is reachable by.
class _WrittenBar {
  const _WrittenBar(this.address, this.bar);

  final WrittenBarAddress address;
  final Bar bar;
}

/// A node of the passage tree: either a written bar or a passage of them.
sealed class _PlayNode {
  const _PlayNode();
}

/// A single written bar at one point of the form.
class _BarNode extends _PlayNode {
  const _BarNode(this.index);

  /// Index into the expander's flattened bar list.
  final int index;
}

/// A repeated passage: a body that repeats, plus the brackets that follow its closing barline.
class _GroupNode extends _PlayNode {
  const _GroupNode({
    required this.body,
    required this.outro,
    required this.passCount,
    required this.brackets,
    required this.startAddress,
  });

  /// The bars from the repeat-start barline through the repeat-end barline.
  final List<_PlayNode> body;

  /// The bracketed bars that follow the closing barline, selected by pass like the body.
  final List<_PlayNode> outro;

  /// How many times this passage is played.
  final int passCount;

  /// The bracket in force at each direct bar child of [body], with inheritance applied; see R3.
  final Map<int, Volta?> brackets;

  /// The repeat-start bar, used as the passage's identity on each played bar of it.
  final WrittenBarAddress startAddress;
}

/// Flattens a song, matches its repeats, expands them, and collects the result.
class _Expander {
  _Expander(Song song)
    : _bars = <_WrittenBar>[
        for (final Section section in song.sections)
          for (int index = 0; index < section.bars.length; index++)
            _WrittenBar(
              WrittenBarAddress(sectionId: section.id, barIndex: index),
              section.bars[index],
            ),
      ];

  final List<_WrittenBar> _bars;

  /// Maps a repeat-start bar's linear index to the index of the repeat-end bar that closes it.
  final Map<int, int> _endOfStart = <int, int>{};

  /// Linear indices whose bracket a passage claimed, so that a stray bracket can be reported.
  final Set<int> _claimedBrackets = <int>{};

  final List<RepeatPassage> _passages = <RepeatPassage>[];
  final List<PlayedBar> _played = <PlayedBar>[];
  final List<PlayOrderIssue> _issues = <PlayOrderIssue>[];

  /// Runs the whole derivation and freezes the result.
  PlayOrder expand() {
    if (_bars.isEmpty) {
      return PlayOrder(
        played: const <PlayedBar>[],
        passages: const <RepeatPassage>[],
        issues: const <PlayOrderIssue>[],
      );
    }
    _matchRepeats();
    final List<_PlayNode> root = _build(0, _bars.length - 1);
    _emitNodes(root, const <PlayedPass>[]);
    _reportStrayBrackets();
    return PlayOrder(
      played: _played,
      passages: _passages,
      issues: _distinctIssues(),
    );
  }

  /// The issues with exact repeats removed, keeping the order they were met in.
  ///
  /// A problem is identified by its kind and the bar it is about, so the same problem met twice —
  /// a two-bar `%` whose two references both run off the start of the song, say — is one thing to
  /// report rather than two.
  List<PlayOrderIssue> _distinctIssues() {
    final List<PlayOrderIssue> distinct = <PlayOrderIssue>[];
    for (final PlayOrderIssue issue in _issues) {
      if (!distinct.contains(issue)) {
        distinct.add(issue);
      }
    }
    return distinct;
  }

  /// Matches every repeat end with the nearest still-open repeat start, using a stack.
  ///
  /// A stack is what makes nesting work and what makes each barline belong to exactly one passage:
  /// the innermost open start is always the one an end closes. Leftover starts and ends with
  /// nothing open are reported rather than guessed at.
  void _matchRepeats() {
    final List<int> open = <int>[];
    for (int index = 0; index < _bars.length; index++) {
      final Bar bar = _bars[index].bar;
      if (bar.startsRepeat) {
        open.add(index);
      }
      if (bar.endsRepeat) {
        if (open.isEmpty) {
          _issues.add(
            PlayOrderIssue(
              kind: PlayOrderIssueKind.repeatEndWithoutStart,
              at: _bars[index].address,
            ),
          );
        } else {
          _endOfStart[open.removeLast()] = index;
        }
      }
    }
    for (final int start in open) {
      _issues.add(
        PlayOrderIssue(
          kind: PlayOrderIssueKind.repeatStartWithoutEnd,
          at: _bars[start].address,
        ),
      );
    }
  }

  /// Builds the node list for the written range [lo]..[hi], turning matched repeats into groups.
  List<_PlayNode> _build(int lo, int hi) {
    final List<_PlayNode> nodes = <_PlayNode>[];
    int index = lo;
    while (index <= hi) {
      final int? end = _endOfStart[index];
      if (end == null || end > hi) {
        nodes.add(_BarNode(index));
        index++;
        continue;
      }

      // The repeat-start bar is a plain member of its own passage; only the bars after it can open
      // a nested one, which is what keeps a one-bar passage from being read as nested in itself.
      final List<_PlayNode> body = <_PlayNode>[
        _BarNode(index),
        ..._build(index + 1, end),
      ];
      final Map<int, Volta?> brackets = _bracketsOf(body);
      final int outroEnd = _outroEnd(end, hi);
      final List<_PlayNode> outro = <_PlayNode>[
        for (int bar = end + 1; bar <= outroEnd; bar++) _BarNode(bar),
      ];

      _claimedBrackets.addAll(<int>[
        for (final _PlayNode node in body)
          if (node is _BarNode && _bars[node.index].bar.volta != null)
            node.index,
        for (int bar = end + 1; bar <= outroEnd; bar++) bar,
      ]);

      final int highest = _highestVolta(brackets, body, end, outroEnd);
      final int passCount = highest >= 2 ? highest : 2;
      _passages.add(
        RepeatPassage(
          start: _bars[index].address,
          end: _bars[end].address,
          passCount: passCount,
          passCountBasis: highest >= 2
              ? PassCountBasis.voltaRequired
              : PassCountBasis.assumedTwoPasses,
          crossesSection:
              _bars[index].address.sectionId != _bars[end].address.sectionId,
        ),
      );
      nodes.add(
        _GroupNode(
          body: body,
          outro: outro,
          passCount: passCount,
          brackets: brackets,
          startAddress: _bars[index].address,
        ),
      );
      index = outroEnd + 1;
    }
    return nodes;
  }

  /// The bracket in force at every direct bar child of [body], carrying the last bracket forward.
  ///
  /// Only the group's own direct bar children participate: a nested passage is not filtered by its
  /// parent's bracket, and it does not break the parent's inheritance either.
  Map<int, Volta?> _bracketsOf(List<_PlayNode> body) {
    final Map<int, Volta?> brackets = <int, Volta?>{};
    Volta? current;
    for (final _PlayNode node in body) {
      if (node is! _BarNode) {
        continue;
      }
      final Volta? own = _bars[node.index].bar.volta;
      if (own != null) {
        current = own;
      }
      brackets[node.index] = current;
    }
    return brackets;
  }

  /// Returns the last bar of the bracketed run that immediately follows [end], or [end] itself.
  ///
  /// The run stops at the first bar with no bracket of its own, and at a bar that opens another
  /// passage: an ending is a run of bars, and a repeat start inside it is a shape this derivation
  /// reports instead of silently absorbing.
  int _outroEnd(int end, int hi) {
    int last = end;
    while (last + 1 <= hi && _bars[last + 1].bar.volta != null) {
      if (_endOfStart.containsKey(last + 1)) {
        _issues.add(
          PlayOrderIssue(
            kind: PlayOrderIssueKind.repeatNestedInAlternativeEnding,
            at: _bars[last + 1].address,
          ),
        );
        break;
      }
      last++;
    }
    return last;
  }

  /// The highest numbered bracket this passage is asked to honour, or 0 when there is none.
  int _highestVolta(
    Map<int, Volta?> brackets,
    List<_PlayNode> body,
    int end,
    int outroEnd,
  ) {
    int highest = 0;
    for (final _PlayNode node in body) {
      if (node is! _BarNode) {
        continue;
      }
      final Volta? bracket = brackets[node.index];
      if (bracket != null && bracket.number > highest) {
        highest = bracket.number;
      }
    }
    for (int bar = end + 1; bar <= outroEnd; bar++) {
      final Volta? bracket = _bars[bar].bar.volta;
      if (bracket != null && bracket.number > highest) {
        highest = bracket.number;
      }
    }
    return highest;
  }

  /// Emits every node of [nodes] under the pass chain [passes], in order.
  void _emitNodes(List<_PlayNode> nodes, List<PlayedPass> passes) {
    for (final _PlayNode node in nodes) {
      _emitNode(node, passes);
    }
  }

  /// Emits one node: a bar once, a passage once per pass with its brackets selected.
  void _emitNode(_PlayNode node, List<PlayedPass> passes) {
    switch (node) {
      case final _BarNode barNode:
        _emitBar(barNode.index, passes);
      case final _GroupNode group:
        for (int pass = 1; pass <= group.passCount; pass++) {
          final List<PlayedPass> inner = <PlayedPass>[
            ...passes,
            PlayedPass(
              repeatStart: group.startAddress,
              pass: pass,
              passCount: group.passCount,
            ),
          ];
          bool playedSomething = false;
          for (final _PlayNode child in group.body) {
            if (child is _BarNode) {
              if (!_playsOnPass(group.brackets[child.index], pass)) {
                continue;
              }
              playedSomething = true;
            } else {
              // A nested passage always contributes at least its own first pass.
              playedSomething = true;
            }
            _emitNode(child, inner);
          }
          for (final _PlayNode child in group.outro) {
            if (child is _BarNode &&
                !_playsOnPass(_bars[child.index].bar.volta, pass)) {
              continue;
            }
            playedSomething = true;
            _emitNode(child, inner);
          }
          if (!playedSomething) {
            _issues.add(
              PlayOrderIssue(
                kind: PlayOrderIssueKind.passPlaysNothing,
                at: group.startAddress,
              ),
            );
          }
        }
    }
  }

  /// Whether a bracket keeps a bar on [pass]: no bracket, or an unnumbered one, always does.
  bool _playsOnPass(Volta? bracket, int pass) {
    if (bracket == null || bracket.number == 0) {
      return true;
    }
    return bracket.number == pass;
  }

  /// Emits the played positions of written bar [index].
  ///
  /// A plain bar yields one played bar that sounds itself. A repeat-previous bar yields one played
  /// bar per bar it repeats — two for `r` — each naming the `%` bar as what is written and the
  /// bar it refers to, after any chain, as what sounds.
  void _emitBar(int index, List<PlayedPass> passes) {
    switch (_bars[index].bar.repeatPrevious) {
      case RepeatPrevious.none:
        _addPlayed(index, index, passes);
      case RepeatPrevious.oneBar:
        _addPlayed(index, _sourceOf(index, 1, index), passes);
      case RepeatPrevious.twoBars:
        // `r` is two bars of music: the bar two back sounds first, then the bar one back.
        _addPlayed(index, _sourceOf(index, 2, index), passes);
        _addPlayed(index, _sourceOf(index, 1, index), passes);
    }
  }

  /// The written bar that sounds when the bar at [index] asks for the bar [back] bars before it.
  ///
  /// The chain is followed because a `%` may refer to another `%`; it terminates because every
  /// reference points strictly backwards, and it cannot cycle for the same reason. When it runs off
  /// the start of the song there is no music to name, so [owner] — the `%` bar itself — is
  /// returned and the anomaly is reported.
  int _sourceOf(int index, int back, int owner) {
    int target = index - back;
    while (target >= 0) {
      final RepeatPrevious previous = _bars[target].bar.repeatPrevious;
      if (previous == RepeatPrevious.none) {
        return target;
      }
      target -= previous == RepeatPrevious.twoBars ? 2 : 1;
    }
    _issues.add(
      PlayOrderIssue(
        kind: PlayOrderIssueKind.percentWithoutPreviousBar,
        at: _bars[owner].address,
      ),
    );
    return owner;
  }

  /// Appends one played position, resolving its addresses through the flattened bar list.
  void _addPlayed(int written, int source, List<PlayedPass> passes) {
    _played.add(
      PlayedBar(
        position: _played.length,
        written: _bars[written].address,
        source: _bars[source].address,
        passes: passes,
      ),
    );
  }

  /// Reports every bracket no passage claimed.
  void _reportStrayBrackets() {
    for (int index = 0; index < _bars.length; index++) {
      if (_bars[index].bar.volta != null && !_claimedBrackets.contains(index)) {
        _issues.add(
          PlayOrderIssue(
            kind: PlayOrderIssueKind.voltaOutsideRepeat,
            at: _bars[index].address,
          ),
        );
      }
    }
  }
}
