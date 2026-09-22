import 'dart:convert';

import 'package:achaago_mobile/core/api_client.dart';
import 'package:achaago_mobile/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// These only exercise `auth: false` requests: the auth-token and
/// refresh-token paths go through [SessionStore], which wraps the
/// `flutter_secure_storage` plugin and needs a platform to talk to. That
/// behavior is covered indirectly by the repository/screen code paths
/// instead.
void main() {
  group('ApiClient', () {
    test('decodes a successful JSON array response', () async {
      final client = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/services'));
          return http.Response(
            jsonEncode([
              {'id': '1', 'code': 'porter', 'name_mn': 'Портер'},
            ]),
            200,
          );
        }),
      );

      final result = await client.get('/services', auth: false);

      expect(result, isA<List>());
      expect((result as List).single['code'], 'porter');
    });

    test('maps a JSON {detail} error body to a matching ApiException', () async {
      final client = ApiClient(
        client: MockClient((request) async => http.Response(jsonEncode({'detail': 'OTP_INVALID'}), 401)),
      );

      await expectLater(
        () => client.post('/auth/otp/verify', body: {'phone': '+97699000000', 'code': '1111'}, auth: false),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'OTP_INVALID').having((e) => e.status, 'status', 401)),
      );
    });

    test('falls back to UNKNOWN when the error body has no detail field', () async {
      final client = ApiClient(client: MockClient((request) async => http.Response('not json', 500)));

      await expectLater(
        () => client.get('/config', auth: false),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'UNKNOWN')),
      );
    });

    test('surfaces any transport failure as a NETWORK ApiException', () async {
      final client = ApiClient(client: MockClient((request) async => throw Exception('connection refused')));

      await expectLater(
        () => client.get('/config', auth: false),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK').having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });

    test('collects field-level validation errors from a 422 response', () async {
      final client = ApiClient(
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'detail': 'INVALID_INPUT',
                'fields': ['phone'],
              }),
              422,
            )),
      );

      await expectLater(
        () => client.post('/auth/otp/request', body: {'phone': 'bad'}, auth: false),
        throwsA(isA<ApiException>().having((e) => e.fields, 'fields', ['phone'])),
      );
    });
  });
}
