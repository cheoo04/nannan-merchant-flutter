import 'package:flutter/material.dart';

/// Tokens de couleurs — traduits fidèlement depuis styles.css oklch du projet React.
/// Utiliser UNIQUEMENT ces constantes dans l'app. Jamais de hex bruts dans les widgets.
abstract class AppColors {
  // ── Background & surfaces ──────────────────────────────────
  /// oklch(0.995 0.003 240) → blanc légèrement bleuté
  static const background = Color(0xFFF8F9FC);

  /// oklch(1 0 0) → blanc pur
  static const card = Color(0xFFFFFFFF);

  // ── Texte ──────────────────────────────────────────────────
  /// oklch(0.2 0.04 250) → quasi-noir bleuté
  static const foreground = Color(0xFF1A1D2E);

  /// oklch(0.5 0.02 245) → gris moyen
  static const mutedForeground = Color(0xFF6B7280);

  // ── Primaire (violet bleu) ─────────────────────────────────
  /// oklch(0.7 0.17 240) → violet-bleu principal
  static const primary = Color(0xFF5B7CFF);
  static const primaryForeground = Color(0xFFFAFAFF);

  /// oklch(0.95 0.04 240) → violet très clair (fond soft)
  static const primarySoft = Color(0xFFEEF2FF);

  // ── Secondaire ─────────────────────────────────────────────
  static const secondary = Color(0xFFF1F2F8);
  static const secondaryForeground = Color(0xFF1A1D2E);

  // ── Warm (orange alertes) ─────────────────────────────────
  /// oklch(0.78 0.16 65) → orange
  static const warm = Color(0xFFE8854A);
  static const warmForeground = Color(0xFF2A1A0A);
  static const warmSoft = Color(0xFFFFF0E6);

  // ── Succès (vert ouvert) ──────────────────────────────────
  /// oklch(0.65 0.16 155) → vert
  static const success = Color(0xFF34A96B);
  static const successForeground = Color(0xFFFAFFFD);

  // ── Destructive ────────────────────────────────────────────
  static const destructive = Color(0xFFD94F2A);
  static const destructiveForeground = Color(0xFFFFFAF9);

  // ── Bordure ────────────────────────────────────────────────
  /// oklch(0.92 0.01 240) → gris très clair
  static const border = Color(0xFFE8EAF2);

  // ── Gradient hero ─────────────────────────────────────────
  /// linear-gradient(160deg, oklch(0.74 0.16 240) 0%, oklch(0.58 0.18 250) 100%)
  static const gradientHeroStart = Color(0xFF6B8EFF);
  static const gradientHeroEnd = Color(0xFF3B5BDB);

  static const gradientHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientHeroStart, gradientHeroEnd],
    // angle 160deg ≈ topLeft→bottomRight
  );

  // ── Overlay blanc semi-transparent (dans le header) ────────
  static const headerOverlay = Color(0x26FFFFFF); // white/15
}
