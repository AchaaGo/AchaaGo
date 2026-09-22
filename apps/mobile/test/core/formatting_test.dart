import 'package:achaago_mobile/core/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('groups thousands and appends the tugrik sign', () {
      expect(formatMoney(46000), '46,000₮');
      expect(formatMoney(500), '500₮');
      expect(formatMoney(1234567), '1,234,567₮');
      expect(formatMoney(0), '0₮');
    });
  });

  group('formatPhoneDisplay', () {
    test('splits eight digits into two groups of four', () {
      expect(formatPhoneDisplay('99112233'), '9911 2233');
    });

    test('leaves four or fewer digits ungrouped', () {
      expect(formatPhoneDisplay('9911'), '9911');
      expect(formatPhoneDisplay(''), '');
    });

    test('strips non-digits and caps at eight digits', () {
      expect(formatPhoneDisplay('99-11 22 33 44 55'), '9911 2233');
    });
  });

  group('onlyDigits', () {
    test('keeps only digits, up to maxLength', () {
      expect(onlyDigits('99a11b22cc33', maxLength: 4), '9911');
      expect(onlyDigits('0000'), '0000');
    });
  });

  group('newIdempotencyKey', () {
    test('produces a 32-character lowercase hex string that varies per call', () {
      final a = newIdempotencyKey();
      final b = newIdempotencyKey();
      expect(a.length, 32);
      expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(a), isTrue);
      expect(a, isNot(equals(b)));
    });
  });
}
