/// GET /driver/me.
class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.status,
    required this.isOnline,
    this.rating,
    this.name,
    required this.plateNumber,
    required this.serviceId,
  });

  final String id;
  final String status; // pending | approved | suspended
  final bool isOnline;
  final double? rating;
  final String? name;
  final String plateNumber;
  final String serviceId;

  bool get isApproved => status == 'approved';

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        id: json['id'] as String,
        status: json['status'] as String,
        isOnline: json['is_online'] as bool? ?? false,
        rating: (json['rating'] as num?)?.toDouble(),
        name: json['name'] as String?,
        plateNumber: json['plate_number'] as String? ?? '',
        serviceId: json['service_id'] as String? ?? '',
      );
}
