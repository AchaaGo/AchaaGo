import 'dart:convert';

import 'package:achaago_mobile/core/api_client.dart';
import 'package:achaago_mobile/repositories/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object body, [int status = 200]) =>
    // Like FastAPI: UTF-8 bytes, content-type without a charset.
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json'});

CustomerRepository repository(
        Future<http.Response> Function(http.Request request) handler) =>
    CustomerRepository(ApiClient(client: MockClient(handler)));

const session = '6f1c2b9e-4d3a-4b7e-9a10-2f5c8d7e1a33';

void main() {
  group('searchPlaces', () {
    test('sends the query and the Places session', () async {
      late http.Request seen;
      final results = await repository((request) async {
        seen = request;
        return jsonResponse([
          {'id': 'ChIJabc', 'address': 'Сүхбаатарын талбай, Улаанбаатар'},
        ]);
      }).searchPlaces('  Сүх ', session: session);

      expect(seen.url.path, endsWith('/places'));
      expect(seen.url.queryParameters, {'q': 'Сүх', 'session': session});
      expect(results.single.id, 'ChIJabc');
      expect(results.single.address, 'Сүхбаатарын талбай, Улаанбаатар');
    });

    test('sends no session parameter when there is none', () async {
      late http.Request seen;
      await repository((request) async {
        seen = request;
        return jsonResponse([]);
      }).searchPlaces('Сүх');

      expect(seen.url.queryParameters, {'q': 'Сүх'});
    });

    test('does not call the server for a query under two characters', () async {
      var calls = 0;
      final results = await repository((request) async {
        calls++;
        return jsonResponse([]);
      }).searchPlaces(' с ');

      expect(results, isEmpty);
      expect(calls, 0);
    });
  });

  group('place', () {
    test('spends the Places session on the lookup', () async {
      late http.Request seen;
      final place = await repository((request) async {
        seen = request;
        return jsonResponse(
            {'lat': 47.9186, 'lng': 106.9177, 'address': 'Сүхбаатарын талбай'});
      }).place('ChIJabc_-1', session: session);

      expect(seen.url.path, endsWith('/places/ChIJabc_-1'));
      expect(seen.url.queryParameters, {'session': session});
      expect(place.lat, 47.9186);
      expect(place.address, 'Сүхбаатарын талбай');
    });

    test('sends no session parameter when there is none', () async {
      late http.Request seen;
      await repository((request) async {
        seen = request;
        return jsonResponse({'lat': 47.9, 'lng': 106.9, 'address': 'Зайсан'});
      }).place('zaisan');

      expect(seen.url.queryParameters, isEmpty);
    });
  });

  group('reverseGeocode', () {
    test('asks /geocode for the point and returns the address', () async {
      late http.Request seen;
      final address = await repository((request) async {
        seen = request;
        return jsonResponse({'address': 'Энхтайвны өргөн чөлөө 1, Улаанбаатар'});
      }).reverseGeocode(47.9186, 106.9177);

      expect(seen.url.path, endsWith('/geocode'));
      expect(seen.url.queryParameters, {'lat': '47.918600', 'lng': '106.917700'});
      expect(address, 'Энхтайвны өргөн чөлөө 1, Улаанбаатар');
    });

    test('is null when the server has no address for the point', () async {
      final address = await repository((request) async =>
              jsonResponse({'detail': 'PLACE_NOT_FOUND'}, 404))
          .reverseGeocode(47.9186, 106.9177);

      expect(address, isNull);
    });

    test('is null when the server is an older one without /geocode', () async {
      final address = await repository((request) async =>
              jsonResponse({'detail': 'Not Found'}, 404))
          .reverseGeocode(47.9186, 106.9177);

      expect(address, isNull);
    });

    test('is null when the network fails', () async {
      final address = await repository((request) async => throw Exception('offline'))
          .reverseGeocode(47.9186, 106.9177);

      expect(address, isNull);
    });

    test('is null for an empty or one-character address', () async {
      for (final value in ['', ' ', 'А']) {
        final address = await repository(
                (request) async => jsonResponse({'address': value}))
            .reverseGeocode(47.9186, 106.9177);
        expect(address, isNull, reason: 'address "$value"');
      }
    });

    test('cuts an address the server would refuse for being too long', () async {
      final address = await repository(
              (request) async => jsonResponse({'address': 'а' * 400}))
          .reverseGeocode(47.9186, 106.9177);

      expect(address, 'а' * 300);
    });
  });
}
