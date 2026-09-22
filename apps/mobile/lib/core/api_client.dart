import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_exception.dart';
import 'session_store.dart';

/// Thin REST wrapper mirroring apps/web/src/lib/api.ts `api()`: same base
/// path (`AppConfig.apiBaseUrl`), same JSON-in/JSON-out shape, same
/// `{detail, fields}` error decoding into an [ApiException]. Unlike the
/// web app (which relies on the browser's httpOnly cookies), this client
/// attaches the stored access token itself and transparently refreshes it
/// once via `POST /auth/refresh` on a 401 before giving up.
class ApiClient {
  ApiClient({http.Client? client, SessionStore? sessionStore})
      : _client = client ?? http.Client(),
        _sessionStore = sessionStore ?? SessionStore();

  final http.Client _client;
  final SessionStore _sessionStore;

  /// Invoked when a request fails auth and the refresh attempt also
  /// fails, so the app can drop the user back to the login screen.
  Future<void> Function()? onSessionExpired;

  Future<dynamic> get(String path, {bool auth = true}) => _send('GET', path, auth: auth);

  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers, bool auth = true}) =>
      _send('POST', path, body: body, headers: headers, auth: auth);

  Future<dynamic> put(String path, {Object? body, bool auth = true}) => _send('PUT', path, body: body, auth: auth);

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) => _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {bool auth = true}) => _send('DELETE', path, auth: auth);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool auth = true,
    bool allowRefresh = true,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final requestHeaders = <String, String>{'Content-Type': 'application/json', ...?headers};
    if (auth) {
      final token = await _sessionStore.readAccessToken();
      if (token != null) requestHeaders['Authorization'] = 'Bearer $token';
    }

    late final http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(requestHeaders);
      if (body != null) request.body = body is String ? body : jsonEncode(body);
      final streamed = await _client.send(request).timeout(AppConfig.requestTimeout);
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      // Any transport failure (timeout, no connection, TLS error, a plugin
      // exception on some platform, ...) degrades to the same offline
      // state the UI already knows how to show, rather than crashing the
      // screen with an exception type it doesn't catch.
      throw ApiException('NETWORK', 0);
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = <String, dynamic>{'detail': 'UNKNOWN'};
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final errorMap = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'detail': 'UNKNOWN'};
    final code = (errorMap['detail'] as String?) ?? 'UNKNOWN';
    final fields = (errorMap['fields'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

    if (response.statusCode == 401 && auth && allowRefresh && (code == 'SESSION_EXPIRED' || code == 'LOGIN_REQUIRED')) {
      if (await _tryRefresh()) {
        return _send(method, path, body: body, headers: headers, auth: auth, allowRefresh: false);
      }
      await onSessionExpired?.call();
    }

    throw ApiException(code, response.statusCode, fields: fields);
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/auth/refresh');
      final response = await _client
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh_token': refreshToken}))
          .timeout(AppConfig.requestTimeout);
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await _sessionStore.save(
        accessToken: decoded['access_token'] as String,
        refreshToken: decoded['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
