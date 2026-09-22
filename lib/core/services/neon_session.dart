// lib/core/services/neon_session.dart
//
// Le marchand Neon courant, une fois résolu via GET /api/v1/merchants/me
// après login (voir LoginScreen._login() dans main.dart). Volontairement
// minimal (pas de ChangeNotifier) — juste un point de stockage unique que
// les écrans/notifiers migrés (ProductsNotifier.setMerchantId, et Dashboard
// une fois migré) peuvent lire dès qu'ils sont créés.
//
// TODO : si un jour la gestion multi-boutiques est nécessaire, ce holder
// devra devenir une vraie liste + une notion de "boutique active".
class NeonSession {
  NeonSession._();

  static String? merchantId;
  static String? merchantName;

  static void setCurrentMerchant(Map<String, dynamic>? merchant) {
    merchantId = merchant?['id'] as String?;
    merchantName = merchant?['name'] as String?;
  }

  static void clear() {
    merchantId = null;
    merchantName = null;
  }
}
