import '../l10n/errors_mn.dart';

/// Mirrors apps/web/src/lib/api.ts `ApiError`: carries the backend's
/// machine-readable `detail` code plus the HTTP status, and resolves a
/// Mongolian message for display via [describeError].
class ApiException implements Exception {
  ApiException(this.code, this.status, {this.fields = const []});

  final String code;
  final int status;
  final List<String> fields;

  String get message => describeError(code);

  bool get isSessionExpired => code == 'SESSION_EXPIRED' || code == 'LOGIN_REQUIRED';
  bool get isNetworkError => code == 'NETWORK';

  @override
  String toString() => 'ApiException($code, $status)';
}
