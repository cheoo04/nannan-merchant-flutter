import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Transforme n'importe quelle exception technique (SocketException,
/// ClientException, TimeoutException, PostgrestException, StorageException,
/// AuthException, ...) en un message clair, en français, présentable à
/// l'utilisateur final.
///
/// Objectif : aucun message brut du type
/// "ClientException with SocketException: Failed host lookup..."
/// ne doit jamais s'afficher dans l'UI. On log toujours l'erreur d'origine
/// pour le debug, et on renvoie un message humain pour l'affichage.
String friendlyError(Object error, {String? fallback}) {
  // Erreurs réseau bas niveau (pas de connexion, DNS, hôte injoignable...)
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

  // Erreurs d'authentification Supabase — le message est déjà écrit pour un
  // humain côté Supabase mais on filtre les cas les plus fréquents pour
  // proposer un texte plus naturel en français.
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('already registered') || msg.contains('already exists')) {
      return 'Un compte existe déjà avec ces informations.';
    }
    if (msg.contains('invalid login credentials') || msg.contains('invalid credentials')) {
      return 'Identifiants incorrects. Vérifiez votre email/téléphone et mot de passe.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Veuillez confirmer votre email avant de continuer.';
    }
    if (msg.contains('network') || msg.contains('socket') || msg.contains('failed host lookup')) {
      return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
    }
    return error.message;
  }

  // Erreurs base de données (Postgrest / Supabase)
  if (error is PostgrestException) {
    return 'Une erreur est survenue lors de la communication avec le serveur. Réessayez.';
  }

  if (error is StorageException) {
    return "Une erreur est survenue lors de l'envoi du fichier. Réessayez.";
  }

  // Dernier filet de sécurité : si le message contient des indices
  // techniques réseau connus, on les remplace quand même par un message
  // générique au lieu de laisser passer le texte brut (ex: ClientException
  // levée par package:http, qui n'a pas de type dédié détectable ci-dessus).
  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('network is unreachable') ||
      raw.contains('handshakeexception')) {
    return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
  }

  return fallback ?? 'Une erreur est survenue. Réessayez.';
}
