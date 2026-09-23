import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/app_config.dart';
import '../../core/api_exception.dart';
import '../../l10n/errors_mn.dart';
import '../../l10n/strings.dart';
import '../../models/driver_profile.dart';
import '../../models/order.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_view.dart';
import '../login/phone_entry_screen.dart';
import 'driver_active_order_screen.dart';

/// Driver landing screen: registration status, online/offline toggle
/// (`/driver/online` + `/driver/offline`), a periodic location push while
/// online (`/driver/location`, every `AppConfig.driverLocationInterval`),
/// and the current assigned order if any (`/driver/offers`).
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _loading = true;
  String? _error;
  DriverProfile? _profile;
  Order? _activeOrder;
  bool _busyToggle = false;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final appState = AppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await appState.driverRepository.me();
      Order? active;
      if (profile.isApproved) {
        final offers = await appState.driverRepository.offers();
        if (offers.isNotEmpty) active = offers.first;
        if (profile.isOnline) {
          _startLocationLoop();
        } else {
          _stopLocationLoop();
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _activeOrder = active;
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

  void _startLocationLoop() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(AppConfig.driverLocationInterval, (_) => _pushLocation());
    _pushLocation();
  }

  void _stopLocationLoop() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<Position?> _currentPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 6)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _pushLocation() async {
    final appState = AppScope.of(context);
    final position = await _currentPosition();
    if (position == null || !mounted) return;
    try {
      await appState.driverRepository.updateLocation(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // The next tick retries; a single dropped update is not fatal.
    }
  }

  Future<void> _toggleOnline(bool goOnline) async {
    final appState = AppScope.of(context);
    setState(() {
      _busyToggle = true;
      _error = null;
    });
    try {
      if (goOnline) {
        final position = await _currentPosition();
        if (position == null) {
          setState(() => _error = Strings.driverLocationPermissionNeeded);
          return;
        }
        await appState.driverRepository.goOnline(lat: position.latitude, lng: position.longitude);
        _startLocationLoop();
      } else {
        await appState.driverRepository.goOffline();
        _stopLocationLoop();
      }
      final profile = await appState.driverRepository.me();
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyToggle = false);
    }
  }

  Future<void> _openOrder() async {
    final order = _activeOrder;
    if (order == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DriverActiveOrderScreen(initialOrder: order)));
    _load();
  }

  Future<void> _logout() async {
    final appState = AppScope.of(context);
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
      _stopLocationLoop();
      await appState.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const PhoneEntryScreen()), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AchaaGo · Жолооч'),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    final profile = _profile;
    if (profile == null) {
      return ListView(children: [EmptyState(message: _error ?? Strings.emptyServicesTitle, icon: Icons.wifi_off, onRetry: _load)]);
    }
    if (!profile.isApproved) {
      final pending = profile.status == 'pending';
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          Icon(pending ? Icons.hourglass_top : Icons.block, size: 48, color: AppColors.muted),
          const SizedBox(height: 16),
          Text(
            pending ? Strings.driverPendingHeading : Strings.driverSuspendedHeading,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            pending ? Strings.driverPendingBody : Strings.driverSuspendedBody,
            style: const TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: SwitchListTile(
            value: profile.isOnline,
            onChanged: _busyToggle ? null : _toggleOnline,
            activeThumbColor: AppColors.ink,
            title: Text(
              profile.isOnline ? Strings.driverOnline : Strings.driverOffline,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(profile.name ?? ''),
          ),
        ),
        ErrorBanner(message: _error),
        const SizedBox(height: 16),
        if (_activeOrder != null)
          Card(
            color: AppColors.accentSoft,
            child: ListTile(
              onTap: _openOrder,
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(describeStatus(_activeOrder!.status)),
              subtitle: Text('${_activeOrder!.pickup.address} → ${_activeOrder!.dropoff.address}'),
              trailing: const Icon(Icons.chevron_right),
            ),
          )
        else
          EmptyState(
            message: profile.isOnline ? Strings.driverWaitingForOrder : Strings.driverOfflinePrompt,
            icon: Icons.inbox_outlined,
          ),
        if (profile.rating != null) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, color: AppColors.accent, size: 18),
              const SizedBox(width: 6),
              Text('${Strings.driverRatingLabel}: ${profile.rating!.toStringAsFixed(1)}'),
            ],
          ),
        ],
      ],
    );
  }
}
