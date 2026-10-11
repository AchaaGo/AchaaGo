import 'dart:convert';

import 'package:achaago_mobile/core/api_client.dart';
import 'package:achaago_mobile/core/api_exception.dart';
import 'package:achaago_mobile/core/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// These only exercise `auth: false` requests. Authenticated requests
/// (token read from [SessionStore]) are covered in session_store_test.dart.
void main() {
  group('ApiClient', () {
    test('decodes a successful JSON array response', () async {
      final client = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/services'));
          // Like FastAPI: UTF-8 bytes, content-type without a charset.
          return http.Response.bytes(
            utf8.encode(jsonEncode([
              {'id': '1', 'code': 'porter', 'name_mn': 'Портер'},
            ])),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.get('/services', auth: false);

      expect(result, isA<List>());
      expect((result as List).single['code'], 'porter');
      expect(result.single['name_mn'], 'Портер');
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

  // No platform channel exists for flutter_secure_storage in tests, so
  // SessionStore keeps tokens in memory here (see session_store_test.dart).
  group('ApiClient token refresh', () {
    Future<SessionStore> loggedIn() async {
      final store = SessionStore();
      await store.save(accessToken: 'old', refreshToken: 'r1');
      return store;
    }

    test('parallel requests that hit an expired token share one refresh', () async {
      var refreshCalls = 0;
      final store = await loggedIn();
      final client = ApiClient(
        sessionStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response(jsonEncode({'access_token': 'new', 'refresh_token': 'r2'}), 200);
          }
          if (request.headers['Authorization'] == 'Bearer new') return http.Response('[]', 200);
          return http.Response(jsonEncode({'detail': 'SESSION_EXPIRED'}), 401);
        }),
      );

      final results = await Future.wait([client.get('/services'), client.get('/orders'), client.get('/driver/me')]);

      expect(results, everyElement(isA<List>()));
      expect(refreshCalls, 1);
      expect(await store.readRefreshToken(), 'r2');
    });

    test('a refresh that fails on the network keeps the user logged in', () async {
      var expired = false;
      final store = await loggedIn();
      final client = ApiClient(
        sessionStore: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) throw Exception('offline');
          return http.Response(jsonEncode({'detail': 'SESSION_EXPIRED'}), 401);
        }),
      )..onSessionExpired = () async {
          expired = true;
        };

      await expectLater(
        () => client.get('/orders'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
      );
      expect(expired, isFalse);
      expect(await store.readRefreshToken(), 'r1');
    });

    test('a refresh the server rejects ends the session', () async {
      var expired = false;
      final store = await loggedIn();
      final client = ApiClient(
        sessionStore: store,
        client: MockClient((request) async => http.Response(jsonEncode({'detail': 'SESSION_EXPIRED'}), 401)),
      )..onSessionExpired = () async {
          expired = true;
        };

      await expectLater(
        () => client.get('/orders'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_EXPIRED')),
      );
      expect(expired, isTrue);
    });
  });
}
