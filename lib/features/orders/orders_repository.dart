// --- Fichier : lib/features/orders/orders_repository.dart ---
import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';
import '../../shared/models/models.dart';

class MerchantIdentity {
  final String id;
  final String category;
  const MerchantIdentity({required this.id, required this.category});
}

class OrdersRepository {
  final ANanNanApiClient _api;
  final OrderService _orderService;

  OrdersRepository({ANanNanApiClient? api})
      : _api = api ?? ANanNanApiClient(),
        _orderService = OrderService(api ?? ANanNanApiClient());

  /// Résout le marchand à partir de GET /api/v1/merchants/me
  Future<MerchantIdentity?> resolveMerchant(String userId) async {
    try {
      final merchants = await MerchantService(_api).getMine();
      if (merchants.isEmpty) return null;
      final m = merchants.first;
      return MerchantIdentity(
        id: m['id'] as String,
        category: (m['business_type'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Charge les commandes d'un marchand depuis l'API Neon
  Future<List<OrderModel>> fetchOrders(
    String merchantId, {
    String? statusFilter,
  }) async {
    final data = await _orderService.listForMerchant(
      merchantId,
      statusFilter: statusFilter,
    );
    return data
        .cast<Map<String, dynamic>>()
        .map((e) => OrderModel.fromJson(e))
        .toList();
  }

  /// Récupère les items d'une commande via GET /api/v1/orders/{orderId}
  Future<List<OrderItemModel>> fetchOrderItems(String orderId) async {
    final order = await _orderService.get(orderId);
    final items = (order['items'] as List?) ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map((e) => OrderItemModel.fromJson(e))
        .toList();
  }

  /// Accepter la commande -> passe le statut à 'preparing' ou 'confirmed'
  Future<bool> acceptOrder(String orderId) async {
    try {
      await _orderService.updateStatus(orderId, 'preparing');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Refuser ou annuler la commande -> passe le statut à 'cancelled'
  Future<bool> refuseOrder(String orderId) async {
    try {
      await _orderService.updateStatus(orderId, 'cancelled');
      return true;
    } catch (_) {
      return false;
    }
  }
}
