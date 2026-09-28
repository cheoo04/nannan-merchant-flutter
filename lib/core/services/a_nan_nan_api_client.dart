// --- Fichier : lib/core/services/a_nan_nan_api_client.dart ---
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ANanNanApiException implements Exception {
  final int statusCode;
  final String message;
  const ANanNanApiException(this.statusCode, this.message);

  @override
  String toString() => 'ANanNanApiException($statusCode): $message';
}

class ANanNanApiClient {
  static final ANanNanApiClient _instance = ANanNanApiClient._internal();
  factory ANanNanApiClient({http.Client? client}) {
    if (client != null) _instance._http = client;
    return _instance;
  }
  ANanNanApiClient._internal() : _http = http.Client();

  static const String baseUrl = 'https://api-a-nan-nan.vercel.app';
  static const _kAccessToken = 'anannan_access_token';
  static const _kRefreshToken = 'anannan_refresh_token';

  http.Client _http;
  String? _accessToken;
  String? _refreshToken;

  // Verrou pour éviter les refreshs simultanés (anti-stampede)
  Future<void>? _refreshFuture;

  // Callback global branché dans main.dart si la session est définitivement expirée
  static VoidCallback? onSessionExpired;

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
    return _accessToken != null && _accessToken!.isNotEmpty;
  }

  // ── Auth ───────────────────────────────────────────────────────
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
    final tokens = body['tokens'] as Map<String, dynamic>;
    await _saveSession(
        tokens['access_token'] as String, tokens['refresh_token'] as String);
    return body['user'] as Map<String, dynamic>;
  }

  Future<void> login({required String phone, required String pin}) async {
    final body = await _postPublic('/api/v1/auth/login', {
      'phone': phone,
      'pin': pin,
    });
    await _saveSession(
        body['access_token'] as String, body['refresh_token'] as String);
  }

  Future<void> refreshSession() async {
    if (_refreshFuture != null) return _refreshFuture!;

    _refreshFuture = () async {
      await _loadSession();
      if (_refreshToken == null) {
        throw const ANanNanApiException(401, 'Pas de session à rafraîchir');
      }
      try {
        final body = await _postPublic(
            '/api/v1/auth/refresh', {'refresh_token': _refreshToken});
        await _saveSession(
            body['access_token'] as String, body['refresh_token'] as String);
      } catch (e) {
        await clearSession();
        onSessionExpired?.call();
        rethrow;
      } finally {
        _refreshFuture = null;
      }
    }();

    return _refreshFuture!;
  }

  Future<Map<String, dynamic>> me() async =>
      await get('/api/v1/auth/me') as Map<String, dynamic>;

  Future<void> logout() => clearSession();

  // ── Requêtes génériques authentifiées ─────────────────────────
  Future<Map<String, String>> _authHeaders() async {
    await _loadSession();
    if (_accessToken == null) {
      throw const ANanNanApiException(
          401, 'Non connecté (téléphone + PIN requis)');
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
      res = await _retryAfterRefresh(
          () => _http.get(uri, headers: _headersSync()));
    }
    return _handle(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    var res = await _http.post(uri,
        headers: await _authHeaders(), body: jsonEncode(body));
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(() =>
          _http.post(uri, headers: _headersSync(), body: jsonEncode(body)));
    }
    return _handle(res);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    var res = await _http.patch(uri,
        headers: await _authHeaders(), body: jsonEncode(body));
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(() =>
          _http.patch(uri, headers: _headersSync(), body: jsonEncode(body)));
    }
    return _handle(res);
  }

  Future<dynamic> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    var res = await _http.delete(uri, headers: await _authHeaders());
    if (res.statusCode == 401) {
      res = await _retryAfterRefresh(
          () => _http.delete(uri, headers: _headersSync()));
    }
    return _handle(res);
  }

  // ── Téléversement Hybride (Standard < 4 Mo / Pré-signé Cloud Direct >= 4 Mo) ──
  MediaType _resolveMediaType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'gif':
        return MediaType('image', 'gif');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'mov':
        return MediaType('video', 'quicktime');
      case 'jpg':
      case 'jpeg':
      default:
        return MediaType('image', 'jpeg');
    }
  }

  /// Téléverse un fichier : route automatiquement vers S3 direct (presign)
  /// pour les vidéos et les fichiers de plus de 4 Mo.
  Future<String> uploadFile({
    required List<int> bytes,
    required String filename,
    String folder = 'general',
  }) async {
    final mediaType = _resolveMediaType(filename);
    final isVideo = mediaType.type == 'video';
    const maxVercelBytes = 4 * 1024 * 1024; // 4 Mo limite Vercel

    // Si c'est une vidéo ou un fichier lourd, utiliser obligatoirement l'URL signée
    if (isVideo || bytes.length >= maxVercelBytes) {
      return uploadPresignedFile(
        bytes: bytes,
        filename: filename,
        contentType: mediaType.toString(),
        folder: folder,
      );
    }

    await _loadSession();
    if (_accessToken == null) {
      throw const ANanNanApiException(401, 'Non connecté');
    }
    final uri = Uri.parse('$baseUrl/api/v1/uploads');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $_accessToken'
      ..fields['folder'] = folder
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: mediaType,
      ));

    var streamed = await _http.send(request);
    var res = await http.Response.fromStream(streamed);

    if (res.statusCode == 401) {
      await refreshSession();
      final retry = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $_accessToken'
        ..fields['folder'] = folder
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: mediaType,
        ));
      streamed = await _http.send(retry);
      res = await http.Response.fromStream(streamed);
    }

    final body = _handle(res) as Map<String, dynamic>;
    return body['url'] as String;
  }

  /// Implémentation conforme OpenAPI de POST /api/v1/uploads/presign
  /// Contourne Vercel en téléversant directement vers S3/Neon Storage
  Future<String> uploadPresignedFile({
    required List<int> bytes,
    required String filename,
    required String contentType,
    String folder = 'publications',
  }) async {
    // 1. Demande de l'URL pré-signée au backend
    final presignData = await post('/api/v1/uploads/presign', body: {
      'filename': filename,
      'content_type': contentType,
      'folder': folder,
      'size_bytes': bytes.length,
    }) as Map<String, dynamic>;

    final uploadUrl = presignData['upload_url'] as String;
    final publicUrl = presignData['public_url'] as String;

    // 2. PUT direct vers le Cloud Storage
    // NOTE : Aucun Bearer Token ici ! S3 rejetterait la signature sinon.
    final uploadResponse = await _http.put(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Type': contentType,
      },
      body: bytes,
    );

    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw ANanNanApiException(
        uploadResponse.statusCode,
        "Échec du transfert direct de la vidéo vers le stockage Cloud.",
      );
    }

    return publicUrl;
  }

  Map<String, String> _headersSync() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $_accessToken',
      };

  Future<http.Response> _retryAfterRefresh(
      Future<http.Response> Function() retry) async {
    try {
      await refreshSession();
      return await retry();
    } catch (_) {
      await clearSession();
      onSessionExpired?.call();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postPublic(String path, Object? body) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await _http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
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
        message = (decoded['detail'] as List)
            .map((e) =>
                e is Map ? '${e['loc']?.last}: ${e['msg']}' : e.toString())
            .join(', ');
      }
    } catch (_) {}
    if (kDebugMode) {
      debugPrint('ANanNanApiClient error ${res.statusCode}: $message');
    }
    throw ANanNanApiException(res.statusCode, message);
  }
}
