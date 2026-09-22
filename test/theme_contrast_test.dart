import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/theme/brand.dart';

/// WCAG 2.1 contrast guards for the LunarFlow palette.
///
/// This file exists because the brand brief, taken literally, is not
/// accessible: NOT ONE of the seven colours it names reaches 4.5:1 against the
/// background it also names. `Brand.rose` — the colour the brief nominates for
/// "important typography" — is 3.21:1, which is a heading, not body text.
///
/// The theme therefore derives `Brand.deep` and `Brand.ink` to carry the load.
/// These tests assert the pairings that decision rests on, reading them off the
/// REAL [ThemeData] rather than off [Brand], so that re-pointing a ColorScheme
/// role in `app_theme.dart` is caught here too.
///
/// Bars used:
///   4.5:1  normal-size text                       (WCAG 1.4.3 AA)
///   3.0:1  large text, and the boundary of any UI
///          component or state you must be able to
///          identify                               (WCAG 1.4.3 / 1.4.11)
void main() {
  group('LunarFlow light theme', () {
    final scheme = AppTheme.light().colorScheme;

    test('body text clears AA on the page and on a card', () {
      expectContrast(scheme.onSurface, scheme.surface, atLeast: 4.5);
      expectContrast(scheme.onSurface, scheme.surfaceContainerLow,
          atLeast: 4.5);
    });

    test('secondary text clears AA on the page and on a card', () {
      expectContrast(scheme.onSurfaceVariant, scheme.surface, atLeast: 4.5);
      expectContrast(scheme.onSurfaceVariant, scheme.surfaceContainerLow,
          atLeast: 4.5);
    });

    test('a filled primary button can carry its own label', () {
      expectContrast(scheme.onPrimary, scheme.primary, atLeast: 4.5);
    });

    test('primary works as a hairline: outlines, focus rings, today marker', () {
      // calendar_screen.dart draws `Border.all(color: scheme.primary)` around
      // today, and month_ring.dart paints today's dots in it. A 1-2dp mark has
      // to clear the UI-component bar against the page it sits on.
      expectContrast(scheme.primary, scheme.surface, atLeast: 3.0);
    });

    test('the FAB label clears AA on the brand pink', () {
      expectContrast(scheme.onPrimaryContainer, scheme.primaryContainer,
          atLeast: 4.5);
    });

    test('the FAB has an identifiable edge despite a low-contrast fill', () {
      // Brand.pink is deliberately only ~2.1:1 on the page — it is a surface
      // colour, not an accent that can hold an edge. The app is flat (elevation
      // 0 everywhere, zero BoxShadow), so nothing else supplies that boundary.
      // floatingActionButtonTheme adds a `primary` outline; this asserts the
      // outline is still doing its job.
      final fab = AppTheme.light().floatingActionButtonTheme;
      final shape = fab.shape as RoundedRectangleBorder;
      expect(shape.side.style, BorderStyle.solid,
          reason: 'the FAB outline is load-bearing for contrast');
      expectContrast(shape.side.color, scheme.surface, atLeast: 3.0);
      expect(contrast(fab.backgroundColor!, scheme.surface), lessThan(3.0),
          reason: 'if the fill ever clears 3:1 on its own, drop the outline');
    });

    test('nav pill and selected chips carry readable labels', () {
      expectContrast(scheme.onSecondaryContainer, scheme.secondaryContainer,
          atLeast: 4.5);
    });

    test('the recessed tint stays readable', () {
      // surfaceContainerHighest is this app's *recessed* fill — text-field
      // backgrounds, the disclaimer strip, unselected option chips.
      expectContrast(scheme.onSurface, scheme.surfaceContainerHighest,
          atLeast: 4.5);
    });

    test('cards read as lifted, not recessed', () {
      // The inversion is deliberate and easy to undo by accident: a blush page
      // with cards LIGHTER than it.
      expect(
        scheme.surfaceContainerLow.computeLuminance(),
        greaterThan(scheme.surface.computeLuminance()),
        reason: 'cards must sit above the page, not below it',
      );
    });
  });

  group('LunarFlow dark theme', () {
    final scheme = AppTheme.dark().colorScheme;

    test('body and secondary text clear AA', () {
      expectContrast(scheme.onSurface, scheme.surface, atLeast: 4.5);
      expectContrast(scheme.onSurfaceVariant, scheme.surface, atLeast: 4.5);
    });

    test('a filled primary button can carry its own label', () {
      expectContrast(scheme.onPrimary, scheme.primary, atLeast: 4.5);
    });

    test('primary works as a hairline', () {
      expectContrast(scheme.primary, scheme.surface, atLeast: 3.0);
    });

    test('white is never the foreground on brand pink', () {
      // 2.32:1 — the trap this palette sets in BOTH themes, not just light.
      expect(contrast(const Color(0xFFFFFFFF), Brand.pink), lessThan(3.0));
      expectContrast(scheme.onPrimary, Brand.pink, atLeast: 4.5);
    });
  });

  group('phase colours are data, not brand', () {
    test('the six tokens are untouched by the rebrand', () {
      // These encode cycle state on the ring and calendar and are deliberately
      // NOT part of the brand palette — their teal/periwinkle/amber hue spread
      // is the only thing that makes six states distinguishable. Changing one
      // is a product decision, not a styling one.
      expect(PhaseColors.light.menstrual, const Color(0xFFD64F6E));
      expect(PhaseColors.light.follicular, const Color(0xFF6FB3A8));
      expect(PhaseColors.light.ovulatory, const Color(0xFF7E9CE8));
      expect(PhaseColors.light.luteal, const Color(0xFFD9A15B));
      expect(PhaseColors.light.fertile, const Color(0xFF9CCFC6));
      expect(PhaseColors.light.predicted, const Color(0xFFB0A8C0));
    });

    test('the menstrual token still clears the 3:1 marker bar on the new page',
        () {
      // The page moved from pure white to blush, which cost every phase token
      // ~0.2 of contrast. Menstrual is the one used as a solid day fill.
      expectContrast(PhaseColors.light.menstrual, Brand.bg, atLeast: 3.0);
    });
  });

  group('typography', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    test('body roles use Public Sans, display roles use Fraunces', () {
      for (final t in [light.textTheme, dark.textTheme]) {
        expect(t.bodyMedium!.fontFamily, 'PublicSans');
        expect(t.labelLarge!.fontFamily, 'PublicSans');
        expect(t.titleMedium!.fontFamily, 'PublicSans');
        expect(t.displayLarge!.fontFamily, 'Fraunces');
        expect(t.headlineSmall!.fontFamily, 'Fraunces');
        expect(t.titleLarge!.fontFamily, 'Fraunces');
      }
    });

    test('every Fraunces style carries an explicit wght axis', () {
      // The trap: `fontVariations` REPLACES the axis values the pubspec
      // `weight:` entry supplies. A style that sets SOFT/WONK/opsz but forgets
      // wght renders at the font's default weight, silently and only on device.
      final t = light.textTheme;
      final serifStyles = {
        'displayLarge': t.displayLarge,
        'displayMedium': t.displayMedium,
        'displaySmall': t.displaySmall,
        'headlineLarge': t.headlineLarge,
        'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall,
        'titleLarge': t.titleLarge,
      };
      serifStyles.forEach((name, style) {
        final axes = style!.fontVariations!.map((v) => v.axis).toSet();
        expect(axes, contains('wght'), reason: '$name is missing the wght axis');
        expect(axes, contains('WONK'), reason: '$name lost the WONK axis');
      });
    });

    // NOTE: font SIZES do not exist on a raw ThemeData — M3 keeps colour and
    // geometry in separate themes and merges the geometry at resolve time, so
    // `AppTheme.light().textTheme.bodyMedium.fontSize` is null even on a stock
    // theme. Anything asserting on size has to pump a real context first.
    testWidgets('rose is used ONLY where the text is large enough', (t) async {
      // Brand.rose is 3.21:1 — valid at >=24px (or >=18.66px bold), invalid
      // below. This asserts the RULE rather than individual sizes, so
      // re-tuning a font size cannot quietly push rose under the bar.
      late TextTheme tt;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(builder: (c) {
          tt = Theme.of(c).textTheme;
          return const SizedBox();
        }),
      ));

      final roles = <String, TextStyle?>{
        'displayLarge': tt.displayLarge,
        'displayMedium': tt.displayMedium,
        'displaySmall': tt.displaySmall,
        'headlineLarge': tt.headlineLarge,
        'headlineMedium': tt.headlineMedium,
        'headlineSmall': tt.headlineSmall,
        'titleLarge': tt.titleLarge,
        'titleMedium': tt.titleMedium,
        'titleSmall': tt.titleSmall,
        'bodyLarge': tt.bodyLarge,
        'bodyMedium': tt.bodyMedium,
        'bodySmall': tt.bodySmall,
        'labelLarge': tt.labelLarge,
        'labelMedium': tt.labelMedium,
        'labelSmall': tt.labelSmall,
      };

      var checked = 0;
      roles.forEach((name, style) {
        if (style?.color != Brand.rose) return;
        checked++;
        final size = style!.fontSize;
        expect(size, isNotNull, reason: '$name resolved without a size');
        final bold =
            (style.fontWeight ?? FontWeight.w400).value >= FontWeight.w700.value;
        expect(
          size! >= 24 || (bold && size >= 18.66),
          isTrue,
          reason: '$name is ${size}px and coloured Brand.rose (3.21:1), '
              'below the WCAG large-text threshold',
        );
      });
      expect(checked, greaterThan(0),
          reason: 'rose reached no heading at all — the theme lost its accent');
    });

    test('body and label roles sit on AA-passing colours', () {
      final scheme = light.colorScheme;
      final t = light.textTheme;
      final roles = <String, TextStyle?>{
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'titleMedium': t.titleMedium,
        'titleSmall': t.titleSmall,
        'labelLarge': t.labelLarge,
      };
      roles.forEach((name, style) {
        final c = style?.color;
        if (c == null) return;
        expectContrast(c, scheme.surface, atLeast: 4.5);
      });
    });
  });

  group('Brand tokens the brief does not contain', () {
    test('rose is a heading colour and must not be used for body text', () {
      final c = contrast(Brand.rose, Brand.bg);
      expect(c, greaterThanOrEqualTo(3.0), reason: 'usable at large sizes');
      expect(c, lessThan(4.5),
          reason: 'documents WHY Brand.ink exists — if this ever passes 4.5, '
              'the palette changed and the ink/rose split can be revisited');
    });

    test('pink cannot carry text at all', () {
      expect(contrast(Brand.pink, Brand.bg), lessThan(3.0));
    });
  });
}

/// WCAG 2.1 relative-contrast ratio, `(lighter + 0.05) / (darker + 0.05)`.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void expectContrast(Color fg, Color bg, {required double atLeast}) {
  final ratio = contrast(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(atLeast),
    reason: '${_hex(fg)} on ${_hex(bg)} is ${ratio.toStringAsFixed(2)}:1, '
        'needs $atLeast:1',
  );
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
