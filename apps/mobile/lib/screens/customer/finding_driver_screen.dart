import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/app_scope.dart';
import '../../state/order_watcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/map_sheet_screen.dart';
import '../../widgets/order_summary_card.dart';
import '../../widgets/route_illustration.dart';
import 'order_complete_screen.dart';
import 'order_tracking_screen.dart';

/// Screen 5 in AGENTS.md: shown while `status == pending`.
class FindingDriverScreen extends StatefulWidget {
  const FindingDriverScreen({super.key, required this.initialOrder});

  final Order initialOrder;

  @override
  State<FindingDriverScreen> createState() => _FindingDriverScreenState();
}

class _FindingDriverScreenState extends State<FindingDriverScreen> with OrderWatcherMixin {
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
    } else if (updated.status != 'pending') {
      _navigated = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderTrackingScreen(initialOrder: updated)));
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: MapSheetScreen(
            background: const RouteIllustration(showRoute: true, pulse: true),
            children: [
              Text(Strings.findingHeading, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(Strings.findingSubtitle(_order.serviceName), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                child: LinearProgressIndicator(minHeight: 6, color: AppColors.accent, backgroundColor: AppColors.line),
              ),
              const SizedBox(height: 18),
              OrderSummaryCard(order: _order),
              ErrorBanner(message: _error),
              if (_order.canCancel ?? true) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text(Strings.cancelOrder),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
