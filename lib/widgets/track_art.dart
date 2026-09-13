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

  /// Kept at 16 by default and deliberately not larger FOR GLYPH ART: at 18+ a
  /// glyph starts competing with the label rather than supporting it, and every
  /// chip in the row grows by the difference. Raster marks scale this by
  /// [_rasterScale] — see there for why the same ceiling does not apply.
  final double size;

  /// How much larger a raster mark renders than a glyph at the same [size].
  ///
  /// A glyph is a single heavy shape and reads at 16. An illustration is a
  /// scene — a figure, a pose, colour — and at 16 it collapses into a coloured
  /// speck: legible as "something is there", not as what it depicts. The
  /// competing-with-the-label argument that caps glyphs also runs the other way
  /// here, because the whole reason to accept a raster mark is that the picture
  /// IS the content.
  ///
  /// The cost is not free: the chip row grows by `size * (scale - 1)`, and it
  /// grows for EVERY chip in the row, not just this one, because a Row sizes to
  /// its tallest child.
  static const double _rasterScale = 1.75;

  /// Whether [path] is a full-colour raster mark rather than a tintable SVG.
  ///
  /// Raster art is an OPT-OUT of everything the tint buys, so it is detected by
  /// extension rather than by a flag: the asset's own file type is the single
  /// source of truth, and an `.svg` cannot accidentally skip the recolour.
  bool get _isRaster => !path.endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    // A colour filter is deliberately NOT applied to raster art. srcIn repaints
    // every pixel one colour, which turns a full-colour illustration into a
    // featureless silhouette of its own alpha channel. The trade is real and
    // one-directional: raster marks do not follow the label colour, so they do
    // not adapt to the dark theme or dim with the chip's disabled state the way
    // every SVG mark does for free. Use SVG unless the artwork IS the point.
    if (_isRaster) {
      final rasterSize = size * _rasterScale;
      return Image.asset(
        path,
        width: rasterSize,
        height: rasterSize,
        fit: BoxFit.contain,
        // The mark is decorative; RawChip already announces the label. Same
        // reasoning as excludeFromSemantics on the SVG branch below.
        excludeFromSemantics: true,
      );
    }
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
Widget chipLabel(String label, String? art, {Color? artColor}) => art == null
    ? Text(label)
    : chipLabelArt(label, TrackArt(path: art, color: artColor));

/// [chipLabel] for art that is PAINTED rather than loaded -- the flow droplet.
///
/// Delegated to rather than duplicated so the 6px gap cannot drift between a
/// chip whose mark is an SVG and one whose mark is a [CustomPaint]; the flow row
/// sits directly beneath rows of the other kind.
Widget chipLabelArt(String label, Widget art) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      art,
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
