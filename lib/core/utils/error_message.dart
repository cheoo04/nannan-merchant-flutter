// --- Fichier : lib/core/utils/error_message.dart ---
import 'dart:async';
import 'dart:io';
import '../services/a_nan_nan_api_client.dart';

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

  if (error is ANanNanApiException) {
    if (error.statusCode == 401) {
      return 'Session expirée ou identifiants incorrects.';
    }
    if (error.statusCode == 403) {
      return 'Accès non autorisé.';
    }
    if (error.statusCode == 404) {
      return 'Élément introuvable sur le serveur.';
    }
    if (error.statusCode == 413) {
      return 'Le média sélectionné est trop lourd. Réduisez sa durée ou sa résolution.';
    }
    if (error.statusCode == 415) {
      return 'Format de fichier non pris en charge. Utilisez du MP4 ou JPG/PNG.';
    }
    if (error.statusCode == 422) {
      final msg = error.message;
      if (msg.contains('loc') ||
          msg.contains('Input should be') ||
          msg.contains('value_error')) {
        return 'Vérifiez les informations saisies.';
      }
      return msg.isNotEmpty ? msg : 'Informations invalides.';
    }
    if (error.statusCode >= 500) {
      return 'Difficulté technique temporaire sur le serveur. Réessayez dans un instant.';
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

  if (raw.contains('greenlet') ||
      raw.contains('sql') ||
      raw.contains('asyncpg') ||
      raw.contains('traceback')) {
    return 'Une difficulté technique temporaire est survenue. Réessayez.';
  }

  return fallback ?? 'Une erreur est survenue. Réessayez.';
}
