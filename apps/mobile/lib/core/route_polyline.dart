import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Decodes a Google encoded polyline (1e5 precision) into route points.
/// Mirrors apps/web/src/lib/roadRoute.ts's `decodeRoutePath`: rejects
/// malformed input rather than silently drawing a wrong or partial route.
/// Returns null (never throws) so callers can fall back to a straight
/// line between pickup and drop-off, same as when the server has no
/// polyline at all (e.g. the demo maps provider).
List<LatLng>? decodeRoutePolyline(String? encoded) {
  if (encoded == null || encoded.isEmpty || encoded.length > 1000000) return null;
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;

  int? readDelta() {
    var result = 0, shift = 0, value = 0;
    do {
      if (index >= encoded.length || shift > 30) return null;
      value = encoded.codeUnitAt(index) - 63;
      index++;
      if (value < 0 || value > 63) return null;
      result += (value & 31) << shift;
      shift += 5;
    } while (value >= 32);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    final dLat = readDelta();
    if (dLat == null) return null;
    lat += dLat;
    final dLng = readDelta();
    if (dLng == null) return null;
    lng += dLng;
    final point = LatLng(lat / 1e5, lng / 1e5);
    if (point.latitude.abs() > 90 || point.longitude.abs() > 180) return null;
    points.add(point);
  }
  if (points.length < 2) return null;
  return points;
}
