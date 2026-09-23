import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../l10n/strings.dart';
import '../../models/point.dart';
import '../../models/quote.dart';
import '../../models/service.dart';
import '../../state/app_scope.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/map_sheet_screen.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/route_illustration.dart';
import 'finding_driver_screen.dart';
import 'order_tracking_screen.dart';

const _ulaanbaatarCenter = GeoPoint(lat: 47.9186, lng: 106.9177, address: Strings.currentLocation);

/// Screen 4 in AGENTS.md: pickup/drop-off, vehicle + loader + payment
/// selection, and the server-priced order button.
class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key, required this.initialServiceId, required this.services});

  final String initialServiceId;
  final List<ServiceOption> services;

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  GeoPoint _pickup = _ulaanbaatarCenter;
  GeoPoint? _dropoff;
  List<PlaceSuggestion> _suggestions = const [];
  Quote? _quote;
  late String _selectedServiceId = widget.initialServiceId;
  int _loaders = 0;
  String _paymentMethod = 'qpay';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolvePickup();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _resolvePickup() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)),
      );
      if (!mounted) return;
      setState(() => _pickup = GeoPoint(lat: position.latitude, lng: position.longitude, address: Strings.currentLocation));
    } catch (_) {
      // Keep the Ulaanbaatar-center fallback — matches the web app's
      // silent geolocation catch in CustomerFlow.tsx.
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _dropoff = null;
      _quote = null;
      _suggestions = const [];
    });
    _debounce?.cancel();
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final appState = AppScope.of(context);
      try {
        final results = await appState.customerRepository.searchPlaces(value);
        if (mounted) setState(() => _suggestions = results);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    });
  }

  Future<void> _pickPlace(PlaceSuggestion suggestion) async {
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final place = await appState.customerRepository.place(suggestion.id);
      _searchController.text = place.address;
      setState(() {
        _dropoff = place;
        _suggestions = const [];
      });
      await _requote(appState);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requote(AppState appState) async {
    final dropoff = _dropoff;
    if (dropoff == null) return;
    setState(() => _busy = true);
    try {
      final quote = await appState.customerRepository.quote(pickup: _pickup, dropoff: dropoff, loaders: _loaders);
      if (mounted) setState(() => _quote = quote);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleLoader(bool value) {
    setState(() => _loaders = value ? 1 : 0);
    _requote(AppScope.of(context));
  }

  Future<void> _placeOrder() async {
    final appState = AppScope.of(context);
    final dropoff = _dropoff;
    final quote = _quote;
    final price = quote?.priceFor(_selectedServiceId);
    if (dropoff == null || quote == null || price == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await appState.customerRepository.createOrder(
        pickup: _pickup,
        dropoff: dropoff,
        loaders: _loaders,
        serviceId: _selectedServiceId,
        paymentMethod: _paymentMethod,
        expectedTotal: price.breakdown.total,
        quoteToken: quote.quoteToken,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => order.status == 'assigned'
            ? OrderTrackingScreen(initialOrder: order)
            : FindingDriverScreen(initialOrder: order),
      ));
    } on ApiException catch (e) {
      if (e.code == 'QUOTE_CHANGED') {
        await _requote(appState);
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ServicePrice> get _displayPrices {
    final prices = _quote?.prices;
    if (prices != null) return prices;
    return widget.services
        .map((service) => ServicePrice(
              service: service,
              breakdown: PriceBreakdown(
                total: service.baseFare,
                serviceName: service.nameMn,
                baseFare: service.baseFare,
                distanceFare: 0,
                loaderFare: 0,
                nightSurcharge: 0,
              ),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPrice = _quote?.priceFor(_selectedServiceId);
    return Scaffold(
      body: SafeArea(
        child: MapSheetScreen(
          backgroundHeight: 150,
          background: RouteIllustration(showRoute: _dropoff != null),
          children: [
            Row(
              children: [
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)),
                const SizedBox(width: 4),
                Expanded(child: Text(Strings.chooseVehicle, style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 8),
            _AddressRow(dot: true, child: Text(_pickup.address, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 10),
            _AddressRow(
              dot: false,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(hintText: Strings.dropoffHint, isDense: true),
              ),
            ),
            if (_suggestions.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions
                      .map((s) => ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(s.address),
                            onTap: () => _pickPlace(s),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(Strings.chooseVehicle, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                if (_quote != null)
                  Text('${_quote!.distanceKm.toStringAsFixed(1)} км · ~${_quote!.durationMinutes} мин',
                      style: const TextStyle(color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 10),
            for (final price in _displayPrices) _ServicePriceRow(
                  price: price,
                  selected: price.service.id == _selectedServiceId,
                  onTap: () => setState(() => _selectedServiceId = price.service.id),
                ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _loaders > 0,
              onChanged: _busy ? null : _toggleLoader,
              activeThumbColor: AppColors.ink,
              title: const Text(Strings.addLoader, style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('+${formatMoney(_quote?.loaderRate ?? 25000)}'),
            ),
            Row(
              children: [
                Expanded(
                  child: _PaymentOption(
                    label: Strings.payQpay,
                    selected: _paymentMethod == 'qpay',
                    onTap: () => setState(() => _paymentMethod = 'qpay'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PaymentOption(
                    label: Strings.payCash,
                    selected: _paymentMethod == 'cash',
                    onTap: () => setState(() => _paymentMethod = 'cash'),
                  ),
                ),
              ],
            ),
            ErrorBanner(message: _error),
            const SizedBox(height: 8),
            PrimaryButton(
              accent: true,
              busy: _busy,
              label: Strings.orderButton(selectedPrice?.service.nameMn ?? 'Машин', formatMoney(selectedPrice?.breakdown.total ?? 0)),
              onPressed: (_dropoff == null || _quote == null || selectedPrice == null) ? null : _placeOrder,
            ),
            if (_dropoff == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  Strings.dropoffRequiredHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.dot, required this.child});

  final bool dot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final marker = dot
        ? const CircleAvatar(radius: 5, backgroundColor: AppColors.ink)
        : Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: AppColors.accent, border: Border.all(color: AppColors.ink, width: 2)),
          );
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [marker, const SizedBox(width: 10), Expanded(child: child)]);
  }
}

class _ServicePriceRow extends StatelessWidget {
  const _ServicePriceRow({required this.price, required this.selected, required this.onTap});

  final ServicePrice price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.white,
            border: Border.all(color: selected ? AppColors.ink : AppColors.line, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.ink,
                child: Icon(
                  price.service.icon == 'package' ? Icons.inventory_2_outlined : Icons.local_shipping_outlined,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(price.service.nameMn, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(price.service.descriptionMn, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Text(formatMoney(price.breakdown.total), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppColors.accentSoft : Colors.white,
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line, width: 2),
        ),
        child: Text(label),
      ),
    );
  }
}
