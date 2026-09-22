import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/order.dart';
import '../realtime/order_channel.dart';
import 'app_scope.dart';

/// Shared "keep this order's status live" logic for the finding-driver and
/// tracking screens: an authenticated WebSocket for snappy updates
/// (services/api/app/main.py `/ws/orders/{id}`), backed by a REST poll
/// every 5s in case the socket never connects or drops.
mixin OrderWatcherMixin<T extends StatefulWidget> on State<T> {
  OrderChannel? _channel;
  Timer? _pollTimer;
  String? _watchedOrderId;

  void startWatching(String orderId, ValueChanged<Order> onUpdate) {
    stopWatching();
    _watchedOrderId = orderId;
    _connect(orderId, onUpdate);
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll(orderId, onUpdate));
  }

  Future<void> _connect(String orderId, ValueChanged<Order> onUpdate) async {
    final appState = AppScope.of(context);
    final token = await appState.sessionStore.readAccessToken();
    if (token == null || !mounted || _watchedOrderId != orderId) return;
    try {
      final channel = await OrderChannel.connectAuthenticated(orderId: orderId, accessToken: token);
      if (!mounted || _watchedOrderId != orderId) {
        await channel.close();
        return;
      }
      _channel = channel;
      channel.listen(onUpdate);
    } catch (_) {
      // The poll timer below is the reliable fallback.
    }
  }

  Future<void> _poll(String orderId, ValueChanged<Order> onUpdate) async {
    if (!mounted || _watchedOrderId != orderId) return;
    final appState = AppScope.of(context);
    try {
      final fresh = await appState.customerRepository.orderDetail(orderId);
      if (mounted && _watchedOrderId == orderId) onUpdate(fresh);
    } catch (_) {
      // Transient network hiccup; the next tick tries again.
    }
  }

  void stopWatching() {
    _watchedOrderId = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _channel?.close();
    _channel = null;
  }
}
