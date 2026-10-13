import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/formatting.dart';
import '../models/order.dart';
import '../models/point.dart';
import '../models/quote.dart';
import '../models/service.dart';

/// Wraps the customer-facing endpoints of services/api/app/main.py.
class CustomerRepository {
  CustomerRepository(this._api);

  final ApiClient _api;

  Future<List<ServiceOption>> services() async {
    final json = await _api.get('/services') as List;
    return json.map((row) => ServiceOption.fromJson(row as Map<String, dynamic>)).toList();
  }

  /// [session] is the Google Places billing session (see PlaceSession): send
  /// the same token with every search of one typing session and with the
  /// [place] call that ends it.
  Future<List<PlaceSuggestion>> searchPlaces(String query, {String? session}) async {
    if (query.trim().length < 2) return const [];
    final sessionParam = session == null ? '' : '&session=${Uri.encodeQueryComponent(session)}';
    final json = await _api.get('/places?q=${Uri.encodeQueryComponent(query.trim())}$sessionParam') as List;
    return json.map((row) => PlaceSuggestion.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<GeoPoint> place(String placeId, {String? session}) async {
    final sessionParam = session == null ? '' : '?session=${Uri.encodeQueryComponent(session)}';
    final json = await _api.get('/places/${Uri.encodeComponent(placeId)}$sessionParam') as Map<String, dynamic>;
    return GeoPoint.fromJson(json);
  }

  /// The street address of a map tap or GPS fix, or null when there is none
  /// (demo maps, an empty steppe, an older server, or any failure): callers
  /// then label the point themselves, as apps/web does when its geocoder
  /// throws.
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final json = await _api.get('/geocode?lat=${lat.toStringAsFixed(6)}&lng=${lng.toStringAsFixed(6)}');
      if (json is! Map<String, dynamic>) return null;
      final address = (json['address'] as String?)?.trim();
      if (address == null || address.length < 2) return null;
      // Location.address is limited to 300 characters on the server.
      return address.length > 300 ? address.substring(0, 300) : address;
    } on ApiException {
      return null;
    }
  }

  Future<Quote> quote({required GeoPoint pickup, required GeoPoint dropoff, required int loaders}) async {
    final json = await _api.post('/quotes', body: {
      'pickup': pickup.toJson(),
      'dropoff': dropoff.toJson(),
      'loaders': loaders,
    }) as Map<String, dynamic>;
    return Quote.fromJson(json);
  }

  Future<Order> createOrder({
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required int loaders,
    required String serviceId,
    required String paymentMethod,
    required int expectedTotal,
    required String quoteToken,
  }) async {
    final json = await _api.post(
      '/orders',
      headers: {'Idempotency-Key': newIdempotencyKey()},
      body: {
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'loaders': loaders,
        'service_id': serviceId,
        'payment_method': paymentMethod,
        'expected_total': expectedTotal,
        'quote_token': quoteToken,
      },
    ) as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<List<Order>> myOrders({int offset = 0}) async {
    final json = await _api.get('/orders?offset=$offset') as List;
    return json.map((row) => Order.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<Order> orderDetail(String orderId) async {
    final json = await _api.get('/orders/${Uri.encodeComponent(orderId)}') as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<Order> cancelOrder(String orderId, String reason) async {
    final json = await _api.post('/orders/${Uri.encodeComponent(orderId)}/cancel', body: {'reason': reason})
        as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<Order> rateOrder(String orderId, int rating) async {
    final json = await _api.post('/orders/${Uri.encodeComponent(orderId)}/rating', body: {'rating': rating})
        as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<Map<String, dynamic>> qpayInvoice(String orderId) async {
    final json = await _api.post('/orders/${Uri.encodeComponent(orderId)}/qpay-invoice', body: '{}');
    return json as Map<String, dynamic>;
  }

  Future<bool> checkPayment(String orderId) async {
    final json = await _api.post('/orders/${Uri.encodeComponent(orderId)}/check-payment', body: '{}')
        as Map<String, dynamic>;
    return json['paid'] as bool? ?? false;
  }

  Future<Order> publicTracking(String token) async {
    final json = await _api.get('/t/${Uri.encodeComponent(token)}', auth: false) as Map<String, dynamic>;
    return Order.fromJson(json);
  }
}
