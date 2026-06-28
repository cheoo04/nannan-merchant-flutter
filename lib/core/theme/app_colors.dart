import 'package:flutter/material.dart';

/// Tokens de couleurs — convertis exactement depuis oklch du styles.css React.
abstract class AppColors {
  // ── Primaire (bleu ciel) ───────────────────────────────────
  /// oklch(0.7 0.17 240) = #00A8FC
  static const primary = Color(0xFF00A8FC);
  static const primaryForeground = Color(0xFFF9FEFF);

  /// oklch(0.95 0.04 240) = #D7F2FF
  static const primarySoft = Color(0xFFD7F2FF);

  // ── Gradient hero ─────────────────────────────────────────
  /// oklch(0.74 0.16 240) → oklch(0.58 0.18 250), angle 160deg
  static const gradientHeroStart = Color(0xFF26B5FF);
  static const gradientHeroEnd   = Color(0xFF007BDE);

  static const gradientHero = LinearGradient(
    begin: Alignment(-0.77, -1.0), // 160deg
    end:   Alignment(0.77,  1.0),
    colors: [gradientHeroStart, gradientHeroEnd],
  );

  /// gradient-primary 135deg (boutons)
  static const gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [Color(0xFF26B5FF), Color(0xFF0081E8)],
  );

  // ── Surfaces ──────────────────────────────────────────────
  /// oklch(0.995 0.003 240)
  static const background = Color(0xFFF8FAFE);
  static const card       = Color(0xFFFFFFFF);

  // ── Texte ──────────────────────────────────────────────────
  /// oklch(0.22 0.04 250)
  static const foreground     = Color(0xFF1A2235);
  /// oklch(0.5 0.02 245)
  static const mutedForeground = Color(0xFF6B7A99);

  // ── Secondaire ─────────────────────────────────────────────
  static const secondary            = Color(0xFFF0F4FF);
  static const secondaryForeground  = Color(0xFF1A2235);

  // ── Bordure ────────────────────────────────────────────────
  /// oklch(0.92 0.01 240)
  static const border = Color(0xFFE4EAF5);

  // ── Warm / orange alertes ─────────────────────────────────
  static const warm     = Color(0xFFE8854A);
  static const warmSoft = Color(0xFFFFF0E6);

  // ── Succès ────────────────────────────────────────────────
  static const success            = Color(0xFF22C55E);
  static const successForeground  = Colors.white;

  // ── Destructive ────────────────────────────────────────────
  static const destructive           = Color(0xFFEF4444);
  static const destructiveForeground = Colors.white;

  // ── Overlay dans le header gradient ───────────────────────
  /// white / 15%
  static const headerOverlay = Color(0x26FFFFFF);
}
