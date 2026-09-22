import '../core/api_client.dart';
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

  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    if (query.trim().length < 2) return const [];
    final json = await _api.get('/places?q=${Uri.encodeQueryComponent(query.trim())}') as List;
    return json.map((row) => PlaceSuggestion.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<GeoPoint> place(String placeId) async {
    final json = await _api.get('/places/${Uri.encodeComponent(placeId)}') as Map<String, dynamic>;
    return GeoPoint.fromJson(json);
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
