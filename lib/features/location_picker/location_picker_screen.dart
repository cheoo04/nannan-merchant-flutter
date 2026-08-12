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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
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
        decoration: const BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: AppColors.foreground),
      ),
    );
  }
}
