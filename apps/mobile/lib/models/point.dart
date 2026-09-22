/// `Location` in services/api/app/schemas.py: lat in [47, 49], lng in
/// [105, 108] (Ulaanbaatar bounding box), address 2–300 chars.
class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, required this.address});

  final double lat;
  final double lng;
  final String address;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: json['address'] as String,
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'address': address};
}

class PlaceSuggestion {
  const PlaceSuggestion({required this.id, required this.address});

  final String id;
  final String address;

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      PlaceSuggestion(id: json['id'] as String, address: json['address'] as String);
}
