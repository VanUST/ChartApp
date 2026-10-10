// PURPOSE: Describe where everything landed, in a form that answers the two questions the rest of
//          the system asks of a layout: where is this chord drawn, and which chord is under this
//          touch. Every element carries both its identity in the song model and its rectangle on
//          the page, so neither question requires re-running the engine.
// INPUTS: Produced by the layout engine; not constructed by callers.
// OUTPUTS: Immutable values with value equality, which is what makes a layout comparable — a
//          cached layout can be recognised as unchanged without re-engraving it.
// KEYWORDS: layout-result, placed-chord, hit-testing, value-equality, cache-key, anchor-address
import '../chord.dart';
import 'geometry.dart';

/// A chord drawn at a position, with the address that identifies it in the song.
class PlacedChord {
  /// Creates a placed chord for [chord] at ([beat], [step]) with the given [bounds].
  const PlacedChord({
    required this.chord,
    required this.beat,
    required this.step,
    required this.bounds,
  });

  /// The chord that is drawn.
  final Chord chord;

  /// The cell of the bar the chord sits on.
  final int beat;

  /// The order of this chord within its cell, matching the song model's step.
  final int step;

  /// Where the chord is drawn, in page coordinates.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedChord &&
      other.chord == chord &&
      other.beat == beat &&
      other.step == step &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(chord, beat, step, bounds);

  @override
  String toString() => 'placed($chord) at $bounds';
}

/// A bar drawn at a position, together with the chords inside it.
class PlacedBar {
  /// Creates a placed bar for the bar at ([sectionId], [barIndex]).
  const PlacedBar({
    required this.sectionId,
    required this.barIndex,
    required this.bounds,
    required this.chords,
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// The bar's index within its section, in written order.
  ///
  /// Together with [sectionId] this is the bar half of an annotation anchor, so a layout can be
  /// matched to an annotation without either side knowing the other's coordinate system.
  final int barIndex;

  /// Where the bar is drawn, in page coordinates.
  final LayoutRect bounds;

  /// The chords inside the bar, ordered by cell and then by step.
  final List<PlacedChord> chords;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedBar ||
        other.sectionId != sectionId ||
        other.barIndex != barIndex ||
        other.bounds != bounds ||
        other.chords.length != chords.length) {
      return false;
    }
    for (int index = 0; index < chords.length; index++) {
      if (other.chords[index] != chords[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(sectionId, barIndex, bounds, Object.hashAll(chords));

  @override
  String toString() => 'PlacedBar($sectionId[$barIndex]) at $bounds';
}

/// One line of a page: the bars engraved side by side.
class PlacedSystem {
  /// Creates a system with the given [bounds], [bars] and optional section heading.
  const PlacedSystem({
    required this.bounds,
    required this.bars,
    this.sectionId,
    this.sectionLabel,
  });

  /// Where the system is drawn, including any section label above the stave.
  final LayoutRect bounds;

  /// The bars of the system, left to right.
  final List<PlacedBar> bars;

  /// The section this system begins, or null when it continues a section.
  ///
  /// A system begins a section or it does not; the engine always starts a new system at a
  /// section boundary, so a section is never split across the heading that names it.
  final String? sectionId;

  /// The label drawn above this system, or null when the system continues a section.
  final String? sectionLabel;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedSystem ||
        other.bounds != bounds ||
        other.sectionId != sectionId ||
        other.sectionLabel != sectionLabel ||
        other.bars.length != bars.length) {
      return false;
    }
    for (int index = 0; index < bars.length; index++) {
      if (other.bars[index] != bars[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(bounds, sectionId, sectionLabel, Object.hashAll(bars));

  @override
  String toString() =>
      'PlacedSystem(${bars.length} bar(s)${sectionLabel == null ? '' : ', "$sectionLabel"'})';
}

/// One page of engraved music.
class PageLayout {
  /// Creates a page with the given [index], page [size] and [systems].
  const PageLayout({
    required this.index,
    required this.size,
    required this.systems,
  });

  /// Zero-based page number.
  final int index;

  /// The page's extent, which is the size the caller asked for, not the extent of its content.
  final LayoutSize size;

  /// The systems on this page, top to bottom.
  final List<PlacedSystem> systems;

  /// Every bar on this page, in reading order.
  List<PlacedBar> get bars => <PlacedBar>[
    for (final PlacedSystem system in systems) ...system.bars,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! PageLayout ||
        other.index != index ||
        other.size != size ||
        other.systems.length != systems.length) {
      return false;
    }
    for (int index = 0; index < systems.length; index++) {
      if (other.systems[index] != systems[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(index, size, Object.hashAll(systems));

  @override
  String toString() =>
      'PageLayout($index, ${systems.length} system(s), ${bars.length} bar(s))';
}
