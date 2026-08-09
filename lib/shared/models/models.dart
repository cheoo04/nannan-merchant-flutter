// ── MerchantModel ─────────────────────────────────────────────────────────────
class MerchantModel {
  final String id;
  final String ownerId;
  final String name;
  final String category;
  final String? description;
  final String? address;
  final String? phone;
  final String? imageUrl;
  final bool isOpen;
  final String? openingTime;
  final String? closingTime;
  final String? pauseUntil;
  final bool autoScheduleEnabled;
  final String status; // pending | active | suspended
  final String cityCode;
  final DateTime createdAt;

  const MerchantModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.category,
    this.description,
    this.address,
    this.phone,
    this.imageUrl,
    required this.isOpen,
    this.openingTime,
    this.closingTime,
    this.pauseUntil,
    required this.autoScheduleEnabled,
    required this.status,
    required this.cityCode,
    required this.createdAt,
  });

  factory MerchantModel.fromJson(Map<String, dynamic> j) => MerchantModel(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        description: j['description'] as String?,
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        imageUrl: j['image_url'] as String?,
        isOpen: j['is_open'] as bool? ?? false,
        openingTime: j['opening_time'] as String?,
        closingTime: j['closing_time'] as String?,
        pauseUntil: j['pause_until'] as String?,
        autoScheduleEnabled: j['auto_schedule_enabled'] as bool? ?? false,
        status: j['status']?.toString() ?? 'pending',
        cityCode: j['city_code'] as String? ?? 'oume',
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  /// Calcule si le commerce est ouvert maintenant
  /// Miroir exact de isMerchantOpenNow() du React
  bool get isOpenNow {
    if (status != 'active') return false;
    if (!isOpen) return false;
    if (pauseUntil != null &&
        DateTime.parse(pauseUntil!).isAfter(DateTime.now())) return false;
    if (autoScheduleEnabled && openingTime != null && closingTime != null) {
      final now = DateTime.now().toUtc();
      final cur = now.hour * 3600 + now.minute * 60;
      int toSec(String t) {
        final parts = t.split(':').map(int.parse).toList();
        return parts[0] * 3600 + parts[1] * 60;
      }

      final o = toSec(openingTime!);
      final c = toSec(closingTime!);
      if (o <= c) {
        if (cur < o || cur > c) return false;
      } else if (cur < o && cur > c) {
        return false;
      }
    }
    return true;
  }

  /// Libellé + état (miroir de merchantStatusLabel du React)
  ({String label, String tone}) get statusLabel {
    if (pauseUntil != null &&
        DateTime.parse(pauseUntil!).isAfter(DateTime.now())) {
      return (label: 'En pause', tone: 'paused');
    }
    return isOpen
        ? (label: 'Boutique ouverte', tone: 'open')
        : (label: 'Boutique fermée', tone: 'closed');
  }
}

// ── OrderStatus ───────────────────────────────────────────────────────────────
enum OrderStatus {
  pending,
  accepted,
  inDelivery,
  delivered,
  cancelled,
  refunded;

  static OrderStatus fromString(String s) => switch (s) {
        'pending' => OrderStatus.pending,
        'accepted' => OrderStatus.accepted,
        'in_delivery' => OrderStatus.inDelivery,
        'delivered' => OrderStatus.delivered,
        'cancelled' => OrderStatus.cancelled,
        'refunded' => OrderStatus.refunded,
        _ => OrderStatus.pending,
      };

  String get dbValue => switch (this) {
        OrderStatus.inDelivery => 'in_delivery',
        _ => name,
      };
}

// ── OrderModel ────────────────────────────────────────────────────────────────
class OrderModel {
  final String id;
  final String clientId;
  final String merchantId;
  final String? courierId;
  final OrderStatus status;
  final int totalAmount;       // anciennement total_xof → total_amount
  final String paymentMethod;
  final String paymentStatus;
  final String? deliveryAddressId;  // FK vers user_addresses
  final String? deliveryAddressText;  // résolu via join user_addresses (label + detail)
  final double? deliveryLat;
  final double? deliveryLng;
  final String? clientComment;
  final String deliveryMode;
  final int deliveryFee;       // anciennement delivery_fee_xof → delivery_fee
  final String? cashChangeNeeded;
  final String acceptCode;
  final String pickupCode;
  final String deliveryCode;
  final String? scheduledAt;
  final String cityCode;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? merchantConfirmedAt;

  const OrderModel({
    required this.id,
    required this.clientId,
    required this.merchantId,
    this.courierId,
    required this.status,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.deliveryAddressId,
    this.deliveryAddressText,
    this.deliveryLat,
    this.deliveryLng,
    this.clientComment,
    required this.deliveryMode,
    required this.deliveryFee,
    this.cashChangeNeeded,
    required this.acceptCode,
    required this.pickupCode,
    required this.deliveryCode,
    this.scheduledAt,
    required this.cityCode,
    required this.createdAt,
    this.deliveredAt,
    this.merchantConfirmedAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    // Le join user_addresses est optionnel (présent si la query inclut
    // '*, address:user_addresses!delivery_address_id(label,detail,lat,lng)')
    final addr = j['address'] as Map<String, dynamic>?;
    String? addrText;
    if (addr != null) {
      final label = addr['label'] as String? ?? '';
      final detail = addr['detail'] as String? ?? '';
      addrText = [label, detail].where((s) => s.isNotEmpty).join(' — ');
    }

    return OrderModel(
      id: j['id'] as String,
      clientId: j['client_id'] as String,
      merchantId: j['merchant_id'] as String,
      courierId: j['courier_id'] as String?,
      status: OrderStatus.fromString(j['status']?.toString() ?? 'pending'),
      totalAmount: j['total_amount'] as int? ?? 0,
      paymentMethod: j['payment_method']?.toString() ?? 'cash',
      paymentStatus: j['payment_status']?.toString() ?? 'pending',
      deliveryAddressId: j['delivery_address_id'] as String?,
      deliveryAddressText: addrText,
      deliveryLat: (j['address'] as Map?)?.tryGet<double>('lat'),
      deliveryLng: (j['address'] as Map?)?.tryGet<double>('lng'),
      clientComment: j['client_comment'] as String?,
      deliveryMode: j['delivery_mode']?.toString() ?? 'standard',
      deliveryFee: j['delivery_fee'] as int? ?? 0,
      cashChangeNeeded: j['cash_change_needed'] as String?,
      acceptCode: j['accept_code'] as String? ?? '----',
      pickupCode: j['pickup_code'] as String? ?? '----',
      deliveryCode: j['delivery_code'] as String? ?? '----',
      scheduledAt: j['scheduled_at'] as String?,
      cityCode: j['city_code'] as String? ?? 'oume',
      createdAt: DateTime.parse(j['created_at'] as String),
      deliveredAt: j['delivered_at'] != null
          ? DateTime.parse(j['delivered_at'] as String)
          : null,
      merchantConfirmedAt: j['merchant_confirmed_at'] != null
          ? DateTime.parse(j['merchant_confirmed_at'] as String)
          : null,
    );
  }
}

// Helper extension pour éviter les crashes sur les maps imbriquées
extension _MapGet on Map {
  T? tryGet<T>(String key) {
    try { return this[key] as T?; } catch (_) { return null; }
  }
}

// ── OrderItemModel ───────────────────────────────────────────────────────────
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

// ── NotificationRow ───────────────────────────────────────────────────────────
class NotificationRow {
  final String id;
  final String userId;
  final String type; // order | delivery | payment | system
  final String title;
  final String? body;
  final String? orderId;
  final DateTime? readAt;
  final DateTime createdAt;

  // Contexte commande — permet d'afficher "Commande #1234 · 2 200 F" sur
  // la notif sans écran dédié, alimenté par la jointure orders() du fetch.
  // Restent null si orderId est null, ou si la commande n'existe plus.
  final String? orderAcceptCode;
  final int? orderTotalAmount;
  final String? orderStatus;

  const NotificationRow({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.orderId,
    this.readAt,
    required this.createdAt,
    this.orderAcceptCode,
    this.orderTotalAmount,
    this.orderStatus,
  });

  bool get isUnread => readAt == null;

  factory NotificationRow.fromJson(Map<String, dynamic> j) {
    final order = j['orders'] as Map<String, dynamic>?;
    return NotificationRow(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      type: j['type']?.toString() ?? 'system',
      title: j['title'] as String? ?? '',
      body: j['body'] as String?,
      orderId: j['order_id'] as String?,
      readAt: j['read_at'] != null ? DateTime.parse(j['read_at'] as String) : null,
      createdAt: DateTime.parse(j['created_at'] as String),
      orderAcceptCode: order?['accept_code'] as String?,
      orderTotalAmount: order?['total_amount'] as int?,
      orderStatus: order?['status'] as String?,
    );
  }
}