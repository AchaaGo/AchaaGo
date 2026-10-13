import 'package:achaago_mobile/core/formatting.dart';
import 'package:achaago_mobile/core/place_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  // What the server accepts as `session`: services/api/app/main.py
  // PLACE_SESSION_PATTERN.
  final serverPattern = RegExp(r'^[A-Za-z0-9_-]{8,36}$');

  group('newPlaceSessionToken', () {
    test('is a version 4 UUID that the server accepts', () {
      for (var i = 0; i < 100; i++) {
        final token = newPlaceSessionToken();
        expect(token, matches(uuidV4));
        expect(token, matches(serverPattern));
      }
    });

    test('is not repeated', () {
      final tokens = {for (var i = 0; i < 100; i++) newPlaceSessionToken()};
      expect(tokens.length, 100);
    });
  });

  group('PlaceSession', () {
    test('has no token until the first search asks for one', () {
      expect(PlaceSession().current, isNull);
    });

    test('keeps one token for every search of a typing session', () {
      final session = PlaceSession();
      final first = session.token;
      expect(session.token, first);
      expect(session.current, first);
    });

    test('end() starts a fresh session with a different token', () {
      final session = PlaceSession();
      final first = session.token;
      session.end();
      expect(session.current, isNull);
      final second = session.token;
      expect(second, isNot(first));
      expect(second, matches(serverPattern));
    });
  });
}
