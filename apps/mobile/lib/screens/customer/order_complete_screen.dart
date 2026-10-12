import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/order_summary_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/star_rating.dart';

/// Shown once an order reaches `completed` — order summary plus the
/// 1–5 star rating (`POST /orders/{id}/rating`).
class OrderCompleteScreen extends StatefulWidget {
  const OrderCompleteScreen({super.key, required this.order});

  final Order order;

  @override
  State<OrderCompleteScreen> createState() => _OrderCompleteScreenState();
}

class _OrderCompleteScreenState extends State<OrderCompleteScreen> {
  late Order _order = widget.order;
  bool _busy = false;
  String? _error;

  Future<void> _rate(int value) async {
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await appState.customerRepository.rateOrder(_order.id, value);
      if (mounted) setState(() => _order = updated);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _newOrder() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final rated = _order.rating != null;
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                child: Icon(Icons.check, size: 48, color: p.onBrand),
              ),
              const SizedBox(height: 20),
              Text(Strings.deliveredHeading, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(Strings.deliveredSubtitle, style: TextStyle(color: p.muted), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OrderSummaryCard(order: _order),
              const SizedBox(height: 22),
              const Text(Strings.rateDriverPrompt, style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              StarRating(value: _order.rating ?? 0, onChanged: (_busy || rated) ? null : _rate),
              if (rated)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(Strings.thanksForRating, style: TextStyle(color: p.muted)),
                ),
              ErrorBanner(message: _error),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: PrimaryButton(label: Strings.newOrder, onPressed: _newOrder)),
            ],
          ),
        ),
      ),
    );
  }
}
