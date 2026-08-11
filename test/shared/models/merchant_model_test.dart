import 'package:flutter_test/flutter_test.dart';
import 'package:nannan_merchant/shared/models/models.dart';

void main() {
  group('MerchantModel.fromJson — lat/lng', () {
    test('parses lat and lng when present', () {
      final json = {
        'id': 'm1',
        'owner_id': 'u1',
        'name': 'Boutique Test',
        'category': 'boutique',
        'is_open': true,
        'auto_schedule_enabled': false,
        'status': 'active',
        'city_code': 'oume',
        'created_at': '2026-01-01T00:00:00.000Z',
        'lat': 6.3855,
        'lng': -5.4122,
      };

      final merchant = MerchantModel.fromJson(json);

      expect(merchant.lat, 6.3855);
      expect(merchant.lng, -5.4122);
    });

    test('lat and lng are null when absent', () {
      final json = {
        'id': 'm1',
        'owner_id': 'u1',
        'name': 'Boutique Test',
        'category': 'boutique',
        'is_open': true,
        'auto_schedule_enabled': false,
        'status': 'active',
        'city_code': 'oume',
        'created_at': '2026-01-01T00:00:00.000Z',
      };

      final merchant = MerchantModel.fromJson(json);

      expect(merchant.lat, isNull);
      expect(merchant.lng, isNull);
    });
  });
}
