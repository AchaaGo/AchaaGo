import 'dart:math';

/// `46,000₮` — matches apps/web/src/lib/api.ts `money()`.
String formatMoney(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(',');
  }
  return '${buffer.toString()}₮';
}

/// `99112233` -> `9911 2233` — matches apps/web/src/lib/api.ts `phoneFmt()`.
String formatPhoneDisplay(String digitsOnly) {
  final clean = digitsOnly.replaceAll(RegExp(r'\D'), '');
  final trimmed = clean.length > 8 ? clean.substring(0, 8) : clean;
  if (trimmed.length <= 4) return trimmed;
  return '${trimmed.substring(0, 4)} ${trimmed.substring(4)}';
}

String onlyDigits(String value, {int maxLength = 20}) {
  final clean = value.replaceAll(RegExp(r'\D'), '');
  return clean.length > maxLength ? clean.substring(0, maxLength) : clean;
}

final _random = Random.secure();

/// A random idempotency key for `POST /orders` / `/admin/orders`
/// (`Idempotency-Key` header, 8–64 chars — see services/api/app/schemas.py
/// via the FastAPI `Header(min_length=8, max_length=64)` constraint).
String newIdempotencyKey() {
  const chars = 'abcdef0123456789';
  return List.generate(32, (_) => chars[_random.nextInt(chars.length)]).join();
}

/// A random UUID (version 4), 36 characters. Used as the Google Places
/// billing-session token that `GET /places` and `GET /places/{id}` accept as
/// `session` (8–36 letters, digits, `-` or `_`; see services/api/app/main.py).
String newPlaceSessionToken() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  String hex(int start, int end) =>
      bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
