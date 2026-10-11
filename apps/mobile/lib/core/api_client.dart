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
///
/// Refreshing is single-flight: requests that hit 401 together (typical
/// when the app resumes after the 15-minute access token expired) share one
/// refresh, because the server rotates the refresh token on every use. And
/// only a refresh the server actually rejects ends the session; a refresh
/// that fails on a bad connection keeps the user logged in.
class ApiClient {
  ApiClient({http.Client? client, SessionStore? sessionStore})
      : _client = client ?? http.Client(),
        _sessionStore = sessionStore ?? SessionStore();

  final http.Client _client;
  final SessionStore _sessionStore;
  Future<_RefreshOutcome>? _refreshing;

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
    String? usedToken;
    if (auth) {
      usedToken = await _sessionStore.readAccessToken();
      if (usedToken != null) requestHeaders['Authorization'] = 'Bearer $usedToken';
    }

    late final http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(requestHeaders);
      if (body != null) request.body = body is String ? body : jsonEncode(body);
      final timeout = method == 'GET' ? AppConfig.requestTimeout : AppConfig.writeTimeout;
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      // Any transport failure (timeout, no connection, TLS error, a plugin
      // exception on some platform, ...) degrades to the same offline
      // state the UI already knows how to show, rather than crashing the
      // screen with an exception type it doesn't catch.
      throw ApiException('NETWORK', 0);
    }

    dynamic decoded;
    // FastAPI sends `application/json` without a charset, which `response.body`
    // would decode as Latin-1 and garble Cyrillic.
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
      // Another request may already have refreshed while this one was in
      // flight with the old token: then just retry with the new one.
      final current = await _sessionStore.readAccessToken();
      final outcome = current != null && current != usedToken ? _RefreshOutcome.ok : await _refresh();
      if (outcome == _RefreshOutcome.ok) {
        return _send(method, path, body: body, headers: headers, auth: auth, allowRefresh: false);
      }
      if (outcome == _RefreshOutcome.network) throw ApiException('NETWORK', 0);
      await onSessionExpired?.call();
    }

    throw ApiException(code, response.statusCode, fields: fields);
  }

  Future<_RefreshOutcome> _refresh() => _refreshing ??= _doRefresh().whenComplete(() {
        _refreshing = null;
      });

  Future<_RefreshOutcome> _doRefresh() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null) return _RefreshOutcome.expired;
    late final http.Response response;
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/auth/refresh');
      response = await _client
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh_token': refreshToken}))
          .timeout(AppConfig.requestTimeout);
    } catch (_) {
      return _RefreshOutcome.network;
    }
    // 429 and 5xx are temporary: keep the session and let the user retry.
    if (response.statusCode == 429 || response.statusCode >= 500) return _RefreshOutcome.network;
    if (response.statusCode != 200) return _RefreshOutcome.expired;
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await _sessionStore.save(
        accessToken: decoded['access_token'] as String,
        refreshToken: decoded['refresh_token'] as String,
      );
      return _RefreshOutcome.ok;
    } catch (_) {
      return _RefreshOutcome.network;
    }
  }
}

enum _RefreshOutcome { ok, expired, network }
