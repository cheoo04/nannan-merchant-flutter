// --- Fichier : lib/shared/models/models.dart ---

// Helper de conversion sécurisé pour éviter tout crash de type
int _parseInt(dynamic value, [int defaultValue = 0]) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    return double.tryParse(value)?.round() ?? defaultValue;
  }
  return defaultValue;
}

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
  final String status;
  final String cityCode;
  final double? lat;
  final double? lng;
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
    this.lat,
    this.lng,
    required this.createdAt,
  });

  factory MerchantModel.fromJson(Map<String, dynamic> j) {
    final settings = j['settings'] as Map<String, dynamic>?;

    final openStatus = j['status']?.toString() ?? 'pending';
    final isOpenSetting =
        settings?['is_open'] as bool? ?? (openStatus == 'active');

    return MerchantModel(
      id: j['id'] as String,
      ownerId:
          j['owner_id'] as String? ?? j['organization_id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      category: j['business_type'] as String? ??
          j['category'] as String? ??
          'commerce',
      description: j['description'] as String?,
      address: j['address'] as String?,
      phone: j['phone'] as String?,
      imageUrl: j['logo_url'] as String? ?? j['image_url'] as String?,
      isOpen: isOpenSetting,
      openingTime:
          settings?['opening_time'] as String? ?? j['opening_time'] as String?,
      closingTime:
          settings?['closing_time'] as String? ?? j['closing_time'] as String?,
      pauseUntil:
          settings?['pause_until'] as String? ?? j['pause_until'] as String?,
      autoScheduleEnabled: settings?['auto_schedule_enabled'] as bool? ??
          j['auto_schedule_enabled'] as bool? ??
          false,
      status: openStatus,
      cityCode: j['city_code'] as String? ?? 'oume',
      lat:
          (j['latitude'] as num?)?.toDouble() ?? (j['lat'] as num?)?.toDouble(),
      lng: (j['longitude'] as num?)?.toDouble() ??
          (j['lng'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isOpenNow {
    if (status != 'active' && !isOpen) return false;
    if (pauseUntil != null && DateTime.tryParse(pauseUntil!) != null) {
      if (DateTime.parse(pauseUntil!).isAfter(DateTime.now())) {
        return false;
      }
    }
    return isOpen;
  }

  ({String label, String tone}) get statusLabel {
    if (pauseUntil != null && DateTime.tryParse(pauseUntil!) != null) {
      if (DateTime.parse(pauseUntil!).isAfter(DateTime.now())) {
        return (label: 'En pause', tone: 'paused');
      }
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

  // Mappe les statuts réels du backend Neon OpenAPI avec les onglets UI
  static OrderStatus fromString(String s) => switch (s.toLowerCase()) {
        'pending' || 'confirmed' => OrderStatus.pending,
        'accepted' || 'preparing' || 'ready_for_pickup' => OrderStatus.accepted,
        'in_delivery' || 'delivering' => OrderStatus.inDelivery,
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
  final int totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final String? deliveryAddressId;
  final String? deliveryAddressText;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? clientComment;
  final String deliveryMode;
  final int deliveryFee;
  final String? cashChangeNeeded;
  final String acceptCode;
  final String pickupCode;
  final String deliveryCode;
  final String? scheduledAt;
  final String cityCode;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? merchantConfirmedAt;

  int get itemsAmount => totalAmount - deliveryFee;

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
    final addr = j['address'] as Map<String, dynamic>?;
    String? addrText;
    if (addr != null) {
      final label = addr['label'] as String? ?? '';
      final detail = addr['detail'] as String? ?? '';
      addrText = [label, detail].where((s) => s.isNotEmpty).join(' : ');
    } else if (j['notes'] != null && (j['notes'] as String).isNotEmpty) {
      addrText = j['notes'] as String;
    }

    final idStr = j['id']?.toString() ?? '';
    final shortCode =
        idStr.length >= 4 ? idStr.substring(0, 4).toUpperCase() : '1234';

    return OrderModel(
      id: idStr,
      clientId: (j['customer_user_id'] ?? j['client_id'] ?? '') as String,
      merchantId: (j['merchant_id'] ?? '') as String,
      courierId: j['driver_id'] as String? ?? j['courier_id'] as String?,
      status: OrderStatus.fromString(j['status']?.toString() ?? 'pending'),
      totalAmount: _parseInt(j['total_amount']),
      paymentMethod: j['payment_method']?.toString() ?? 'Espèces',
      paymentStatus: j['payment_status']?.toString() ?? 'pending',
      deliveryAddressId:
          (j['delivery_address_id'] ?? j['shipping_address_id']) as String?,
      deliveryAddressText: addrText,
      deliveryLat: (j['address'] as Map?)?.tryGet<double>('lat'),
      deliveryLng: (j['address'] as Map?)?.tryGet<double>('lng'),
      clientComment: (j['notes'] ?? j['client_comment']) as String?,
      deliveryMode: j['order_type']?.toString() ??
          j['delivery_mode']?.toString() ??
          'delivery',
      deliveryFee: _parseInt(j['shipping_amount'] ?? j['delivery_fee']),
      cashChangeNeeded: j['cash_change_needed'] as String?,
      acceptCode: j['accept_code'] as String? ?? shortCode,
      pickupCode: j['pickup_code'] as String? ?? shortCode,
      deliveryCode: j['delivery_code'] as String? ?? shortCode,
      scheduledAt: j['scheduled_at'] as String?,
      cityCode: j['city_code'] as String? ?? 'oume',
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
          DateTime.now(),
      deliveredAt: j['delivered_at'] != null
          ? DateTime.tryParse(j['delivered_at'].toString())
          : null,
      merchantConfirmedAt: j['merchant_confirmed_at'] != null
          ? DateTime.tryParse(j['merchant_confirmed_at'].toString())
          : null,
    );
  }
}

extension _MapGet on Map {
  T? tryGet<T>(String key) {
    try {
      return this[key] as T?;
    } catch (_) {
      return null;
    }
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
        id: j['id']?.toString() ?? '',
        orderId: j['order_id']?.toString() ?? '',
        productId: (j['variant_id'] ?? j['product_id'])?.toString(),
        productName: (j['product_name'] ?? j['title'] ?? 'Article') as String,
        productImage: (j['product_image'] ?? j['image_url']) as String?,
        qty: _parseInt(j['quantity'] ?? j['qty'], 1),
        unitPrice: _parseInt(j['unit_price']),
      );

  int get subtotal => qty * unitPrice;
}

// ── NotificationRow ───────────────────────────────────────────────────────────
class NotificationRow {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String? body;
  final String? orderId;
  final DateTime? readAt;
  final DateTime createdAt;
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
    final isReadBool = j['is_read'] as bool? ?? false;

    DateTime? readDateTime;
    if (j['read_at'] != null) {
      readDateTime = DateTime.tryParse(j['read_at'].toString());
    } else if (isReadBool) {
      readDateTime = DateTime.now();
    }

    return NotificationRow(
      id: j['id']?.toString() ?? '',
      userId: j['user_id']?.toString() ?? '',
      type: (j['event_type'] ?? j['type'])?.toString() ?? 'system',
      title: j['title'] as String? ?? 'Notification',
      body: j['body'] as String?,
      orderId: (j['related_id'] ?? j['order_id'])?.toString(),
      readAt: readDateTime,
      createdAt: DateTime.tryParse(
              j['sent_at']?.toString() ?? j['created_at']?.toString() ?? '') ??
          DateTime.now(),
      orderAcceptCode: order?['accept_code'] as String?,
      orderTotalAmount: _parseInt(order?['total_amount']),
      orderStatus: order?['status'] as String?,
    );
  }
}
