import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nannan_merchant/features/location_picker/nominatim_service.dart';

void main() {
  group('NominatimService.search', () {
    test('parses a successful response into GeocodingResult list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Oumé marché');
        expect(request.url.queryParameters['countrycodes'], 'ci');
        return http.Response(
          jsonEncode([
            {
              'display_name': "Marché de Oumé, Oumé, Côte d'Ivoire",
              'lat': '6.3855',
              'lon': '-5.4122',
            }
          ]),
          200,
        );
      });

      final service = NominatimService(client: mockClient);
      final results = await service.search('Oumé marché');

      expect(results, hasLength(1));
      expect(results.first.displayName, "Marché de Oumé, Oumé, Côte d'Ivoire");
      expect(results.first.lat, 6.3855);
      expect(results.first.lng, -5.4122);
    });

    test('returns an empty list for an empty query without any HTTP call', () async {
      final service = NominatimService(client: MockClient((request) async {
        fail('No HTTP call should be made for an empty query');
      }));

      final results = await service.search('   ');

      expect(results, isEmpty);
    });

    test('throws when Nominatim responds with a non-200 status', () async {
      final mockClient = MockClient((request) async => http.Response('', 503));
      final service = NominatimService(client: mockClient);

      expect(() => service.search('Oumé'), throwsA(isA<http.ClientException>()));
    });
  });
}
