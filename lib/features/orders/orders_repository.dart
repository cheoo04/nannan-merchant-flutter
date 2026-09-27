import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';
import '../../core/utils/error_message.dart';
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

  Future<List<OrderItemModel>> fetchOrderItems(String orderId) async {
    final order = await _orderService.get(orderId);
    final items = (order['items'] as List?) ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map((e) => OrderItemModel.fromJson(e))
        .toList();
  }

  // Tente de confirmer ou de préparer la commande sur le serveur Neon
  Future<String?> acceptOrder(String orderId, {OrderStatus? currentStatus}) async {
    try {
      try {
        await _orderService.updateStatus(orderId, 'preparing');
        return null;
      } catch (_) {
        await _orderService.updateStatus(orderId, 'confirmed');
        return null;
      }
    } catch (e) {
      return friendlyError(e);
    }
  }

  Future<String?> refuseOrder(String orderId) async {
    try {
      await _orderService.updateStatus(orderId, 'cancelled');
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }
}
