// lib/core/services/a_nan_nan_api_client.dart
//
// Client HTTP pour la nouvelle API (api-a-nan-nan.vercel.app), basé sur
// l'openapi.json réel du 19/09. Remplace l'ancienne version qui supposait
// à tort une réutilisation du JWT Supabase — cette API a sa propre auth
// téléphone + PIN à 4 chiffres (register/login/refresh), complètement
// indépendante de Supabase Auth.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ANanNanApiException implements Exception {
  final int statusCode;
  final String message;
  const ANanNanApiException(this.statusCode, this.message);

  @override
  String toString() => 'ANanNanApiException($statusCode): $message';
}

class ANanNanApiClient {
  static const String baseUrl = 'https://api-a-nan-nan.vercel.app';

  static const _kAccessToken = 'anannan_access_token';
  static const _kRefreshToken = 'anannan_refresh_token';

  final http.Client _http;
  String? _accessToken;
  String? _refreshToken;

  ANanNanApiClient({http.Client? client}) : _http = client ?? http.Client();

  // ── Session (persistée en local, pas de Supabase ici) ────────────
  Future<void> _loadSession() async {
    if (_accessToken != null) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_kAccessToken);
    _refreshToken = prefs.getString(_kRefreshToken);
  }

  Future<void> _saveSession(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, access);
    await prefs.setString(_kRefreshToken, refresh);
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
  }

  Future<bool> get isLoggedIn async {
    await _loadSession();
    return _accessToken != null;
  }

  // ── Auth ───────────────────────────────────────────────────────
  /// Inscription — téléphone au format 10 chiffres ou +225..., PIN 4 chiffres.
  Future<Map<String, dynamic>> register({
    required String phone,
    required String pin,
    String? firstName,
    String? lastName,
    String? email,
    String? referralCode,
  }) async {
    final body = await _postPublic('/api/v1/auth/register', {
      'phone': phone,
      'pin': pin,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (email != null) 'email': email,
      if (referralCode != null) 'referral_code': referralCode,
    });
    // AuthResponse = { user, tokens }
    final tokens = body['tokens'] as Map<String, dynamic>;
    await _saveSession(tokens['access_token'] as String, tokens['refresh_token'] as String);
    return body['user'] as Map<String, dynamic>;
  }

  /// Connexion — mêmes identifiants que register (téléphone + PIN),
  /// PAS d'email ni de mot de passe : ce backend n'en a pas.
  Future<void> login({required String phone, required String pin}) async {
    final body = await _postPublic('/api/v1/auth/login', {
      'phone': phone,
      'pin': pin,
    });
    // TokenResponse direct (pas enveloppé dans "tokens" ici, contrairement à register)
    await _saveSession(body['access_token'] as String, body['refresh_token'] as String);
  }

  Future<void> refreshSession() async {
    await _loadSession();
    if (_refreshToken == null) throw const ANanNanApiException(401, 'Pas de session à rafraîchir');
    final body = await _postPublic('/api/v1/auth/refresh', {'refresh_token': _refreshToken});
    await _saveSession(body['access_token'] as String, body['refresh_token'] as String);
  }

  Future<Map<String, dynamic>> me() async => await get('/api/v1/auth/me') as Map<String, dynamic>;

  Future<void> logout() => clearSession();

  // ── Requêtes génériques authentifiées ─────────────────────────
  Future<Map<String, String>> _authHeaders() async {
    await _loadSession();
    if (_accessToken == null) {
      throw const ANanNanApiException(401, 'Non connecté (téléphone + PIN requis)');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    var res = await _http.get(uri, headers: await _authHeaders());
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(() => _http.get(uri, headers: _headersSync()));
    }
    return _handle(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    var res = await _http.post(uri, headers: await _authHeaders(), body: jsonEncode(body));
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(() => _http.post(uri, headers: _headersSync(), body: jsonEncode(body)));
    }
    return _handle(res);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    var res = await _http.patch(uri, headers: await _authHeaders(), body: jsonEncode(body));
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(() => _http.patch(uri, headers: _headersSync(), body: jsonEncode(body)));
    }
    return _handle(res);
  }

  Future<dynamic> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    var res = await _http.delete(uri, headers: await _authHeaders());
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(() => _http.delete(uri, headers: _headersSync()));
    }
    return _handle(res);
  }

  Map<String, String> _headersSync() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $_accessToken',
      };

  Future<http.Response> _retryAfterRefresh(Future<http.Response> Function() retry) async {
    try {
      await refreshSession();
      return await retry();
    } catch (e) {
      await clearSession();
      rethrow;
    }
  }

  // ── Appel public (pas de token requis) ────────────────────────
  Future<Map<String, dynamic>> _postPublic(String path, Object? body) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _http.post(
      uri,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    );
    return _handle(res) as Map<String, dynamic>;
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String message = res.body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['detail'] is String) {
        message = decoded['detail'] as String;
      } else if (decoded is Map && decoded['detail'] is List) {
        // HTTPValidationError (422) : liste de ValidationError
        message = (decoded['detail'] as List)
            .map((e) => e is Map ? '${e['loc']?.last}: ${e['msg']}' : e.toString())
            .join(', ');
      }
    } catch (_) {
      // corps non-JSON, on garde le texte brut
    }
    if (kDebugMode) {
      debugPrint('ANanNanApiClient error ${res.statusCode}: $message');
    }
    throw ANanNanApiException(res.statusCode, message);
  }
}
