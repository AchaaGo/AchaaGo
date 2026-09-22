import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../l10n/errors_mn.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/app_scope.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/order_summary_card.dart';
import '../../widgets/primary_button.dart';

/// Drives an assigned order through the statuses the API allows a driver
/// to set (services/api/app/main.py `driver_status`): accept → arriving →
/// arrived → picked up → delivered → completed. There is no
/// driver-initiated decline/reject endpoint today — see
/// apps/mobile/BACKEND_REQUIREMENTS.md.
class DriverActiveOrderScreen extends StatefulWidget {
  const DriverActiveOrderScreen({super.key, required this.initialOrder});

  final Order initialOrder;

  @override
  State<DriverActiveOrderScreen> createState() => _DriverActiveOrderScreenState();
}

class _DriverActiveOrderScreenState extends State<DriverActiveOrderScreen> {
  late Order _order = widget.initialOrder;
  bool _busy = false;
  String? _error;

  Future<void> _act(Future<Order> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await action();
      if (mounted) setState(() => _order = updated);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(describeStatus(_order.status))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            OrderSummaryCard(order: _order),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(Strings.driverCustomerLabel),
                subtitle: Text(_order.pickup.address),
              ),
            ),
            ErrorBanner(message: _error),
            const SizedBox(height: 20),
            ..._buildActions(appState),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(AppState appState) {
    switch (_order.status) {
      case 'assigned':
        return [
          PrimaryButton(
            accent: true,
            busy: _busy,
            label: Strings.driverAccept,
            onPressed: () => _act(() => appState.driverRepository.accept(_order.id)),
          ),
        ];
      case 'driver_arriving':
        return [
          PrimaryButton(
            accent: true,
            busy: _busy,
            label: Strings.driverArrived,
            onPressed: () => _act(() => appState.driverRepository.setStatus(_order.id, 'arrived')),
          ),
        ];
      case 'arrived':
        return [
          PrimaryButton(
            accent: true,
            busy: _busy,
            label: Strings.driverPickedUp,
            onPressed: () => _act(() => appState.driverRepository.setStatus(_order.id, 'picked_up')),
          ),
        ];
      case 'picked_up':
        return [
          PrimaryButton(
            accent: true,
            busy: _busy,
            label: Strings.driverDelivered,
            onPressed: () => _act(() => appState.driverRepository.setStatus(_order.id, 'delivered')),
          ),
        ];
      case 'delivered':
        if (_order.paymentMethod == 'cash' && _order.paymentStatus != 'paid') {
          return [
            PrimaryButton(
              accent: true,
              busy: _busy,
              label: Strings.driverConfirmCash,
              onPressed: () => _act(() => appState.driverRepository.confirmCashReceived(_order.id)),
            ),
          ];
        }
        return [
          const Text(Strings.driverWaitingForQpay, style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _act(() async {
                      await appState.driverRepository.checkPayment(_order.id);
                      return appState.driverRepository.orderDetail(_order.id);
                    }),
            child: const Text(Strings.driverCheckPayment),
          ),
        ];
      case 'completed':
        return [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(Strings.driverOrderCompleted, style: TextStyle(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          ),
        ];
      default:
        return const [];
    }
  }
}
