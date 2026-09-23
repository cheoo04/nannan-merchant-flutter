// --- Fichier : lib/core/services/a_nan_nan_services.dart ---
import 'a_nan_nan_api_client.dart';

class MerchantService {
  final ANanNanApiClient _api;
  const MerchantService(this._api);

  Future<List<Map<String, dynamic>>> getMine() async =>
      (await _api.get('/api/v1/merchants/me') as List)
          .cast<Map<String, dynamic>>();

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
      await _api.get('/api/v1/merchants/$merchantId/categories')
          as List<dynamic>;

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
        if (parentCategoryId != null && parentCategoryId.isNotEmpty)
          'parent_category_id': parentCategoryId,
        if (description != null && description.isNotEmpty)
          'description': description,
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

  Future<Map<String, dynamic>> create(
    String merchantId, {
    required String title,
    required String slug,
    String type = 'physical_product',
    String? description,
    String status = 'active',
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
        if (description != null && description.isNotEmpty)
          'description': description,
        'status': status,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (images != null && images.isNotEmpty) 'images': images,
        // Ne jamais envoyer une chaîne vide comme UUID
        if (categoryId != null && categoryId.trim().isNotEmpty)
          'category_id': categoryId.trim(),
        if (categoryIds != null && categoryIds.isNotEmpty)
          'category_ids': categoryIds,
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

  Future<List<dynamic>> listForMerchant(String merchantId,
          {String? statusFilter}) async =>
      await _api.get('/api/v1/orders', query: {
        'merchant_id': merchantId,
        if (statusFilter != null) 'status_filter': statusFilter,
      }) as List<dynamic>;

  Future<Map<String, dynamic>> get(String orderId) async =>
      await _api.get('/api/v1/orders/$orderId') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateStatus(
          String orderId, String targetStatus) async =>
      await _api.patch('/api/v1/orders/$orderId/status',
          body: {'target_status': targetStatus}) as Map<String, dynamic>;
}

class PublicationService {
  final ANanNanApiClient _api;
  const PublicationService(this._api);

  Future<List<dynamic>> list(String merchantId,
          {bool activeOnly = true}) async =>
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
        if (description != null && description.isNotEmpty)
          'description': description,
      }) as Map<String, dynamic>;

  Future<Map<String, dynamic>> toggleActive(String publicationId,
          {bool? isActive}) async =>
      await _api.patch('/api/v1/publications/$publicationId/toggle-active',
              body: isActive != null ? {'is_active': isActive} : null)
          as Map<String, dynamic>;

  Future<void> delete(String publicationId) =>
      _api.delete('/api/v1/publications/$publicationId');
}

// ── Ordonnances Médicales ─────────────────────────────────────────────────────
class PrescriptionService {
  final ANanNanApiClient _api;
  const PrescriptionService(this._api);

  Future<List<dynamic>> listForMerchant(String merchantId,
          {String? status}) async =>
      await _api.get('/api/v1/prescriptions', query: {
        'merchant_id': merchantId,
        if (status != null) 'status': status,
      }) as List<dynamic>;

  Future<Map<String, dynamic>> get(String prescriptionId) async =>
      await _api.get('/api/v1/prescriptions/$prescriptionId')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> submitQuote(
    String prescriptionId, {
    required String merchantId,
    required double quotedAmount,
    String? details,
  }) async =>
      await _api.post(
        '/api/v1/prescriptions/$prescriptionId/quote?merchant_id=$merchantId',
        body: {
          'quoted_amount': quotedAmount,
          'currency': 'XOF',
          if (details != null && details.isNotEmpty) 'details': details,
        },
      ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> reject(
    String prescriptionId, {
    String? reason,
  }) async =>
      await _api.post('/api/v1/prescriptions/$prescriptionId/reject', body: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }) as Map<String, dynamic>;
}

// ── Notifications ─────────────────────────────────────────────────────────────
class NotificationService {
  final ANanNanApiClient _api;
  const NotificationService(this._api);

  Future<List<dynamic>> list({int limit = 50, bool unreadOnly = false}) async =>
      await _api.get('/api/v1/notifications', query: {
        'limit': limit.toString(),
        'unread_only': unreadOnly.toString(),
      }) as List<dynamic>;

  Future<int> getUnreadCount() async {
    try {
      final res = await _api.get('/api/v1/notifications/unread-count')
          as Map<String, dynamic>;
      return res['unread_count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAsRead(String notificationId) async =>
      await _api.patch('/api/v1/notifications/$notificationId/read');

  Future<void> registerDeviceToken(
          {required String pushToken, String platform = 'android'}) async =>
      await _api.post('/api/v1/notifications/devices', body: {
        'push_token': pushToken,
        'platform': platform,
      });
}
