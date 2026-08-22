import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Résultat d'une tentative de vérification du PIN.
enum PinVerifyResult { correct, incorrect, locked }

/// Petite interface de stockage clé/valeur — permet d'injecter un faux
/// stockage en test (voir `pin_storage_test.dart`) au lieu de dépendre du
/// canal natif de flutter_secure_storage, qui ne fonctionne pas dans
/// `flutter test` sans device/émulateur.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _FlutterSecureKeyValueStore implements SecureKeyValueStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Gère le code PIN local (verrouillage type Wave) : stockage haché+salé
/// dans le Keychain/Keystore (jamais en clair, jamais dans SharedPreferences
/// qui n'est pas chiffré), et verrou anti brute-force (5 essais → pause 30s).
///
/// Le PIN ne remplace pas l'authentification Supabase — il verrouille l'accès
/// local à une session déjà valide, exactement comme Wave. Voir
/// `docs/superpowers/specs/` pour le détail du flux complet.
class PinStorage {
  static const maxAttempts = 5;
  static const lockoutDuration = Duration(seconds: 30);

  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';
  static const _kAttempts = 'pin_attempts';
  static const _kLockoutUntil = 'pin_lockout_until_ms';

  final SecureKeyValueStore _store;

  PinStorage({SecureKeyValueStore? store}) : _store = store ?? _FlutterSecureKeyValueStore();

  Future<bool> hasPin() async => (await _store.read(_kHash)) != null;

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await _store.write(_kSalt, salt);
    await _store.write(_kHash, _hash(pin, salt));
    await _store.delete(_kAttempts);
    await _store.delete(_kLockoutUntil);
  }

  /// Efface le PIN et tout état de verrou associé — utilisé par le flux
  /// "PIN oublié" (l'ancien PIN oublié ne peut de toute façon jamais être
  /// redonné ; il faut forcément en redéfinir un nouveau après ré-authentification).
  Future<void> clearPin() async {
    await _store.delete(_kHash);
    await _store.delete(_kSalt);
    await _store.delete(_kAttempts);
    await _store.delete(_kLockoutUntil);
  }

  Future<PinVerifyResult> verifyPin(String pin) async {
    if (await remainingLockoutSeconds() > 0) return PinVerifyResult.locked;

    final hash = await _store.read(_kHash);
    final salt = await _store.read(_kSalt);
    if (hash == null || salt == null) return PinVerifyResult.incorrect;

    if (_hash(pin, salt) == hash) {
      await _store.delete(_kAttempts);
      await _store.delete(_kLockoutUntil);
      return PinVerifyResult.correct;
    }

    final attempts = (await _readAttempts()) + 1;
    if (attempts >= maxAttempts) {
      final until = DateTime.now().add(lockoutDuration).millisecondsSinceEpoch;
      await _store.write(_kLockoutUntil, '$until');
      await _store.write(_kAttempts, '0');
      return PinVerifyResult.locked;
    }
    await _store.write(_kAttempts, '$attempts');
    return PinVerifyResult.incorrect;
  }

  Future<int> remainingAttempts() async => maxAttempts - await _readAttempts();

  Future<int> remainingLockoutSeconds() async {
    final raw = await _store.read(_kLockoutUntil);
    if (raw == null) return 0;
    final until = int.tryParse(raw) ?? 0;
    final diffMs = until - DateTime.now().millisecondsSinceEpoch;
    return diffMs > 0 ? (diffMs / 1000).ceil() : 0;
  }

  Future<int> _readAttempts() async {
    final raw = await _store.read(_kAttempts);
    return int.tryParse(raw ?? '0') ?? 0;
  }

  static String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Encode(bytes);
  }

  static String _hash(String pin, String saltB64) {
    final bytes = utf8.encode(pin) + base64Decode(saltB64);
    return sha256.convert(bytes).toString();
  }
}
