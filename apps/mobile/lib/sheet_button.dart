// PURPOSE: Be the one button every modal edit sheet draws, so the form sheet and the text-cue sheet
//          cannot drift into two looks for one gesture. A button whose colours, padding, corner
//          radius and key convention are copied between two files is two buttons the first time one
//          of them is touched, and a musician learns the shape of a control rather than reading it.
// INPUTS: A widget key, an icon, a label, what a press does, whether the operation removes
//         something, and whether the selected thing already carries what the button sets.
// OUTPUTS: A tappable panel-coloured button. A null [onTap] draws the button DIMMED AND DEAD rather
//          than hiding it, so a row of controls keeps its shape and a musician can see that an
//          operation exists and is not available here. A null [active] and an [active] of false
//          draw the same thing: the button is not showing a chosen state.
// KEYWORDS: sheet-button, shared-style, icon-and-label, disabled-dim, danger-colour, active-state
//
// WHY THE LABEL CARRIES THE STATE. Several of these buttons are toggles or cycles — a repeat
// barline that is either there or not, a `%` that steps through three symbols — and a button that
// said only what it DOES would make a musician press it to find out what IS. The label therefore
// names the state for those, and [active] marks it in colour; the caller decides which.
import 'package:flutter/material.dart';

import 'sheet_surface.dart';

/// The colour of a destructive action's label, so a removal is not one slip of a thumb away from
/// looking like the harmless controls beside it.
const Color _dangerColor = Color(0xFFFF8A80);

/// One operation button in a modal edit sheet.
class SheetButton extends StatelessWidget {
  /// Creates a button labelled [label] that calls [onTap], or does nothing when [onTap] is null.
  ///
  /// [danger] colours the label as a removal. [active] marks a button whose operation the selected
  /// thing already carries — a repeat barline that is already there, a bracket that is already
  /// drawn — and is drawn as a chosen state rather than as a second label.
  const SheetButton({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.active = false,
  });

  /// The widget key the tests and the driving tools find this button by.
  ///
  /// A [String] rather than a [Key] because every caller in this application builds a
  /// `ValueKey<String>` from it, and passing the string keeps the key's type and its text in one
  /// place instead of two.
  final String buttonKey;

  /// The glyph beside the label.
  final IconData icon;

  /// The words on the button, which name the operation and, on a toggle, the state it is in.
  final String label;

  /// What a press does, or null when the operation is not available right now.
  final VoidCallback? onTap;

  /// Whether this button removes something.
  final bool danger;

  /// Whether the selected thing already carries what this button sets.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color foreground = !enabled
        ? sheetMutedColor
        : (danger
              ? _dangerColor
              : (active ? sheetAccentColor : sheetOnPanelColor));
    return Material(
      color: enabled
          ? (active ? sheetSelectedCellColor : sheetCellColor)
          : sheetCellColor.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey<String>(buttonKey),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
