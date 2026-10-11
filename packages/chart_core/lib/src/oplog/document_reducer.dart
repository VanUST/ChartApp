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
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return _withChordInserted(bar, e.chord);
      }),
    ),
    final ChordUpdateEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return _withChordReplaced(bar, e.from, e.to);
      }),
    ),
    final ChordDeleteEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return _withChordRemoved(bar, e.removed);
      }),
    ),
    final NoteInsertEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return _withNoteInserted(bar, e.note);
      }),
    ),
    final NoteUpdateEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
        return _withNoteReplaced(bar, e.from, e.to);
      }),
    ),
    final NoteDeleteEvent e => state.copyWith(
      song: _mapBar(state.song, e.sectionId, e.barIndex, (Bar bar) {
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
    final KeyTransposeEvent e => state.copyWith(
      song: _transposedSong(state.song, e.semitones, e.toKey),
    ),
    final SongUpdateEvent e => state.copyWith(
      song: state.song.withMetadata(e.to),
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
    final List<Bar> bars = List<Bar>.of(section.bars);
    bars[barIndex] = change(bars[barIndex]);
    return _replaceSection(song, sectionIndex, section.copyWith(bars: bars));
  }

  /// Returns [song] with section [index] replaced by [section].
  static Song _replaceSection(Song song, int index, Section section) {
    final List<Section> sections = List<Section>.of(song.sections);
    sections[index] = section;
    return song.copyWith(sections: sections);
  }

  // --- Chords ---------------------------------------------------------------------------
  /// Returns a copy of [bar] holding [chord], pushing later chords of the same beat one step up.
  static Bar _withChordInserted(Bar bar, BeatChord chord) {
    final List<BeatChord> chords = <BeatChord>[
      for (final BeatChord existing in bar.chords)
        if (existing.beat == chord.beat && existing.step >= chord.step)
          _chordAtStep(existing, existing.step + 1)
        else
          existing,
      chord,
    ];
    chords.sort(_compareChordAddress);
    return bar.copyWith(chords: chords);
  }

  /// Returns a copy of [bar] without the chord at [removed]'s address, closing the gap.
  static Bar _withChordRemoved(Bar bar, BeatChord removed) {
    final List<BeatChord> chords = <BeatChord>[];
    bool found = false;
    for (final BeatChord existing in bar.chords) {
      if (_sameChordAddress(existing, removed)) {
        found = true;
        continue;
      }
      chords.add(
        existing.beat == removed.beat && existing.step > removed.step
            ? _chordAtStep(existing, existing.step - 1)
            : existing,
      );
    }
    if (!found) {
      throw DocumentReducerException(
        'no chord at beat ${removed.beat}.${removed.step} to delete',
      );
    }
    return bar.copyWith(chords: chords);
  }

  /// Returns a copy of [bar] with the chord at [from]'s address replaced by [to].
  static Bar _withChordReplaced(Bar bar, BeatChord from, BeatChord to) {
    final List<BeatChord> chords = <BeatChord>[];
    bool found = false;
    for (final BeatChord existing in bar.chords) {
      if (_sameChordAddress(existing, from)) {
        chords.add(to);
        found = true;
      } else {
        chords.add(existing);
      }
    }
    if (!found) {
      throw DocumentReducerException(
        'no chord at beat ${from.beat}.${from.step} to update',
      );
    }
    return bar.copyWith(chords: chords);
  }

  /// Returns [placed] with its step replaced by [step], keeping the chord and the size.
  static BeatChord _chordAtStep(BeatChord placed, int step) => BeatChord(
    chord: placed.chord,
    beat: placed.beat,
    step: step,
    size: placed.size,
  );

  /// Whether two placements sit at the same (beat, step) address.
  static bool _sameChordAddress(BeatChord left, BeatChord right) =>
      left.beat == right.beat && left.step == right.step;

  /// Orders two placements by beat and then by step.
  static int _compareChordAddress(BeatChord left, BeatChord right) {
    final int byBeat = left.beat.compareTo(right.beat);
    return byBeat != 0 ? byBeat : left.step.compareTo(right.step);
  }

  // --- Notes ----------------------------------------------------------------------------
  /// Returns a copy of [bar] holding [note], pushing later notes of the same beat one step up.
  static Bar _withNoteInserted(Bar bar, BeatNote note) {
    final List<BeatNote> melody = <BeatNote>[
      for (final BeatNote existing in bar.melody)
        if (existing.beat == note.beat && existing.step >= note.step)
          _noteAtStep(existing, existing.step + 1)
        else
          existing,
      note,
    ];
    melody.sort(_compareNoteAddress);
    return bar.copyWith(melody: melody);
  }

  /// Returns a copy of [bar] without the note at [removed]'s address, closing the gap.
  static Bar _withNoteRemoved(Bar bar, BeatNote removed) {
    final List<BeatNote> melody = <BeatNote>[];
    bool found = false;
    for (final BeatNote existing in bar.melody) {
      if (_sameNoteAddress(existing, removed)) {
        found = true;
        continue;
      }
      melody.add(
        existing.beat == removed.beat && existing.step > removed.step
            ? _noteAtStep(existing, existing.step - 1)
            : existing,
      );
    }
    if (!found) {
      throw DocumentReducerException(
        'no note at beat ${removed.beat}.${removed.step} to delete',
      );
    }
    return bar.copyWith(melody: melody);
  }

  /// Returns a copy of [bar] with the note at [from]'s address replaced by [to].
  static Bar _withNoteReplaced(Bar bar, BeatNote from, BeatNote to) {
    final List<BeatNote> melody = <BeatNote>[];
    bool found = false;
    for (final BeatNote existing in bar.melody) {
      if (_sameNoteAddress(existing, from)) {
        melody.add(to);
        found = true;
      } else {
        melody.add(existing);
      }
    }
    if (!found) {
      throw DocumentReducerException(
        'no note at beat ${from.beat}.${from.step} to update',
      );
    }
    return bar.copyWith(melody: melody);
  }

  /// Returns [placed] with its step replaced by [step], keeping pitch, duration and tie.
  static BeatNote _noteAtStep(BeatNote placed, int step) => BeatNote(
    pitch: placed.pitch,
    value: placed.value,
    beat: placed.beat,
    step: step,
    tiedToNext: placed.tiedToNext,
  );

  /// Whether two note placements sit at the same (beat, step) address.
  static bool _sameNoteAddress(BeatNote left, BeatNote right) =>
      left.beat == right.beat && left.step == right.step;

  /// Orders two note placements by beat and then by step.
  static int _compareNoteAddress(BeatNote left, BeatNote right) {
    final int byBeat = left.beat.compareTo(right.beat);
    return byBeat != 0 ? byBeat : left.step.compareTo(right.step);
  }

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
