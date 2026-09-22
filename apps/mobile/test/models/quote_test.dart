import 'package:achaago_mobile/models/quote.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _service(String id, String code) => {
      'id': id,
      'code': code,
      'name_mn': code == 'porter' ? 'Портер' : 'Амжиргаа',
      'description_mn': 'd',
      'icon': 'truck',
      'base_fare': 30000,
      'per_km_rate': 2000,
      'is_active': true,
      'sort_order': 0,
    };

void main() {
  group('Quote.fromJson', () {
    final json = {
      'distance_km': 4.5,
      'duration_minutes': 16,
      'polyline': null,
      'loader_rate': 25000,
      'approximate': true,
      'quote_token': 'signed-token',
      'prices': [
        {
          'service': _service('svc-porter', 'porter'),
          'breakdown': {
            'total': 46000,
            'service_name': 'Портер',
            'base_fare': 30000,
            'distance_fare': 9000,
            'loader_fare': 0,
            'night_surcharge': 0,
          },
        },
        {
          'service': _service('svc-amjirgaa', 'amjirgaa'),
          'breakdown': {
            'total': 16750,
            'service_name': 'Амжиргаа',
            'base_fare': 10000,
            'distance_fare': 6750,
            'loader_fare': 0,
            'night_surcharge': 0,
          },
        },
      ],
    };

    test('parses distance/duration/prices', () {
      final quote = Quote.fromJson(json);
      expect(quote.distanceKm, 4.5);
      expect(quote.durationMinutes, 16);
      expect(quote.approximate, isTrue);
      expect(quote.quoteToken, 'signed-token');
      expect(quote.prices, hasLength(2));
      expect(quote.prices.first.service.nameMn, 'Портер');
      expect(quote.prices.first.breakdown.total, 46000);
    });

    test('priceFor finds a service by id and returns null otherwise', () {
      final quote = Quote.fromJson(json);
      expect(quote.priceFor('svc-amjirgaa')?.breakdown.total, 16750);
      expect(quote.priceFor('missing'), isNull);
    });
  });
}
