import 'point.dart';

/// The `driver` object inside `order_json()` (services/api/app/orders.py).
/// `id`/`phone` are only present on the non-public shape (the customer's
/// own view or the driver's own view), never on `/t/{token}`.
class OrderDriver {
  const OrderDriver({
    this.id,
    this.phone,
    this.name,
    this.rating,
    this.plateNumber,
    this.location,
    required this.locationFresh,
  });

  final String? id;
  final String? phone;
  final String? name;
  final double? rating;
  final String? plateNumber;
  final GeoPoint? location;
  final bool locationFresh;

  factory OrderDriver.fromJson(Map<String, dynamic> json) => OrderDriver(
        id: json['id'] as String?,
        phone: json['phone'] as String?,
        name: json['name'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        plateNumber: json['plate_number'] as String?,
        location: json['location'] == null
            ? null
            : GeoPoint(
                lat: (json['location']['lat'] as num).toDouble(),
                lng: (json['location']['lng'] as num).toDouble(),
                address: '',
              ),
        locationFresh: json['location_fresh'] as bool? ?? false,
      );
}

/// Order statuses that still need action (see `ACTIVE` in
/// services/api/app/pricing.py).
const activeOrderStatuses = {
  'pending',
  'assigned',
  'driver_arriving',
  'arrived',
  'picked_up',
  'delivered',
};

const terminalOrderStatuses = {'completed', 'cancelled', 'no_driver_found'};

/// `order_json()` — fields marked nullable are omitted from the public
/// `/t/{token}` shape.
class Order {
  const Order({
    required this.id,
    required this.status,
    required this.serviceName,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.durationMinutes,
    required this.updatedAt,
    required this.createdAt,
    this.driver,
    this.serviceId,
    this.loaders,
    this.paymentMethod,
    this.paymentStatus,
    this.totalPrice,
    this.trackingToken,
    this.rating,
    this.canCancel,
  });

  final String id;
  final String status;
  final String serviceName;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final double distanceKm;
  final int durationMinutes;
  final DateTime updatedAt;
  final DateTime createdAt;
  final OrderDriver? driver;

  final String? serviceId;
  final int? loaders;
  final String? paymentMethod;
  final String? paymentStatus;
  final int? totalPrice;
  final String? trackingToken;
  final int? rating;
  final bool? canCancel;

  bool get isActive => activeOrderStatuses.contains(status);
  bool get isTerminal => terminalOrderStatuses.contains(status);

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        status: json['status'] as String,
        serviceName: json['service_name'] as String? ?? '',
        pickup: GeoPoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: GeoPoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        durationMinutes: json['duration_minutes'] as int? ?? 0,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        driver: json['driver'] == null ? null : OrderDriver.fromJson(json['driver'] as Map<String, dynamic>),
        serviceId: json['service_id'] as String?,
        loaders: json['loaders'] as int?,
        paymentMethod: json['payment_method'] as String?,
        paymentStatus: json['payment_status'] as String?,
        totalPrice: json['total_price'] as int?,
        trackingToken: json['tracking_token'] as String?,
        rating: json['rating'] as int?,
        canCancel: json['can_cancel'] as bool?,
      );
}
