// --- Fichier : test/core/api_audit_test.dart ---
import 'package:flutter_test/flutter_test.dart';
import 'package:nannan_merchant/shared/models/models.dart';

void main() {
  group('Audit de conformité API Neon & OpenAPI', () {
    test('Parsing sécurisé des montants décimaux (String, int, double)', () {
      final jsonOrder = {
        'id': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
        'customer_user_id': 'u1-uuid',
        'merchant_id': 'm1-uuid',
        'status': 'confirmed',
        'total_amount': '3500.00', // Décimale string renvoyée par FastAPI
        'shipping_amount': '500.00',
        'payment_method': 'cash',
        'payment_status': 'pending',
        'created_at': '2026-09-27T10:00:00Z',
      };

      final order = OrderModel.fromJson(jsonOrder);
      expect(order.totalAmount, 3500);
      expect(order.deliveryFee, 500);
      expect(order.itemsAmount, 3000);
      expect(
          order.status,
          OrderStatus
              .pending); // 'confirmed' mappe vers 'pending' (onglet Nouvelles)
    });

    test('Mapping des statuts de commande Neon vers les onglets Marchand', () {
      expect(OrderStatus.fromString('confirmed'), OrderStatus.pending);
      expect(OrderStatus.fromString('preparing'), OrderStatus.accepted);
      expect(OrderStatus.fromString('ready_for_pickup'), OrderStatus.accepted);
      expect(OrderStatus.fromString('delivering'), OrderStatus.inDelivery);
      expect(OrderStatus.fromString('delivered'), OrderStatus.delivered);
      expect(OrderStatus.fromString('cancelled'), OrderStatus.cancelled);
    });

    test('Parsing des notifications avec data_payload Neon', () {
      final notifJson = {
        'id': 'notif-123',
        'user_id': 'user-456',
        'event_type': 'order',
        'title': 'Nouvelle commande',
        'body': 'Vous avez reçu une commande de 3500 F',
        'related_id': 'order-789',
        'is_read': false,
        'sent_at': '2026-09-27T10:05:00Z',
        'data_payload': {
          'order_id': 'order-789',
          'amount': 3500,
        },
      };

      final notif = NotificationRow.fromJson(notifJson);
      expect(notif.isUnread, true);
      expect(notif.title, 'Nouvelle commande');
      expect(notif.orderId, 'order-789');
    });
  });
}
