import 'package:intl/intl.dart';

/// Formate un montant en FCFA — ex: 1 500 F
String formatXOF(int amount) {
  final formatted = NumberFormat('#,###', 'fr_FR').format(amount);
  return '$formatted F';
}

/// Formate une date en court — ex: "24 juin"
String formatDateShort(DateTime date) {
  return DateFormat('d MMM', 'fr_FR').format(date);
}

/// Formate une date complète — ex: "24 juin 2026 à 14h30"
String formatDateFull(DateTime date) {
  return DateFormat("d MMM yyyy 'à' HH'h'mm", 'fr_FR').format(date);
}

/// Formate une heure — ex: "14:30"
String formatTime(DateTime date) {
  return DateFormat('HH:mm').format(date);
}

/// Retourne le début de la journée (minuit)
DateTime startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

/// Retourne le début de la semaine (7 jours en arrière)
DateTime startOfWeek() {
  return DateTime.now().subtract(const Duration(days: 7));
}

/// Retourne le début du mois (30 jours en arrière)
DateTime startOfMonth() {
  return DateTime.now().subtract(const Duration(days: 30));
}
