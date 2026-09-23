// --- Fichier : test/core/utils/error_message_test.dart ---
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nannan_merchant/core/services/a_nan_nan_api_client.dart';
import 'package:nannan_merchant/core/utils/error_message.dart';

void main() {
  group('friendlyError', () {
    test('traduit SocketException en message de connexion', () {
      const err = SocketException('Failed host lookup');
      expect(
        friendlyError(err),
        'Pas de connexion internet. Vérifiez votre réseau et réessayez.',
      );
    });

    test('traduit TimeoutException en message clair', () {
      final err = TimeoutException('Timeout');
      expect(
        friendlyError(err),
        'La connexion a mis trop de temps à répondre. Réessayez.',
      );
    });

    test('traduit HttpException en message de serveur', () {
      const err = HttpException('Connection error');
      expect(
        friendlyError(err),
        'Erreur de connexion au serveur. Réessayez dans un instant.',
      );
    });

    test('traduit ANanNanApiException 401 en session expirée', () {
      const err = ANanNanApiException(401, 'Unauthorized');
      expect(
        friendlyError(err),
        'Session expirée ou identifiants incorrects.',
      );
    });

    test('traduit ANanNanApiException 404 en ressource introuvable', () {
      const err = ANanNanApiException(404, 'Not Found');
      expect(
        friendlyError(err),
        'Ressource introuvable.',
      );
    });

    test('traduit ANanNanApiException 422 avec le message fourni', () {
      const err = ANanNanApiException(422, 'Code PIN invalide');
      expect(
        friendlyError(err),
        'Code PIN invalide',
      );
    });

    test("utilise le fallback en cas d'erreur inconnue", () {
      final err = Exception('Erreur inconnue');
      expect(
        friendlyError(err, fallback: 'Une erreur personnalisée'),
        'Une erreur personnalisée',
      );
    });
  });
}
