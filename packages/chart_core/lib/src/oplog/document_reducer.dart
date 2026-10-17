// PURPOSE: Apply a document event to a document, which is the operation every other feature is
//          built on: undo is applying the inverse event, redo is applying the inverse of that,
//          autosave is folding the log, and a sync merge is folding a foreign tail. Keeping the
//          application in one exhaustive switch over the sealed event hierarchy means a new event
//          family cannot be added without the compiler demanding its application.
// INPUTS: The document value being edited and the event to apply. Setlist events go to
//         [DocumentReducer.applySetlist], which folds a [Setlist] instead of a [DocumentState].
// OUTPUTS: A new document value; the input is never mutated. An edit that names a section, bar,
//          stroke or mark the document does not contain throws [DocumentReducerException] rather
//          than being ignored, because a silently dropped event is an edit the user made and the
//          document did not record, which is exactly the class of bug an event log exists to make
//          impossible. Applying an event and then its inverse returns a value equal to the
//          original.
// KEYWORDS: reducer, apply, fold, event-sourcing, undo, exhaustive-switch, fail-loud, immutable
part of 'oplog.dart';

/// Thrown when an event cannot be applied to the document it was handed.
///
/// This is a data failure, not a programming error: it means the document and the log disagree,
/// which is worth reporting rather than absorbing.
class DocumentReducerException implements Exception {
  /// Creates a failure described by [message].
  const DocumentReducerException(this.message);

  /// What could not be applied and to what.
  final String message;
  @override
  String toString() => 'DocumentReducerException: $message';
}

/// Applies document events to the values they edit.
abstract final class DocumentReducer {
  /// Applies [event] to [state] and returns the new document.
  ///
  /// Throws [DocumentReducerException] when the event names something the document does not
  /// contain.
  static DocumentState apply(
    DocumentState state,
    ChartEvent event,
  ) => switch (event) {
    final ChordInsertEvent e => state.copyWith(
      song: _mapBar(state.song, e.anchor.sectionId, e.anchor.bar, (Bar bar) {
        return _withChordInserted(bar, e.chord);
      }),
    ),
    final ChordUpdateEvent e => state.copyWith(
      song: _mapBar(state.song, e.anchor.sectionId, e.anchor.bar, (Bar bar) {
        return _withChordReplaced(bar, e.from, e.to);
      }),
    ),
    final ChordDeleteEvent e => state.copyWith(
      song: _mapBar(state.song, e.anchor.sectionId, e.anchor.bar, (Bar bar) {
        return _withChordRemoved(bar, e.removed);
      }),
    ),
    final NoteInsertEvent e => state.copyWith(
      song: _mapBar(state.song, e.anchor.sectionId, e.anchor.bar, (Bar bar) {
        return _withNoteInserted(bar, e.note);
      }),
    ),
    final NoteUpdateEvent e => state.copyWith(
      song: _mapBar(state.song, e.anchor.sectionId, e.anchor.bar, (Bar bar) {
        return _withNoteReplaced(bar, e.from, e.to);
      }),
    ),
    final NoteDeleteEvent e => state.copyWith(
      song: _mapBar(state.song, e.anchor.sectionId, e.anchor.bar, (Bar bar) {
        return _withNoteRemoved(bar, e.removed);
      }),
    ),
    final MeasureInsertEvent e => state.copyWith(
      song: _withMeasureInserted(state.song, e.sectionId, e.index, e.bar),
    ),
    final MeasureDeleteEvent e => state.copyWith(
      song: _withMeasureRemoved(state.song, e.sectionId, e.index),
    ),
    final MeasureDuplicateEvent e => state.copyWith(
      song: _withMeasureInserted(
        state.song,
        e.sectionId,
        e.index + 1,
        e.duplicate,
      ),
    ),
    final BarsInsertEvent e => _withBarsInserted(state, e),
    final BarsRemoveEvent e => _withBarsRemoved(state, e),
    final BarsReplaceEvent e => _withBarsReplaced(state, e),
    final SectionInsertEvent e => state.copyWith(
      song: _withSectionInserted(state.song, e.index, e.section),
    ),
    final SectionDeleteEvent e => state.copyWith(
      song: _withSectionRemoved(state.song, e.index),
    ),
    final SectionUpdateEvent e => state.copyWith(
      song: _withSectionLabel(state.song, e.sectionId, e.to),
    ),
    final SectionDuplicateEvent e => state.copyWith(
      song: _withSectionInserted(state.song, e.index + 1, e.duplicate),
    ),
    final SectionReorderEvent e => state.copyWith(
      song: _withSectionMoved(state.song, e.sectionId, e.fromIndex, e.toIndex),
    ),
    final RepeatSetEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return bar.copyWith(
          openingBarline: e.to.openingBarline,
          closingBarline: e.to.closingBarline,
          repeatPrevious: e.to.repeatPrevious,
          slashRepeat: e.to.slashRepeat,
        );
      }),
    ),
    final VoltaSetEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        final Volta? bracket = e.to;
        return bracket == null
            ? bar.copyWith(clearVolta: true)
            : bar.copyWith(volta: bracket);
      }),
    ),
    final BarMarkSetEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return bar.copyWith(marks: e.to);
      }),
    ),
    final MeterSetEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return bar.copyWith(timeSignature: e.to);
      }),
    ),
    final BarSizeSetEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return bar.copyWith(size: e.to);
      }),
    ),
    final KeyTransposeEvent e => state.copyWith(
      song: _transposedSong(state.song, e.semitones, e.toKey),
    ),
    final SongUpdateEvent e => state.copyWith(
      song: state.song.withMetadata(e.to),
    ),
    final StaffSetEvent e => state.copyWith(
      song: state.song.copyWith(staffSet: e.to),
    ),
    final InkStrokeAddEvent e => _withStrokeInserted(state, e.index, e.stroke),
    final InkStrokeDeleteEvent e => _withStrokeRemoved(state, e.stroke),
    final AnnotationInsertEvent e => _withAnnotationInserted(
      state,
      e.index,
      e.annotation,
    ),
    final AnnotationDeleteEvent e => _withAnnotationRemoved(state, e.removed),
    final AnnotationMoveEvent e => _withAnnotationMoved(state, e.id, e.to),
    final AnnotationDuplicateEvent e => _withAnnotationInserted(
      state,
      e.index,
      e.duplicate,
    ),
    final TextCueInsertEvent e => _withCueInserted(state, e.index, e.cue),
    final TextCueDeleteEvent e => _withCueRemoved(state, e.removed),
    final TextCueEditEvent e => _withCueEdited(state, e.id, e.to),
    final TextCueMoveEvent e => _withCueMoved(state, e.id, e.to),
    // The divisions are set whole, so applying the event is the assignment its two sides describe
    // and the inverse is exact by construction rather than by arithmetic. See `barline_events.dart`
    // for why this family carries lists instead of a delta.
    final DivisionSetEvent e => state.copyWith(divisions: e.to),
  };

  /// Applies [event] to [setlist] and returns the new setlist.
  ///
  /// Throws [DocumentReducerException] when the event names an entry position the setlist does
  /// not have.
  static Setlist applySetlist(Setlist setlist, SetlistEvent event) =>
      switch (event) {
        final SetlistRenameEvent e => setlist.copyWith(title: e.toTitle),
        final SetlistItemInsertEvent e => _withSetlistItemInserted(
          setlist,
          e.index,
          e.item,
        ),
        final SetlistItemDeleteEvent e => _withSetlistItemRemoved(
          setlist,
          e.index,
        ),
        final SetlistItemMoveEvent e => _withSetlistItemMoved(
          setlist,
          e.fromIndex,
          e.toIndex,
        ),
        final SetlistItemUpdateEvent e => _withSetlistItemReplaced(
          setlist,
          e.index,
          e.to,
        ),
      };
  // --- Bar addressing -------------------------------------------------------------------
  /// Finds the section named by [sectionId], reporting a document that does not contain it.
  static (Section, int) _sectionOf(Song song, String sectionId) {
    final int index = song.sections.indexWhere(
      (Section section) => section.id == sectionId,
    );
    if (index < 0) {
      throw DocumentReducerException(
        'song "${song.id}" has no section "$sectionId"',
      );
    }
    return (song.sections[index], index);
  }

  /// Returns [song] with the bar at ([sectionId], [barIndex]) transformed by [change].
  ///
  /// THE SECTION IS ANCHORED BEFORE [change] RUNS, not after it. A change looks a mark up BY ITS
  /// PLACE, and a place carries its bar — so a mark whose anchor is stale cannot be found by the
  /// place the caller named, and the edit is refused as "no chord at x=… in this bar". Anchoring
  /// first makes every mark in the section say the bar it is in, and the change then finds what it
  /// names. [_replaceSection] re-anchors afterwards as well, which is what covers the events that do
  /// not go through here (`measure.insert` and the bar runs); on this path it is a no-op.
  static Song _mapBar(
    Song song,
    String sectionId,
    int barIndex,
    Bar Function(Bar) change,
  ) {
    final (Section section, int sectionIndex) = _sectionOf(song, sectionId);
    if (barIndex < 0 || barIndex >= section.bars.length) {
      throw DocumentReducerException(
        'section "$sectionId" has no bar $barIndex '
        '(${section.bars.length} bar(s))',
      );
    }
    // A copy either way: [change] must not write into the list the old document still holds.
    final List<Bar> bars = List<Bar>.of(_anchoredBars(section));
    bars[barIndex] = change(bars[barIndex]);
    return _replaceSection(song, sectionIndex, section.copyWith(bars: bars));
  }

  /// Returns [song] with section [index] replaced by [section].
  ///
  /// EVERY MARK'S ANCHOR IS REWRITTEN TO THE BAR THAT HOLDS IT HERE, in one place, for the whole
  /// section. A chord or a note carries an [AnchoredPlace] whose anchor names its bar, and a bar's
  /// address is an INDEX — so inserting a bar renumbers every bar after it, and a mark left pointing
  /// at its old index would name somebody else's music the moment the insertion landed. Rewriting
  /// them at the one point every song-mutating event passes through makes the invariant true by
  /// construction rather than by remembering: after any event this reducer applies, a mark found in
  /// bar n says n.
  ///
  /// WHY THIS IS NOT A SECOND SOURCE OF TRUTH, ALTHOUGH IT LOOKS LIKE ONE. The mark's anchor is
  /// derived from the position the mark was FOUND at, so bar membership stays the single authority
  /// and the anchor is a restatement of it that the reducer keeps honest. The alternative — a mark
  /// that carries no bar at all — cannot be made to work while a bar has an index: `measure.insert`
  /// would silently move every mark after it onto the wrong music, and the defect would be invisible
  /// in the document and visible only on the page.
  ///
  /// THE COST IS PAID PER EVENT AND IS NIL. A section holds tens of bars and a bar a handful of
  /// marks, so re-anchoring a whole section is a few hundred immutable value copies — far less than
  /// one frame of engraving — and it is paid against a class of silent mis-addressing the project has
  /// already paid for once with handwriting (A71 §6, A71 §13г). The check is skipped when nothing
  /// needs it, which is every event after the first on a document this reducer produced.
  static Song _replaceSection(Song song, int index, Section section) {
    final List<Section> sections = List<Section>.of(song.sections);
    sections[index] = section.copyWith(bars: _anchoredBars(section));
    return song.copyWith(sections: sections);
  }

  /// Returns [section]'s bars with every mark anchored to the bar that holds it.
  static List<Bar> _anchoredBars(Section section) {
    if (!_needsAnchoring(section)) {
      return section.bars;
    }
    return <Bar>[
      for (int index = 0; index < section.bars.length; index++)
        _reanchoredBar(section.bars[index], section.id, index),
    ];
  }

  /// Whether any bar of [section] holds a mark whose anchor is not its own address.
  ///
  /// The check exists so that a document that is already consistent — which is every document this
  /// reducer produced — is returned without copying anything, and so that the rewrite is paid only
  /// where an address actually moved.
  static bool _needsAnchoring(Section section) {
    for (int index = 0; index < section.bars.length; index++) {
      final Bar bar = section.bars[index];
      for (final ChordMark mark in bar.chords) {
        if (mark.place.anchor.sectionId != section.id ||
            mark.place.anchor.bar != index) {
          return true;
        }
      }
      for (final NoteMark note in bar.melody) {
        if (note.place.anchor.sectionId != section.id ||
            note.place.anchor.bar != index) {
          return true;
        }
      }
      for (final PercussionMark hit in bar.percussion) {
        if (hit.place.anchor.sectionId != section.id ||
            hit.place.anchor.bar != index) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns [bar] with every mark's anchor naming ([sectionId], [barIndex]).
  ///
  /// Only the anchor is replaced. The offsets are what the musician wrote and are left exactly as
  /// they are: an inserted bar moves a mark to another index, never to another position inside its
  /// own bar.
  static Bar _reanchoredBar(Bar bar, String sectionId, int barIndex) {
    final EventAnchor anchor = EventAnchor(sectionId: sectionId, bar: barIndex);
    AnchoredPlace at(AnchoredPlace place) => AnchoredPlace(
      anchor: anchor,
      offsetX: place.offsetX,
      offsetY: place.offsetY,
    );
    return bar.copyWith(
      chords: <ChordMark>[
        for (final ChordMark mark in bar.chords)
          mark.copyWith(place: at(mark.place)),
      ],
      melody: <NoteMark>[
        for (final NoteMark note in bar.melody)
          note.copyWith(place: at(note.place)),
      ],
      percussion: <PercussionMark>[
        for (final PercussionMark hit in bar.percussion)
          hit.copyWith(place: at(hit.place)),
      ],
    );
  }

  // --- Chords ---------------------------------------------------------------------------
  /// Returns a copy of [bar] that also holds [chord].
  ///
  /// NOTHING IS PUSHED AND NO GAP IS CLOSED. A chord is written where the musician wrote it, so two
  /// chords that share an x are two chords that share an x; nudging one of them along a step to keep
  /// a grid dense would be the grid returning through the side door. The list is kept ordered by
  /// place so that a reader — and a test — can read the chord line left to right.
  static Bar _withChordInserted(Bar bar, ChordMark chord) {
    final List<ChordMark> chords = <ChordMark>[...bar.chords, chord]
      ..sort(_compareChordPlace);
    return bar.copyWith(chords: chords);
  }

  /// Returns a copy of [bar] without the chord written at [removed]'s place.
  ///
  /// THE MARK NAMED IS THE MARK REMOVED, matched by its whole value before its place is used. A
  /// place is a coordinate and two chords may legitimately share one — nothing nudges them apart any
  /// more — so a deletion that matched on the place alone could remove a different chord than the one
  /// the inverse names, and an undo would then restore the wrong document. Matching the value first
  /// makes the inverse exact; the place is the fallback for a caller that describes a mark slightly
  /// differently, and a place nothing matches is still the reported failure it was.
  static Bar _withChordRemoved(Bar bar, ChordMark removed) {
    int at = bar.chords.indexWhere((ChordMark existing) => existing == removed);
    if (at < 0) {
      at = bar.chords.indexWhere(
        (ChordMark existing) => existing.place == removed.place,
      );
    }
    if (at < 0) {
      throw DocumentReducerException(
        'no chord at x=${removed.place.offsetX} in this bar to delete',
      );
    }
    final List<ChordMark> chords = <ChordMark>[...bar.chords]..removeAt(at);
    return bar.copyWith(chords: chords);
  }

  /// Returns a copy of [bar] with the chord at [from]'s place replaced by [to].
  ///
  /// [to] may sit at a DIFFERENT place in the same bar: moving a chord is exactly this event, now
  /// that a chord's position is part of its value rather than an address that has to stay fixed. The
  /// replaced mark is found by its whole value first, for the reason the deletion gives.
  static Bar _withChordReplaced(Bar bar, ChordMark from, ChordMark to) {
    int at = bar.chords.indexWhere((ChordMark existing) => existing == from);
    if (at < 0) {
      at = bar.chords.indexWhere(
        (ChordMark existing) => existing.place == from.place,
      );
    }
    if (at < 0) {
      throw DocumentReducerException(
        'no chord at x=${from.place.offsetX} in this bar to update',
      );
    }
    final List<ChordMark> chords = <ChordMark>[...bar.chords];
    chords[at] = to;
    chords.sort(_compareChordPlace);
    return bar.copyWith(chords: chords);
  }

  /// Orders two chord marks by their place along the bar, then across it.
  ///
  /// The tie-break on the vertical offset matters only for two chords written at exactly the same x
  /// — which a hand-edited file can hold and the palette can produce — and it exists so that the
  /// order is total and a document compares equal to itself after a round trip.
  static int _compareChordPlace(ChordMark left, ChordMark right) {
    final int byX = left.place.offsetX.compareTo(right.place.offsetX);
    return byX != 0 ? byX : left.place.offsetY.compareTo(right.place.offsetY);
  }

  // --- Notes ----------------------------------------------------------------------------
  /// Returns a copy of [bar] that also holds [note], ordered by its place along the bar.
  static Bar _withNoteInserted(Bar bar, NoteMark note) {
    final List<NoteMark> melody = <NoteMark>[...bar.melody, note]
      ..sort(_compareNotePlace);
    return bar.copyWith(melody: melody);
  }

  /// Returns a copy of [bar] without the note written at [removed]'s place.
  ///
  /// Matched by its whole value before its place, for the reason the chord deletion gives: two notes
  /// may share a coordinate, and the inverse names one of them exactly.
  static Bar _withNoteRemoved(Bar bar, NoteMark removed) {
    int at = bar.melody.indexWhere((NoteMark existing) => existing == removed);
    if (at < 0) {
      at = bar.melody.indexWhere(
        (NoteMark existing) => existing.place == removed.place,
      );
    }
    if (at < 0) {
      throw DocumentReducerException(
        'no note at x=${removed.place.offsetX} in this bar to delete',
      );
    }
    final List<NoteMark> melody = <NoteMark>[...bar.melody]..removeAt(at);
    return bar.copyWith(melody: melody);
  }

  /// Returns a copy of [bar] with the note at [from]'s place replaced by [to].
  static Bar _withNoteReplaced(Bar bar, NoteMark from, NoteMark to) {
    int at = bar.melody.indexWhere((NoteMark existing) => existing == from);
    if (at < 0) {
      at = bar.melody.indexWhere(
        (NoteMark existing) => existing.place == from.place,
      );
    }
    if (at < 0) {
      throw DocumentReducerException(
        'no note at x=${from.place.offsetX} in this bar to update',
      );
    }
    final List<NoteMark> melody = <NoteMark>[...bar.melody];
    melody[at] = to;
    melody.sort(_compareNotePlace);
    return bar.copyWith(melody: melody);
  }

  /// Orders two note marks by their place along the bar. The place's x is the note's time.
  static int _compareNotePlace(NoteMark left, NoteMark right) =>
      left.place.offsetX.compareTo(right.place.offsetX);

  // --- Measures -------------------------------------------------------------------------
  /// Returns [song] with [bar] inserted at [index] of section [sectionId].
  static Song _withMeasureInserted(
    Song song,
    String sectionId,
    int index,
    Bar bar,
  ) {
    final (Section section, int sectionIndex) = _sectionOf(song, sectionId);
    if (index < 0 || index > section.bars.length) {
      throw DocumentReducerException(
        'cannot insert a bar at $index of section "$sectionId" '
        '(${section.bars.length} bar(s))',
      );
    }
    final List<Bar> bars = List<Bar>.of(section.bars)..insert(index, bar);
    return _replaceSection(song, sectionIndex, section.copyWith(bars: bars));
  }

  /// Returns [song] without the bar at [index] of section [sectionId].
  static Song _withMeasureRemoved(Song song, String sectionId, int index) {
    final (Section section, int sectionIndex) = _sectionOf(song, sectionId);
    if (index < 0 || index >= section.bars.length) {
      throw DocumentReducerException(
        'section "$sectionId" has no bar $index to remove',
      );
    }
    final List<Bar> bars = List<Bar>.of(section.bars)..removeAt(index);
    return _replaceSection(song, sectionIndex, section.copyWith(bars: bars));
  }

  // --- Runs of bars: paste, its undo, and a replacement in place ---------------------------------
  //
  // These three helpers are what make a SELECTION edit cost one undo. `measure.insert` repeated
  // would be one event per bar, and D36 names that price as unacceptable for a paste; the price the
  // eraser already pays (A69) is not paid twice. The run is carried whole in both directions, so undo
  // restores values rather than reconstructing them, and an insertion additionally carries the ink
  // and the re-addressing it causes (`AnchorMove`), because an insertion that moved the music and
  // left the handwriting on its old indices would silently draw the ink over the copies.

  /// Returns [state] with [event]'s run of bars inserted, its ink added and its moves applied.
  ///
  /// THE MOVES ARE APPLIED BEFORE THE STROKES ARE APPENDED, and the order matters for a reason worth
  /// stating: a move names an object by id and the pasted strokes are new ids, so the two sets cannot
  /// collide — but applying the moves first means the document the strokes land in already has every
  /// older object where its bar now is, which is the state a reader would see.
  static DocumentState _withBarsInserted(
    DocumentState state,
    BarsInsertEvent event,
  ) {
    final Song song = _withBarRunInserted(
      state.song,
      event.sectionId,
      event.index,
      event.bars,
    );
    final DocumentState moved = _withAnchorMoves(
      state.copyWith(song: song),
      event.moves,
    );
    return _withStrokesAppended(moved, event.strokes);
  }

  /// Returns [state] with [event]'s run of bars removed, its ink removed and its moves reversed.
  ///
  /// THE MOVES ARE STORED IN THE DIRECTION THE INSERTION APPLIED THEM and reversed here, so one list
  /// describes both directions and the two cannot drift apart.
  static DocumentState _withBarsRemoved(
    DocumentState state,
    BarsRemoveEvent event,
  ) {
    final Song song = _withBarRunRemoved(
      state.song,
      event.sectionId,
      event.index,
      event.bars.length,
    );
    final DocumentState uninked = _withStrokesRemoved(
      state.copyWith(song: song),
      event.strokes,
    );
    return _withAnchorMoves(uninked, event.moves, reversed: true);
  }

  /// Returns [state] with [event]'s run of bars replaced, its old ink removed and its new ink added.
  ///
  /// The two runs must be the same length. `from` is NOT compared against what the section actually
  /// holds, for the same reason `chord.update` does not compare its own `from`: the event states the
  /// change, and an event whose `from` had to match would turn an undo after an unrelated edit into a
  /// crash. What the event does guarantee — and what undo relies on — is that `to` is a complete
  /// description of the bars the edit leaves behind.
  static DocumentState _withBarsReplaced(
    DocumentState state,
    BarsReplaceEvent event,
  ) {
    if (event.from.length != event.to.length) {
      throw DocumentReducerException(
        'bars.replace must replace the same number of bars it removes '
        '(${event.from.length} -> ${event.to.length})',
      );
    }
    final Song song = _withBarRunReplaced(
      state.song,
      event.sectionId,
      event.index,
      event.to,
    );
    final DocumentState uninked = _withStrokesRemoved(
      state.copyWith(song: song),
      event.removedStrokes,
    );
    return _withStrokesAppended(uninked, event.addedStrokes);
  }

  /// Returns [song] with [bars] inserted at [index] of section [sectionId].
  static Song _withBarRunInserted(
    Song song,
    String sectionId,
    int index,
    List<Bar> bars,
  ) {
    final (Section section, int sectionIndex) = _sectionOf(song, sectionId);
    if (index < 0 || index > section.bars.length) {
      throw DocumentReducerException(
        'cannot insert ${bars.length} bar(s) at $index of section "$sectionId" '
        '(${section.bars.length} bar(s))',
      );
    }
    if (bars.isEmpty) {
      throw DocumentReducerException(
        'a run of bars cannot be empty: an insertion of nothing is not an edit',
      );
    }
    final List<Bar> next = List<Bar>.of(section.bars)..insertAll(index, bars);
    return _replaceSection(song, sectionIndex, section.copyWith(bars: next));
  }

  /// Returns [song] without [count] bars starting at [index] of section [sectionId].
  static Song _withBarRunRemoved(
    Song song,
    String sectionId,
    int index,
    int count,
  ) {
    final (Section section, int sectionIndex) = _sectionOf(song, sectionId);
    if (index < 0 || count <= 0 || index + count > section.bars.length) {
      throw DocumentReducerException(
        'section "$sectionId" has no run of $count bar(s) at $index '
        '(${section.bars.length} bar(s))',
      );
    }
    final List<Bar> next = List<Bar>.of(section.bars)
      ..removeRange(index, index + count);
    if (next.isEmpty) {
      throw DocumentReducerException(
        'removing bars $index..${index + count - 1} of section "$sectionId" '
        'would leave it with no bars, which the page cannot draw or touch',
      );
    }
    return _replaceSection(song, sectionIndex, section.copyWith(bars: next));
  }

  /// Returns [song] with [count] bars starting at [index] of section [sectionId] replaced by [to].
  static Song _withBarRunReplaced(
    Song song,
    String sectionId,
    int index,
    List<Bar> to,
  ) {
    final (Section section, int sectionIndex) = _sectionOf(song, sectionId);
    if (index < 0 || index + to.length > section.bars.length) {
      throw DocumentReducerException(
        'section "$sectionId" has no run of ${to.length} bar(s) at $index '
        '(${section.bars.length} bar(s))',
      );
    }
    final List<Bar> next = List<Bar>.of(section.bars)
      ..replaceRange(index, index + to.length, to);
    return _replaceSection(song, sectionIndex, section.copyWith(bars: next));
  }

  /// Returns [state] with every object an [AnchorMove] names re-addressed.
  ///
  /// Throws when a move names an object the document does not hold: an event that moved a mark which
  /// is not there means the log and the document disagree, and silently skipping it would leave the
  /// mark on the wrong bar — which is the failure this whole mechanism exists to prevent.
  static DocumentState _withAnchorMoves(
    DocumentState state,
    List<AnchorMove> moves, {
    bool reversed = false,
  }) {
    DocumentState next = state;
    for (final AnchorMove move in moves) {
      final EventAnchor destination = reversed ? move.from : move.to;
      switch (move.kind) {
        case AnchorMoveKind.stroke:
          final int index = next.strokes.indexWhere(
            (InkStroke stroke) => stroke.id == move.id,
          );
          if (index < 0) {
            throw DocumentReducerException(
              'no stroke "${move.id}" to re-address',
            );
          }
          final List<InkStroke> strokes = List<InkStroke>.of(next.strokes);
          final InkStroke stroke = strokes[index];
          strokes[index] = InkStroke(
            id: stroke.id,
            tool: stroke.tool,
            color: stroke.color,
            size: stroke.size,
            anchor: destination,
            points: stroke.points,
          );
          next = next.copyWith(strokes: strokes);
        case AnchorMoveKind.annotation:
          final int index = next.annotations.indexWhere(
            (Annotation mark) => mark.id == move.id,
          );
          if (index < 0) {
            throw DocumentReducerException(
              'no annotation "${move.id}" to re-address',
            );
          }
          final List<Annotation> marks = List<Annotation>.of(next.annotations);
          marks[index] = marks[index].copyWith(
            place: AnchoredPlace(
              anchor: destination,
              offsetX: marks[index].place.offsetX,
              offsetY: marks[index].place.offsetY,
            ),
          );
          next = next.copyWith(annotations: marks);
        case AnchorMoveKind.textCue:
          final int index = next.textCues.indexWhere(
            (TextCue cue) => cue.id == move.id,
          );
          if (index < 0) {
            throw DocumentReducerException(
              'no text cue "${move.id}" to re-address',
            );
          }
          final List<TextCue> cues = List<TextCue>.of(next.textCues);
          cues[index] = cues[index].copyWith(
            place: AnchoredPlace(
              anchor: destination,
              offsetX: cues[index].place.offsetX,
              offsetY: cues[index].place.offsetY,
            ),
          );
          next = next.copyWith(textCues: cues);
      }
    }
    return next;
  }

  /// Returns [state] with [strokes] appended to the document's stroke list, in order.
  ///
  /// Appending rather than inserting: a pasted run lands on top of everything the document already
  /// holds, which is what a paste looks like and what makes its inverse — a removal by id — restore
  /// the list exactly.
  static DocumentState _withStrokesAppended(
    DocumentState state,
    List<InkStroke> strokes,
  ) {
    if (strokes.isEmpty) {
      return state;
    }
    final List<InkStroke> next = List<InkStroke>.of(state.strokes);
    for (final InkStroke stroke in strokes) {
      if (next.any((InkStroke other) => other.id == stroke.id)) {
        throw DocumentReducerException(
          'stroke "${stroke.id}" is already present',
        );
      }
      next.add(stroke);
    }
    return state.copyWith(strokes: next);
  }

  /// Returns [state] without the strokes in [strokes], matched by identity.
  static DocumentState _withStrokesRemoved(
    DocumentState state,
    List<InkStroke> strokes,
  ) {
    if (strokes.isEmpty) {
      return state;
    }
    final List<InkStroke> next = List<InkStroke>.of(state.strokes);
    for (final InkStroke stroke in strokes) {
      final int index = next.indexWhere(
        (InkStroke other) => other.id == stroke.id,
      );
      if (index < 0) {
        throw DocumentReducerException('no stroke "${stroke.id}" to remove');
      }
      next.removeAt(index);
    }
    return state.copyWith(strokes: next);
  }

  // --- Sections -------------------------------------------------------------------------
  /// Returns [song] with [section] inserted at [index].
  static Song _withSectionInserted(Song song, int index, Section section) {
    if (index < 0 || index > song.sections.length) {
      throw DocumentReducerException(
        'cannot insert a section at $index of a song with '
        '${song.sections.length} section(s)',
      );
    }
    final List<Section> sections = List<Section>.of(song.sections)
      ..insert(index, section);
    return song.copyWith(sections: sections);
  }

  /// Returns [song] without the section at [index].
  static Song _withSectionRemoved(Song song, int index) {
    if (index < 0 || index >= song.sections.length) {
      throw DocumentReducerException(
        'song has no section $index to remove '
        '(${song.sections.length} section(s))',
      );
    }
    final List<Section> sections = List<Section>.of(song.sections)
      ..removeAt(index);
    return song.copyWith(sections: sections);
  }

  /// Returns [song] with the label of section [sectionId] replaced by [label].
  static Song _withSectionLabel(
    Song song,
    String sectionId,
    SectionLabel label,
  ) {
    final (Section section, int index) = _sectionOf(song, sectionId);
    return _replaceSection(song, index, section.copyWith(label: label));
  }

  /// Returns [song] with the section [sectionId] moved to [toIndex].
  static Song _withSectionMoved(
    Song song,
    String sectionId,
    int fromIndex,
    int toIndex,
  ) {
    if (fromIndex < 0 || fromIndex >= song.sections.length) {
      throw DocumentReducerException(
        'song has no section at $fromIndex to move',
      );
    }
    if (toIndex < 0 || toIndex >= song.sections.length) {
      throw DocumentReducerException(
        'cannot move a section to $toIndex of a song with '
        '${song.sections.length} section(s)',
      );
    }
    final List<Section> sections = List<Section>.of(song.sections);
    final Section moved = sections[fromIndex];
    if (moved.id != sectionId) {
      throw DocumentReducerException(
        'section at $fromIndex is "${moved.id}", not "$sectionId"',
      );
    }
    sections
      ..removeAt(fromIndex)
      ..insert(toIndex, moved);
    return song.copyWith(sections: sections);
  }

  // --- Key ------------------------------------------------------------------------------
  /// Returns [song] with its chord line moved by [semitones] and its key relabelled [toKey].
  static Song _transposedSong(Song song, int semitones, Key toKey) =>
      transposeSong(song, semitones, toKey: toKey);

  // --- Ink ------------------------------------------------------------------------------
  /// Returns [state] with [stroke] inserted at [index] of the stroke list.
  static DocumentState _withStrokeInserted(
    DocumentState state,
    int index,
    InkStroke stroke,
  ) {
    if (index < 0 || index > state.strokes.length) {
      throw DocumentReducerException(
        'cannot insert a stroke at $index of a document with '
        '${state.strokes.length} stroke(s)',
      );
    }
    if (state.strokes.any((InkStroke other) => other.id == stroke.id)) {
      throw DocumentReducerException(
        'stroke "${stroke.id}" is already present',
      );
    }
    final List<InkStroke> strokes = List<InkStroke>.of(state.strokes)
      ..insert(index, stroke);
    return state.copyWith(strokes: strokes);
  }

  /// Returns [state] without the stroke identified by [stroke]'s id.
  static DocumentState _withStrokeRemoved(
    DocumentState state,
    InkStroke stroke,
  ) {
    final int index = state.strokes.indexWhere(
      (InkStroke other) => other.id == stroke.id,
    );
    if (index < 0) {
      throw DocumentReducerException('no stroke "${stroke.id}" to remove');
    }
    final List<InkStroke> strokes = List<InkStroke>.of(state.strokes)
      ..removeAt(index);
    return state.copyWith(strokes: strokes);
  }

  // --- Annotations ----------------------------------------------------------------------
  /// Returns [state] with [annotation] inserted at [index] of the mark list.
  static DocumentState _withAnnotationInserted(
    DocumentState state,
    int index,
    Annotation annotation,
  ) {
    if (index < 0 || index > state.annotations.length) {
      throw DocumentReducerException(
        'cannot insert an annotation at $index of a document with '
        '${state.annotations.length} annotation(s)',
      );
    }
    if (state.annotations.any(
      (Annotation other) => other.id == annotation.id,
    )) {
      throw DocumentReducerException(
        'annotation "${annotation.id}" is already present',
      );
    }
    final List<Annotation> annotations = List<Annotation>.of(state.annotations)
      ..insert(index, annotation);
    return state.copyWith(annotations: annotations);
  }

  /// Returns [state] without the annotation identified by [removed]'s id.
  static DocumentState _withAnnotationRemoved(
    DocumentState state,
    Annotation removed,
  ) {
    final int index = state.annotations.indexWhere(
      (Annotation other) => other.id == removed.id,
    );
    if (index < 0) {
      throw DocumentReducerException('no annotation "${removed.id}" to remove');
    }
    final List<Annotation> annotations = List<Annotation>.of(state.annotations)
      ..removeAt(index);
    return state.copyWith(annotations: annotations);
  }

  /// Returns [state] with the annotation [id] placed at [to].
  static DocumentState _withAnnotationMoved(
    DocumentState state,
    String id,
    AnchoredPlace to,
  ) {
    final int index = state.annotations.indexWhere(
      (Annotation other) => other.id == id,
    );
    if (index < 0) {
      throw DocumentReducerException('no annotation "$id" to move');
    }
    final List<Annotation> annotations = List<Annotation>.of(state.annotations);
    annotations[index] = annotations[index].copyWith(place: to);
    return state.copyWith(annotations: annotations);
  }

  // --- Text cues ------------------------------------------------------------------------
  /// Returns [state] with [cue] inserted at [index] of the text-cue list.
  static DocumentState _withCueInserted(
    DocumentState state,
    int index,
    TextCue cue,
  ) {
    if (index < 0 || index > state.textCues.length) {
      throw DocumentReducerException(
        'cannot insert a text cue at $index of a document with '
        '${state.textCues.length} cue(s)',
      );
    }
    if (state.textCues.any((TextCue other) => other.id == cue.id)) {
      throw DocumentReducerException('text cue "${cue.id}" is already present');
    }
    final List<TextCue> cues = List<TextCue>.of(state.textCues)
      ..insert(index, cue);
    return state.copyWith(textCues: cues);
  }

  /// Returns [state] without the text cue identified by [removed]'s id.
  static DocumentState _withCueRemoved(DocumentState state, TextCue removed) {
    final int index = state.textCues.indexWhere(
      (TextCue other) => other.id == removed.id,
    );
    if (index < 0) {
      throw DocumentReducerException('no text cue "${removed.id}" to remove');
    }
    final List<TextCue> cues = List<TextCue>.of(state.textCues)
      ..removeAt(index);
    return state.copyWith(textCues: cues);
  }

  /// Returns [state] with the text of cue [id] replaced by [text].
  static DocumentState _withCueEdited(
    DocumentState state,
    String id,
    String text,
  ) {
    final int index = state.textCues.indexWhere(
      (TextCue other) => other.id == id,
    );
    if (index < 0) {
      throw DocumentReducerException('no text cue "$id" to edit');
    }
    final List<TextCue> cues = List<TextCue>.of(state.textCues);
    cues[index] = cues[index].copyWith(text: text);
    return state.copyWith(textCues: cues);
  }

  /// Returns [state] with the text cue [id] placed at [to].
  static DocumentState _withCueMoved(
    DocumentState state,
    String id,
    AnchoredPlace to,
  ) {
    final int index = state.textCues.indexWhere(
      (TextCue other) => other.id == id,
    );
    if (index < 0) {
      throw DocumentReducerException('no text cue "$id" to move');
    }
    final List<TextCue> cues = List<TextCue>.of(state.textCues);
    cues[index] = cues[index].copyWith(place: to);
    return state.copyWith(textCues: cues);
  }

  // --- Setlists -------------------------------------------------------------------------
  /// Returns [setlist] with [item] inserted at [index].
  static Setlist _withSetlistItemInserted(
    Setlist setlist,
    int index,
    SetlistItem item,
  ) {
    if (index < 0 || index > setlist.items.length) {
      throw DocumentReducerException(
        'cannot insert a setlist entry at $index of a setlist with '
        '${setlist.items.length} entries',
      );
    }
    final List<SetlistItem> items = List<SetlistItem>.of(setlist.items)
      ..insert(index, item);
    return setlist.copyWith(items: items);
  }

  /// Returns [setlist] without the entry at [index].
  static Setlist _withSetlistItemRemoved(Setlist setlist, int index) {
    if (index < 0 || index >= setlist.items.length) {
      throw DocumentReducerException(
        'setlist has no entry $index to remove '
        '(${setlist.items.length} entries)',
      );
    }
    final List<SetlistItem> items = List<SetlistItem>.of(setlist.items)
      ..removeAt(index);
    return setlist.copyWith(items: items);
  }

  /// Returns [setlist] with the entry at [fromIndex] moved to [toIndex].
  static Setlist _withSetlistItemMoved(
    Setlist setlist,
    int fromIndex,
    int toIndex,
  ) {
    if (fromIndex < 0 || fromIndex >= setlist.items.length) {
      throw DocumentReducerException(
        'setlist has no entry at $fromIndex to move',
      );
    }
    if (toIndex < 0 || toIndex >= setlist.items.length) {
      throw DocumentReducerException(
        'cannot move a setlist entry to $toIndex of a setlist with '
        '${setlist.items.length} entries',
      );
    }
    final List<SetlistItem> items = List<SetlistItem>.of(setlist.items);
    final SetlistItem moved = items.removeAt(fromIndex);
    items.insert(toIndex, moved);
    return setlist.copyWith(items: items);
  }

  /// Returns [setlist] with the entry at [index] replaced by [item].
  static Setlist _withSetlistItemReplaced(
    Setlist setlist,
    int index,
    SetlistItem item,
  ) {
    if (index < 0 || index >= setlist.items.length) {
      throw DocumentReducerException('setlist has no entry $index to update');
    }
    final List<SetlistItem> items = List<SetlistItem>.of(setlist.items);
    items[index] = item;
    return setlist.copyWith(items: items);
  }
}
