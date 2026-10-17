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
  static DocumentState apply(DocumentState state, ChartEvent event) =>
      switch (event) {
        final BarSizeSetEvent e => state.copyWith(
          song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
            return bar.copyWith(size: e.to);
          }),
        ),
        final SongUpdateEvent e => state.copyWith(
          song: state.song.withMetadata(e.to),
        ),
        final InkStrokeAddEvent e => _withStrokeInserted(
          state,
          e.index,
          e.stroke,
        ),
        final InkStrokeDeleteEvent e => _withStrokeRemoved(state, e.stroke),
        final TextCueInsertEvent e => _withCueInserted(state, e.index, e.cue),
        final TextCueDeleteEvent e => _withCueRemoved(state, e.removed),
        final TextCueEditEvent e => _withCueEdited(state, e.id, e.to),
        final TextCueMoveEvent e => _withCueMoved(state, e.id, e.to),
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
    final List<Bar> bars = List<Bar>.of(section.bars);
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
    sections[index] = section;
    return song.copyWith(sections: sections);
  }

  // --- Sections -------------------------------------------------------------------------
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
