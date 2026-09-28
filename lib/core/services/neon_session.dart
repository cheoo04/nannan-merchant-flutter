// --- Fichier : lib/core/services/neon_session.dart ---
class NeonSession {
  NeonSession._();

  static String? merchantId;
  static String? merchantName;
  static String? businessType;
  static bool isPharmacy = false;

  static void setCurrentMerchant(Map<String, dynamic>? merchant) {
    merchantId = merchant?['id'] as String?;
    merchantName = merchant?['name'] as String?;
    final bType = (merchant?['business_type'] as String? ??
            merchant?['category'] as String? ??
            '')
        .toLowerCase();
    businessType = bType;
    isPharmacy =
        bType == 'pharmacie' || bType == 'pharmacy' || bType.contains('pharma');
  }

  static void clear() {
    merchantId = null;
    merchantName = null;
    businessType = null;
    isPharmacy = false;
  }
}
