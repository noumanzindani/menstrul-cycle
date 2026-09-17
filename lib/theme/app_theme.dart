import 'package:flutter/material.dart';
import '../models/enums.dart';
import 'brand.dart';
import 'typography.dart';

/// Cycle-phase colors, exposed as a [ThemeExtension] so widgets read them via
/// `Theme.of(context).extension<PhaseColors>()` and they adapt to light/dark
/// automatically. Tones are soft and supportive — never alarmist.
@immutable
class PhaseColors extends ThemeExtension<PhaseColors> {
  const PhaseColors({
    required this.menstrual,
    required this.follicular,
    required this.ovulatory,
    required this.luteal,
    required this.fertile,
    required this.predicted,
  });

  final Color menstrual;
  final Color follicular;
  final Color ovulatory;
  final Color luteal;
  final Color fertile;
  final Color predicted;

  Color forPhase(CyclePhase phase) => switch (phase) {
        CyclePhase.menstrual => menstrual,
        CyclePhase.follicular => follicular,
        CyclePhase.ovulatory => ovulatory,
        CyclePhase.luteal => luteal,
        CyclePhase.unknown => predicted,
      };

  static const light = PhaseColors(
    menstrual: Color(0xFFD64F6E), // rose
    follicular: Color(0xFF6FB3A8), // soft teal
    ovulatory: Color(0xFF7E9CE8), // periwinkle
    luteal: Color(0xFFD9A15B), // warm amber
    fertile: Color(0xFF9CCFC6), // light teal wash
    predicted: Color(0xFFB0A8C0), // muted lavender-grey
  );

  static const dark = PhaseColors(
    menstrual: Color(0xFFE97B93),
    follicular: Color(0xFF7FC7BB),
    ovulatory: Color(0xFF98B0EE),
    luteal: Color(0xFFE3B579),
    fertile: Color(0xFF5E8A82),
    predicted: Color(0xFF6E6885),
  );

  @override
  PhaseColors copyWith({
    Color? menstrual,
    Color? follicular,
    Color? ovulatory,
    Color? luteal,
    Color? fertile,
    Color? predicted,
  }) {
    return PhaseColors(
      menstrual: menstrual ?? this.menstrual,
      follicular: follicular ?? this.follicular,
      ovulatory: ovulatory ?? this.ovulatory,
      luteal: luteal ?? this.luteal,
      fertile: fertile ?? this.fertile,
      predicted: predicted ?? this.predicted,
    );
  }

  @override
  PhaseColors lerp(ThemeExtension<PhaseColors>? other, double t) {
    if (other is! PhaseColors) return this;
    return PhaseColors(
      menstrual: Color.lerp(menstrual, other.menstrual, t)!,
      follicular: Color.lerp(follicular, other.follicular, t)!,
      ovulatory: Color.lerp(ovulatory, other.ovulatory, t)!,
      luteal: Color.lerp(luteal, other.luteal, t)!,
      fertile: Color.lerp(fertile, other.fertile, t)!,
      predicted: Color.lerp(predicted, other.predicted, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  /// The seed only supplies M3's *derived* neutrals — the surface ramp, the
  /// outlines, the disabled tones. It does NOT supply the brand accent, and it
  /// is worth knowing why before touching it.
  ///
  /// `ColorScheme.fromSeed` normalises the seed through HCT and reads its tone
  /// from a fixed ramp, so the seed's own lightness is discarded. Measured:
  /// seeding `#F7A8C4` and seeding the brand pink `#F489AF` produce light
  /// primaries of `#8B4A63` and `#8B4A61` — two units of blue apart. Changing
  /// this constant is therefore very nearly a no-op.
  ///
  /// Every colour the user actually reads as "LunarFlow" is an explicit
  /// override in [_brandLight] / [_brandDark], taken from [Brand].
  static const Color seed = Color(0xFFF489AF);

  static ThemeData light() => _build(Brightness.light, PhaseColors.light);
  static ThemeData dark() => _build(Brightness.dark, PhaseColors.dark);

  /// Light: a blush page with cards that lift off it.
  ///
  /// Note this inverts the previous design (soft-pink cards on a pure-white
  /// scaffold). `surfaceContainerLow` is the card fill and is deliberately
  /// LIGHTER than `surface`; the rest of M3's container ramp is left alone
  /// because this app leans on `surfaceContainerHighest` as a *recessed* tint
  /// for text fields, banners and unselected chips.
  static ColorScheme _brandLight(ColorScheme s) => s.copyWith(
        surface: Brand.bg,
        onSurface: Brand.ink,
        onSurfaceVariant: Brand.inkMuted,
        surfaceContainerLow: Brand.cream,
        surfaceContainerLowest: Brand.white,

        // `primary` is the one brand colour that clears both bars: 4.31:1 on
        // the page (so it can be a 1dp outline) and 4.72:1 under white text.
        // Brand.pink is 2.12:1 and would fail as either.
        primary: Brand.deep,
        onPrimary: Brand.white,

        // …so the brand pink lands here instead, where it covers area rather
        // than drawing hairlines. M3 puts primaryContainer on the FAB.
        primaryContainer: Brand.pink,
        onPrimaryContainer: Brand.onPink,

        secondaryContainer: Brand.blushLight,
        onSecondaryContainer: Brand.ink,
        tertiaryContainer: Brand.blush,
        onTertiaryContainer: Brand.ink,
      );

  /// Dark: M3's derived surfaces are already a warm near-black at the brand
  /// hue (`#191113`), so only the accents are overridden.
  ///
  /// [Brand.onPink] stays the foreground on a pink fill in BOTH themes —
  /// white on [Brand.pink] is 2.32:1 in the dark theme too.
  static ColorScheme _brandDark(ColorScheme s) => s.copyWith(
        primary: Brand.pink,
        onPrimary: Brand.onPink,
        secondaryContainer: s.primaryContainer,
      );

  static ThemeData _build(Brightness brightness, PhaseColors phases) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final scheme = brightness == Brightness.light
        ? _brandLight(base)
        : _brandDark(base);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Public Sans as the default face, so a widget that builds a bare
      // TextStyle instead of reading a textTheme role still lands on-brand.
      fontFamily: 'PublicSans',
      textTheme: buildTextTheme(scheme),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        // minimumSize is Size(double.infinity, 52) — full-width by design.
        // Never put a bare FilledButton in a Row; see CLAUDE.md.
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
      ),
      // The FAB carries Brand.pink (via primaryContainer), which is only
      // 2.12:1 against the page — under the 3:1 WCAG bar for identifying a
      // control. The app is flat (elevation 0, no shadow anywhere), so there
      // is no drop shadow to supply that edge. The outline does it instead.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          side: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.card),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      // Shapes only. `filled` is deliberately NOT set here: several screens
      // pass their own fillColor, and forcing a global fill would change them.
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      extensions: [phases],
    );
  }
}
