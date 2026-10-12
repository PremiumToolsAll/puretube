import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Selectable accent themes for the app.
/// Dark WILLOW backgrounds stay fixed for every option —
/// only the accent colors change.
enum AppThemeOption {
  emerald('Emerald', Color(0xFF10B981), Color(0xFF34D399)),
  teal('Teal', Color(0xFF14B8A6), Color(0xFF2DD4BF)),
  orange('Orange', Color(0xFFF97316), Color(0xFFFB923C)),
  blue('Blue', Color(0xFF3B82F6), Color(0xFF60A5FA)),
  purple('Purple', Color(0xFF8B5CF6), Color(0xFFA78BFA)),
  green('Green', Color(0xFF22C55E), Color(0xFF4ADE80)),
  white('White', Color(0xFFFFFFFF), Color(0xFFD4D4D4));

  final String label;
  final Color accent;
  final Color accentLight;

  const AppThemeOption(this.label, this.accent, this.accentLight);

  /// Parse a persisted option name; falls back to emerald.
  static AppThemeOption fromName(String? name) =>
      AppThemeOption.values.firstWhere(
        (o) => o.name == name,
        orElse: () => AppThemeOption.emerald,
      );
}

/// WILLOW theme: dark green-black with selectable accents,
/// refined toward the Infinity QR palette (sage-tinted cards,
/// warmer dark background, gold accents).
class AppTheme {
  /// Default (emerald) accents — kept for static references.
  static const primary = Color(0xFF10B981);
  static const accent = Color(0xFF34D399);
  static const willowBg = Color(0xFF0C110E);
  static const willowCard = Color(0xFF16211C);
  static const willowCardHigh = Color(0xFF1C2A23);
  static const sage = Color(0xFF2D4A3E);
  static const gold = Color(0xFFC9A55C);

  /// Default dark theme (emerald) — backwards compatible.
  static ThemeData get dark => darkFor(AppThemeOption.emerald);

  /// Dark WILLOW theme with the given accent option.
  /// Backgrounds stay fixed; only accent colors change.
  static ThemeData darkFor(AppThemeOption option) {
    final primary = option.accent;
    final accent = option.accentLight;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: willowBg,
      colorScheme: scheme.copyWith(
        primary: primary,
        secondary: accent,
        surface: willowBg,
        surfaceContainerLowest: willowBg,
        surfaceContainerLow: willowBg,
        surfaceContainer: willowCard,
        surfaceContainerHigh: willowCardHigh,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: willowBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: willowCard,
        labelStyle: TextStyle(color: Colors.white70),
        side: BorderSide.none,
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: primary),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? primary.withOpacity(0.5)
                : null),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: willowCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: willowCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }
}
