import 'package:achaago_mobile/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppState.bootstrap', () {
    test('falls back to signedOut instead of hanging when secure storage throws', () async {
      // No platform channel mock is registered for flutter_secure_storage in
      // this test environment, so SessionStore's real read() throws
      // MissingPluginException — the same shape of failure some real
      // Android devices hit on Keystore access. Before the fix, that
      // exception had nothing catching it and bootstrap() never
      // completed; SplashScreen would be stuck on its spinner forever.
      final appState = AppState();
      await appState.bootstrap();
      expect(appState.status, AuthStatus.signedOut);
    });
  });
}
