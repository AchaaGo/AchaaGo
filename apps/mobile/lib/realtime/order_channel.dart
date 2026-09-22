import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../models/order.dart';

typedef OrderSnapshotHandler = void Function(Order order);

/// Wraps `/ws/orders/{id}` and `/ws/tracking/{token}`
/// (services/api/app/main.py `websocket_order`). The server pushes a full
/// order snapshot on every status/location change and at least every 20s,
/// so this only needs to decode `{"type": "snapshot", "order": {...}}`.
///
/// The authenticated order socket has no cookie jar to rely on (unlike
/// the web app), so per the server's own fallback it expects the access
/// token as the first JSON text frame within 10 seconds of connecting.
class OrderChannel {
  OrderChannel._(this._channel);

  final WebSocketChannel _channel;
  StreamSubscription<dynamic>? _subscription;

  static Future<OrderChannel> connectAuthenticated({
    required String orderId,
    required String accessToken,
  }) async {
    final uri = Uri.parse('${AppConfig.wsBaseUrl}/ws/orders/${Uri.encodeComponent(orderId)}');
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    channel.sink.add(jsonEncode({'token': accessToken}));
    return OrderChannel._(channel);
  }

  static Future<OrderChannel> connectTracking(String trackingToken) async {
    final uri = Uri.parse('${AppConfig.wsBaseUrl}/ws/tracking/${Uri.encodeComponent(trackingToken)}');
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return OrderChannel._(channel);
  }

  void listen(
    OrderSnapshotHandler onSnapshot, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) {
    _subscription = _channel.stream.listen(
      (dynamic message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'snapshot' && data['order'] != null) {
            onSnapshot(Order.fromJson(data['order'] as Map<String, dynamic>));
          }
        } catch (_) {
          // Malformed/unknown frame: the server resends a snapshot soon.
        }
      },
      onDone: onDone,
      onError: (Object error, StackTrace _) => onError?.call(error),
      cancelOnError: false,
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _channel.sink.close();
  }
}
