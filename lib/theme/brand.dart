import 'package:flutter/material.dart';

/// The LunarFlow brand palette, and the single place any brand colour is
/// written down in Dart.
///
/// Seven of these come straight from the brand brief. Two do not, and the
/// reason they exist is the whole point of this file: **not one colour in the
/// brief reaches 4.5:1 against the brief's own background.** Measured against
/// [bg]: [rose] 3.21, [pink] 2.12, [blush] 1.70, [blushLight] 1.40. White on
/// [pink] is 2.32. A palette built only from the brief would fail WCAG AA on
/// every screen of a health app.
///
/// So [deep] and [ink] are derived. Both are borrowed from the marketing site
/// (`site/src/styles/global.css`) rather than invented here, so the app and the
/// site cannot drift apart.
abstract final class Brand {
  // ---------------------------------------------------------------------
  // From the brand brief.
  // ---------------------------------------------------------------------

  /// The dominant brand accent. A SURFACE colour: it can be filled, but at
  /// 2.12:1 on [bg] it can never carry body text or act as a thin outline.
  /// Reaches the UI as `primaryContainer` — M3 puts that on the FAB.
  static const Color pink = Color(0xFFF489AF);

  /// Headings and large labels ONLY — 3.21:1 on [bg] clears the 3:1 large-text
  /// bar and fails the 4.5:1 body bar. Body text is [ink].
  static const Color rose = Color(0xFFCB6A8A);

  static const Color blush = Color(0xFFF7A9B5);
  static const Color blushLight = Color(0xFFFBC2CC);

  /// The main app background.
  static const Color bg = Color(0xFFFDF2F2);

  /// Card and sheet fill. Deliberately *lighter* than [bg], so a card reads as
  /// lifted off the page. This inverts the old design, where soft-pink cards
  /// sat on a pure-white scaffold.
  static const Color cream = Color(0xFFFFF7F7);

  static const Color white = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------
  // Derived. Not in the brief — see the class doc.
  // ---------------------------------------------------------------------

  /// The one brand colour that can carry white text and act as an outline:
  /// 4.31:1 on [bg] (clears the 3:1 bar for UI components) and 4.72:1 under
  /// white text (clears AA). Mirrors the site's `--color-brand-deep`.
  static const Color deep = Color(0xFFD62E68);

  /// Body text. 12.33:1 on [bg]. This is the app's existing ink, unchanged by
  /// the rebrand — the warm near-black was already tuned to sit under pink.
  static const Color ink = Color(0xFF3A2A30);

  /// Secondary text. 5.88:1 on [bg]. Mirrors the site's `--color-ink-muted`.
  static const Color inkMuted = Color(0xFF6B5A61);

  /// Text and icons on a [pink] fill. 5.64:1. White would be 2.32:1, so a
  /// filled brand-pink control is always dark-on-pink, in BOTH themes.
  static const Color onPink = Color(0xFF4C2431);
}

/// The corner-radius scale.
///
/// These values were already the design system's, but were retyped as bare
/// literals in ~70 places (and twice as named-but-duplicated constants, in
/// `day_entry_form.dart` and `onboarding_screen.dart`). Naming them once means
/// a field can no longer drift to Material's default 4dp by accident.
abstract final class Radii {
  /// Chips and other small controls.
  static const double chip = 12;

  /// Inline banners.
  static const double banner = 14;

  /// Filled buttons and text fields — deliberately between [chip] and [card].
  static const double control = 16;

  /// Cards, sheets and settings groups.
  static const double card = 20;

  /// Fully-rounded pills.
  static const double pill = 999;
}
