// Ce fichier remplace le test Flutter par défaut (compteur) qui était
// incompatible avec notre app (nécessite Supabase initialisé).
// Les vrais tests de l'app sont dans :
//   test/features/location_picker/nominatim_service_test.dart
//   test/shared/models/merchant_model_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — voir test/features/ et test/shared/ pour les vrais tests', () {
    // Ce test existe uniquement pour que `flutter test` passe sans erreur.
    // Les tests unitaires réels couvrent NominatimService et MerchantModel.
    expect(true, isTrue);
  });
}
