import '../core/api_client.dart';
import '../models/driver_profile.dart';
import '../models/order.dart';

/// Wraps `/driver/*` and the shared cash-confirmation endpoint used by
/// drivers (services/api/app/main.py).
class DriverRepository {
  DriverRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> register({
    required String name,
    required String licenseInfo,
    required String serviceId,
    required String plateNumber,
    required String model,
    required int capacityKg,
  }) async {
    final json = await _api.post('/driver/register', body: {
      'name': name,
      'license_info': licenseInfo,
      'service_id': serviceId,
      'plate_number': plateNumber,
      'model': model,
      'capacity_kg': capacityKg,
    });
    return json as Map<String, dynamic>;
  }

  Future<DriverProfile> me() async {
    final json = await _api.get('/driver/me') as Map<String, dynamic>;
    return DriverProfile.fromJson(json);
  }

  Future<void> goOnline({required double lat, required double lng}) async {
    await _api.post('/driver/online', body: {'lat': lat, 'lng': lng});
  }

  Future<void> goOffline() async {
    await _api.post('/driver/offline', body: '{}');
  }

  Future<void> updateLocation({required double lat, required double lng}) async {
    await _api.post('/driver/location', body: {'lat': lat, 'lng': lng});
  }

  Future<List<Order>> offers() async {
    final json = await _api.get('/driver/offers') as List;
    return json.map((row) => Order.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<Order> accept(String orderId) async {
    final json = await _api.post('/driver/orders/${Uri.encodeComponent(orderId)}/accept', body: '{}')
        as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<Order> setStatus(String orderId, String status, {String? reason}) async {
    final json = await _api.post(
      '/driver/orders/${Uri.encodeComponent(orderId)}/status',
      body: {'status': status, if (reason != null) 'reason': reason},
    ) as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<Order> confirmCashReceived(String orderId) async {
    final json = await _api.post('/orders/${Uri.encodeComponent(orderId)}/cash-received', body: '{}')
        as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<bool> checkPayment(String orderId) async {
    final json = await _api.post('/orders/${Uri.encodeComponent(orderId)}/check-payment', body: '{}')
        as Map<String, dynamic>;
    return json['paid'] as bool? ?? false;
  }

  /// `GET /orders/{id}` also authorizes the order's assigned driver (see
  /// `get_order()` in services/api/app/orders.py), so the driver flows can
  /// use it directly to refresh an order without going through
  /// [CustomerRepository].
  Future<Order> orderDetail(String orderId) async {
    final json = await _api.get('/orders/${Uri.encodeComponent(orderId)}') as Map<String, dynamic>;
    return Order.fromJson(json);
  }
}
