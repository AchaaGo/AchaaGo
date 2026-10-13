import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api_exception.dart';
import '../../core/formatting.dart';
import '../../core/place_session.dart';
import '../../core/search_revision.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../models/point.dart';
import '../../models/quote.dart';
import '../../models/service.dart';
import '../../state/app_scope.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/live_map_view.dart';
import '../../widgets/map_sheet_screen.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/theme_toggle_button.dart';
import 'finding_driver_screen.dart';
import 'order_tracking_screen.dart';

const _ulaanbaatarCenter =
    GeoPoint(lat: 47.9186, lng: 106.9177, address: Strings.currentLocation);

/// Screen 4 in AGENTS.md: pickup/drop-off, vehicle + loader + payment
/// selection, and the server-priced order button.
///
/// The address, map and quote behaviour follows apps/web's CustomerFlow.tsx:
/// one search field for whichever address is being edited, a Places billing
/// session per typing session, map taps and "current location" resolved to a
/// street address, a quote requested only once both addresses are settled,
/// and a device fix that arrives late never overwrites a pickup the customer
/// chose.
class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({
    super.key,
    required this.initialServiceId,
    required this.services,
    this.initialPickup,
  });

  final String initialServiceId;
  final List<ServiceOption> services;

  /// The device position the home screen already found; when null the
  /// planner asks for the position itself.
  final GeoPoint? initialPickup;

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  final _searchRevision = SearchRevision();
  final _placeSession = PlaceSession();
  bool _searching = false;
  bool _searched = false;

  final _searchFocusNode = FocusNode();

  late GeoPoint _pickup = widget.initialPickup ?? _ulaanbaatarCenter;
  GeoPoint? _dropoff;

  /// Which row the shared search field currently edits.
  String _editingTarget = 'dropoff';

  /// True from the first keystroke of a new pickup search until a place
  /// (or "use current location") is actually chosen — blocks ordering and
  /// requoting against a pickup that's mid-edit, matching the same
  /// `pickupReady` gate apps/web's CustomerFlow.tsx added.
  bool _pickupPending = false;

  /// Set once the customer works on the pickup; from then on a late device
  /// fix must not replace it (web's `pickupTouched`).
  bool _pickupTouched = false;

  List<PlaceSuggestion> _suggestions = const [];
  Quote? _quote;

  /// Numbers each quote request so a slower, older answer never replaces a
  /// newer one (for example when a late device fix triggers a requote).
  int _quoteRevision = 0;
  late String _selectedServiceId = widget.initialServiceId;
  int _loaders = 0;
  String _paymentMethod = 'qpay';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialPickup == null) _resolvePickup();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchRevision.next();
    _quoteRevision++;
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// The device position, or null when location is off, denied or too slow.
  Future<Position?> _devicePosition(
      {Duration timeLimit = const Duration(seconds: 6)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: timeLimit),
      );
    } catch (_) {
      // Keep the Ulaanbaatar-center fallback — matches the web app's
      // silent geolocation catch in CustomerFlow.tsx.
      return null;
    }
  }

  Future<void> _resolvePickup() async {
    final position = await _devicePosition();
    if (position == null || !mounted || _pickupTouched) return;
    setState(() => _pickup = GeoPoint(
        lat: position.latitude,
        lng: position.longitude,
        address: Strings.currentLocation));
    // The customer may already have chosen a destination while the fix was
    // coming in: price the real pickup, not the city-centre placeholder.
    if (_dropoff != null) {
      setState(() => _quote = null);
      await _requote(AppScope.of(context));
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    final revision = _searchRevision.next();
    _debounce?.cancel();
    if (_editingTarget == 'pickup') _pickupTouched = true;
    setState(() {
      _quote = null;
      _suggestions = const [];
      _searching = query.length >= 3;
      _searched = false;
      _error = null;
      if (_editingTarget == 'pickup') {
        _pickupPending = true;
      } else {
        _dropoff = null;
      }
    });
    if (query.length < 3) {
      _placeSession.end();
      return;
    }
    final session = _placeSession.token;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || !_searchRevision.isCurrent(revision)) return;
      final appState = AppScope.of(context);
      try {
        final results = await appState.customerRepository
            .searchPlaces(query, session: session);
        if (mounted && _searchRevision.isCurrent(revision)) {
          setState(() {
            _suggestions = results;
            _searching = false;
            _searched = true;
          });
        }
      } on ApiException catch (e) {
        if (mounted && _searchRevision.isCurrent(revision)) {
          setState(() {
            _error = e.message;
            _searching = false;
            _searched = true;
          });
        }
      }
    });
  }

  /// Switches the shared search field to edit [target], preloading it with
  /// that row's current address (blank for the default GPS pickup) —
  /// mirrors apps/web's `editAddress`.
  void _startEditing(String target) {
    if (_busy) return;
    _debounce?.cancel();
    _searchRevision.next();
    _placeSession.end();
    if (target == 'pickup') _pickupTouched = true;
    setState(() {
      _editingTarget = target;
      _suggestions = const [];
      _searching = false;
      _searched = false;
      _error = null;
      _searchController.text = target == 'pickup'
          ? (_pickupPending || _pickup.address == Strings.currentLocation
              ? ''
              : _pickup.address)
          : (_dropoff?.address ?? '');
    });
    _searchFocusNode.requestFocus();
  }

  /// Settles the edited address on [place] and prices the route.
  Future<void> _applyPlace(GeoPoint place) async {
    setState(() {
      if (_editingTarget == 'pickup') {
        _pickup = place;
        _pickupPending = false;
        _pickupTouched = true;
      } else {
        _dropoff = place;
      }
      _searchController.text = place.address;
      _suggestions = const [];
      _searching = false;
      _searched = false;
      _quote = null;
    });
    await _requote(AppScope.of(context));
  }

  Future<void> _pickPlace(PlaceSuggestion suggestion) async {
    _debounce?.cancel();
    _searchRevision.next();
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The lookup spends the search session's token, which ends the session.
      final place = await appState.customerRepository
          .place(suggestion.id, session: _placeSession.current);
      if (!mounted) return;
      _placeSession.end();
      _searchFocusNode.unfocus();
      await _applyPlace(place);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A tap on the map sets whichever address is being edited, as on the web,
  /// labelled with its street address when the server can find one.
  Future<void> _pickOnMap(LatLng location) async {
    if (_busy) return;
    _debounce?.cancel();
    _searchRevision.next();
    _placeSession.end();
    _searchFocusNode.unfocus();
    final appState = AppScope.of(context);
    setState(() {
      _suggestions = const [];
      _searching = false;
      _searched = false;
      _quote = null;
      _error = null;
      _busy = true;
    });
    try {
      final address = await appState.customerRepository
          .reverseGeocode(location.latitude, location.longitude);
      if (!mounted) return;
      await _applyPlace(GeoPoint(
        lat: location.latitude,
        lng: location.longitude,
        address: address ?? Strings.mapSelectedPoint,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocationForPickup() async {
    if (_busy) return;
    _debounce?.cancel();
    _searchRevision.next();
    _placeSession.end();
    final appState = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _quote = null;
      _suggestions = const [];
      _searching = false;
      _searched = false;
    });
    try {
      final position =
          await _devicePosition(timeLimit: const Duration(seconds: 10));
      if (!mounted) return;
      if (position == null) {
        setState(() => _error = Strings.locationFailed);
        return;
      }
      final address = await appState.customerRepository
          .reverseGeocode(position.latitude, position.longitude);
      if (!mounted) return;
      await _applyPlace(GeoPoint(
        lat: position.latitude,
        lng: position.longitude,
        address: address ?? Strings.currentLocation,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prices the settled route. A failure clears the quote (the order button
  /// stays off and "retry" appears) rather than leaving a stale price.
  Future<void> _requote(AppState appState) async {
    final dropoff = _dropoff;
    if (dropoff == null || _pickupPending) return;
    final pickup = _pickup;
    final revision = ++_quoteRevision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quote = await appState.customerRepository
          .quote(pickup: pickup, dropoff: dropoff, loaders: _loaders);
      if (mounted && revision == _quoteRevision) setState(() => _quote = quote);
    } on ApiException catch (e) {
      if (mounted && revision == _quoteRevision) {
        setState(() {
          _quote = null;
          _error = e.message;
        });
      }
    } finally {
      if (mounted && revision == _quoteRevision) setState(() => _busy = false);
    }
  }

  void _toggleLoader(bool value) {
    setState(() => _loaders = value ? 1 : 0);
    _requote(AppScope.of(context));
  }

  void _openOrder(Order order) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => order.status == 'assigned'
          ? OrderTrackingScreen(initialOrder: order)
          : FindingDriverScreen(initialOrder: order),
    ));
  }

  Future<void> _placeOrder() async {
    final appState = AppScope.of(context);
    final dropoff = _dropoff;
    final quote = _quote;
    final price = quote?.priceFor(_selectedServiceId);
    if (_pickupPending || dropoff == null || quote == null || price == null) {
      return;
    }
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
      _openOrder(order);
    } on ApiException catch (e) {
      if (e.code == 'ACTIVE_ORDER_EXISTS') {
        // Already ordered (another device, or a lost response): go to that
        // order, as the web does, instead of leaving the customer stuck here.
        final active = await _activeOrder(appState);
        if (active != null && mounted) {
          _openOrder(active);
          return;
        }
      }
      if (e.code == 'QUOTE_CHANGED') {
        await _requote(appState);
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Order?> _activeOrder(AppState appState) async {
    try {
      final orders = await appState.customerRepository.myOrders();
      for (final order in orders) {
        if (order.isActive) return order;
      }
    } catch (_) {
      // Looking up the current order is a convenience; the error message
      // already tells the customer they have one.
    }
    return null;
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
    final p = context.palette;
    final selectedPrice = _quote?.priceFor(_selectedServiceId);
    final canRetryQuote =
        !_pickupPending && _dropoff != null && _quote == null && !_busy;
    return Scaffold(
      body: SafeArea(
        child: MapSheetScreen(
          backgroundHeight:
              (MediaQuery.sizeOf(context).height * 0.32).clamp(220.0, 320.0),
          background: LiveMapView(
            pickup: _pickupPending ? null : _pickup,
            dropoff: _dropoff,
            routePolyline: _quote?.polyline,
            // Only once priced, like the web: an unpriced pair has no route.
            showRoute: !_pickupPending && _dropoff != null && _quote != null,
            onPick: _pickOnMap,
            onRetryRoute:
                _busy ? null : () => _requote(AppScope.of(context)),
          ),
          header: _buildRouteHeader(),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(Strings.chooseVehicle,
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                if (_quote != null)
                  Text(
                      '${_quote!.distanceKm.toStringAsFixed(1)} км · ~${_quote!.durationMinutes} мин',
                      style: TextStyle(color: p.muted)),
              ],
            ),
            const SizedBox(height: 10),
            for (final price in _displayPrices)
              _ServicePriceRow(
                price: price,
                selected: price.service.id == _selectedServiceId,
                onTap: () =>
                    setState(() => _selectedServiceId = price.service.id),
              ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _loaders > 0,
              onChanged: _busy ? null : _toggleLoader,
              activeThumbColor: p.onBrand,
              title: const Text(Strings.addLoader,
                  style: TextStyle(fontWeight: FontWeight.w700)),
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
            if (canRetryQuote)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  onPressed: () => _requote(AppScope.of(context)),
                  child: const Text(Strings.retryQuote),
                ),
              ),
            PrimaryButton(
              accent: true,
              busy: _busy,
              label: Strings.orderButton(
                  selectedPrice?.service.nameMn ?? 'Машин',
                  formatMoney(selectedPrice?.breakdown.total ?? 0)),
              onPressed: (_pickupPending ||
                      _dropoff == null ||
                      _quote == null ||
                      selectedPrice == null)
                  ? null
                  : _placeOrder,
            ),
            if (_pickupPending || _dropoff == null || (_quote == null && !_busy))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _pickupPending
                      ? Strings.needsPickup
                      : _dropoff == null
                          ? Strings.dropoffRequiredHint
                          : Strings.needsQuote,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteHeader() {
    final editingPickup = _editingTarget == 'pickup';
    final queryLength = _searchController.text.trim().length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      color: context.palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Буцах',
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(Strings.searchPrompt,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(Strings.routeSearchHelp,
                      style: TextStyle(
                          color: context.palette.muted, fontSize: 13)),
                ])),
            const ThemeToggleButton(),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _AddressTab(
                    label: Strings.pickupTab,
                    selected: editingPickup,
                    onTap: () => _startEditing('pickup'))),
            const SizedBox(width: 10),
            Expanded(
                child: _AddressTab(
                    label: Strings.dropoffTab,
                    selected: !editingPickup,
                    onTap: () => _startEditing('dropoff'))),
          ]),
          const SizedBox(height: 12),
          _buildAddressField(
            target: _editingTarget,
            dot: editingPickup,
            hint: editingPickup
                ? Strings.searchPickup
                : Strings.searchDestination,
          ),
          if (editingPickup)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _useCurrentLocationForPickup,
                child: const Text(Strings.useCurrentLocation),
              ),
            ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text(Strings.searchPlacesLoading),
              ]),
            ),
          if (!_searching && queryLength > 0 && queryLength < 3)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(Strings.searchPlacesShort,
                  style: TextStyle(color: context.palette.muted)),
            ),
          if (_suggestions.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(suggestion.address),
                      onTap: _busy ? null : () => _pickPlace(suggestion),
                    );
                  },
                ),
              ),
            ),
          if (_searched &&
              !_searching &&
              _suggestions.isEmpty &&
              _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(Strings.searchPlacesEmpty,
                  style: TextStyle(color: context.palette.muted)),
            ),
        ],
      ),
    );
  }

  Widget _buildAddressField(
      {required String target, required bool dot, required String hint}) {
    if (_editingTarget == target) {
      return _AddressRow(
        dot: dot,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          enabled: !_busy,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Хаяг арилгах',
                    onPressed: _busy
                        ? null
                        : () {
                            _searchController.clear();
                            _onSearchChanged('');
                            _searchFocusNode.requestFocus();
                          },
                  ),
          ),
        ),
      );
    }
    final address = target == 'pickup' ? _pickup.address : _dropoff?.address;
    return _AddressRow(
      dot: dot,
      child: InkWell(
        onTap: () => _startEditing(target),
        child: Row(
          children: [
            Expanded(
              child: Text(
                address ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: address == null ? context.palette.muted : null),
              ),
            ),
            const SizedBox(width: 8),
            Text(Strings.changeAddress,
                style: TextStyle(
                    color: context.palette.ink,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
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
    final p = context.palette;
    final marker = dot
        ? CircleAvatar(radius: 5, backgroundColor: p.ink)
        : Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: p.accent, border: Border.all(color: p.ink, width: 2)),
          );
    return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [marker, const SizedBox(width: 10), Expanded(child: child)]);
  }
}

class _AddressTab extends StatelessWidget {
  const _AddressTab(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: selected ? p.accentSoft : p.surface,
        side: BorderSide(
            color: selected ? p.accent : p.line, width: selected ? 2 : 1),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _ServicePriceRow extends StatelessWidget {
  const _ServicePriceRow(
      {required this.price, required this.selected, required this.onTap});

  final ServicePrice price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? p.accentSoft : p.surface,
            border: Border.all(
                color: selected ? p.accent : p.line, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: p.inkDeep,
                child: Icon(
                  price.service.icon == 'package'
                      ? Icons.inventory_2_outlined
                      : Icons.local_shipping_outlined,
                  color: p.mint,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(price.service.nameMn,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(price.service.descriptionMn,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ),
              ),
              Text(formatMoney(price.breakdown.total),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? p.accentSoft : p.surface,
          side: BorderSide(
              color: selected ? p.accent : p.line, width: 2),
        ),
        child: Text(label),
      ),
    );
  }
}
