import 'package:flutter/material.dart';

import 'brand.dart';

/// LunarFlow typography.
///
/// The app shipped on stock Roboto with no `TextTheme` override at all. That
/// turns out to be the reason this file can exist as one edit: every screen
/// already reads a semantic role (`theme.textTheme.titleMedium` and friends),
/// with only a handful of raw `TextStyle` constructions in all of `lib/`. So
/// restyling the whole app happens here, not screen by screen.
///
/// Two families, matching the marketing site:
///   * **Public Sans** for everything you read.
///   * **Fraunces** for display and headline roles — the editorial note.
const String _body = 'PublicSans';
const String _display = 'Fraunces';

/// Fraunces is a variable font, and its non-weight axes are the whole point of
/// choosing it: `WONK` is what stops it reading as a stock serif, and pushing
/// `opsz` high gives large settings the wide, low-contrast cut instead of the
/// Didone-ish one the small optical size produces.
///
/// `wght` must be repeated here. Setting `fontVariations` replaces the axis
/// values the pubspec `weight:` entry would otherwise supply, so a style that
/// lists variations but omits `wght` silently renders at the font's default.
List<FontVariation> _fraunces({
  required double weight,
  required double opsz,
  required double soft,
}) =>
    [
      FontVariation('wght', weight),
      FontVariation('opsz', opsz),
      FontVariation('SOFT', soft),
      const FontVariation('WONK', 1),
    ];

/// Builds the app's text theme for [scheme].
///
/// Colour rule, and it is a WCAG constraint rather than a preference:
/// [Brand.rose] is 3.21:1 on the light page. That clears the 3:1 bar for LARGE
/// text (>=24px, or >=18.66px bold) and fails the 4.5:1 bar for everything
/// else. So rose is allowed on `display*` and `headline*`, whose smallest M3
/// size is 24px, and nowhere else. `titleLarge` is 22px at w400 and therefore
/// takes ink, serif face notwithstanding.
///
/// In dark mode rose reaches 5.28:1 and would be safe anywhere, but it stays on
/// the same roles so the two themes render the same hierarchy.
TextTheme buildTextTheme(ColorScheme scheme) {
  final typography = Typography.material2021();
  final base = (scheme.brightness == Brightness.light
          ? typography.black
          : typography.white)
      .apply(
    fontFamily: _body,
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  TextStyle serif(
    TextStyle? from, {
    required double weight,
    required double opsz,
    required double soft,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      (from ?? const TextStyle()).copyWith(
        fontFamily: _display,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: _fraunces(weight: weight, opsz: opsz, soft: soft),
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  return base.copyWith(
    // Display and headline: Fraunces, rose, tightened.
    displayLarge: serif(base.displayLarge,
        weight: 600,
        opsz: 120,
        soft: 24,
        color: Brand.rose,
        letterSpacing: -0.5,
        height: 1.04),
    displayMedium: serif(base.displayMedium,
        weight: 600,
        opsz: 120,
        soft: 24,
        color: Brand.rose,
        letterSpacing: -0.4,
        height: 1.06),
    displaySmall: serif(base.displaySmall,
        weight: 600,
        opsz: 72,
        soft: 20,
        color: Brand.rose,
        letterSpacing: -0.3,
        height: 1.1),
    headlineLarge: serif(base.headlineLarge,
        weight: 600,
        opsz: 48,
        soft: 20,
        color: Brand.rose,
        letterSpacing: -0.2,
        height: 1.15),
    headlineMedium: serif(base.headlineMedium,
        weight: 600,
        opsz: 40,
        soft: 18,
        color: Brand.rose,
        letterSpacing: -0.2,
        height: 1.2),
    headlineSmall: serif(base.headlineSmall,
        weight: 600,
        opsz: 32,
        soft: 18,
        color: Brand.rose,
        letterSpacing: -0.1,
        height: 1.25),

    // titleLarge is the screen-heading / app-bar role. Serif for continuity,
    // but INK: at 22px w400 it is not "large text" and rose would fail AA.
    titleLarge: serif(base.titleLarge,
        weight: 600, opsz: 24, soft: 16, color: scheme.onSurface, height: 1.3),

    // Everything below is Public Sans. Slightly more weight than Material's
    // defaults on the title/label roles, which reads better on a tinted ground.
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
    bodySmall: base.bodySmall?.copyWith(
      height: 1.4,
      color: scheme.onSurfaceVariant,
    ),
  );
}
