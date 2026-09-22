// lib/core/services/a_nan_nan_services.dart
//
// Services métier au-dessus de ANanNanApiClient. Mis à jour le 19/09 après
// que le backend a ajouté : image_url/images sur les offerings, logo_url/
// story_images sur les merchants, stock_quantity/is_in_stock sur les
// variantes, et un vrai système de catégories. Les anciens TODO temporaires
// (metadata_ comme solution de contournement pour l'image) sont retirés.

import 'a_nan_nan_api_client.dart';

class MerchantService {
  final ANanNanApiClient _api;
  const MerchantService(this._api);

  /// GET /api/v1/merchants/me — livré par le backend le 20/09, résout le
  /// blocage central de la migration. Retourne les marchands dont
  /// l'utilisateur connecté est owner/staff. Vide = pas encore marchand,
  /// un seul = cas normal, plusieurs = multi-boutiques (pas encore géré
  /// dans l'UI — à faire quand un vrai cas se présente).
  Future<List<Map<String, dynamic>>> getMine() async =>
      (await _api.get('/api/v1/merchants/me') as List).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> getById(String merchantId) async =>
      await _api.get('/api/v1/merchants/$merchantId') as Map<String, dynamic>;

  Future<Map<String, dynamic>> create({
    required String name,
    required String slug,
    String businessType = 'retail',
    String? organizationId,
    String? logoUrl,
    String? bannerUrl,
    double? latitude,
    double? longitude,
    String? address,
    String? phone,
    List<String>? storyImages,
  }) async =>
      await _api.post('/api/v1/merchants', body: {
        'name': name,
        'slug': slug,
        'business_type': businessType,
        if (organizationId != null) 'organization_id': organizationId,
        if (logoUrl != null) 'logo_url': logoUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (storyImages != null) 'story_images': storyImages,
      }) as Map<String, dynamic>;

  Future<Map<String, dynamic>> update(
    String merchantId, {
    String? name,
    String? businessType,
    String? logoUrl,
    String? bannerUrl,
    double? latitude,
    double? longitude,
    String? address,
    String? phone,
    List<String>? storyImages,
    Map<String, dynamic>? settings,
  }) async =>
      await _api.patch('/api/v1/merchants/$merchantId', body: {
        if (name != null) 'name': name,
        if (businessType != null) 'business_type': businessType,
        if (logoUrl != null) 'logo_url': logoUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (storyImages != null) 'story_images': storyImages,
        if (settings != null) 'settings': settings,
      }) as Map<String, dynamic>;
}

class CategoryService {
  final ANanNanApiClient _api;
  const CategoryService(this._api);

  Future<List<dynamic>> list(String merchantId) async =>
      await _api.get('/api/v1/merchants/$merchantId/categories') as List<dynamic>;

  Future<Map<String, dynamic>> create(
    String merchantId, {
    required String name,
    required String slug,
    String? parentCategoryId,
    String? description,
  }) async =>
      await _api.post('/api/v1/merchants/$merchantId/categories', body: {
        'name': name,
        'slug': slug,
        if (parentCategoryId != null) 'parent_category_id': parentCategoryId,
        if (description != null) 'description': description,
      }) as Map<String, dynamic>;
}

class OfferingService {
  final ANanNanApiClient _api;
  const OfferingService(this._api);

  Future<List<dynamic>> list(String merchantId, {String? status}) async =>
      await _api.get('/api/v1/merchants/$merchantId/offerings',
          query: status != null ? {'status': status} : null) as List<dynamic>;

  Future<Map<String, dynamic>> get(String offeringId) async =>
      await _api.get('/api/v1/offerings/$offeringId') as Map<String, dynamic>;

  /// type: physical_product | restaurant_meal | service | digital_product | bundle
  /// Chaque offre doit avoir au moins 1 variante (prix, éventuellement sku,
  /// stockQuantity/isInStock).
  Future<Map<String, dynamic>> create(
    String merchantId, {
    required String title,
    required String slug,
    String type = 'physical_product',
    String? description,
    String status = 'draft',
    required double price,
    int? stockQuantity,
    bool isInStock = true,
    String? imageUrl,
    List<String>? images,
    String? categoryId,
    List<String>? categoryIds,
  }) async =>
      await _api.post('/api/v1/merchants/$merchantId/offerings', body: {
        'type': type,
        'title': title,
        'slug': slug,
        if (description != null) 'description': description,
        'status': status,
        if (imageUrl != null) 'image_url': imageUrl,
        if (images != null) 'images': images,
        if (categoryId != null) 'category_id': categoryId,
        if (categoryIds != null) 'category_ids': categoryIds,
        'variants': [
          {
            'price': price,
            'is_default': true,
            'position': 0,
            if (stockQuantity != null) 'stock_quantity': stockQuantity,
            'is_in_stock': isInStock,
          }
        ],
      }) as Map<String, dynamic>;
}

class OrderService {
  final ANanNanApiClient _api;
  const OrderService(this._api);

  Future<List<dynamic>> listForMerchant(String merchantId, {String? statusFilter}) async =>
      await _api.get('/api/v1/orders', query: {
        'merchant_id': merchantId,
        if (statusFilter != null) 'status_filter': statusFilter,
      }) as List<dynamic>;

  Future<Map<String, dynamic>> get(String orderId) async =>
      await _api.get('/api/v1/orders/$orderId') as Map<String, dynamic>;

  /// target_status: confirmed | preparing | ready_for_pickup | delivering | delivered | cancelled
  Future<Map<String, dynamic>> updateStatus(String orderId, String targetStatus) async =>
      await _api.patch('/api/v1/orders/$orderId/status',
          body: {'target_status': targetStatus}) as Map<String, dynamic>;
}

/// Substitut aux "stories" en attendant un vrai endpoint dédié — utilise
/// /api/v1/merchants/{id}/publications (image/vidéo + description, pas
/// d'expiration 24h contrairement aux vraies stories, contrôlé par is_active).
/// NOTE: merchants.story_images (tableau simple) existe aussi maintenant —
/// à choisir avec le backend lequel des deux est la voie officielle pour
/// les stories avant de s'engager dans l'un ou l'autre côté Marchand.
class PublicationService {
  final ANanNanApiClient _api;
  const PublicationService(this._api);

  Future<List<dynamic>> list(String merchantId, {bool activeOnly = true}) async =>
      await _api.get('/api/v1/merchants/$merchantId/publications',
          query: {'active_only': activeOnly.toString()}) as List<dynamic>;

  Future<Map<String, dynamic>> create(
    String merchantId, {
    required String title,
    required String mediaUrl,
    String mediaType = 'image',
    String? description,
  }) async =>
      await _api.post('/api/v1/merchants/$merchantId/publications', body: {
        'title': title,
        'media_url': mediaUrl,
        'media_type': mediaType,
        if (description != null) 'description': description,
      }) as Map<String, dynamic>;

  Future<Map<String, dynamic>> toggleActive(String publicationId, {bool? isActive}) async =>
      await _api.patch('/api/v1/publications/$publicationId/toggle-active',
          body: isActive != null ? {'is_active': isActive} : null) as Map<String, dynamic>;

  Future<void> delete(String publicationId) => _api.delete('/api/v1/publications/$publicationId');
}
