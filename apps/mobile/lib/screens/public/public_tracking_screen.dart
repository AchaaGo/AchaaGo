import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../l10n/errors_mn.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../realtime/order_channel.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/map_sheet_screen.dart';
import '../../widgets/route_illustration.dart';

/// `GET /t/{token}` + `/ws/tracking/{token}` — no login required. Mirrors
/// apps/web's PublicTracking.tsx.
class PublicTrackingScreen extends StatefulWidget {
  const PublicTrackingScreen({super.key, required this.token});

  final String token;

  @override
  State<PublicTrackingScreen> createState() => _PublicTrackingScreenState();
}

class _PublicTrackingScreenState extends State<PublicTrackingScreen> {
  Order? _order;
  String? _error;
  OrderChannel? _channel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _channel?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final appState = AppScope.of(context);
    setState(() => _error = null);
    try {
      final order = await appState.customerRepository.publicTracking(widget.token);
      if (!mounted) return;
      setState(() => _order = order);
      _connect();
      _pollTimer ??= Timer.periodic(const Duration(seconds: 8), (_) => _poll());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _connect() async {
    try {
      final channel = await OrderChannel.connectTracking(widget.token);
      if (!mounted) {
        await channel.close();
        return;
      }
      _channel = channel;
      channel.listen((order) {
        if (mounted) setState(() => _order = order);
      });
    } catch (_) {
      // The 8s poll below is the reliable fallback.
    }
  }

  Future<void> _poll() async {
    final appState = AppScope.of(context);
    try {
      final order = await appState.customerRepository.publicTracking(widget.token);
      if (mounted) setState(() => _order = order);
    } catch (_) {
      // Transient network hiccup; the next tick tries again.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(message: _error!, icon: Icons.link_off, onRetry: _load),
      );
    }
    final order = _order;
    if (order == null) {
      return const Scaffold(backgroundColor: AppColors.ink, body: LoadingView(dark: true));
    }
    final driver = order.driver;
    return Scaffold(
      body: SafeArea(
        child: MapSheetScreen(
          background: RouteIllustration(showRoute: true, showTruck: driver != null),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(20)),
              child: Text(describeStatus(order.status), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            Text(Strings.publicTrackingHeading, style: Theme.of(context).textTheme.headlineSmall),
            if (driver != null) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.ink,
                        child: Icon(Icons.local_shipping, color: AppColors.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(driver.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Row(children: [
                              const Icon(Icons.star, size: 14, color: AppColors.accent),
                              const SizedBox(width: 4),
                              Text(driver.rating?.toStringAsFixed(1) ?? 'Шинэ'),
                            ]),
                          ],
                        ),
                      ),
                      Text(driver.plateNumber ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(Strings.pickupLabel, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  Text(order.pickup.address),
                  const SizedBox(height: 10),
                  const Text(Strings.dropoffLabel, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  Text(order.dropoff.address),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(order.serviceName),
                      Text('${order.distanceKm.toStringAsFixed(1)} км'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              Strings.publicTrackingPrivacyNote,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
