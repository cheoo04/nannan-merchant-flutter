import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nannan_merchant/core/utils/error_message.dart';

void main() {
  group('friendlyError — erreurs réseau bas niveau', () {
    test('SocketException → message réseau', () {
      final msg = friendlyError(const SocketException('Failed host lookup'));
      expect(msg, contains('connexion internet'));
    });

    test('TimeoutException → message de timeout', () {
      final msg = friendlyError(TimeoutException('trop long'));
      expect(msg, contains('trop de temps'));
    });
  });

  group('friendlyError — AuthException (identifiants, etc.)', () {
    test('"Invalid login credentials" → message identifiants', () {
      final msg = friendlyError(const AuthException('Invalid login credentials'));
      expect(msg.toLowerCase(), contains('identifiants'));
    });

    test('message AuthException légitime et inconnu → renvoyé tel quel', () {
      final msg = friendlyError(const AuthException('Un message Supabase légitime'));
      expect(msg, 'Un message Supabase légitime');
    });
  });

  group('friendlyError — régression AuthRetryableFetchException (23/08)', () {
    // Bug constaté en prod : un AuthRetryableFetchException (levé par
    // Supabase quand la requête réseau échoue au niveau transport, ex.
    // connexion coupée) hérite de AuthException. Le message brut du type
    // "ClientException: Software caused connection abort, uri=..." finissait
    // par s'afficher tel quel à l'écran de connexion, au lieu du message
    // "Pas de connexion internet" attendu.
    test('AuthRetryableFetchException avec message technique brut → message réseau', () {
      final msg = friendlyError(AuthRetryableFetchException(
        message: 'ClientException: Software caused connection abort, '
            'uri=https://exemple.supabase.co/auth/v1/token?grant_type=password',
      ));
      expect(msg, contains('connexion internet'));
      expect(msg.toLowerCase(), isNot(contains('clientexception')));
      expect(msg.toLowerCase(), isNot(contains('uri=')));
    });

    test('AuthRetryableFetchException même sans mot-clé connu → jamais le message brut', () {
      // Le type seul (AuthRetryableFetchException) doit suffire à déclencher
      // le message réseau, indépendamment du contenu exact du message.
      final msg = friendlyError(AuthRetryableFetchException(message: 'texte imprévisible'));
      expect(msg, contains('connexion internet'));
    });
  });

  group('friendlyError — filet de sécurité générique (erreurs sans type dédié)', () {
    test('Exception générique contenant "ClientException" → message réseau', () {
      final msg = friendlyError(
        Exception('ClientException: Software caused connection abort, uri=https://x.co'),
      );
      expect(msg, contains('connexion internet'));
    });

    test('erreur totalement inconnue → message générique par défaut', () {
      final msg = friendlyError(Exception('quelque chose de jamais vu'));
      expect(msg, 'Une erreur est survenue. Réessayez.');
    });

    test('erreur inconnue avec fallback personnalisé → fallback utilisé', () {
      final msg = friendlyError(Exception('jamais vu'), fallback: 'Message de repli');
      expect(msg, 'Message de repli');
    });
  });
}
