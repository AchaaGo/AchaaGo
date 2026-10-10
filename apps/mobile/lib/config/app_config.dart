/// Single place to configure how the app reaches the AchaaGo backend.
///
/// Override any of these at build/run time, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8187/api \
///               --dart-define=WS_BASE_URL=ws://192.168.1.20:8187
///
/// Defaults target the same gateway as the customer web app, including on
/// physical iPhones. Local development can override these with dart-defines.
class AppConfig {
  const AppConfig._();

  /// REST API origin, including the gateway's `/api` prefix (see
  /// infra/nginx.conf: `location /api/ { proxy_pass http://api:8000/; }`).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://64.119.31.106:8187/api',
  );

  /// WebSocket origin. Order/tracking sockets live at the gateway root
  /// (`/ws/...`), not under `/api`, so this is a separate value.
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://64.119.31.106:8187',
  );

  static const String brandName = String.fromEnvironment(
    'BRAND_NAME',
    defaultValue: 'AchaaGo',
  );

  /// Accepted by the backend only while SMS_PROVIDER=console
  /// (services/api/app/main.py `otp_verify`). Real SMS codes are 4 digits.
  static const String devOtpCode = '00';

  static const Duration requestTimeout = Duration(seconds: 15);

  /// How often the driver app pushes a location update while online.
  static const Duration driverLocationInterval = Duration(seconds: 5);
}
