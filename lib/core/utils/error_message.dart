// --- Fichier : lib/core/utils/error_message.dart ---
import 'dart:async';
import 'dart:io';
import '../services/a_nan_nan_api_client.dart';

/// Transforme n'importe quelle exception technique (SocketException,
/// TimeoutException, ANanNanApiException, ...) en un message clair en français.
String friendlyError(Object error, {String? fallback}) {
  if (error is SocketException) {
    return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
  }

  if (error is TimeoutException) {
    return 'La connexion a mis trop de temps à répondre. Réessayez.';
  }

  if (error is HttpException) {
    return 'Erreur de connexion au serveur. Réessayez dans un instant.';
  }

  if (error is FormatException) {
    return 'Une erreur inattendue est survenue. Réessayez.';
  }

  // Erreurs retournées par l'API Neon/FastAPI
  if (error is ANanNanApiException) {
    if (error.statusCode == 401) {
      return 'Session expirée ou identifiants incorrects.';
    }
    if (error.statusCode == 404) {
      return 'Ressource introuvable.';
    }
    if (error.statusCode == 422) {
      return error.message.isNotEmpty ? error.message : 'Données invalides.';
    }
    return error.message;
  }

  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection abort') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('network is unreachable') ||
      raw.contains('handshakeexception')) {
    return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
  }

  return fallback ?? 'Une erreur est survenue. Réessayez.';
}
