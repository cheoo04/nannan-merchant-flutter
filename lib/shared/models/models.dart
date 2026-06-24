// ============================================================
// MODÈLES DART — Correspondent exactement aux tables Supabase
// Utiliser fromJson() pour parser les réponses Supabase
// ============================================================

// ── MerchantModel ────────────────────────────────────────────
class MerchantModel {
  final String id;
  final String ownerId;
  final String name;
  final String category;
  final String? description;
  final String? address;
  final double? lat;
  final double? lng;
  final String? phone;
  final String? imageUrl;
  final bool isOpen;
  final String? openingTime;   // "08:00:00"
  final String? closingTime;
  final String? pauseUntil;
  final bool autoScheduleEnabled;
  final String status;         // pending | active | suspended
  final String cityCode;
  final DateTime createdAt;

  const MerchantModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.category,
    this.description,
    this.address,
    this.lat,
    this.lng,
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

  factory MerchantModel.fromJson(Map<String, dynamic> json) {
    return MerchantModel(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String?,
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      phone: json['phone'] as String?,
      imageUrl: json['image_url'] as String?,
      isOpen: json['is_open'] as bool? ?? false,
      openingTime: json['opening_time'] as String?,
      closingTime: json['closing_time'] as String?,
      pauseUntil: json['pause_until'] as String?,
      autoScheduleEnabled: json['auto_schedule_enabled'] as bool? ?? false,
      status: json['status'] as String? ?? 'pending',
      cityCode: json['city_code'] as String? ?? 'oume',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isActive => status == 'active';
}

// ── OrderStatus ───────────────────────────────────────────────
enum OrderStatus {
  pending,
  accepted,
  inDelivery,
  delivered,
  cancelled,
  refunded;

  static OrderStatus fromString(String s) {
    return switch (s) {
      'pending' => OrderStatus.pending,
      'accepted' => OrderStatus.accepted,
      'in_delivery' => OrderStatus.inDelivery,
      'delivered' => OrderStatus.delivered,
      'cancelled' => OrderStatus.cancelled,
      'refunded' => OrderStatus.refunded,
      _ => OrderStatus.pending,
    };
  }

  String get label => switch (this) {
    OrderStatus.pending => 'En attente',
    OrderStatus.accepted => 'Acceptée',
    OrderStatus.inDelivery => 'En livraison',
    OrderStatus.delivered => 'Livrée',
    OrderStatus.cancelled => 'Annulée',
    OrderStatus.refunded => 'Remboursée',
  };

  String get dbValue => switch (this) {
    OrderStatus.inDelivery => 'in_delivery',
    _ => name,
  };
}

// ── OrderModel ────────────────────────────────────────────────
class OrderModel {
  final String id;
  final String clientId;
  final String merchantId;
  final String? courierId;
  final OrderStatus status;
  final int totalXof;
  final String paymentMethod;    // cash | mobile_money | card
  final String paymentStatus;    // pending | paid | failed | refunded
  final String? deliveryAddress;
  final String? clientComment;
  final String deliveryMode;     // standard | express
  final int deliveryFeeXof;
  final String acceptCode;       // Code 4 chiffres
  final String pickupCode;
  final String deliveryCode;
  final String? scheduledAt;
  final String cityCode;
  final DateTime createdAt;
  final DateTime? merchantConfirmedAt;
  final DateTime? deliveredAt;

  // Joints (non présents dans la table orders, chargés séparément)
  final List<OrderItemModel> items;

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
    this.merchantConfirmedAt,
    this.deliveredAt,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      merchantId: json['merchant_id'] as String,
      courierId: json['courier_id'] as String?,
      status: OrderStatus.fromString(json['status'] as String? ?? 'pending'),
      totalXof: json['total_xof'] as int? ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      deliveryAddress: json['delivery_address'] as String?,
      clientComment: json['client_comment'] as String?,
      deliveryMode: json['delivery_mode'] as String? ?? 'standard',
      deliveryFeeXof: json['delivery_fee_xof'] as int? ?? 0,
      acceptCode: json['accept_code'] as String? ?? '----',
      pickupCode: json['pickup_code'] as String? ?? '----',
      deliveryCode: json['delivery_code'] as String? ?? '----',
      scheduledAt: json['scheduled_at'] as String?,
      cityCode: json['city_code'] as String? ?? 'oume',
      createdAt: DateTime.parse(json['created_at'] as String),
      merchantConfirmedAt: json['merchant_confirmed_at'] != null
          ? DateTime.parse(json['merchant_confirmed_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
    );
  }
}

// ── OrderItemModel ────────────────────────────────────────────
class OrderItemModel {
  final String id;
  final String orderId;
  final String? productId;
  final String productName;    // SNAPSHOT — ne pas joindre products
  final String? productImage;
  final int qty;
  final int unitPrice;         // SNAPSHOT

  const OrderItemModel({
    required this.id,
    required this.orderId,
    this.productId,
    required this.productName,
    this.productImage,
    required this.qty,
    required this.unitPrice,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String,
      productImage: json['product_image'] as String?,
      qty: json['qty'] as int,
      unitPrice: json['unit_price'] as int,
    );
  }

  int get subtotal => qty * unitPrice;
}

// ── ProductModel ──────────────────────────────────────────────
class ProductModel {
  final String id;
  final String merchantId;
  final String name;
  final String? description;
  final int priceXof;
  final String? imageUrl;
  final String category;
  final bool isAvailable;
  final String cityCode;
  final DateTime createdAt;

  const ProductModel({
    required this.id,
    required this.merchantId,
    required this.name,
    this.description,
    required this.priceXof,
    this.imageUrl,
    required this.category,
    required this.isAvailable,
    required this.cityCode,
    required this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      merchantId: json['merchant_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceXof: json['price_xof'] as int? ?? 0,
      imageUrl: json['image_url'] as String?,
      category: json['category'] as String,
      isAvailable: json['is_available'] as bool? ?? true,
      cityCode: json['city_code'] as String? ?? 'oume',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson({required String merchantId, required String addedByUserId}) {
    return {
      'merchant_id': merchantId,
      'added_by_user_id': addedByUserId,
      'name': name,
      'description': description,
      'price_xof': priceXof,
      'image_url': imageUrl,
      'category': category,
      'is_available': isAvailable,
      'city_code': cityCode,
    };
  }
}

// ── PrescriptionModel ─────────────────────────────────────────
class PrescriptionModel {
  final String id;
  final String clientId;
  final String merchantId;
  final String status; // received | analyzing | quoted | accepted | paid | cancelled
  final List<String> imagePaths;
  final String? clientNote;
  final String? deliveryAddress;
  final Map<String, dynamic>? quoteItems; // [{name, qty, unit_price_xof}]
  final int? productSubtotalXof;
  final int? deliveryFeeXof;
  final int? totalXof;
  final int? estimatedReadyMinutes;
  final String? pharmacistNote;
  final String? orderId;
  final DateTime createdAt;

  const PrescriptionModel({
    required this.id,
    required this.clientId,
    required this.merchantId,
    required this.status,
    required this.imagePaths,
    this.clientNote,
    this.deliveryAddress,
    this.quoteItems,
    this.productSubtotalXof,
    this.deliveryFeeXof,
    this.totalXof,
    this.estimatedReadyMinutes,
    this.pharmacistNote,
    this.orderId,
    required this.createdAt,
  });

  factory PrescriptionModel.fromJson(Map<String, dynamic> json) {
    return PrescriptionModel(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      merchantId: json['merchant_id'] as String,
      status: json['status'] as String? ?? 'received',
      imagePaths: (json['image_paths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      clientNote: json['client_note'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      quoteItems: json['quote_items'] as Map<String, dynamic>?,
      productSubtotalXof: json['products_subtotal_xof'] as int?,
      deliveryFeeXof: json['delivery_fee_xof'] as int?,
      totalXof: json['total_xof'] as int?,
      estimatedReadyMinutes: json['estimated_ready_minutes'] as int?,
      pharmacistNote: json['pharmacist_note'] as String?,
      orderId: json['order_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
