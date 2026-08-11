# Sélecteur de Position GPS Marchand — Implementation Plan

> **Pour l'exécutant :** ce plan a été rédigé pour être exécuté sur une machine où
> Flutter/Dart sont installés (poste de dev local), pas dans un environnement sans
> ces outils. Toutes les commandes `flutter`/`dart` de ce document doivent y être
> lancées. Les skills `superpowers:subagent-driven-development` et
> `superpowers:executing-plans` ne sont pas disponibles dans l'environnement où ce
> plan a été rédigé (pas d'agents secondaires ici) — exécution en ligne (inline),
> tâche par tâche, avec revue entre chaque tâche.

**Goal:** Permettre à un marchand de renseigner et modifier sa position GPS
(`merchants.lat`/`merchants.lng`) via recherche d'adresse ou position device,
avec ajustement manuel sur une carte — à l'inscription et depuis les réglages boutique.

**Architecture:** Un composant unique `LocationPickerScreen` (carte `flutter_map` +
recherche `NominatimService` + GPS `geolocator`) réutilisé à deux points d'entrée :
`BecomeMerchantScreen` (inscription) et les réglages boutique dans `products_screen.dart`
(modification, via `DashboardNotifier`).

**Tech Stack:** Flutter/Dart, `flutter_map`, `geolocator`, `latlong2`, `http`
(déjà transitif via `supabase_flutter`, ajouté en direct), Nominatim (OpenStreetMap).

## Global Constraints

- SDK Dart : `>=3.3.0 <4.0.0` (contrainte existante du projet, `pubspec.yaml`)
- Colonnes DB déjà existantes, ne pas migrer : `merchants.lat`, `merchants.lng`
  (`double precision`, nullable) — noms de colonnes confirmés, pas `latitude`/`longitude`
- Géocodage : Nominatim public (`https://nominatim.openstreetmap.org/search`),
  paramètre `countrycodes=ci`, respecter la limite de 1 requête/seconde (debounce
  500ms sur la recherche), toujours un `User-Agent` identifiable dans les requêtes
- Ne jamais utiliser Google Maps / Google Places / Mapbox (contrainte du dev client,
  gestion de coûts) — uniquement `flutter_map` + OpenStreetMap + Nominatim
- Toute erreur affichée à l'utilisateur doit passer par `friendlyError()`
  (`lib/core/utils/error_message.dart`) — jamais de `e.toString()` brut
- Ce plan ne couvre pas : l'app Livreur, l'app Client, `orders.delivery_lat/lng`,
  le correctif du compte marchand orphelin (sujets séparés, voir la spec)

---

## Task 1: Dépendances et permissions plateforme

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml:1-16`
- Modify: `ios/Runner/Info.plist:44-46`

**Interfaces:**
- Produces: packages `flutter_map`, `geolocator`, `latlong2`, `http` disponibles
  pour toutes les tâches suivantes.

- [ ] **Step 1: Ajouter les dépendances**

```bash
flutter pub add flutter_map geolocator latlong2 http
```

Cette commande écrit elle-même les bonnes contraintes de version résolues dans
`pubspec.yaml`/`pubspec.lock` — ne pas les taper à la main (les versions exactes
publiées peuvent avoir changé depuis la rédaction de ce plan).

- [ ] **Step 2: Vérifier la résolution**

Run: `flutter pub get`
Expected: `Got dependencies!` sans erreur de conflit de versions.

- [ ] **Step 3: Ajouter la permission Android**

Dans `android/app/src/main/AndroidManifest.xml`, juste après le bloc caméra existant :

```xml
    <!-- Caméra (image_picker — photo produit, ordonnance, couverture boutique) -->
    <uses-permission android:name="android.permission.CAMERA"/>

    <!-- Localisation (position GPS de la boutique) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

    <application
```

- [ ] **Step 4: Ajouter la permission iOS**

Dans `ios/Runner/Info.plist`, juste avant `</dict>` :

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Nannan Marchand utilise votre position pour localiser précisément votre boutique sur la carte.</string>
</dict>
```

- [ ] **Step 5: Vérifier que le projet compile toujours**

Run: `flutter analyze`
Expected: aucune nouvelle erreur (des infos de lint pré-existantes sans rapport
peuvent rester, c'est normal — voir historique du projet).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "chore: ajout flutter_map, geolocator, latlong2, http + permissions localisation"
```

---

## Task 2: `MerchantModel` — champs `lat`/`lng`

**Files:**
- Modify: `lib/shared/models/models.dart:2-56`
- Test: `test/shared/models/merchant_model_test.dart`

**Interfaces:**
- Produces: `MerchantModel.lat` (`double?`), `MerchantModel.lng` (`double?`),
  consommés par les Tasks 5 et 6.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/shared/models/merchant_model_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nannan_merchant/shared/models/models.dart';

void main() {
  group('MerchantModel.fromJson — lat/lng', () {
    test('parses lat and lng when present', () {
      final json = {
        'id': 'm1',
        'owner_id': 'u1',
        'name': 'Boutique Test',
        'category': 'boutique',
        'is_open': true,
        'auto_schedule_enabled': false,
        'status': 'active',
        'city_code': 'oume',
        'created_at': '2026-01-01T00:00:00.000Z',
        'lat': 6.3855,
        'lng': -5.4122,
      };

      final merchant = MerchantModel.fromJson(json);

      expect(merchant.lat, 6.3855);
      expect(merchant.lng, -5.4122);
    });

    test('lat and lng are null when absent', () {
      final json = {
        'id': 'm1',
        'owner_id': 'u1',
        'name': 'Boutique Test',
        'category': 'boutique',
        'is_open': true,
        'auto_schedule_enabled': false,
        'status': 'active',
        'city_code': 'oume',
        'created_at': '2026-01-01T00:00:00.000Z',
      };

      final merchant = MerchantModel.fromJson(json);

      expect(merchant.lat, isNull);
      expect(merchant.lng, isNull);
    });
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `flutter test test/shared/models/merchant_model_test.dart`
Expected: FAIL — `The getter 'lat' isn't defined for the type 'MerchantModel'`

- [ ] **Step 3: Ajouter les champs au modèle**

Dans `lib/shared/models/models.dart`, remplacer :

```dart
  final String cityCode;
  final DateTime createdAt;

  const MerchantModel({
```

par :

```dart
  final String cityCode;
  final double? lat;
  final double? lng;
  final DateTime createdAt;

  const MerchantModel({
```

Puis remplacer :

```dart
    required this.cityCode,
    required this.createdAt,
  });
```

par :

```dart
    required this.cityCode,
    this.lat,
    this.lng,
    required this.createdAt,
  });
```

Puis remplacer :

```dart
        cityCode: j['city_code'] as String? ?? 'oume',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
```

par :

```dart
        cityCode: j['city_code'] as String? ?? 'oume',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
```

(`num?` plutôt que `double?` en cast : Supabase peut renvoyer un entier JSON
pour une valeur `.0`, `toDouble()` couvre les deux cas.)

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `flutter test test/shared/models/merchant_model_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/shared/models/models.dart test/shared/models/merchant_model_test.dart
git commit -m "feat: ajoute lat/lng à MerchantModel"
```

---

## Task 3: `NominatimService` — recherche d'adresse

**Files:**
- Create: `lib/features/location_picker/nominatim_service.dart`
- Test: `test/features/location_picker/nominatim_service_test.dart`

**Interfaces:**
- Produces: `class GeocodingResult { displayName: String, lat: double, lng: double }`,
  `class NominatimService { Future<List<GeocodingResult>> search(String query) }`.
  Consommé par la Task 4.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/features/location_picker/nominatim_service_test.dart` :

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nannan_merchant/features/location_picker/nominatim_service.dart';

void main() {
  group('NominatimService.search', () {
    test('parses a successful response into GeocodingResult list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Oumé marché');
        expect(request.url.queryParameters['countrycodes'], 'ci');
        return http.Response(
          jsonEncode([
            {
              'display_name': "Marché de Oumé, Oumé, Côte d'Ivoire",
              'lat': '6.3855',
              'lon': '-5.4122',
            }
          ]),
          200,
        );
      });

      final service = NominatimService(client: mockClient);
      final results = await service.search('Oumé marché');

      expect(results, hasLength(1));
      expect(results.first.displayName, "Marché de Oumé, Oumé, Côte d'Ivoire");
      expect(results.first.lat, 6.3855);
      expect(results.first.lng, -5.4122);
    });

    test('returns an empty list for an empty query without any HTTP call', () async {
      final service = NominatimService(client: MockClient((request) async {
        fail('No HTTP call should be made for an empty query');
      }));

      final results = await service.search('   ');

      expect(results, isEmpty);
    });

    test('throws when Nominatim responds with a non-200 status', () async {
      final mockClient = MockClient((request) async => http.Response('', 503));
      final service = NominatimService(client: mockClient);

      expect(() => service.search('Oumé'), throwsA(isA<http.ClientException>()));
    });
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

Run: `flutter test test/features/location_picker/nominatim_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:nannan_merchant/features/location_picker/nominatim_service.dart'`

- [ ] **Step 3: Implémenter**

Créer `lib/features/location_picker/nominatim_service.dart` :

```dart
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
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

Run: `flutter test test/features/location_picker/nominatim_service_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/location_picker/nominatim_service.dart test/features/location_picker/nominatim_service_test.dart
git commit -m "feat: service de géocodage Nominatim pour la recherche d'adresse"
```

---

## Task 4: `LocationPickerScreen` — composant carte + recherche + GPS

**Files:**
- Create: `lib/features/location_picker/location_picker_screen.dart`

**Interfaces:**
- Consumes: `NominatimService.search(String)` (Task 3), `friendlyError()`
  (`lib/core/utils/error_message.dart`, déjà existant), `AppColors`
  (`lib/core/theme/app_colors.dart`, déjà existant).
- Produces: `class LocationPickResult { lat: double, lng: double, address: String? }`,
  `class LocationPickerScreen extends StatefulWidget` avec paramètres
  `initialLat: double?`, `initialLng: double?`, `initialAddress: String?`,
  retourné via `Navigator.pop(LocationPickResult)`. Consommé par les Tasks 5 et 6.

Ce composant est un écran plein d'interactions visuelles (carte, GPS device) —
pas de test automatisé pertinent ici ; la vérification se fait manuellement sur
device réel (Task 7), conformément à la spec validée.

- [ ] **Step 1: Créer le fichier**

Créer `lib/features/location_picker/location_picker_screen.dart` :

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/error_message.dart';
import 'nominatim_service.dart';

/// Position sélectionnée, retournée par [LocationPickerScreen] via
/// `Navigator.pop`.
class LocationPickResult {
  final double lat;
  final double lng;
  final String? address;

  const LocationPickResult({required this.lat, required this.lng, this.address});
}

/// Centre par défaut de la carte quand aucune position initiale n'est
/// fournie — Oumé, Côte d'Ivoire (simple point de départ visuel, pas une
/// position précise).
const _defaultCenter = LatLng(6.3833, -5.4167);

/// Écran de sélection de position : recherche d'adresse (Nominatim),
/// position GPS device, ou ajustement manuel en déplaçant la carte
/// sous un marqueur fixé au centre de l'écran.
class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  final _nominatim = NominatimService();

  LatLng? _selected;
  String? _resolvedAddress;
  List<GeocodingResult> _results = [];
  bool _searching = false;
  bool _locating = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _selected = LatLng(widget.initialLat!, widget.initialLng!);
      _resolvedAddress = widget.initialAddress;
      _searchController.text = widget.initialAddress ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    setState(() => _error = null);
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    setState(() => _searching = true);
    try {
      final results = await _nominatim.search(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectResult(GeocodingResult result) {
    final point = LatLng(result.lat, result.lng);
    setState(() {
      _selected = point;
      _resolvedAddress = result.displayName;
      _searchController.text = result.displayName;
      _results = [];
    });
    _mapController.move(point, 17);
  }

  Future<void> _useCurrentPosition() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _error =
            'La localisation est désactivée sur votre téléphone. Activez-la dans les réglages, ou recherchez votre adresse ci-dessus.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _error =
            'Position refusée — recherchez votre adresse ci-dessus, ou autorisez la localisation dans les réglages du téléphone.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _selected = point;
        _resolvedAddress = null;
      });
      _mapController.move(point, 17);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    final point = _selected;
    if (point == null) return;
    Navigator.of(context).pop(LocationPickResult(
      lat: point.latitude,
      lng: point.longitude,
      address: _resolvedAddress,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selected ?? _defaultCenter,
              initialZoom: _selected != null ? 17 : 13,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  setState(() {
                    _selected = camera.center;
                    _resolvedAddress = null;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nannan.nannan_merchant',
              ),
            ],
          ),

          // Marqueur fixe au centre de l'écran — c'est la carte qui bouge
          // en dessous, pas le marqueur (pattern "pin central" classique
          // des apps de livraison, fonctionne sans plugin de drag additionnel).
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.location_pin, size: 44, color: AppColors.primary),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 64),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Rechercher une adresse...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      ),
                    ),
                  ),
                  if (_results.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 4)),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined, size: 20),
                            title: Text(r.displayName,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => _selectResult(r),
                          );
                        },
                      ),
                    ),
                  if (!_searching && _results.isEmpty && _searchController.text.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('Aucune adresse trouvée',
                          style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                    ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(fontSize: 12, color: AppColors.destructive)),
                    ),
                ],
              ),
            ),
          ),

          Positioned(
            left: 12, right: 12, bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _locating ? null : _useCurrentPosition,
                      icon: _locating
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Utiliser ma position actuelle'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.card,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selected == null ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Confirmer cette position',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: AppColors.foreground),
      ),
    );
  }
}
```

- [ ] **Step 2: Vérifier la compilation**

Run: `flutter analyze lib/features/location_picker/location_picker_screen.dart`
Expected: aucune erreur.

⚠️ Si `flutter analyze` signale un renommage sur `MapOptions.onPositionChanged`
ou sur les paramètres de `TileLayer`/`FlutterMap.children` (l'API exacte peut
légèrement varier selon la version de `flutter_map` résolue par `flutter pub add`
à la Task 1) : le principe ne change pas (recalculer `_selected` depuis le centre
de la caméra après un geste utilisateur) — adapter uniquement le nom du callback
d'après ce que `flutter analyze`/l'auto-complétion IDE proposent pour la version
installée.

- [ ] **Step 3: Commit**

```bash
git add lib/features/location_picker/location_picker_screen.dart
git commit -m "feat: écran LocationPickerScreen (carte + recherche + GPS)"
```

---

## Task 5: Intégration à l'inscription (`BecomeMerchantScreen`)

**Files:**
- Modify: `lib/features/become_merchant/become_merchant_screen.dart:40-156,272-389`

**Interfaces:**
- Consumes: `LocationPickerScreen`, `LocationPickResult` (Task 4)

- [ ] **Step 1: Ajouter les champs d'état**

Remplacer (ligne ~44) :

```dart
  final _address = TextEditingController();
```

par :

```dart
  final _address = TextEditingController();
  double? _lat;
  double? _lng;
```

- [ ] **Step 2: Ajouter le handler d'ouverture du sélecteur**

Après la méthode `_submitInfo` (juste avant `// ── Soumission finale`), ajouter :

```dart
  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: _lat,
          initialLng: _lng,
          initialAddress: _address.text.trim().isEmpty ? null : _address.text.trim(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lat = result.lat;
      _lng = result.lng;
      if (result.address != null && result.address!.isNotEmpty) {
        _address.text = result.address!;
      }
    });
  }
```

- [ ] **Step 3: Ajouter l'import**

En haut du fichier, après :

```dart
import '../../core/utils/error_message.dart';
```

ajouter :

```dart
import '../location_picker/location_picker_screen.dart';
```

- [ ] **Step 4: Inclure `lat`/`lng` dans le payload de candidature**

Remplacer (dans `_submitTerms`) :

```dart
          'address': _address.text.trim(),
          'business_name': _businessName.text.trim(),
```

par :

```dart
          'address': _address.text.trim(),
          'lat': _lat,
          'lng': _lng,
          'business_name': _businessName.text.trim(),
```

- [ ] **Step 5: Ajouter le bouton dans `_StepInfo`**

Remplacer la signature de `_StepInfo` :

```dart
class _StepInfo extends StatelessWidget {
  final TextEditingController name, phone, city, address, businessName, description;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onNext;

  const _StepInfo({
    required this.name, required this.phone, required this.city,
    required this.address, required this.businessName, required this.description,
    required this.category, required this.onCategoryChanged, required this.onNext,
  });
```

par :

```dart
class _StepInfo extends StatelessWidget {
  final TextEditingController name, phone, city, address, businessName, description;
  final String category;
  final double? lat;
  final double? lng;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onNext;
  final VoidCallback onPickLocation;

  const _StepInfo({
    required this.name, required this.phone, required this.city,
    required this.address, required this.businessName, required this.description,
    required this.category, this.lat, this.lng,
    required this.onCategoryChanged, required this.onNext, required this.onPickLocation,
  });
```

Puis, remplacer le bloc du champ adresse :

```dart
        _Field(label: 'Adresse du commerce', controller: address,
            placeholder: 'Quartier, repère'),
        const SizedBox(height: 12),
```

par :

```dart
        _Field(label: 'Adresse du commerce', controller: address,
            placeholder: 'Quartier, repère'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onPickLocation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  lat != null ? Icons.check_circle_rounded : Icons.location_on_outlined,
                  size: 16,
                  color: lat != null ? AppColors.success : AppColors.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lat != null ? 'Position définie sur la carte' : 'Localiser mon commerce sur la carte',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: lat != null ? AppColors.success : AppColors.foreground,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.mutedForeground),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
```

- [ ] **Step 6: Passer les nouveaux paramètres à `_StepInfo` depuis le parent**

Remplacer :

```dart
                _Step.info => _StepInfo(
                    name: _name, phone: _phone, city: _city,
                    address: _address, businessName: _businessName,
                    description: _description, category: _category,
                    onCategoryChanged: (v) => setState(() => _category = v),
                    onNext: _submitInfo,
                  ),
```

par :

```dart
                _Step.info => _StepInfo(
                    name: _name, phone: _phone, city: _city,
                    address: _address, businessName: _businessName,
                    description: _description, category: _category,
                    lat: _lat, lng: _lng,
                    onCategoryChanged: (v) => setState(() => _category = v),
                    onNext: _submitInfo,
                    onPickLocation: _pickLocation,
                  ),
```

- [ ] **Step 7: Vérifier la compilation**

Run: `flutter analyze lib/features/become_merchant/become_merchant_screen.dart`
Expected: aucune erreur.

- [ ] **Step 8: Commit**

```bash
git add lib/features/become_merchant/become_merchant_screen.dart
git commit -m "feat: capture de la position GPS à l'inscription marchand"
```

---

## Task 6: Intégration aux réglages boutique (modification)

**Files:**
- Modify: `lib/features/dashboard/dashboard_notifier.dart:245-259`
- Modify: `lib/features/products/products_screen.dart:60-151,875-876`

**Interfaces:**
- Consumes: `LocationPickerScreen`, `LocationPickResult` (Task 4)
- Produces: `DashboardNotifier.updateLocation({required double lat, required double lng, String? address})`,
  `ProductsNotifier.updateLocation(...)` (délègue à `DashboardNotifier`, même signature)

- [ ] **Step 1: Ajouter `updateLocation` à `DashboardNotifier`**

Dans `lib/features/dashboard/dashboard_notifier.dart`, après la méthode `saveSchedule`
(après la ligne `  }` qui suit `      notifyListeners();\n    }\n  }` du bloc `saveSchedule`), ajouter :

```dart
  /// Contrairement aux méthodes ci-dessus (toggleOpen, pauseMerchant,
  /// resumeMerchant, saveSchedule) qui avalent l'erreur en interne sans la
  /// relancer, celle-ci fait un `rethrow` après avoir enregistré l'état —
  /// c'est une action utilisateur explicite (bouton "Confirmer" du sélecteur
  /// de position) et l'écran appelant doit pouvoir afficher un toast d'échec
  /// via son propre try/catch.
  Future<void> updateLocation({
    required double lat,
    required double lng,
    String? address,
  }) async {
    if (merchant == null) return;
    try {
      final patch = <String, dynamic>{'lat': lat, 'lng': lng};
      if (address != null && address.trim().isNotEmpty) {
        patch['address'] = address.trim();
      }
      await _db.from('merchants').update(patch).eq('id', merchant!.id);
      final userId = _db.auth.currentUser?.id;
      if (userId != null) await _loadMerchant(userId);
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }
```

- [ ] **Step 2: Déléguer depuis `ProductsNotifier`**

Dans `lib/features/products/products_screen.dart`, remplacer :

```dart
  Future<void> saveSchedule({required bool enabled, String? opening, String? closing}) =>
      dashboardNotifier.saveSchedule(enabled: enabled, opening: opening, closing: closing);
```

par :

```dart
  Future<void> saveSchedule({required bool enabled, String? opening, String? closing}) =>
      dashboardNotifier.saveSchedule(enabled: enabled, opening: opening, closing: closing);
  Future<void> updateLocation({required double lat, required double lng, String? address}) =>
      dashboardNotifier.updateLocation(lat: lat, lng: lng, address: address);
```

- [ ] **Step 3: Ajouter l'import de `LocationPickerScreen`**

En haut de `lib/features/products/products_screen.dart`, à côté des imports
`core/utils/`, ajouter :

```dart
import '../location_picker/location_picker_screen.dart';
```

- [ ] **Step 4: Ajouter la section "Position" dans `_ShopAvailabilityState`**

Dans `lib/features/products/products_screen.dart`, juste après le bloc
`if (_showSched) ...[ ... ],` de la section horaires (juste avant la fermeture
`        ],\n      ),\n    );\n  }\n}` de `_ShopAvailabilityState.build`), ajouter
un nouveau bloc au même niveau (enfant direct du `Column` principal) :

```dart
          const SizedBox(height: 12),

          // Position GPS
          GestureDetector(
            onTap: () async {
              final result = await Navigator.of(context).push<LocationPickResult>(
                MaterialPageRoute(
                  builder: (_) => LocationPickerScreen(
                    initialLat: m.lat,
                    initialLng: m.lng,
                    initialAddress: m.address,
                  ),
                ),
              );
              if (result == null) return;
              try {
                await widget.notifier.updateLocation(
                  lat: result.lat, lng: result.lng, address: result.address,
                );
                toast.success('Position mise à jour');
              } catch (e) {
                toast.error(friendlyError(e));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    m.lat != null ? Icons.check_circle_rounded : Icons.location_on_outlined,
                    size: 14,
                    color: m.lat != null ? AppColors.success : AppColors.foreground,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Position de la boutique',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    m.lat != null ? 'Définie' : 'Non définie',
                    style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
```

- [ ] **Step 5: Vérifier la compilation**

Run: `flutter analyze lib/features/products/products_screen.dart lib/features/dashboard/dashboard_notifier.dart`
Expected: aucune erreur.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/dashboard_notifier.dart lib/features/products/products_screen.dart
git commit -m "feat: modification de la position GPS depuis les réglages boutique"
```

---

## Task 7: Vérification manuelle finale (QA)

Conformément au skill `verification-before-completion` : ne pas considérer la
fonctionnalité terminée avant d'avoir vérifié manuellement sur un device réel
(ou émulateur avec position simulée) chacun des points suivants.

- [ ] **Step 1: Lancer la suite de tests complète**

Run: `flutter test`
Expected: tous les tests passent, y compris les nouveaux (`merchant_model_test.dart`,
`nominatim_service_test.dart`).

- [ ] **Step 2: Checklist manuelle — Inscription**

- [ ] Ouvrir `BecomeMerchantScreen`, taper une adresse dans la recherche, sélectionner
      un résultat → le marqueur se place au bon endroit sur la carte
- [ ] Ajuster manuellement le marqueur en déplaçant la carte → la position suit
- [ ] Appuyer sur "Utiliser ma position actuelle" → autoriser la permission →
      le marqueur se place sur la position réelle du téléphone
- [ ] Refuser la permission → un message clair s'affiche, la recherche reste utilisable
- [ ] Confirmer → retour à l'écran d'inscription, bouton passé à "Position définie"
- [ ] Soumettre la candidature → vérifier en base que `partner_applications.payload`
      contient bien `lat`/`lng`

- [ ] **Step 3: Checklist manuelle — Réglages boutique**

- [ ] Ouvrir la section réglages boutique d'un compte marchand déjà actif avec
      `lat`/`lng` déjà en base → la carte s'ouvre centrée dessus
- [ ] Modifier la position, confirmer → toast de succès, `merchants.lat`/`lng`
      mis à jour en base
- [ ] Couper le réseau puis retenter → toast d'erreur lisible (pas de message technique brut)

- [ ] **Step 4: Commit final si des ajustements ont été faits pendant la QA**

```bash
git add -A
git commit -m "fix: ajustements suite à la vérification manuelle QA position GPS"
```

---

## Point ouvert à traiter séparément (hors ce plan)

La fonction `approve_partner_application()` (base de données, hors dépôt) doit
recopier `payload.lat`/`payload.lng` vers `merchants.lat`/`merchants.lng` au moment
de la création de la ligne marchand. À vérifier/adapter en base une fois ce plan
exécuté — sinon la capture à l'inscription (Task 5) n'aura aucun effet réel tant
que cette fonction ne le fait pas.
