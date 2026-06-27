import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.primaryForeground,
        secondary: AppColors.secondary,
        onSecondary: AppColors.secondaryForeground,
        surface: AppColors.card,
        onSurface: AppColors.foreground,
        error: AppColors.destructive,
        onError: AppColors.destructiveForeground,
        outline: AppColors.border,
      ),
      // Typographie : Sora (display) + Inter (body)
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        // Sora pour titres
        displayLarge: GoogleFonts.sora(
          fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        displayMedium: GoogleFonts.sora(
          fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        displaySmall: GoogleFonts.sora(
          fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        headlineMedium: GoogleFonts.sora(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        headlineSmall: GoogleFonts.sora(
          fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        titleLarge: GoogleFonts.sora(
          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        titleMedium: GoogleFonts.sora(
          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.foreground,
        ),
        // Inter pour body
        bodyLarge: GoogleFonts.inter(
          fontSize: 16, color: AppColors.foreground,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14, color: AppColors.foreground,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12, color: AppColors.mutedForeground,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w600,
          color: AppColors.mutedForeground, letterSpacing: 0.8,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
        // shadow-card du React : 0 1px 2px rgba(0,0,0,0.04), 0 4px 16px rgba(0,0,0,0.06)
        shadowColor: Colors.black,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.primaryForeground,
          minimumSize: const Size(44, 44), // touch target min 44pt
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.mutedForeground),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.mutedForeground,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 0.5,
      ),
    );
  }
}
