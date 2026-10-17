// PURPOSE: Draw the scene bar — the one line a musician reads on stage: where they are in the
//          playlist, how fast the tune is, what it is, what key it is being shown in, how many
//          repeats it carries, whether the whole song is on one page, and how far the chart is
//          magnified. Every reading control lives here so the performance surface has one place to
//          look, and the key badge is the handle that opens the twelve-key grid.
// INPUTS: The displayed position, the displayed song (already transposed for the screen), the
//         interval it was transposed by, the current page mode, the current view zoom, the callbacks
//         that open the key grid, change the mode and move the view, and [SceneBar.compact] —
//         whether this is the narrow form. The caller decides that from the WINDOW width, because
//         the bar itself is drawn in a pane narrower than the window whenever the song list is a
//         permanent column.
// OUTPUTS: A dark, high-contrast bar. In the full form it carries position, tempo, style, key,
//          repeats, the page-mode toggle and — when the caller supplies the view callbacks — the
//          zoom control, wrapping onto more lines rather than clipping or scrolling. In the compact
//          form it carries the four fields a performer reads off before starting — position, tempo,
//          the key badge (still the transpose handle) and the page-mode toggle — plus the zoom
//          control, and defers the two reference readings, STYLE and REPEATS, behind one `more`
//          control in the same bar. Nothing is removed from the widget tree without a control that
//          reaches it: the deferred menu shows both values and the STYLE row still opens the same
//          song-info sheet the full bar's STYLE field opens. The key badge's label is IDENTICAL in
//          both forms, because the reading is the reading and only its size changes.
// KEYWORDS: scene-bar, performance-surface, pos-over-n, bpm, style, key-badge, repeats,
//           fit-pages-toggle, zoom-control, dark-surface, arm-length, compact-form, deferred-fields
//
// WHY IT IS DARK AND LARGE. This is the surface a musician reads in a dark room from an arm's
// length away, so the bar carries its own colours instead of following the application theme, and
// no text is smaller than 16 logical pixels except the one-word captions. The chart page itself
// stays white: paper is what a chart page looks like, and this bar is chrome around it.
//
// WHY THE NARROW FORM DEFERS RATHER THAN SHRINKS EVERYTHING. A phone-width chart pane leaves about
// 400 logical pixels of width, and six captioned fields plus a bordered key badge do not fit one
// row there: the bar wraps to three or four rows and takes roughly half the screen (measured at
// 412x915, see the layout report). Shrinking every field until six fit would put the tempo and the
// key below the size this bar exists to be read at. The two fields that a performer does NOT need
// while playing are the two the chart itself already states: STYLE is written on the page's own
// header and is edited in the song-info sheet, and REPEATS is by definition what the repeat signs
// on the page say. They move one tap away; the four that are read at a glance stay.

import 'package:chart_core/chart_core.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file now
// names the musical one in [localizedKeyName]; its widget keys are all ValueKey, so nothing here
// needs Flutter's. Same rule as `key_grid.dart`.
import 'package:flutter/material.dart' hide Key;

import 'l10n/app_localizations.dart';

/// How a song is placed on the surface it is read on (owner decision D13).
enum PageMode {
  /// Every system of the song on one page, scaled down to fit.
  ///
  /// The default in the editor on a tablet: a whole tune on one screen is what a reader wants
  /// while working, and the fit reports honestly when the song is too long to stay legible.
  fit,

  /// The song paginated at the surface's own size, one page at a time.
  ///
  /// The default on a phone, where a fitted page of a long tune would be unreadable, and the
  /// scene default once a setlist exists.
  pages,
}

/// The dark background of the scene bar.
const Color sceneBarColor = Color(0xFF0B1622);

/// The colour of the scene bar's values.
const Color sceneBarTextColor = Color(0xFFF5F8FB);

/// The colour of the scene bar's small captions.
const Color sceneBarCaptionColor = Color(0xFF8FA8C0);

/// The accent used for the key badge and the active page mode.
const Color sceneBarAccent = Color(0xFFFFC857);

/// The width from which a surface counts as a tablet.
///
/// It decides three things and all three are the same question — "is this surface a tablet or a
/// phone": the default page mode (FIT at or above it, PAGES below), this bar's own form (the full
/// bar at or above it, the compact one below) and, in the viewer's shell, whether the tools sit in
/// the app bar or in a bottom dock. One number rather than three, because a surface that is a
/// tablet for one of them and a phone for another has no form of its own.
///
/// It is read against the WINDOW and never against the pane. The pane is the right measure for the
/// page mode — how wide the music is engraved is what decides whether a whole tune fits — but it is
/// the wrong measure for the form: the owner's tablet is 824 logical pixels of window against 564 of
/// pane, so a bar that called itself compact on a 564-pixel pane would drop STYLE and REPEATS on the
/// owner's own device. The form is a fact about the surface, and the surface is the window.
///
/// THE BAR'S FORM IS THE ONE DECISION THAT ALSO READS THE HEIGHT, through [sceneBarTabletHeight].
/// Width answers "is this surface narrow"; height answers "is it short", and a short surface is one
/// where the chart, not the fields, is what runs out of room. Neither shell form nor page-mode
/// default follows it there, because neither of those is a question about vertical room.
const double sceneBarTabletWidth = 600;

/// The height below which a surface is too short for the scene bar's full form.
///
/// The width threshold's sibling, and it decides ONE thing: whether this bar is compact. A surface
/// at least [sceneBarTabletWidth] wide but shorter than this cannot afford two rows of readings,
/// because those rows come out of the chart — and a chart pane shorter than one system
/// (`pageMargin` + `sectionLabelHeight` + `barHeight` = 98 logical pixels) cannot show a single
/// chord. Measured on the built web app at 915x412: the full bar left the pane **65** logical pixels,
/// so FIT could not fit and its paginated fallback had no room to show even one system's chord row;
/// the compact form returns about **85** of those pixels, which puts a whole system on screen.
///
/// It is deliberately NOT read for the shell form or the page-mode default. The shell is about where
/// a hand goes and the page mode is about how wide the music is engraved; this is about HEIGHT, and
/// height is the axis on which the chart runs out of room. Extending the width rule to a second axis
/// rather than carving an exception out of it is the point — see A49 for the measurement and A50 for
/// the FIT fallback the extra room makes useful.
const double sceneBarTabletHeight = 600;

/// The scene bar: position, tempo, style, key badge, repeats and the page-mode toggle.
class SceneBar extends StatelessWidget {
  /// Creates a scene bar for one displayed song.
  ///
  /// [compact] selects the narrow form, which keeps the four fields a performer reads off before
  /// starting and defers STYLE and REPEATS into one control in the same bar. It is passed in rather
  /// than measured, because the bar's own width is the pane width and the pane width is not the
  /// question [sceneBarTabletWidth] answers — see the constant's own note. It defaults to false, so
  /// a caller that does not know about the two forms gets the bar this widget has always drawn.
  const SceneBar({
    super.key,
    required this.position,
    required this.songCount,
    required this.song,
    required this.semitones,
    required this.pageMode,
    required this.onOpenKeyGrid,
    required this.onPageModeChanged,
    required this.onEditTempo,
    required this.onEditStyle,
    this.compact = false,
    this.zoom = 1,
    this.zoomLocked = false,
    this.onToggleZoomLock,
    this.onZoomIn,
    this.onZoomOut,
    this.onZoomReset,
  });

  /// Whether this bar is the narrow form: four readings and a control, instead of six.
  final bool compact;

  /// The displayed song's one-based position in the loaded playlist.
  final int position;

  /// How many songs the loaded playlist holds.
  final int songCount;

  /// The song as displayed, already transposed, whose key, tempo and style are shown.
  final Song song;

  /// The interval from the written key that produced [song], in semitones.
  final int semitones;

  /// The page mode currently in force.
  final PageMode pageMode;

  /// Called when the key badge is pressed, to open the twelve-key grid.
  final VoidCallback onOpenKeyGrid;

  /// Called when the musician picks the other page mode.
  final ValueChanged<PageMode> onPageModeChanged;

  /// Called when the BPM field is pressed, to edit the tempo where it is read.
  ///
  /// The tempo and the style are the two facts in this bar a musician changes while working, and
  /// they are displayed here rather than inside a menu, so the edit belongs here too: a field that
  /// shows a value and cannot change it is text, not a control.
  final VoidCallback onEditTempo;

  /// Called when the STYLE field is pressed, to edit the style where it is read.
  final VoidCallback onEditStyle;

  /// The magnification the chart is currently shown at, where 1 is the page mode's own view.
  ///
  /// It is a READING as well as a handle: the number is the only thing that tells a musician who
  /// has pinched the chart that he is looking at it through a zoom rather than at a chart that has
  /// changed. It never falls below 1, because at 1 the page already fills the pane.
  final double zoom;

  /// Whether the scale is FIXED, which greys the two step controls and the reset.
  ///
  /// The lock itself is the caller's state; this bar only reports it and stops answering for what it
  /// covers. A control that is refused without saying so is the defect the whole application avoids —
  /// the three buttons stay exactly where they are and stop answering, which is what a fixed scale
  /// means when it is drawn.
  final bool zoomLocked;

  /// Called to fix the scale or release it, or null on a bar that draws no zoom control.
  ///
  /// The lock stands beside the scale it locks, because that is where a musician looks when he wants
  /// the number to stop moving. It is ALSO drawn in the always-visible bars of the shell: the scene
  /// bar is what the chrome hides, and a lock whose state is only visible while everything else is
  /// visible is a lock he cannot tell is on.
  final VoidCallback? onToggleZoomLock;

  /// Called to magnify the chart one step, or null on a bar that draws no zoom control.
  ///
  /// The whole control is drawn only when [onZoomReset] is non-null, so a caller that builds a bar
  /// for one field — a widget test, a render harness — gets exactly the bar it built before the view
  /// existed. That is deliberate: the zoom belongs to the VIEWER's state, and a bar constructed
  /// without it has no view to change.
  final VoidCallback? onZoomIn;

  /// Called to shrink the chart one step, or null when no zoom control is drawn.
  final VoidCallback? onZoomOut;

  /// Called to return the chart to its page mode's own view, or null when none is drawn.
  ///
  /// This is the "how he gets back" control of D33: after a two-finger pan the musician has no
  /// scrollbar and no edges in view, so the way back to a known place has to be a named control.
  final VoidCallback? onZoomReset;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      key: const ValueKey<String>('scene-bar'),
      color: sceneBarColor,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 8,
      ),
      child: Wrap(
        spacing: compact ? 6 : 16,
        runSpacing: compact ? 4 : 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: compact ? _compactFields(l10n) : _fullFields(l10n),
      ),
    );
  }

  /// The six readings of the full bar, which is what a tablet and a desktop get.
  ///
  /// The order is the order a performer reads them in: where they are, how fast, what it is, in
  /// what key, how many repeats, and whether the whole tune is on the page.
  List<Widget> _fullFields(AppLocalizations l10n) => <Widget>[
    _Field(
      fieldKey: 'scene-bar-pos',
      caption: l10n.sceneCaptionPos,
      value: '$position/$songCount',
    ),
    _separator(large: true),
    _Field(
      fieldKey: 'scene-bar-bpm',
      caption: l10n.sceneCaptionBpm,
      value: song.tempo > 0 ? '${song.tempo}' : '—',
      onTap: onEditTempo,
    ),
    _separator(large: true),
    _Field(
      fieldKey: 'scene-bar-style',
      caption: l10n.sceneCaptionStyle,
      value: song.style.isEmpty ? '—' : song.style,
      onTap: onEditStyle,
    ),
    _separator(large: true),
    _KeyBadge(
      key: const ValueKey<String>('scene-bar-key-badge'),
      song: song,
      semitones: semitones,
      onTap: onOpenKeyGrid,
      l10n: l10n,
    ),
    _separator(large: true),
    _Field(
      fieldKey: 'scene-bar-repeat',
      caption: l10n.sceneCaptionRepeats,
      value: repeatSummary(song, l10n),
    ),
    _separator(large: true),
    _PageModeToggle(mode: pageMode, onChanged: onPageModeChanged, l10n: l10n),
    if (onZoomReset != null)
      _ZoomControl(
        zoom: zoom,
        locked: zoomLocked,
        onToggleLock: onToggleZoomLock,
        onZoomIn: onZoomIn,
        onZoomOut: onZoomOut,
        onReset: onZoomReset!,
        l10n: l10n,
      ),
  ];

  /// The four readings the compact bar keeps, plus the one control that reaches what it deferred.
  ///
  /// WHAT IS KEPT AND WHY. POS is why the musician opened this chart; BPM is the count-in; the key
  /// badge is the two-tap transposition of D9 and the single most-used control in the application;
  /// and the page-mode toggle changes how the tune is engraved, which is not something to hunt for
  /// while playing. WHAT IS DEFERRED: STYLE and REPEATS, both into [_DeferredFields], which states
  /// both values and keeps the STYLE row an edit entry to the same sheet the full field opens.
  List<Widget> _compactFields(AppLocalizations l10n) => <Widget>[
    _Field(
      fieldKey: 'scene-bar-pos',
      caption: l10n.sceneCaptionPos,
      value: '$position/$songCount',
      compact: true,
    ),
    _separator(large: false),
    _Field(
      fieldKey: 'scene-bar-bpm',
      caption: l10n.sceneCaptionBpm,
      value: song.tempo > 0 ? '${song.tempo}' : '—',
      onTap: onEditTempo,
      compact: true,
    ),
    _separator(large: false),
    _KeyBadge(
      key: const ValueKey<String>('scene-bar-key-badge'),
      song: song,
      semitones: semitones,
      onTap: onOpenKeyGrid,
      compact: true,
      l10n: l10n,
    ),
    _separator(large: false),
    _PageModeToggle(
      mode: pageMode,
      onChanged: onPageModeChanged,
      compact: true,
      l10n: l10n,
    ),
    if (onZoomReset != null)
      _ZoomControl(
        zoom: zoom,
        locked: zoomLocked,
        onToggleLock: onToggleZoomLock,
        onZoomIn: onZoomIn,
        onZoomOut: onZoomOut,
        onReset: onZoomReset!,
        compact: true,
        l10n: l10n,
      ),
    // No rule before the deferred-readings control: a separating line belongs between two VALUES,
    // and this stands beside the toggle as a control rather than as a reading of its own.
    _DeferredFields(
      style: song.style,
      repeats: repeatSummary(song, l10n),
      onEditStyle: onEditStyle,
      l10n: l10n,
    ),
  ];

  /// The thin rule between two fields, so the eye separates values without a heavy border.
  ///
  /// [large] is the full bar's height; the compact form uses a shorter rule so it does not make its
  /// own row taller than the fields standing on it.
  Widget _separator({required bool large}) => Container(
    width: 1,
    height: large ? 34 : 20,
    color: const Color(0xFF24405C),
  );
}

/// The summary of the repeats and alternative endings a song carries.
///
/// A musician standing in front of a chart wants to know before starting whether the tune repeats
/// and how many endings there are. The count is of the bars that START a repeated passage, the
/// brackets drawn, and the `%` bars, which is what can be seen on the page; expanding the passage
/// into a play order is a different question the model does not yet answer.
///
/// [song] with no repeat sign at all returns the catalogue's word for "none", so an absence is
/// stated rather than shown as an empty field.
///
/// [l10n] IS REQUIRED AND NOT OPTIONAL. Two of the three segments are written words — the word for
/// "none" and the word for an alternative ending — and the ending count takes a Russian plural the
/// English one does not ("1 вольта", "2 вольты", "5 вольт"). A default would have to be an English
/// catalogue, which is a second source of English text living beside the first; the four callers
/// all have a context and pass one. The two tests that call this directly pass the English
/// catalogue explicitly, which is exactly the fact they are asserting.
String repeatSummary(Song song, AppLocalizations l10n) {
  int passages = 0;
  int voltas = 0;
  int previousBars = 0;
  for (final Section section in song.sections) {
    for (final Bar bar in section.bars) {
      if (bar.startsRepeat) {
        passages++;
      }
      if (bar.volta != null) {
        voltas++;
      }
      if (bar.repeatPrevious != RepeatPrevious.none) {
        previousBars++;
      }
    }
  }
  final List<String> parts = <String>[];
  if (passages > 0) {
    parts.add(l10n.repeatPassages(passages));
  }
  if (voltas > 0) {
    parts.add(l10n.repeatVoltas(voltas));
  }
  if (previousBars > 0) {
    parts.add(l10n.repeatPrevious(previousBars));
  }
  return parts.isEmpty ? l10n.repeatNone : parts.join(' · ');
}

/// Names [key] for a musician, with [l10n] supplying the word for its mode.
///
// PURPOSE: Name a key for a musician, so that the key badge, the song list and the twelve-key grid
//          all say the same words about the same key.
// INPUTS: l10n — the catalogue. key — the key to name.
// OUTPUTS: The key's own letter name followed by the catalogue's word for its mode, such as
//          `D major` in English and `D мажор` in Russian.
// KEYWORDS: key-name, localization, one-definition, tonic-letters, mode-word
//
// WHY THE LETTER IS NOT TRANSLATED AND THE MODE WORD IS. A chord chart writes chord roots in Latin
// letters — `D`, `Eb`, `F#` — in every language, because that is the notation rather than a word: a
// key badge reading `Ре мажор` would name a note the page beside it does not contain. The mode,
// by contrast, IS a word, and it is the half a Russian reader needs in Russian.
//
// WHY THIS IS NOT `key.toString()`. `Key.toString()` exists for spike logs and test failure
// messages (it says so itself in `chart_core`), and `chart_core` is deliberately free of both
// Flutter and a translation catalogue. Translation belongs on this side of that boundary, so the
// interface builds its own name from the key's public parts.
String localizedKeyName(AppLocalizations l10n, Key key) =>
    key.mode == Mode.major
    ? l10n.keyNameMajor('${key.tonic}')
    : l10n.keyNameMinor('${key.tonic}');

/// Writes the signed interval [semitones] with the unit [l10n] abbreviates it by.
///
// PURPOSE: Write a signed interval in semitones the way a musician reads it, so the key badge and
//          the twelve-key grid cannot abbreviate the unit differently.
// INPUTS: l10n — the catalogue. semitones — the signed interval from the written key.
// OUTPUTS: A signed number followed by the catalogue's unit, such as `+2 st` in English and
//          `+2 пт` in Russian.
// KEYWORDS: interval, label, semitones, one-definition, abbreviation
String localizedSemitoneInterval(AppLocalizations l10n, int semitones) =>
    l10n.semitonesShort('${semitones > 0 ? '+' : ''}$semitones');

/// One captioned value in the bar, pressable when the value it shows can be changed here.
class _Field extends StatelessWidget {
  /// Creates a field with a [caption] above its [value], carrying [fieldKey] for tests.
  ///
  /// [onTap] makes the field a control: the reading is then also the handle that edits it, which is
  /// what keeps a musician from hunting a menu for a value they can already see. A field without
  /// one is a reading and stays plain text, so the two are told apart by whether the bar reacts.
  /// [compact] selects the smaller type the narrow form uses, which is a size and NOT a different
  /// reading: the caption and the value are the same strings in both forms.
  const _Field({
    required this.fieldKey,
    required this.caption,
    required this.value,
    this.onTap,
    this.compact = false,
  });

  /// The value.
  final String value;

  /// The one-word caption above it.
  final String caption;

  /// The widget key the tests find this field by.
  final String fieldKey;

  /// What a press does, or null when this value cannot be changed from the bar.
  final VoidCallback? onTap;

  /// Whether this field is drawn at the narrow form's smaller size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget reading = Column(
      key: ValueKey<String>(fieldKey),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          caption,
          style: TextStyle(
            color: sceneBarCaptionColor,
            fontSize: compact ? 9 : 11,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: sceneBarTextColor,
            fontSize: compact ? 15 : 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    if (onTap == null) {
      return reading;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: reading,
      ),
    );
  }
}

/// The key the chart is shown in, and the handle that opens the twelve-key grid.
class _KeyBadge extends StatelessWidget {
  /// Creates a badge for [song] shown at [semitones] from the written key.
  ///
  /// [compact] shrinks the badge for the narrow form and also shortens its one-word caption, which
  /// is the only text on it that is not a reading. The label itself — the key and the interval —
  /// is byte for byte the same string in both forms, because that is what the musician reads and
  /// what the key-grid test asserts.
  const _KeyBadge({
    super.key,
    required this.song,
    required this.semitones,
    required this.onTap,
    required this.l10n,
    this.compact = false,
  });

  /// The displayed song.
  final Song song;

  /// The interval from the written key.
  final int semitones;

  /// Called when the badge is pressed.
  final VoidCallback onTap;

  /// The catalogue, used for the caption and the unit on the interval.
  final AppLocalizations l10n;

  /// Whether this badge is drawn at the narrow form's smaller size.
  final bool compact;

  /// The badge label: the key and the interval a musician would say, in that order.
  ///
  /// The interval is always shown, including `+0 st` in the written key, because a musician thinks
  /// in both a key and a distance, and a hidden zero would make "written" and "moved" look alike.
  String get label => l10n.keyBadgeLabel(
    localizedKeyName(l10n, song.key),
    localizedSemitoneInterval(l10n, semitones),
  );

  @override
  Widget build(BuildContext context) => Tooltip(
    // THE INSTRUCTION THE CAPTION USED TO CARRY, moved into the tooltip. The full form's caption
    // read «ТОН. · коснитесь, чтобы транспонировать», which is a sentence in the place every other
    // field has one word — and it was long enough to wrap the whole bar onto a second row at the
    // owner's tablet width (measured: the scene bar 141 logical pixels tall instead of 56). The
    // gesture is still named, where a reader who does not know it can find it, and the reading keeps
    // the one word every other reading has.
    message: l10n.keyBadgeTooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sceneBarAccent, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              compact ? l10n.sceneCaptionKeyCompact : l10n.sceneCaptionKeyFull,
              style: TextStyle(
                color: sceneBarCaptionColor,
                fontSize: compact ? 9 : 11,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: sceneBarAccent,
                fontSize: compact ? 16 : 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The two readings the compact bar defers, behind one control in the bar itself.
///
/// WHY THEY ARE STATED RATHER THAN HIDDEN. Deferring a reading is not deleting it: the menu shows
/// the style and the repeat summary as the full bar would, and the style row is still the edit
/// entry — picking it opens the same song-info sheet, focused on the same field, that pressing the
/// full bar's STYLE field opens. The repeats row is disabled because the repeat summary is a
/// reading and not a control anywhere: there has never been a way to change it from this bar.
class _DeferredFields extends StatelessWidget {
  /// Creates the deferred-readings control for [style] and [repeats].
  ///
  /// [onEditStyle] is called when the style row is picked. The widget carries no key of its own:
  /// the key a test or a driving tool finds it by is on the [PopupMenuButton] inside it.
  const _DeferredFields({
    required this.style,
    required this.repeats,
    required this.onEditStyle,
    required this.l10n,
  });

  /// The style as the full bar would show it, which may be empty.
  final String style;

  /// The repeat summary as the full bar would show it, which is the word for "none" when nothing
  /// is written.
  final String repeats;

  /// Called when the style row is picked, to open the song-info sheet on the style field.
  final VoidCallback onEditStyle;

  /// The catalogue, used for the tooltip and the two row captions.
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey<String>('scene-bar-more'),
    tooltip: l10n.sceneDeferredTooltip,
    icon: const Icon(Icons.more_horiz, color: sceneBarTextColor, size: 20),
    // The default padding of a menu button reserves a 48-pixel touch target, which is more width
    // than the narrow bar can spend on a control that is not a reading. It is pulled in to the same
    // size as the fields standing beside it: this bar is read at arm's length, not tapped blind.
    padding: EdgeInsets.zero,
    onSelected: (String picked) {
      if (picked == 'style') {
        onEditStyle();
      }
    },
    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'style',
        child: Text(l10n.sceneDeferredStyleRow(style.isEmpty ? '—' : style)),
      ),
      PopupMenuItem<String>(
        value: 'repeats',
        enabled: false,
        child: Text(l10n.sceneDeferredRepeatsRow(repeats)),
      ),
    ],
  );
}

/// The zoom control: one step out, the current magnification (which is also the reset), one step in,
/// and the lock that fixes all three.
///
/// WHY IT IS HERE AND NOT IN A MENU. D33 asks for a zoom reachable through the interface beside the
/// touch gesture, and D34 gives the GESTURE to two fingers — but two fingers are also how the page
/// is turned, and a musician who has pinched the chart has no scrollbar and no page edges on screen
/// to tell him where he is. The reset has to be visible and named, and a reading that cannot be
/// corrected where it is read is text rather than a control. The three keys are the same keys in both
/// forms of the bar, because the view is not a reading the narrow form may defer: it is the state
/// the chart under the bar is drawn in.
class _ZoomControl extends StatelessWidget {
  /// Creates the control for [zoom].
  const _ZoomControl({
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.l10n,
    this.locked = false,
    this.onToggleLock,
    this.compact = false,
  });

  /// The magnification in force, at or above 1.
  final double zoom;

  /// Whether the scale is fixed, which greys this control's three buttons.
  final bool locked;

  /// Called to fix the scale or release it, or null when this bar draws no lock.
  final VoidCallback? onToggleLock;

  /// Called by the `+` half, or null when the bar was built without one.
  final VoidCallback? onZoomIn;

  /// Called by the `−` half, or null when the bar was built without one.
  final VoidCallback? onZoomOut;

  /// Called by the middle, which returns the view to the page mode's own.
  final VoidCallback onReset;

  /// The catalogue, for the caption and the tooltips.
  final AppLocalizations l10n;

  /// Whether this control is drawn at the narrow form's smaller size.
  final bool compact;

  /// The number a musician reads: the magnification, written as notation rather than as a word.
  ///
  /// A `×` and a number are the same in every language (owner decision D27), so this is deliberately
  /// NOT a catalogue entry: translating it would be translating arithmetic. One decimal is shown
  /// below 2 and one above it too, so the label is the same shape at every step and `×1.0` and `×4.0`
  /// are read the same way.
  String get label => '×${zoom.toStringAsFixed(1)}';

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('scene-bar-zoom'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        l10n.sceneCaptionZoom,
        style: TextStyle(
          color: sceneBarCaptionColor,
          fontSize: compact ? 9 : 11,
          letterSpacing: 1.2,
        ),
      ),
      Row(
        // SHRINK-WRAPPED for the same reason the page-mode toggle is: a `Row` inside the bar's
        // `Wrap` defaults to `MainAxisSize.max` and would claim the whole bar, pushing everything
        // after it onto a line of its own.
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // THE THREE BUTTONS STOP ANSWERING, THEY DO NOT DISAPPEAR. A fixed scale is a state in
          // which these three cannot do anything; a control that vanished would move the lock, which
          // stands next to them, and a musician's hand would learn a bar whose shape changes with a
          // mode. Greyed and in place, they say "the scale is fixed" without a word.
          _ZoomButton(
            fieldKey: 'scene-bar-zoom-out',
            glyph: '−',
            tooltip: locked ? l10n.zoomLockedTooltip : l10n.zoomOutTooltip,
            onTap: locked ? null : onZoomOut,
            compact: compact,
          ),
          _ZoomButton(
            fieldKey: 'scene-bar-zoom-reset',
            glyph: label,
            tooltip: locked ? l10n.zoomLockedTooltip : l10n.zoomResetTooltip,
            onTap: locked ? null : onReset,
            compact: compact,
          ),
          _ZoomButton(
            fieldKey: 'scene-bar-zoom-in',
            glyph: '+',
            tooltip: locked ? l10n.zoomLockedTooltip : l10n.zoomInTooltip,
            onTap: locked ? null : onZoomIn,
            compact: compact,
          ),
          // THE LOCK ITSELF, beside the number it fixes. Its own colour carries the state: accent for
          // fixed, the bar's ordinary ink for free.
          if (onToggleLock != null)
            _ZoomButton(
              fieldKey: 'scene-bar-zoom-lock',
              glyph: locked ? '🔒' : '🔓',
              tooltip: locked
                  ? l10n.tooltipViewLockOn
                  : l10n.tooltipViewLockOff,
              onTap: onToggleLock,
              compact: compact,
              selected: locked,
            ),
        ],
      ),
    ],
  );
}

/// One button of the zoom control.
class _ZoomButton extends StatelessWidget {
  /// Creates a button showing [glyph], with a [tooltip] and an [onTap].
  const _ZoomButton({
    required this.fieldKey,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    required this.compact,
    this.selected = false,
  });

  /// The widget key the tests and the driving harness find this button by.
  final String fieldKey;

  /// The one or two characters drawn on it: a sign, or the magnification itself.
  final String glyph;

  /// What the button does, said in words for a reader who cannot see the glyph.
  final String tooltip;

  /// What a press does, or null when this half is not offered at this zoom.
  final VoidCallback? onTap;

  /// Whether this button is drawn at the narrow form's smaller size.
  final bool compact;

  /// Whether this button shows a state rather than only an action.
  ///
  /// True for the lock while the view is fixed: the accent fill is the same signal the page-mode
  /// toggle uses for its active half, so "this is on" looks the same wherever it is drawn.
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      key: ValueKey<String>(fieldKey),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10,
          vertical: compact ? 3 : 6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected ? sceneBarAccent : null,
          border: Border.all(
            color: selected
                ? sceneBarAccent
                : (onTap == null ? sceneBarCaptionColor : sceneBarAccent),
            width: 1.5,
          ),
        ),
        child: Text(
          glyph,
          style: TextStyle(
            color: selected
                ? sceneBarColor
                : (onTap == null ? sceneBarCaptionColor : sceneBarTextColor),
            fontSize: compact ? 13 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// The FIT | PAGES control.
class _PageModeToggle extends StatelessWidget {
  /// Creates a toggle showing [mode] and reporting picks to [onChanged].
  ///
  /// [compact] selects the narrow form's smaller buttons and shorter caption. The control and its
  /// two keys are the same widget in both forms: the page mode is not a reading that can be
  /// deferred, because it decides how the chart under the bar is engraved.
  const _PageModeToggle({
    required this.mode,
    required this.onChanged,
    required this.l10n,
    this.compact = false,
  });

  /// The mode currently in force.
  final PageMode mode;

  /// Called with the other mode when it is picked.
  final ValueChanged<PageMode> onChanged;

  /// The catalogue, used for the caption and the two button labels.
  final AppLocalizations l10n;

  /// Whether this toggle is drawn at the narrow form's smaller size.
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('scene-bar-page-mode'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        l10n.sceneCaptionPage,
        style: TextStyle(
          color: sceneBarCaptionColor,
          fontSize: compact ? 9 : 11,
          letterSpacing: 1.2,
        ),
      ),
      Row(
        // SHRINK-WRAPPED, AND THAT IS A FIX RATHER THAN A STYLE CHOICE. This Row stands inside the
        // bar's `Wrap`, and a Row's default `MainAxisSize.max` expands to whatever width the parent
        // offers — so this control alone claimed the WHOLE bar and pushed every field after it onto
        // a line of its own, on a phone and on a tablet alike. Measured at 412 logical pixels of
        // window: the bar was three rows (POS/BPM/KEY, then PAGE, then the deferred-readings
        // control) with most of the second and third row empty. With `min`, the same control is as
        // wide as its two buttons and the bar is one row.
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ModeButton(
            fieldKey: 'scene-bar-mode-fit',
            text: l10n.sceneModeFit,
            active: mode == PageMode.fit,
            onTap: () => onChanged(PageMode.fit),
            compact: compact,
          ),
          _ModeButton(
            fieldKey: 'scene-bar-mode-pages',
            text: l10n.sceneModePages,
            active: mode == PageMode.pages,
            onTap: () => onChanged(PageMode.pages),
            compact: compact,
          ),
        ],
      ),
    ],
  );
}

/// One half of the page-mode toggle.
class _ModeButton extends StatelessWidget {
  /// Creates a button labelled [text], active when [active], calling [onTap] when pressed.
  ///
  /// [compact] selects the narrow form's smaller label and padding.
  const _ModeButton({
    required this.fieldKey,
    required this.text,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  /// The label.
  final String text;

  /// Whether this is the mode in force.
  final bool active;

  /// Called when the button is pressed.
  final VoidCallback onTap;

  /// The widget key the tests find this button by.
  final String fieldKey;

  /// Whether this button is drawn at the narrow form's smaller size.
  final bool compact;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey<String>(fieldKey),
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: active ? sceneBarAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? sceneBarAccent : sceneBarCaptionColor,
          width: 1.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? sceneBarColor : sceneBarTextColor,
          fontSize: compact ? 13 : 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
