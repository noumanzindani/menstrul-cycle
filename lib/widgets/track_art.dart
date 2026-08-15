import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A tinted, decorative SVG mark for a tracking chip.
///
/// A named wrapper rather than a bare [SvgPicture] on purpose: it keeps [path]
/// readable from the element tree, so a test can assert WHICH art rendered
/// (`tester.widget<TrackArt>(...).path`). An `SvgPicture` hides its asset
/// behind a `BytesLoader`, which would make the art assertable only as
/// "something is there".
///
/// ## Two rules this widget exists to enforce
///
/// **It is decorative and carries NO semantics.** `RawChip` already emits a
/// container `Semantics` node holding the label and the selected state, so a
/// `semanticsLabel` here makes TalkBack announce "Cramps Cramps". Nothing in
/// this repo could catch that: `find.text` matches only `Text`/`EditableText`,
/// never `Semantics(label:)`, and there are no golden tests and no CI. It has
/// to be prevented at the source, which is why [excludeFromSemantics] is passed
/// unconditionally rather than exposed as a parameter.
///
/// **It is recoloured, not merely drawn.** [ColorFilter.mode] with
/// [BlendMode.srcIn] repaints every drawn pixel in [color], which is what makes
/// one asset correct in both the light and dark themes without a second file or
/// a per-icon audit. The cost is that the artwork must be monochrome — a
/// multi-colour SVG silently flattens to a single tint.
class TrackArt extends StatelessWidget {
  const TrackArt({super.key, required this.path, this.color, this.size = 16});

  /// The asset path, from `option_art.dart`'s `artFor()` / `kFlowArt`.
  final String path;

  /// The ink colour, or null to INHERIT the surrounding label colour.
  ///
  /// Null is the normal case and the reason this widget needs no colour
  /// plumbing: `RawChip` wraps whatever is passed to `label:` in a
  /// `DefaultTextStyle` carrying its resolved label style, so reading that here
  /// — inside the label subtree — yields the exact colour the adjacent [Text]
  /// is painted in, already resolved for selected / unselected / disabled. The
  /// mark therefore tracks the chip's state for free, and cannot drift out of
  /// sync with the word beside it.
  ///
  /// Pass a colour only to deliberately depart from the label, as the flow row
  /// does.
  final Color? color;

  /// Kept at 16 by default and deliberately not larger: at 18+ the mark starts
  /// competing with the label rather than supporting it, and every chip in the
  /// row grows by the difference.
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink =
        color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}

/// Builds a chip label: the mark, a gap, then the text.
///
/// Lives in `label:` rather than the chip's `avatar:` slot, and that is the
/// whole reason this helper exists. `RawChip._paintSelectionOverlay` paints a
/// darkening scrim over the avatar and draws the selection checkmark on top of
/// it whenever `showCheckmark` is true — the Material 3 default for both
/// `FilterChip` and `ChoiceChip`, and `app_theme.dart`'s `ChipThemeData` sets
/// only `shape`, so nothing overrides it. Art in the avatar slot is therefore
/// obliterated in the SELECTED state: the one state the user just worked to
/// create, and the one a static screenshot never shows. Turning the checkmark
/// off to rescue the art would remove the only non-colour selection cue.
///
/// Putting the mark inside the label dissolves all of that — no scrim, the
/// checkmark survives, and the [Text] stays in the tree so every existing
/// `find.text(...)` assertion and every `tester.tap(find.text(...))` keeps
/// working.
///
/// [art] is routinely null (deliberate exclusions, art not yet drawn, unknown
/// keys); the chip then renders exactly as it always did — a bare [Text], not a
/// Row with an empty slot, so an undecorated group has no phantom gutter.
///
/// [artColor] departs from the inherited label colour; see [TrackArt.color].
Widget chipLabel(String label, String? art, {Color? artColor}) {
  if (art == null) return Text(label);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TrackArt(path: art, color: artColor),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
