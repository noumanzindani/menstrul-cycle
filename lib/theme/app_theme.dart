import 'package:flutter/material.dart';
import '../models/enums.dart';

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

  /// Muted rose-plum: warm and calming, works for a broad audience, reads well
  /// with the gender-neutral toggle (not hot-pink).
  static const Color seed = Color(0xFFB5476B);

  static ThemeData light() => _build(Brightness.light, PhaseColors.light);
  static ThemeData dark() => _build(Brightness.dark, PhaseColors.dark);

  static ThemeData _build(Brightness brightness, PhaseColors phases) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
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
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      extensions: [phases],
    );
  }
}
