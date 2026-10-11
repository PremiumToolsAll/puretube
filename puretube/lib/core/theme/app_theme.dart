import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// PureTube design system — AMOLED Black + Material 3.
class AppTheme {
  // ── Colors ────────────────────────────────────────────────
  static const Color primary = Color(0xFF6200EA);
  static const Color primaryLight = Color(0xFF9D46FF);
  static const Color accent = Color(0xFF00BCD4);
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color card = Color(0xFF1A1A1A);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color error = Color(0xFFCF6679);
  static const Color success = Color(0xFF4CAF50);

  static const LinearGradient premiumGradient =
      LinearGradient(
    colors: [primary, Color(0xFF2962FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme =
        GoogleFonts.interTextTheme(base.textTheme);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        background: background,
        error: error,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: primary,
        labelStyle: GoogleFonts.inter(
            color: textPrimary, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor:
            WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.selected)
                    ? primary
                    : Colors.grey),
        trackColor:
            WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.selected)
                    ? primary.withOpacity(0.4)
                    : Colors.grey.shade800),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(
              color: primary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: GoogleFonts.inter(
            color: textSecondary.withOpacity(0.6)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:
              CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ── Typography shortcuts ──────────────────────────────────
  static TextStyle get title => GoogleFonts.inter(
      fontSize: 20, fontWeight: FontWeight.bold);
  static TextStyle get subtitle => GoogleFonts.inter(
      fontSize: 16, fontWeight: FontWeight.w500);
  static TextStyle get body => GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.normal);
  static TextStyle get caption => GoogleFonts.inter(
      fontSize: 12, fontWeight: FontWeight.w300);
}
