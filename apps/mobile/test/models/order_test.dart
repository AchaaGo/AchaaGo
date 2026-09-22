import 'package:achaago_mobile/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Order.fromJson', () {
    test('parses the full (non-public) shape returned to the customer/driver', () {
      final json = {
        'id': 'order-1',
        'status': 'assigned',
        'service_name': 'Портер',
        'pickup': {'lat': 47.9, 'lng': 106.9, 'address': 'A хаяг'},
        'dropoff': {'lat': 47.91, 'lng': 106.91, 'address': 'B хаяг'},
        'distance_km': 5.2,
        'duration_minutes': 12,
        'updated_at': '2026-01-01T00:00:00+00:00',
        'created_at': '2026-01-01T00:00:00+00:00',
        'driver': {
          'id': 'driver-1',
          'phone': '+97699112233',
          'name': 'Бат',
          'rating': 4.5,
          'plate_number': '1234 УНЕ',
          'location': {'lat': 47.9, 'lng': 106.9},
          'location_fresh': true,
          'last_seen': '2026-01-01T00:00:00+00:00',
        },
        'service_id': 'svc-1',
        'loaders': 1,
        'payment_method': 'cash',
        'payment_status': 'pending',
        'price_breakdown': {'total': 50000},
        'total_price': 50000,
        'tracking_token': 'tok',
        'rating': null,
        'can_cancel': true,
      };

      final order = Order.fromJson(json);

      expect(order.id, 'order-1');
      expect(order.status, 'assigned');
      expect(order.isActive, isTrue);
      expect(order.isTerminal, isFalse);
      expect(order.pickup.address, 'A хаяг');
      expect(order.dropoff.address, 'B хаяг');
      expect(order.driver, isNotNull);
      expect(order.driver!.id, 'driver-1');
      expect(order.driver!.phone, '+97699112233');
      expect(order.driver!.location!.lat, 47.9);
      expect(order.canCancel, isTrue);
      expect(order.totalPrice, 50000);
      expect(order.paymentMethod, 'cash');
    });

    test('parses the public /t/{token} shape, which omits private fields', () {
      final json = {
        'id': 'order-1',
        'status': 'driver_arriving',
        'service_name': 'Портер',
        'pickup': {'lat': 47.9, 'lng': 106.9, 'address': 'A'},
        'dropoff': {'lat': 47.91, 'lng': 106.91, 'address': 'B'},
        'distance_km': 5.2,
        'duration_minutes': 12,
        'updated_at': '2026-01-01T00:00:00+00:00',
        'created_at': '2026-01-01T00:00:00+00:00',
        'driver': {
          'name': 'Бат',
          'rating': 4.5,
          'plate_number': '1234 УНЕ',
          'location': null,
          'location_fresh': false,
        },
      };

      final order = Order.fromJson(json);

      expect(order.driver!.id, isNull);
      expect(order.driver!.phone, isNull);
      expect(order.driver!.location, isNull);
      expect(order.canCancel, isNull);
      expect(order.totalPrice, isNull);
      expect(order.serviceId, isNull);
      expect(order.isActive, isTrue);
    });

    test('treats completed/cancelled/no_driver_found as terminal, everything else as active', () {
      for (final status in ['completed', 'cancelled', 'no_driver_found']) {
        final order = Order.fromJson(_minimalOrder(status));
        expect(order.isTerminal, isTrue, reason: status);
        expect(order.isActive, isFalse, reason: status);
      }
      for (final status in ['pending', 'assigned', 'driver_arriving', 'arrived', 'picked_up', 'delivered']) {
        final order = Order.fromJson(_minimalOrder(status));
        expect(order.isActive, isTrue, reason: status);
        expect(order.isTerminal, isFalse, reason: status);
      }
    });
  });
}

Map<String, dynamic> _minimalOrder(String status) => {
      'id': 'o',
      'status': status,
      'service_name': 's',
      'pickup': {'lat': 47.9, 'lng': 106.9, 'address': 'A'},
      'dropoff': {'lat': 47.9, 'lng': 106.9, 'address': 'B'},
      'updated_at': '2026-01-01T00:00:00+00:00',
      'created_at': '2026-01-01T00:00:00+00:00',
      'driver': null,
    };
