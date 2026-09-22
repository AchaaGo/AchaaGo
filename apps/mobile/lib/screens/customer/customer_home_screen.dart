import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/errors_mn.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../models/service.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../driver/driver_registration_screen.dart';
import '../login/phone_entry_screen.dart';
import '../public/public_tracking_entry_screen.dart';
import 'finding_driver_screen.dart';
import 'order_tracking_screen.dart';
import 'route_planner_screen.dart';

/// Screen 3 in AGENTS.md: service selection, plus an entry point back
/// into whatever order is currently active (the mobile equivalent of the
/// web app resuming its WebSocket-tracked order on reload).
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  bool _loading = true;
  String? _error;
  List<ServiceOption> _services = const [];
  Order? _currentOrder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = await appState.customerRepository.services();
      Order? active;
      try {
        final orders = await appState.customerRepository.myOrders();
        if (orders.isNotEmpty && orders.first.isActive) active = orders.first;
      } catch (_) {
        // Current-order lookup is a convenience; ignore failures here.
      }
      if (!mounted) return;
      setState(() {
        _services = services;
        _currentOrder = active;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _openCurrentOrder() {
    final order = _currentOrder;
    if (order == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => order.status == 'pending'
          ? FindingDriverScreen(initialOrder: order)
          : OrderTrackingScreen(initialOrder: order),
    ));
  }

  void _openRoutePlanner(String? serviceId) {
    if (_services.isEmpty) return;
    final resolved = serviceId ??
        _services.firstWhere((s) => s.code == 'porter', orElse: () => _services.first).id;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoutePlannerScreen(initialServiceId: resolved, services: _services),
    )).then((_) => _load());
  }

  Future<void> _handleMenu(String value) async {
    final appState = AppScope.of(context);
    switch (value) {
      case 'current_order':
        _openCurrentOrder();
        break;
      case 'become_driver':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverRegistrationScreen()));
        if (mounted) await appState.refreshUser();
        break;
      case 'track':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PublicTrackingEntryScreen()));
        break;
      case 'logout':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(Strings.logoutConfirmTitle),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text(Strings.confirmNo)),
              TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text(Strings.menuLogout)),
            ],
          ),
        );
        if (confirmed == true) {
          await appState.logout();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
            (route) => false,
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AchaaGo'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenu,
            itemBuilder: (context) => [
              if (_currentOrder != null)
                const PopupMenuItem(value: 'current_order', child: Text(Strings.menuCurrentOrder)),
              const PopupMenuItem(value: 'track', child: Text(Strings.menuTrackByLink)),
              if (!(appState.user?.isDriver ?? false))
                const PopupMenuItem(value: 'become_driver', child: Text(Strings.menuBecomeDriver)),
              const PopupMenuItem(value: 'logout', child: Text(Strings.menuLogout)),
            ],
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(appState.user?.name),
      ),
    );
  }

  Widget _buildBody(String? name) {
    if (_loading) return const LoadingView();
    if (_error != null && _services.isEmpty) {
      return ListView(
        children: [EmptyState(message: _error!, icon: Icons.wifi_off, onRetry: _load)],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(Strings.greeting(name), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(Strings.homeHeading, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (_currentOrder != null) _CurrentOrderCard(order: _currentOrder!, onTap: _openCurrentOrder),
        if (_services.isEmpty)
          const EmptyState(message: Strings.emptyServicesTitle)
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.86,
            children: _services.map((service) => _ServiceCard(
                  service: service,
                  onTap: () => _openRoutePlanner(service.id),
                )).toList(),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _services.isEmpty ? null : () => _openRoutePlanner(null),
          icon: const Icon(Icons.search),
          label: const Text(Strings.searchPrompt),
        ),
      ],
    );
  }
}

class _CurrentOrderCard extends StatelessWidget {
  const _CurrentOrderCard({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppColors.accentSoft,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.local_shipping_outlined, color: AppColors.ink),
        title: const Text(Strings.menuCurrentOrder, style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(describeStatus(order.status)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});

  final ServiceOption service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.ground,
          border: Border.all(color: AppColors.line, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: AppColors.ink,
              child: Icon(
                service.icon == 'package' ? Icons.inventory_2_outlined : Icons.local_shipping_outlined,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 9),
            Text(service.nameMn, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              service.descriptionMn,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text('${Strings.startingPricePrefix}${formatMoney(service.baseFare)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
