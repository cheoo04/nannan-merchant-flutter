import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';
import '../../shared/merchant_category.dart';

SupabaseClient get _db => Supabase.instance.client;

class OrdersNotifier extends ChangeNotifier {
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

  OrdersNotifier() {
    _init();
  }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loading = false; notifyListeners(); return; }

    final m = await _db.from('merchants').select('id, category').eq('owner_id', user.id).maybeSingle();
    if (m == null) { loading = false; notifyListeners(); return; }

    _merchantId = m['id'] as String;
    _merchantCategory = (m['category'] as String?) ?? '';
    await _load();
    _subscribe();
  }

  Future<void> _load() async {
    try {
      final data = await _db
          .from('orders')
          .select()
          .eq('merchant_id', _merchantId!)
          .order('created_at', ascending: false)
          .limit(200);
      orders = (data as List).map((e) => OrderModel.fromJson(e)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _subscribe() {
    _channel = _db
        .channel('orders-merchant-$_merchantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'merchant_id',
            value: _merchantId!,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
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
    final data = await _db
        .from('order_items')
        .select()
        .eq('order_id', orderId)
        .order('created_at');
    final items = (data as List).map((e) => OrderItemModel.fromJson(e)).toList();
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

      // .eq('status', 'pending') : garde-fou contre un double traitement
      // (ex: deux onglets ouverts, ou commande déjà traitée entre-temps).
      final updated = await _db.from('orders').update({
        'status': 'accepted',
        'merchant_confirmed_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId).eq('status', 'pending').select();

      if ((updated as List).isEmpty) return 'Commande déjà traitée';

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
      final updated = await _db.from('orders')
          .update({'status': 'cancelled'})
          .eq('id', orderId)
          .eq('status', 'pending')
          .select();
      if ((updated as List).isEmpty) return 'Commande déjà traitée';
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
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }
}

// ── OrderItemModel (ajout ici pour éviter import circulaire) ──
class OrderItemModel {
  final String id;
  final String orderId;
  final String? productId;
  final String productName;
  final String? productImage;
  final int qty;
  final int unitPrice;

  const OrderItemModel({
    required this.id,
    required this.orderId,
    this.productId,
    required this.productName,
    this.productImage,
    required this.qty,
    required this.unitPrice,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> j) => OrderItemModel(
        id: j['id'] as String,
        orderId: j['order_id'] as String,
        productId: j['product_id'] as String?,
        productName: j['product_name'] as String,
        productImage: j['product_image'] as String?,
        qty: j['qty'] as int,
        unitPrice: j['unit_price'] as int,
      );

  int get subtotal => qty * unitPrice;
}