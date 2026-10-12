import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// WILLOW theme: dark green-black with emerald accents,
/// refined toward the Infinity QR palette (sage-tinted cards,
/// warmer dark background, gold accents).
class AppTheme {
  static const primary = Color(0xFF10B981);
  static const accent = Color(0xFF34D399);
  static const willowBg = Color(0xFF0C110E);
  static const willowCard = Color(0xFF16211C);
  static const willowCardHigh = Color(0xFF1C2A23);
  static const sage = Color(0xFF2D4A3E);
  static const gold = Color(0xFFC9A55C);

  static ThemeData get dark {
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
          const ProgressIndicatorThemeData(color: primary),
      sliderTheme: const SliderThemeData(
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
