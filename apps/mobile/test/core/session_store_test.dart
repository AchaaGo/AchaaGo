import 'package:achaago_mobile/core/api_client.dart';
import 'package:achaago_mobile/core/session_store.dart';
import 'package:achaago_mobile/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// No platform channel is registered for flutter_secure_storage in tests, so
// its real read/write/delete throw — the same shape of failure some real
// Android devices hit on Keystore access. Everything below runs in that
// "persistent storage is broken" condition.
void main() {
  group('SessionStore with unusable persistent storage', () {
    test('keeps tokens in memory for the session', () async {
      final store = SessionStore();
      await store.save(accessToken: 'access', refreshToken: 'refresh');
      expect(await store.readAccessToken(), 'access');
      expect(await store.readRefreshToken(), 'refresh');

      await store.saveAccessToken('access2');
      expect(await store.readAccessToken(), 'access2');
    });

    test('clear() forgets the tokens and does not throw', () async {
      final store = SessionStore();
      await store.save(accessToken: 'access', refreshToken: 'refresh');
      await store.clear();
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('a fresh store reads null instead of throwing', () async {
      final store = SessionStore();
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('authenticated requests', () {
    test('ApiClient sends the token the shared store holds', () async {
      String? sentAuth;
      final store = SessionStore();
      await store.save(accessToken: 'abc', refreshToken: 'r');
      final client = ApiClient(
        client: MockClient((request) async {
          sentAuth = request.headers['Authorization'];
          return http.Response('[]', 200);
        }),
        sessionStore: store,
      );

      await client.get('/services');
      expect(sentAuth, 'Bearer abc');
    });

    test('AppState wires its ApiClient to the same store it saves to', () async {
      // The post-login hang: AppState and ApiClient each made their own
      // SessionStore, so a token saved at login was invisible to requests
      // whenever persistent storage didn't work.
      String? sentAuth;
      final appState = http.runWithClient(
        () => AppState(),
        () => MockClient((request) async {
          sentAuth = request.headers['Authorization'];
          return http.Response('[]', 200);
        }),
      );

      await appState.sessionStore.save(accessToken: 'abc', refreshToken: 'r');
      await appState.api.get('/services');
      expect(sentAuth, 'Bearer abc');
    });
  });
}
