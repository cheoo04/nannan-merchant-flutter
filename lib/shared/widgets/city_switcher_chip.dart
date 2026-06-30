import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Affiche la ville du commerce du marchand connecté.
///
/// IMPORTANT — différence volontaire avec le CitySwitcher de l'app client :
/// côté client, changer de ville sert à PARCOURIR les commerces d'une autre
/// ville (cities.code). Côté marchand, la ville est un attribut FIXE du
/// commerce (merchants.city_code) : il n'a qu'UN SEUL commerce, à UN SEUL
/// endroit. Permettre de la changer ici déplacerait silencieusement la
/// boutique d'une ville à l'autre — un changement structurel qui doit
/// passer par l'admin (formulaire dédié), pas un tap accidentel sur un chip.
/// C'est donc un badge d'affichage, pas un vrai sélecteur interactif.
class CitySwitcherChip extends StatelessWidget {
  final String cityCode;

  const CitySwitcherChip({super.key, required this.cityCode});

  static const Map<String, String> _cityNames = {
    'oume': 'Oumé',
    'yakro': 'Yamoussoukro',
  };

  String get _label => _cityNames[cityCode] ?? cityCode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showInfo(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.headerOverlay,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(_label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Votre commerce est enregistré à $_label. '
        'Pour le déplacer vers une autre ville, contactez le support.',
      ),
      duration: const Duration(seconds: 4),
    ));
  }
}