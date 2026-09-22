import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/errors_mn.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/app_scope.dart';
import '../../state/order_watcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/map_sheet_screen.dart';
import '../../widgets/order_summary_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/route_illustration.dart';
import 'order_complete_screen.dart';

/// Screen 6 in AGENTS.md: live driver tracking for an assigned order.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key, required this.initialOrder});

  final Order initialOrder;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> with OrderWatcherMixin {
  late Order _order = widget.initialOrder;
  bool _navigated = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    startWatching(_order.id, _handleUpdate);
  }

  @override
  void dispose() {
    stopWatching();
    super.dispose();
  }

  void _handleUpdate(Order updated) {
    if (!mounted || _navigated) return;
    setState(() => _order = updated);
    if (updated.status == 'completed') {
      _navigated = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderCompleteScreen(order: updated)));
    } else if (updated.status == 'cancelled' || updated.status == 'no_driver_found') {
      _navigated = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _cancel() async {
    final appState = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(Strings.cancelConfirmTitle),
        content: const Text(Strings.cancelConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text(Strings.confirmNo)),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text(Strings.confirmYes)),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.customerRepository.cancelOrder(_order.id, Strings.cancelReasonDefault);
      if (!mounted) return;
      _navigated = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call() async {
    final phone = _order.driver?.phone;
    if (phone == null) return;
    final launched = await _tryLaunch(Uri(scheme: 'tel', path: phone));
    if (!launched) _notify(Strings.callUnavailable);
  }

  Future<void> _message() async {
    final phone = _order.driver?.phone;
    if (phone == null) return;
    final launched = await _tryLaunch(Uri(scheme: 'sms', path: phone));
    if (!launched) _notify(Strings.messageUnavailable);
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showQpay() async {
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await appState.customerRepository.qpayInvoice(_order.id);
      if (mounted) _openQpayDialog(data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openQpayDialog(Map<String, dynamic> data) {
    final amount = data['amount'] as int? ?? _order.totalPrice ?? 0;
    final isDemo = data['demo'] == true;
    final qrImage = data['qr_image'] as String?;
    final urls = (data['urls'] as List?) ?? const [];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('QPay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatMoney(amount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
            const SizedBox(height: 12),
            if (isDemo)
              const Text(Strings.qpayDemoNotice, style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center)
            else if (qrImage != null && qrImage.isNotEmpty)
              Image.memory(base64Decode(qrImage), width: 220, height: 220),
            for (final entry in urls)
              if (entry is Map)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      accent: true,
                      label: (entry['description'] as String?) ?? Strings.qpayOpenLink,
                      onPressed: () async {
                        final link = entry['link'] as String?;
                        if (link == null) return;
                        final launched = await _tryLaunch(Uri.parse(link));
                        if (!launched) _notify(Strings.linkOpenFailed);
                      },
                    ),
                  ),
                ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text(Strings.close))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = _order.driver;
    final initials = (driver?.name?.trim().isNotEmpty ?? false) ? driver!.name!.trim().substring(0, 1).toUpperCase() : 'Ж';
    final needsQpay = _order.paymentMethod == 'qpay' && _order.paymentStatus != 'paid';
    return Scaffold(
      body: SafeArea(
        child: MapSheetScreen(
          background: RouteIllustration(showRoute: true, showTruck: driver?.location != null),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(describeStatus(_order.status), style: const TextStyle(color: AppColors.muted)),
                      Text('~${_order.durationMinutes} мин', style: Theme.of(context).textTheme.headlineMedium),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 2), borderRadius: BorderRadius.circular(10)),
                  child: Text(driver?.plateNumber ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.ink,
                  child: Text(initials, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 18)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver?.name ?? 'Жолооч', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                      Row(children: [
                        const Icon(Icons.star, size: 15, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Text('${driver?.rating?.toStringAsFixed(1) ?? 'Шинэ'} · ${_order.serviceName}', style: const TextStyle(color: AppColors.muted)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: accentButtonStyle,
                    onPressed: driver?.phone != null ? _call : null,
                    icon: const Icon(Icons.call),
                    label: const Text(Strings.callDriver),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: driver?.phone != null ? _message : null,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text(Strings.messageDriver),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OrderSummaryCard(order: _order),
            if (needsQpay) ...[
              const SizedBox(height: 12),
              PrimaryButton(label: Strings.payWithQpayButton, busy: _busy, onPressed: _showQpay),
            ],
            ErrorBanner(message: _error),
            if (_order.canCancel ?? false) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: _busy ? null : _cancel, child: const Text(Strings.cancelOrder)),
            ],
          ],
        ),
      ),
    );
  }
}
