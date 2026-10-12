import 'package:achaago_mobile/core/session_store.dart';
import 'package:achaago_mobile/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  AppState newState() {
    final state = AppState(sessionStore: SessionStore());
    addTearDown(state.dispose);
    return state;
  }

  group('theme choice', () {
    test('follows the device until a theme is picked', () async {
      final state = newState();
      await state.loadThemeMode();
      expect(state.themeMode, ThemeMode.system);
    });

    test('is remembered across app starts', () async {
      await newState().setThemeMode(ThemeMode.dark);

      final restarted = newState();
      await restarted.loadThemeMode();
      expect(restarted.themeMode, ThemeMode.dark);

      await restarted.setThemeMode(ThemeMode.light);
      final again = newState();
      await again.loadThemeMode();
      expect(again.themeMode, ThemeMode.light);
    });

    test('notifies listeners, so the app rebuilds with the new theme', () async {
      final state = newState();
      var notified = 0;
      state.addListener(() => notified++);
      await state.setThemeMode(ThemeMode.dark);
      expect(notified, 1);
      expect(state.themeMode, ThemeMode.dark);
    });

    test('survives logging out: it is a device preference, not part of the session', () async {
      final store = SessionStore();
      final state = AppState(sessionStore: store);
      addTearDown(state.dispose);
      await state.setThemeMode(ThemeMode.dark);
      await store.save(accessToken: 'access', refreshToken: 'refresh');

      await store.clear();

      expect(await store.readAccessToken(), isNull);
      expect(await store.readThemePreference(), 'dark');
    });

    test('an unknown saved value falls back to the device setting', () async {
      await SessionStore().saveThemePreference('sepia');
      final state = newState();
      await state.loadThemeMode();
      expect(state.themeMode, ThemeMode.system);
    });
  });
}
