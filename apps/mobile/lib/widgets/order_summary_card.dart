import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../l10n/strings.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

/// Mirrors the `Summary` component in apps/web CustomerFlow.tsx: pickup
/// dot, dropoff marker, then service + loader + payment method and total.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final paymentLabel = order.paymentMethod == 'qpay' ? Strings.payQpay : Strings.payCash;
    final loaderSuffix = (order.loaders ?? 0) > 0 ? ' + ачигч' : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.ground, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AddressRow(dot: true, text: order.pickup.address),
          const SizedBox(height: 10),
          _AddressRow(dot: false, text: order.dropoff.address),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.line),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${order.serviceName}$loaderSuffix · $paymentLabel',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              if (order.totalPrice != null)
                Text(formatMoney(order.totalPrice!), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.dot, required this.text});

  final bool dot;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: dot
              ? const CircleAvatar(radius: 5, backgroundColor: AppColors.ink)
              : Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: AppColors.accent, border: Border.all(color: AppColors.ink, width: 2)),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
