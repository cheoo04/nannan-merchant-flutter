import 'package:intl/intl.dart';

/// Formate un montant FCFA — ex: "1 500 F"
/// Miroir de formatXOF() du projet React
String formatXOF(int amount) {
  return '${NumberFormat('#,###', 'fr_FR').format(amount)} F';
}

/// Formate une date courte — ex: "24 juin"
String formatDateShort(DateTime date) =>
    DateFormat('d MMM', 'fr_FR').format(date);

/// Formate heure — ex: "14:30"
String formatTime(DateTime date) => DateFormat('HH:mm').format(date);
