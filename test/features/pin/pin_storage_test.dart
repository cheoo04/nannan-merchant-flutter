import 'package:flutter_test/flutter_test.dart';
import 'package:nannan_merchant/features/pin/pin_storage.dart';

/// Fake en mémoire de [SecureKeyValueStore] — évite de dépendre du canal
/// natif de flutter_secure_storage dans les tests (qui échouerait dans
/// `flutter test`, sans device/émulateur).
class _FakeStore implements SecureKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

void main() {
  late _FakeStore store;
  late PinStorage pin;

  setUp(() {
    store = _FakeStore();
    pin = PinStorage(store: store, userId: 'user-1');
  });

  group('PinStorage — cycle de vie de base', () {
    test('hasPin() est false tant qu\'aucun PIN n\'est défini', () async {
      expect(await pin.hasPin(), isFalse);
    });

    test('setPin() puis hasPin() devient true', () async {
      await pin.setPin('1234');
      expect(await pin.hasPin(), isTrue);
    });

    test('le PIN n\'est jamais stocké en clair', () async {
      await pin.setPin('1234');
      final allValues = store._data.values.join(' ');
      expect(allValues.contains('1234'), isFalse);
    });

    test('clearPin() efface tout, hasPin() redevient false', () async {
      await pin.setPin('1234');
      await pin.clearPin();
      expect(await pin.hasPin(), isFalse);
    });
  });

  group('PinStorage.verifyPin — vérification', () {
    test('le bon PIN retourne correct', () async {
      await pin.setPin('1234');
      expect(await pin.verifyPin('1234'), PinVerifyResult.correct);
    });

    test('un mauvais PIN retourne incorrect', () async {
      await pin.setPin('1234');
      expect(await pin.verifyPin('0000'), PinVerifyResult.incorrect);
    });

    test('un succès réinitialise le compteur d\'essais', () async {
      await pin.setPin('1234');
      await pin.verifyPin('0000'); // 1 essai raté
      await pin.verifyPin('1234'); // succès
      expect(await pin.remainingAttempts(), 5);
    });
  });

  group('PinStorage — verrou anti brute-force (5 essais / 30s)', () {
    test('se verrouille après 5 échecs consécutifs', () async {
      await pin.setPin('1234');
      for (var i = 0; i < 4; i++) {
        expect(await pin.verifyPin('0000'), PinVerifyResult.incorrect);
      }
      // 5e échec → verrouillage
      expect(await pin.verifyPin('0000'), PinVerifyResult.locked);
    });

    test('reste verrouillé même avec le bon PIN pendant le cooldown', () async {
      await pin.setPin('1234');
      for (var i = 0; i < 5; i++) {
        await pin.verifyPin('0000');
      }
      expect(await pin.verifyPin('1234'), PinVerifyResult.locked);
    });

    test('remainingLockoutSeconds() > 0 pendant le verrou, 0 sinon', () async {
      await pin.setPin('1234');
      expect(await pin.remainingLockoutSeconds(), 0);
      for (var i = 0; i < 5; i++) {
        await pin.verifyPin('0000');
      }
      expect(await pin.remainingLockoutSeconds(), greaterThan(0));
    });
  });

  group('PinStorage — isolation entre comptes (device partagé)', () {
    test('deux userId différents ont des PIN totalement indépendants', () async {
      // Même stockage physique partagé (même device), deux comptes différents.
      final pinA = PinStorage(store: store, userId: 'user-A');
      final pinB = PinStorage(store: store, userId: 'user-B');

      await pinA.setPin('1111');

      expect(await pinB.hasPin(), isFalse);
      expect(await pinA.hasPin(), isTrue);
    });

    test('le verrou anti brute-force d\'un compte n\'affecte pas l\'autre', () async {
      final pinA = PinStorage(store: store, userId: 'user-A');
      final pinB = PinStorage(store: store, userId: 'user-B');
      await pinA.setPin('1111');
      await pinB.setPin('2222');

      for (var i = 0; i < 5; i++) {
        await pinA.verifyPin('0000');
      }
      expect(await pinA.remainingLockoutSeconds(), greaterThan(0));
      expect(await pinB.remainingLockoutSeconds(), 0);
      expect(await pinB.verifyPin('2222'), PinVerifyResult.correct);
    });
  });
}
