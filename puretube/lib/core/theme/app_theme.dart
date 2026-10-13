import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Selectable themes for the app.
/// The WILLOW options share dark green-black backgrounds and differ only
/// in accent color; Sonora is a full theme change (dark brown-black +
/// gold), matching the audio (SONORA) mode vibe.
enum AppThemeOption {
  emerald('Willow', Color(0xFF10B981), Color(0xFF34D399)),
  teal('Teal', Color(0xFF14B8A6), Color(0xFF2DD4BF)),
  orange('Orange', Color(0xFFF97316), Color(0xFFFB923C)),
  blue('Blue', Color(0xFF3B82F6), Color(0xFF60A5FA)),
  purple('Purple', Color(0xFF8B5CF6), Color(0xFFA78BFA)),
  green('Green', Color(0xFF22C55E), Color(0xFF4ADE80)),
  white('White', Color(0xFFFFFFFF), Color(0xFFD4D4D4)),
  sonora('Sonora', Color(0xFFD4A574), Color(0xFFE8C39A),
      bg: Color(0xFF14100C),
      card: Color(0xFF211914),
      cardHigh: Color(0xFF2B211A));

  final String label;
  final Color accent;
  final Color accentLight;
  final Color bg;
  final Color card;
  final Color cardHigh;

  const AppThemeOption(
    this.label,
    this.accent,
    this.accentLight, {
    this.bg = AppTheme.willowBg,
    this.card = AppTheme.willowCard,
    this.cardHigh = AppTheme.willowCardHigh,
  });

  /// Parse a persisted option name; falls back to emerald.
  static AppThemeOption fromName(String? name) =>
      AppThemeOption.values.firstWhere(
        (o) => o.name == name,
        orElse: () => AppThemeOption.emerald,
      );
}

/// App themes: WILLOW (dark green-black with selectable accents,
/// refined toward the Infinity QR palette) and SONORA (dark
/// brown-black with gold, matching the audio mode vibe).
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

  /// Dark theme with the given option.
  /// WILLOW options keep green-black backgrounds and only change accents;
  /// Sonora swaps to its own dark brown-black surfaces with gold accents.
  static ThemeData darkFor(AppThemeOption option) {
    final primary = option.accent;
    final accent = option.accentLight;
    final bg = option.bg;
    final card = option.card;
    final cardHigh = option.cardHigh;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme.copyWith(
        primary: primary,
        secondary: accent,
        surface: bg,
        surfaceContainerLowest: bg,
        surfaceContainerLow: bg,
        surfaceContainer: card,
        surfaceContainerHigh: cardHigh,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        labelStyle: const TextStyle(color: Colors.white70),
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
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
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
