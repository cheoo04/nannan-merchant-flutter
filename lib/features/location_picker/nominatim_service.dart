import 'dart:convert';

import 'package:http/http.dart' as http;

/// Un résultat de recherche d'adresse renvoyé par Nominatim.
class GeocodingResult {
  final String displayName;
  final double lat;
  final double lng;

  const GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lng,
  });

  factory GeocodingResult.fromJson(Map<String, dynamic> j) => GeocodingResult(
        displayName: j['display_name'] as String,
        lat: double.parse(j['lat'] as String),
        lng: double.parse(j['lon'] as String),
      );
}

/// Recherche d'adresse via le service public Nominatim (OpenStreetMap).
/// Gratuit, sans clé API — cohérent avec le choix de `flutter_map` déjà
/// fait pour le reste du projet (pas de Google Maps / Mapbox).
class NominatimService {
  final http.Client _client;

  NominatimService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://nominatim.openstreetmap.org/search';

  /// Recherche des adresses en Côte d'Ivoire correspondant à [query].
  /// Retourne une liste vide pour une requête vide (aucun appel réseau fait).
  Future<List<GeocodingResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': query,
      'countrycodes': 'ci',
      'format': 'json',
      'limit': '5',
    });

    final response = await _client.get(
      uri,
      headers: {'User-Agent': 'NannanMerchantApp/1.0 (com.nannan.nannan_merchant)'},
    );

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Nominatim a répondu avec le code ${response.statusCode}',
        uri,
      );
    }

    final data = jsonDecode(response.body) as List;
    return data
        .map((e) => GeocodingResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
