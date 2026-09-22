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
