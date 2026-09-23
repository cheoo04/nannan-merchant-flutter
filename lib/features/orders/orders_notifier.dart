// --- Fichier : lib/features/orders/orders_notifier.dart ---
import 'package:flutter/foundation.dart';
import '../../shared/models/models.dart';
import '../../shared/merchant_category.dart';
import '../../core/utils/error_message.dart';
import '../../core/services/neon_session.dart';
import 'orders_repository.dart';

class OrdersNotifier extends ChangeNotifier {
  final OrdersRepository _repo;

  List<OrderModel> orders = [];
  Map<String, List<OrderItemModel>> itemsCache = {};
  bool loading = true;
  String? error;

  // État UI
  String activeTab = 'all';
  String? acceptingOrderId;
  String codeInput = '';
  String? busyOrderId;

  String? _merchantId;
  String _merchantCategory = '';

  bool get isPharmacy => categoryNeedsPrescriptionFlow(_merchantCategory);

  OrdersNotifier({OrdersRepository? repo})
      : _repo = repo ?? OrdersRepository() {
    _init();
  }

  Future<void> _init() async {
    _merchantId = NeonSession.merchantId;
    if (_merchantId == null) {
      final merchant = await _repo.resolveMerchant('');
      if (merchant == null) {
        loading = false;
        notifyListeners();
        return;
      }
      _merchantId = merchant.id;
      _merchantCategory = merchant.category;
    }
    await _load();
  }

  Future<void> _load() async {
    if (_merchantId == null) return;
    try {
      orders = await _repo.fetchOrders(_merchantId!);
      error = null;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_merchantId == null) return;
    try {
      orders = await _repo.fetchOrders(_merchantId!);
      error = null;
      notifyListeners();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
    }
  }

  Map<String, int> get counts {
    final c = <String, int>{
      'all': orders.length,
      'pending': 0,
      'accepted': 0,
      'in_delivery': 0,
      'delivered': 0,
      'cancelled': 0,
    };
    for (final o in orders) {
      final key = o.status.dbValue;
      c[key] = (c[key] ?? 0) + 1;
    }
    return c;
  }

  List<OrderModel> get visibleOrders {
    if (activeTab == 'all') return orders;
    return orders.where((o) => o.status.dbValue == activeTab).toList();
  }

  Future<List<OrderItemModel>> fetchItems(String orderId) async {
    if (itemsCache.containsKey(orderId)) return itemsCache[orderId]!;
    final items = await _repo.fetchOrderItems(orderId);
    itemsCache[orderId] = items;
    notifyListeners();
    return items;
  }

  void setTab(String tab) {
    activeTab = tab;
    notifyListeners();
  }

  void startAccept(String orderId) {
    acceptingOrderId = orderId;
    codeInput = '';
    notifyListeners();
  }

  void cancelAccept() {
    acceptingOrderId = null;
    codeInput = '';
    notifyListeners();
  }

  void setCode(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    codeInput = digits.length > 4 ? digits.substring(0, 4) : digits;
    notifyListeners();
  }

  Future<String?> acceptOrder(String orderId) async {
    busyOrderId = orderId;
    notifyListeners();
    try {
      final ok = await _repo.acceptOrder(orderId);
      if (!ok) return 'Commande déjà traitée ou erreur serveur';

      acceptingOrderId = null;
      codeInput = '';
      await refresh();
      return null;
    } catch (e) {
      return friendlyError(e);
    } finally {
      busyOrderId = null;
      notifyListeners();
    }
  }

  Future<String?> refuseOrder(String orderId) async {
    busyOrderId = orderId;
    notifyListeners();
    try {
      final ok = await _repo.refuseOrder(orderId);
      if (!ok) return 'Commande déjà traitée ou erreur serveur';
      await refresh();
      return null;
    } catch (e) {
      return friendlyError(e);
    } finally {
      busyOrderId = null;
      notifyListeners();
    }
  }
}
