// --- Fichier : lib/features/pin/pin_storage.dart ---
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Résultat d'une tentative de vérification du PIN.
enum PinVerifyResult { correct, incorrect, locked }

/// Interface de stockage clé/valeur sécurisée.
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
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Interface pour une synchronisation distante optionnelle.
abstract class PinRemoteStore {
  Future<void> push({required String? hash, required String? salt});
  Future<({String hash, String salt})?> pull();
}

/// Implémentation locale / autonome (ne dépend plus de Supabase).
class _LocalPinRemoteStore implements PinRemoteStore {
  const _LocalPinRemoteStore();

  @override
  Future<void> push({required String? hash, required String? salt}) async {
    // Le stockage local FlutterSecureStorage reste la source de vérité.
  }

  @override
  Future<({String hash, String salt})?> pull() async {
    return null;
  }
}

/// Gère le code PIN local (verrouillage type Wave) : stockage haché+salé
/// dans le Keychain/Keystore (jamais en clair), et verrou anti brute-force (5 essais → pause 30s).
class PinStorage {
  static const maxAttempts = 5;
  static const lockoutDuration = Duration(seconds: 30);

  final SecureKeyValueStore _store;
  final PinRemoteStore _remote;
  final String _kHash;
  final String _kSalt;
  final String _kAttempts;
  final String _kLockoutUntil;

  PinStorage({
    SecureKeyValueStore? store,
    PinRemoteStore? remote,
    required String userId,
  })  : _store = store ?? _FlutterSecureKeyValueStore(),
        _remote = remote ?? const _LocalPinRemoteStore(),
        _kHash = 'pin_hash_$userId',
        _kSalt = 'pin_salt_$userId',
        _kAttempts = 'pin_attempts_$userId',
        _kLockoutUntil = 'pin_lockout_until_ms_$userId';

  Future<bool> hasPin() async => (await _store.read(_kHash)) != null;

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    await _store.write(_kSalt, salt);
    await _store.write(_kHash, hash);
    await _store.delete(_kAttempts);
    await _store.delete(_kLockoutUntil);
    await _remote.push(hash: hash, salt: salt);
  }

  /// Efface le PIN et l'état de verrou associé.
  Future<void> clearPin() async {
    await _store.delete(_kHash);
    await _store.delete(_kSalt);
    await _store.delete(_kAttempts);
    await _store.delete(_kLockoutUntil);
    await _remote.push(hash: null, salt: null);
  }

  Future<bool> restoreFromRemote() async {
    final backup = await _remote.pull();
    if (backup == null) return false;
    await _store.write(_kHash, backup.hash);
    await _store.write(_kSalt, backup.salt);
    await _store.delete(_kAttempts);
    await _store.delete(_kLockoutUntil);
    return true;
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
