import 'package:achaago_mobile/core/route_polyline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeRoutePolyline', () {
    // Canonical example from Google's polyline algorithm documentation:
    // https://developers.google.com/maps/documentation/utilities/polylinealgorithm
    const encoded = r'_p~iF~ps|U_ulLnnqC_mqNvxq`@';

    test('decodes the documented example to its three known points', () {
      final points = decodeRoutePolyline(encoded)!;
      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 1e-5));
      expect(points[0].longitude, closeTo(-120.2, 1e-5));
      expect(points[1].latitude, closeTo(40.7, 1e-5));
      expect(points[1].longitude, closeTo(-120.95, 1e-5));
      expect(points[2].latitude, closeTo(43.252, 1e-5));
      expect(points[2].longitude, closeTo(-126.453, 1e-5));
    });

    test('returns null for null, empty, or overly long input', () {
      expect(decodeRoutePolyline(null), isNull);
      expect(decodeRoutePolyline(''), isNull);
      expect(decodeRoutePolyline('a' * 1000001), isNull);
    });

    test('returns null for a single-point route (needs at least two)', () {
      expect(decodeRoutePolyline(r'_p~iF~ps|U'), isNull);
    });

    test('returns null instead of throwing on truncated/malformed input', () {
      expect(decodeRoutePolyline('~~~~~~~~~~~~~~~~'), isNull);
      expect(decodeRoutePolyline('!!!!'), isNull);
      expect(decodeRoutePolyline(encoded.substring(0, encoded.length - 2)), isNull);
    });
  });
}
