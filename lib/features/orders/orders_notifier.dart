import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';
import '../../shared/merchant_category.dart';
import 'orders_repository.dart';

SupabaseClient get _db => Supabase.instance.client;

class OrdersNotifier extends ChangeNotifier {
  final OrdersRepository _repo;

  List<OrderModel> orders = [];
  Map<String, List<OrderItemModel>> itemsCache = {};
  bool loading = true;
  String? error;

  // État UI
  String activeTab = 'all'; // all | pending | accepted | in_delivery | delivered | cancelled
  String? acceptingOrderId;
  String codeInput = '';
  String? busyOrderId;

  RealtimeChannel? _channel;
  String? _merchantId;
  String _merchantCategory = '';

  bool get isPharmacy => categoryNeedsPrescriptionFlow(_merchantCategory);

  OrdersNotifier({OrdersRepository repo = const OrdersRepository()}) : _repo = repo {
    _init();
  }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loading = false; notifyListeners(); return; }

    final merchant = await _repo.resolveMerchant(user.id);
    if (merchant == null) { loading = false; notifyListeners(); return; }

    _merchantId = merchant.id;
    _merchantCategory = merchant.category;
    await _load();
    _subscribe();
  }

  Future<void> _load() async {
    try {
      orders = await _repo.fetchOrders(_merchantId!);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _subscribe() {
    _channel = _repo.subscribeOrders(
      merchantId: _merchantId!,
      channelName: 'orders-merchant-$_merchantId',
      onChange: _load,
    );
  }

  // ── Counts par statut ─────────────────────────────────────
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

  // ── Chargement items d'une commande ───────────────────────
  Future<List<OrderItemModel>> fetchItems(String orderId) async {
    if (itemsCache.containsKey(orderId)) return itemsCache[orderId]!;
    final items = await _repo.fetchOrderItems(orderId);
    itemsCache[orderId] = items;
    notifyListeners();
    return items;
  }

  // ── Actions UI ────────────────────────────────────────────
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
      // Vérifier le code localement d'abord
      final order = orders.firstWhere((o) => o.id == orderId);
      if (order.acceptCode != codeInput) return 'Code incorrect';

      final ok = await _repo.acceptOrder(orderId);
      if (!ok) return 'Commande déjà traitée';

      acceptingOrderId = null;
      codeInput = '';
      return null; // null = succès
    } catch (e) {
      return e.toString();
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
      if (!ok) return 'Commande déjà traitée';
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      busyOrderId = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_channel != null) _repo.removeChannel(_channel!);
    super.dispose();
  }
}