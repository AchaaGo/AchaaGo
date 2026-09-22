import 'package:achaago_mobile/l10n/errors_mn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeError', () {
    test('translates a known backend error code', () {
      expect(describeError('OTP_INVALID'), mnErrors['OTP_INVALID']);
      expect(describeError('ACTIVE_ORDER_EXISTS'), isNotEmpty);
    });

    test('falls back to the UNKNOWN message for an unrecognized code', () {
      expect(describeError('SOMETHING_NEW_FROM_THE_SERVER'), mnErrors['UNKNOWN']);
    });
  });

  group('describeStatus', () {
    test('translates every status the API can return for an order', () {
      const statuses = [
        'pending',
        'assigned',
        'driver_arriving',
        'arrived',
        'picked_up',
        'delivered',
        'completed',
        'cancelled',
        'no_driver_found',
      ];
      for (final status in statuses) {
        expect(describeStatus(status), isNot(equals(status)), reason: 'missing translation for $status');
      }
    });

    test('falls back to the raw status if it is somehow unrecognized', () {
      expect(describeStatus('made_up_status'), 'made_up_status');
    });
  });
}
