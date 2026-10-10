// PURPOSE: Draw the scene bar — the one line a musician reads on stage: where they are in the
//          playlist, how fast the tune is, what it is, what key it is being shown in, how many
//          repeats it carries, and whether the whole song is on one page. Every reading control
//          lives here so the performance surface has one place to look, and the key badge is the
//          handle that opens the twelve-key grid.
// INPUTS: The displayed position, the displayed song (already transposed for the screen), the
//         interval it was transposed by, the current page mode, the callbacks that open the key
//         grid and change the mode, and [SceneBar.compact] — whether this is the narrow form. The
//         caller decides that from the WINDOW width, because the bar itself is drawn in a pane
//         narrower than the window whenever the song list is a permanent column.
// OUTPUTS: A dark, high-contrast bar. In the full form it carries position, tempo, style, key,
//          repeats and the page-mode toggle, wrapping onto more lines rather than clipping or
//          scrolling. In the compact form it carries the four fields a performer reads off before
//          starting — position, tempo, the key badge (still the transpose handle) and the page-mode
//          toggle — and defers the two reference readings, STYLE and REPEATS, behind one `more`
//          control in the same bar. Nothing is removed from the widget tree without a control that
//          reaches it: the deferred menu shows both values and the STYLE row still opens the same
//          song-info sheet the full bar's STYLE field opens. The key badge's label is IDENTICAL in
//          both forms, because the reading is the reading and only its size changes.
// KEYWORDS: scene-bar, performance-surface, pos-over-n, bpm, style, key-badge, repeats,
//           fit-pages-toggle, dark-surface, arm-length, compact-form, deferred-fields
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
import 'package:flutter/material.dart';

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
const double sceneBarTabletWidth = 600;

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

  @override
  Widget build(BuildContext context) => Container(
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
      children: compact ? _compactFields() : _fullFields(),
    ),
  );

  /// The six readings of the full bar, which is what a tablet and a desktop get.
  ///
  /// The order is the order a performer reads them in: where they are, how fast, what it is, in
  /// what key, how many repeats, and whether the whole tune is on the page.
  List<Widget> _fullFields() => <Widget>[
    _Field(
      fieldKey: 'scene-bar-pos',
      caption: 'POS',
      value: '$position/$songCount',
    ),
    _separator(large: true),
    _Field(
      fieldKey: 'scene-bar-bpm',
      caption: 'BPM',
      value: song.tempo > 0 ? '${song.tempo}' : '—',
      onTap: onEditTempo,
    ),
    _separator(large: true),
    _Field(
      fieldKey: 'scene-bar-style',
      caption: 'STYLE',
      value: song.style.isEmpty ? '—' : song.style,
      onTap: onEditStyle,
    ),
    _separator(large: true),
    _KeyBadge(
      key: const ValueKey<String>('scene-bar-key-badge'),
      song: song,
      semitones: semitones,
      onTap: onOpenKeyGrid,
    ),
    _separator(large: true),
    _Field(
      fieldKey: 'scene-bar-repeat',
      caption: 'REPEATS',
      value: repeatSummary(song),
    ),
    _separator(large: true),
    _PageModeToggle(mode: pageMode, onChanged: onPageModeChanged),
  ];

  /// The four readings the compact bar keeps, plus the one control that reaches what it deferred.
  ///
  /// WHAT IS KEPT AND WHY. POS is why the musician opened this chart; BPM is the count-in; the key
  /// badge is the two-tap transposition of D9 and the single most-used control in the application;
  /// and the page-mode toggle changes how the tune is engraved, which is not something to hunt for
  /// while playing. WHAT IS DEFERRED: STYLE and REPEATS, both into [_DeferredFields], which states
  /// both values and keeps the STYLE row an edit entry to the same sheet the full field opens.
  List<Widget> _compactFields() => <Widget>[
    _Field(
      fieldKey: 'scene-bar-pos',
      caption: 'POS',
      value: '$position/$songCount',
      compact: true,
    ),
    _separator(large: false),
    _Field(
      fieldKey: 'scene-bar-bpm',
      caption: 'BPM',
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
    ),
    _separator(large: false),
    _PageModeToggle(
      mode: pageMode,
      onChanged: onPageModeChanged,
      compact: true,
    ),
    // No rule before the deferred-readings control: a separating line belongs between two VALUES,
    // and this stands beside the toggle as a control rather than as a reading of its own.
    _DeferredFields(
      style: song.style,
      repeats: repeatSummary(song),
      onEditStyle: onEditStyle,
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
/// [song] with no repeat sign at all returns `none`, so an absence is stated rather than shown as
/// an empty field.
String repeatSummary(Song song) {
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
    parts.add('$passages×');
  }
  if (voltas > 0) {
    parts.add('$voltas volta');
  }
  if (previousBars > 0) {
    parts.add('$previousBars %');
  }
  return parts.isEmpty ? 'none' : parts.join(' · ');
}

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
    this.compact = false,
  });

  /// The displayed song.
  final Song song;

  /// The interval from the written key.
  final int semitones;

  /// Called when the badge is pressed.
  final VoidCallback onTap;

  /// Whether this badge is drawn at the narrow form's smaller size.
  final bool compact;

  /// The badge label: the key and the interval a musician would say, in that order.
  ///
  /// The interval is always shown, including `+0 st` in the written key, because a musician thinks
  /// in both a key and a distance, and a hidden zero would make "written" and "moved" look alike.
  String get label => '${song.key} · ${semitones > 0 ? '+' : ''}$semitones st';

  @override
  Widget build(BuildContext context) => InkWell(
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
            compact ? 'KEY' : 'KEY · tap to transpose',
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
  });

  /// The style as the full bar would show it, which may be empty.
  final String style;

  /// The repeat summary as the full bar would show it, which is `none` when nothing is written.
  final String repeats;

  /// Called when the style row is picked, to open the song-info sheet on the style field.
  final VoidCallback onEditStyle;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey<String>('scene-bar-more'),
    tooltip: 'Style and repeats',
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
        child: Text('STYLE · ${style.isEmpty ? '—' : style}'),
      ),
      PopupMenuItem<String>(
        value: 'repeats',
        enabled: false,
        child: Text('REPEATS · $repeats'),
      ),
    ],
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
    this.compact = false,
  });

  /// The mode currently in force.
  final PageMode mode;

  /// Called with the other mode when it is picked.
  final ValueChanged<PageMode> onChanged;

  /// Whether this toggle is drawn at the narrow form's smaller size.
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('scene-bar-page-mode'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        'PAGE',
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
            text: 'FIT',
            active: mode == PageMode.fit,
            onTap: () => onChanged(PageMode.fit),
            compact: compact,
          ),
          _ModeButton(
            fieldKey: 'scene-bar-mode-pages',
            text: 'PAGES',
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
