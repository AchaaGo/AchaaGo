import '../core/api_client.dart';
import '../core/session_store.dart';
import '../models/user.dart';

class AuthResult {
  const AuthResult(this.accessToken, this.refreshToken, this.user);

  final String accessToken;
  final String refreshToken;
  final AppUser user;
}

/// Wraps `/auth/*` — services/api/app/main.py.
class AuthRepository {
  AuthRepository(this._api, this._sessionStore);

  final ApiClient _api;
  final SessionStore _sessionStore;

  Future<void> requestOtp(String phoneE164) async {
    await _api.post('/auth/otp/request', body: {'phone': phoneE164}, auth: false);
  }

  Future<AuthResult> verifyOtp(String phoneE164, String code) async {
    final json = await _api.post(
      '/auth/otp/verify',
      body: {'phone': phoneE164, 'code': code},
      auth: false,
    ) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String;
    final refreshToken = json['refresh_token'] as String;
    final user = AppUser.fromJson(json['user'] as Map<String, dynamic>);
    await _sessionStore.save(accessToken: accessToken, refreshToken: refreshToken);
    return AuthResult(accessToken, refreshToken, user);
  }

  Future<AppUser> me() async {
    final json = await _api.get('/auth/me') as Map<String, dynamic>;
    return AppUser.fromJson(json);
  }

  Future<void> logout() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    try {
      await _api.post('/auth/logout', body: {'refresh_token': refreshToken}, auth: false);
    } catch (_) {
      // Best-effort: the local session is cleared regardless.
    }
    await _sessionStore.clear();
  }

  Future<bool> hasStoredSession() async => await _sessionStore.readAccessToken() != null;
}
