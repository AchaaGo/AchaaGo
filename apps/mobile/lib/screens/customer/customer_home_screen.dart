import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/errors_mn.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../models/point.dart';
import '../../models/service.dart';
import '../../state/app_scope.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../../widgets/live_map_view.dart';
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
  GeoPoint _pickup = const GeoPoint(
      lat: 47.9186, lng: 106.9177, address: Strings.currentLocation);

  @override
  void initState() {
    super.initState();
    _load();
    _resolvePickup();
  }

  Future<void> _resolvePickup() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)),
      );
      if (mounted) {
        setState(() => _pickup = GeoPoint(
            lat: position.latitude,
            lng: position.longitude,
            address: Strings.currentLocation));
      }
    } catch (_) {
      // A denied or unavailable location keeps the map centered on Ulaanbaatar.
    }
  }

  Future<void> _load() async {
    final appState = AppScope.read(context);
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
    } catch (e) {
      // Anything that isn't an ApiException used to leave this screen
      // spinning forever. Show the retry state, with the exception type so
      // a bug report from a real device says what actually failed.
      if (!mounted) return;
      setState(() {
        _error = '${Strings.offlineBody}\n(${e.runtimeType})';
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
        _services
            .firstWhere((s) => s.code == 'porter',
                orElse: () => _services.first)
            .id;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => RoutePlannerScreen(
              initialServiceId: resolved, services: _services),
        ))
        .then((_) => _load());
  }

  Future<void> _handleMenu(String value) async {
    final appState = AppScope.of(context);
    switch (value) {
      case 'current_order':
        _openCurrentOrder();
        break;
      case 'become_driver':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const DriverRegistrationScreen()));
        if (mounted) await appState.refreshUser();
        break;
      case 'track':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const PublicTrackingEntryScreen()));
        break;
      case 'logout':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(Strings.logoutConfirmTitle),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text(Strings.confirmNo)),
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text(Strings.menuLogout)),
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
      body: Stack(
        children: [
          Positioned.fill(child: LiveMapView(pickup: _pickup)),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundControl(
                      icon: Icons.menu,
                      tooltip: 'Цэс',
                      onPressed: () => _showMenu(context, appState)),
                  PopupMenuButton<String>(
                    onSelected: _handleMenu,
                    itemBuilder: (context) => [
                      if (_currentOrder != null)
                        const PopupMenuItem(
                            value: 'current_order',
                            child: Text(Strings.menuCurrentOrder)),
                      const PopupMenuItem(
                          value: 'track', child: Text(Strings.menuTrackByLink)),
                      if (!(appState.user?.isDriver ?? false))
                        const PopupMenuItem(
                            value: 'become_driver',
                            child: Text(Strings.menuBecomeDriver)),
                      const PopupMenuItem(
                          value: 'logout', child: Text(Strings.menuLogout)),
                    ],
                    tooltip: 'Профайл',
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: const CircleAvatar(
                      radius: 25,
                      backgroundColor: AppColors.surface,
                      child: Icon(Icons.person_outline, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.sizeOf(context).height * 0.55,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x2414213D),
                      blurRadius: 28,
                      offset: Offset(0, -8))
                ],
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                        width: 40,
                        height: 5,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Color(0xFFD9D3C6),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(3))))),
                  ),
                  Expanded(
                      child: RefreshIndicator(
                          onRefresh: _load,
                          child: _buildBody(appState.user?.name))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundControl(
      {required IconData icon,
      required String tooltip,
      required VoidCallback onPressed}) {
    return Material(
      color: AppColors.surface,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
          icon: Icon(icon, color: AppColors.ink),
          tooltip: tooltip,
          onPressed: onPressed),
    );
  }

  void _showMenu(BuildContext context, AppState appState) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentOrder != null)
              ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text(Strings.menuCurrentOrder),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openCurrentOrder();
                  }),
            ListTile(
                leading: const Icon(Icons.link),
                title: const Text(Strings.menuTrackByLink),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleMenu('track');
                }),
            if (!(appState.user?.isDriver ?? false))
              ListTile(
                  leading: const Icon(Icons.drive_eta_outlined),
                  title: const Text(Strings.menuBecomeDriver),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleMenu('become_driver');
                  }),
            ListTile(
                leading: const Icon(Icons.logout),
                title: const Text(Strings.menuLogout),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleMenu('logout');
                }),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String? name) {
    if (_loading) return const LoadingView();
    if (_error != null && _services.isEmpty) {
      return ListView(
        children: [
          EmptyState(message: _error!, icon: Icons.wifi_off, onRetry: _load)
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(Strings.greeting(name),
            style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(Strings.homeHeading,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (_currentOrder != null)
          _CurrentOrderCard(order: _currentOrder!, onTap: _openCurrentOrder),
        OutlinedButton.icon(
          onPressed: _services.isEmpty ? null : () => _openRoutePlanner(null),
          icon: const Icon(Icons.search),
          label: const Text(Strings.searchPrompt),
        ),
        const SizedBox(height: 14),
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
            children: _services
                .map((service) => _ServiceCard(
                      service: service,
                      onTap: () => _openRoutePlanner(service.id),
                    ))
                .toList(),
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
        leading:
            const Icon(Icons.local_shipping_outlined, color: AppColors.ink),
        title: const Text(Strings.menuCurrentOrder,
            style: TextStyle(fontWeight: FontWeight.w700)),
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
              backgroundColor: AppColors.inkDeep,
              child: Icon(
                service.icon == 'package'
                    ? Icons.inventory_2_outlined
                    : Icons.local_shipping_outlined,
                color: AppColors.mint,
              ),
            ),
            const SizedBox(height: 9),
            Text(service.nameMn,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              service.descriptionMn,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
                '${Strings.startingPricePrefix}${formatMoney(service.baseFare)}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
