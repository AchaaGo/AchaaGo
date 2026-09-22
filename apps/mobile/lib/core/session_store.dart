import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT pair issued by `/auth/otp/verify` / `/auth/refresh`
/// (services/api/app/security.py `issue_tokens`). The web app relies on
/// httpOnly cookies for this; the mobile app has no cookie jar shared with
/// a browser, so it stores the tokens itself and sends them as
/// `Authorization: Bearer <token>`.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'ag_access_token';
  static const _refreshKey = 'ag_refresh_token';

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> saveAccessToken(String accessToken) => _storage.write(key: _accessKey, value: accessToken);

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
