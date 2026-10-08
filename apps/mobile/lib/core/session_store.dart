import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT pair issued by `/auth/otp/verify` / `/auth/refresh`
/// (services/api/app/security.py `issue_tokens`). The web app relies on
/// httpOnly cookies for this; the mobile app has no cookie jar shared with
/// a browser, so it stores the tokens itself and sends them as
/// `Authorization: Bearer <token>`.
///
/// Keystore-backed storage is unreliable on some Android devices (reads
/// throw, e.g. BadPaddingException on certain OEM builds). Tokens are
/// therefore also kept in memory, and every storage call is best-effort:
/// if persisting fails the app still works for the current session and the
/// user just has to log in again after a restart. Because the memory copy
/// lives on this instance, AppState and ApiClient must share one store.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'ag_access_token';
  static const _refreshKey = 'ag_refresh_token';

  String? _accessToken;
  String? _refreshToken;

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _write(_accessKey, accessToken);
    await _write(_refreshKey, refreshToken);
  }

  Future<void> saveAccessToken(String accessToken) async {
    _accessToken = accessToken;
    await _write(_accessKey, accessToken);
  }

  Future<String?> readAccessToken() async => _accessToken ?? await _read(_accessKey);

  Future<String?> readRefreshToken() async => _refreshToken ?? await _read(_refreshKey);

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _delete(_accessKey);
    await _delete(_refreshKey);
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}
