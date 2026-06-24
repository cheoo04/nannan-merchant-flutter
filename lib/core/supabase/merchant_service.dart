import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';

/// Accès rapide au client Supabase
SupabaseClient get _supabase => Supabase.instance.client;

// ============================================================
// MERCHANT SERVICE — Toutes les opérations DB côté marchand
// ============================================================

class MerchantService {
  // ── Profil marchand ──────────────────────────────────────

  /// Récupère le commerce du marchand connecté
  static Future<MerchantModel?> getMyMerchant() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await _supabase
        .from('merchants')
        .select()
        .eq('owner_id', userId)
        .maybeSingle();

    return data != null ? MerchantModel.fromJson(data) : null;
  }

  /// Active/désactive la boutique (toggle Ouvert/Fermé)
  static Future<void> setMerchantOpen(String merchantId, bool isOpen) async {
    final patch = <String, dynamic>{'is_open': isOpen};
    if (isOpen) patch['pause_until'] = null; // Annule la pause si on réouvre

    final response = await _supabase
        .from('merchants')
        .update(patch)
        .eq('id', merchantId);

    if (response.error != null) throw response.error!;
  }

  /// Met à jour la photo du commerce
  static Future<void> setMerchantImage(String merchantId, String? imageUrl) async {
    await _supabase
        .from('merchants')
        .update({'image_url': imageUrl})
        .eq('id', merchantId);
  }

  // ── Commandes ─────────────────────────────────────────────

  /// Charge les commandes du marchand connecté
  static Future<List<OrderModel>> getMerchantOrders({
    List<String>? statuses,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    // 1. Récupérer l'id du merchant via owner_id
    final merchant = await getMyMerchant();
    if (merchant == null) return [];

    var query = _supabase
        .from('orders')
        .select()
        .eq('merchant_id', merchant.id)
        .order('created_at', ascending: false)
        .limit(200);

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    }

    final data = await query;
    return (data as List).map((e) => OrderModel.fromJson(e)).toList();
  }

  /// Accepter une commande avec le code de validation
  static Future<void> acceptOrder(String orderId, String acceptCode) async {
    // Vérification du code côté client avant d'envoyer
    final order = await _supabase
        .from('orders')
        .select('accept_code')
        .eq('id', orderId)
        .single();

    if (order['accept_code'] != acceptCode) {
      throw Exception('Code de validation incorrect');
    }

    await _supabase.from('orders').update({
      'status': 'accepted',
      'merchant_confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Refuser une commande
  static Future<void> refuseOrder(String orderId) async {
    await _supabase.from('orders').update({
      'status': 'cancelled',
    }).eq('id', orderId);
  }

  /// Récupère les articles d'une commande
  static Future<List<OrderItemModel>> getOrderItems(String orderId) async {
    final data = await _supabase
        .from('order_items')
        .select()
        .eq('order_id', orderId)
        .order('created_at');

    return (data as List).map((e) => OrderItemModel.fromJson(e)).toList();
  }

  // ── Produits ──────────────────────────────────────────────

  /// Récupère tous les produits du marchand
  static Future<List<ProductModel>> getMerchantProducts(String merchantId) async {
    final data = await _supabase
        .from('products')
        .select()
        .eq('merchant_id', merchantId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => ProductModel.fromJson(e)).toList();
  }

  /// Crée un nouveau produit
  static Future<void> createProduct(ProductModel product, String merchantId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Non connecté');

    await _supabase.from('products').insert(
      product.toInsertJson(merchantId: merchantId, addedByUserId: userId),
    );
  }

  /// Met à jour un produit
  static Future<void> updateProduct(String productId, Map<String, dynamic> patch) async {
    await _supabase.from('products').update(patch).eq('id', productId);
  }

  /// Active/désactive la disponibilité d'un produit
  static Future<void> toggleProductAvailability(String productId, bool isAvailable) async {
    await _supabase.from('products').update({
      'is_available': isAvailable,
    }).eq('id', productId);
  }

  /// Supprime un produit
  static Future<void> deleteProduct(String productId) async {
    await _supabase.from('products').delete().eq('id', productId);
  }

  // ── Prescriptions (Pharmacie) ─────────────────────────────

  /// Récupère les ordonnances du marchand (pharmacie)
  static Future<List<PrescriptionModel>> getMerchantPrescriptions(String merchantId) async {
    final data = await _supabase
        .from('prescriptions')
        .select()
        .eq('merchant_id', merchantId)
        .order('created_at', ascending: false);

    return (data as List).map((e) => PrescriptionModel.fromJson(e)).toList();
  }

  /// Envoie un devis au client
  static Future<void> sendQuote(
    String prescriptionId, {
    required List<Map<String, dynamic>> quoteItems,
    required int deliveryFee,
    required int estimatedMinutes,
    String? pharmacistNote,
  }) async {
    final subtotal = quoteItems.fold<int>(
      0,
      (sum, item) => sum + ((item['qty'] as int) * (item['unit_price_xof'] as int)),
    );

    await _supabase.from('prescriptions').update({
      'status': 'quoted',
      'quote_items': quoteItems,
      'products_subtotal_xof': subtotal,
      'delivery_fee_xof': deliveryFee,
      'total_xof': subtotal + deliveryFee,
      'estimated_ready_minutes': estimatedMinutes,
      'pharmacist_note': pharmacistNote,
      'quoted_at': DateTime.now().toIso8601String(),
    }).eq('id', prescriptionId);
  }

  /// Change le statut d'une ordonnance
  static Future<void> updatePrescriptionStatus(
    String prescriptionId,
    String status,
  ) async {
    await _supabase.from('prescriptions').update({
      'status': status,
    }).eq('id', prescriptionId);
  }

  // ── Upload images ─────────────────────────────────────────

  /// Upload une photo produit dans Supabase Storage
  /// Retourne l'URL publique
  static Future<String> uploadProductImage(
    List<int> bytes,
    String fileName,
    String merchantId,
  ) async {
    final path = 'products/$merchantId/$fileName';
    await _supabase.storage.from('products').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    return _supabase.storage.from('products').getPublicUrl(path);
  }
}
