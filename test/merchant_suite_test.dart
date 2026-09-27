import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nannan_merchant/core/services/a_nan_nan_api_client.dart';
import 'package:nannan_merchant/core/utils/error_message.dart';
import 'package:nannan_merchant/features/products/products_screen.dart';
import 'package:nannan_merchant/shared/models/models.dart';

void main() {
  group('1. Tests du modèle Boutique et Gestion de la Pause', () {
    test('La pause expirée est automatiquement ignorée (anti-bug pause zombie)', () {
      final json = {
        'id': 'm1-uuid',
        'name': 'Maquis Le Fromager',
        'status': 'active',
        'is_open': true,
        // Date de pause passée (1970)
        'pause_until': '1970-01-01T00:00:00.000Z',
      };

      final merchant = MerchantModel.fromJson(json);
      expect(merchant.pauseUntil, isNull);
      expect(merchant.isOpenNow, isTrue);
      expect(merchant.statusLabel.label, 'Boutique ouverte');
    });

    test('Une pause future met correctement le statut en pause', () {
      final futureDate = DateTime.now().toUtc().add(const Duration(minutes: 30)).toIso8601String();
      final json = {
        'id': 'm1-uuid',
        'name': 'Maquis Le Fromager',
        'status': 'active',
        'is_open': true,
        'pause_until': futureDate,
      };

      final merchant = MerchantModel.fromJson(json);
      expect(merchant.pauseUntil, isNotNull);
      expect(merchant.isOpenNow, isFalse);
      expect(merchant.statusLabel.label, 'En pause');
      expect(merchant.statusLabel.tone, 'paused');
    });
  });

  group('2. Tests des Commandes et Parsing Financier (Neon/FastAPI)', () {
    test('Conversion sans crash des décimales String en montants XOF', () {
      final orderJson = {
        'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        'customer_user_id': 'user-123',
        'merchant_id': 'm1-uuid',
        'status': 'confirmed',
        'total_amount': '4500.00',    // Format décimal String FastAPI
        'shipping_amount': '500.00',  // Format décimal String FastAPI
        'payment_method': 'Espèces',
        'created_at': '2026-09-27T12:00:00Z',
      };

      final order = OrderModel.fromJson(orderJson);
      expect(order.totalAmount, 4500);
      expect(order.deliveryFee, 500);
      expect(order.itemsAmount, 4000); // Montant net revenant au marchand
      expect(order.status, OrderStatus.pending); // 'confirmed' mappe vers 'pending'
    });

    test('Mappage des statuts OpenAPI vers les onglets UI', () {
      expect(OrderStatus.fromString('confirmed'), OrderStatus.pending);
      expect(OrderStatus.fromString('preparing'), OrderStatus.accepted);
      expect(OrderStatus.fromString('ready_for_pickup'), OrderStatus.accepted);
      expect(OrderStatus.fromString('delivering'), OrderStatus.inDelivery);
      expect(OrderStatus.fromString('delivered'), OrderStatus.delivered);
      expect(OrderStatus.fromString('cancelled'), OrderStatus.cancelled);
    });
  });

  group('3. Tests du Catalogue et Résolution des Catégories', () {
    test('Résolution dynamique du category_id en nom lisible', () {
      final offeringJson = {
        'id': 'offering-1',
        'merchant_id': 'm1-uuid',
        'title': 'Attiéké Poisson',
        'status': 'active',
        'category_id': 'cat-uuid-1',
        'variants': [
          {'price': '1500.00', 'is_in_stock': true, 'is_default': true}
        ],
      };

      final categoryMap = {'cat-uuid-1': 'Plats Ivoiriens'};
      final product = DbProduct.fromOffering(offeringJson, categoryNames: categoryMap);

      expect(product.name, 'Attiéké Poisson');
      expect(product.category, 'Plats Ivoiriens');
      expect(product.priceXof, 1500);
      expect(product.isAvailable, isTrue);
    });

    test('Un produit avec status draft est correctement identifié comme masqué', () {
      final offeringJson = {
        'id': 'offering-2',
        'merchant_id': 'm1-uuid',
        'title': 'Jus de Bissap',
        'status': 'draft', // Masqué
        'variants': [
          {'price': '500', 'is_in_stock': true, 'is_default': true}
        ],
      };

      final product = DbProduct.fromOffering(offeringJson);
      expect(product.isAvailable, isFalse);
    });
  });

  group('4. Tests de la gestion des erreurs réseau', () {
    test('Interception des erreurs 401 et 422', () {
      const err401 = ANanNanApiException(401, 'Unauthorized');
      expect(friendlyError(err401), 'Session expirée ou identifiants incorrects.');

      const err422 = ANanNanApiException(422, 'Le code PIN doit contenir 4 chiffres');
      expect(friendlyError(err422), 'Le code PIN doit contenir 4 chiffres');
    });

    test('Interception des coupures réseau', () {
      const socketErr = SocketException('Failed host lookup');
      expect(friendlyError(socketErr), contains('Pas de connexion internet'));
    });
  });
}
