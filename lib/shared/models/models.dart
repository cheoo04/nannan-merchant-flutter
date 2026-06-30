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
    return isOpenNow
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
  final int totalXof;
  final String paymentMethod;
  final String paymentStatus;
  final String? deliveryAddress;
  final String? clientComment;
  final String deliveryMode;
  final int deliveryFeeXof;
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
    required this.totalXof,
    required this.paymentMethod,
    required this.paymentStatus,
    this.deliveryAddress,
    this.clientComment,
    required this.deliveryMode,
    required this.deliveryFeeXof,
    required this.acceptCode,
    required this.pickupCode,
    required this.deliveryCode,
    this.scheduledAt,
    required this.cityCode,
    required this.createdAt,
    this.deliveredAt,
    this.merchantConfirmedAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) => OrderModel(
        id: j['id'] as String,
        clientId: j['client_id'] as String,
        merchantId: j['merchant_id'] as String,
        courierId: j['courier_id'] as String?,
        status: OrderStatus.fromString(j['status']?.toString() ?? 'pending'),
        totalXof: j['total_xof'] as int? ?? 0,
        paymentMethod: j['payment_method']?.toString() ?? 'cash',
        paymentStatus: j['payment_status']?.toString() ?? 'pending',
        deliveryAddress: j['delivery_address'] as String?,
        clientComment: j['client_comment'] as String?,
        deliveryMode: j['delivery_mode']?.toString() ?? 'standard',
        deliveryFeeXof: j['delivery_fee_xof'] as int? ?? 0,
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

  const NotificationRow({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.orderId,
    this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  factory NotificationRow.fromJson(Map<String, dynamic> j) => NotificationRow(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        type: j['type']?.toString() ?? 'system',
        title: j['title'] as String? ?? '',
        body: j['body'] as String?,
        orderId: j['order_id'] as String?,
        readAt: j['read_at'] != null ? DateTime.parse(j['read_at'] as String) : null,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}