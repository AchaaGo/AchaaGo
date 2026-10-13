import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/route_polyline.dart';
import '../l10n/strings.dart';
import '../models/point.dart';
import '../theme/app_theme.dart';
import '../theme/map_style.dart';

const _ulaanbaatarCenter = LatLng(47.9186, 106.9177);

/// The route line is the same blue in both themes, as on the web map: the
/// white casing keeps it readable on the dark map too.
const _routeColor = brandBlue;

/// Bounds smaller than this (about 40 m) are one place seen twice: centre on
/// it instead of zooming to the map's maximum.
const _minBoundsSpan = 0.0004;

LatLng _toLatLng(GeoPoint point) => LatLng(point.lat, point.lng);

bool _samePoint(GeoPoint? a, GeoPoint? b) =>
    a == null || b == null ? a == b : a.lat == b.lat && a.lng == b.lng;

/// The road route to draw, or null. Only the server's decoded road geometry
/// is ever drawn — never a straight line between the endpoints.
List<LatLng>? drawableRoute({
  required bool showRoute,
  GeoPoint? pickup,
  GeoPoint? dropoff,
  List<LatLng>? routePoints,
}) =>
    showRoute && pickup != null && dropoff != null ? routePoints : null;

/// A route was asked for between two endpoints but there is no road
/// geometry for it: show the notice instead of a line.
bool needsRouteNotice({
  required bool showRoute,
  GeoPoint? pickup,
  GeoPoint? dropoff,
  List<LatLng>? routePoints,
}) =>
    showRoute &&
    pickup != null &&
    dropoff != null &&
    drawableRoute(
            showRoute: showRoute,
            pickup: pickup,
            dropoff: dropoff,
            routePoints: routePoints) ==
        null;

/// What the camera should do for the current endpoints, or null for nothing.
/// Both endpoints: fit them and the road route ([routePoints], once there is
/// one). One endpoint: pan to it, so a late GPS fix recentres the map. Two
/// endpoints that are the same place: centre on them rather than zooming to
/// the map's maximum.
CameraUpdate? planCameraUpdate({
  GeoPoint? pickup,
  GeoPoint? dropoff,
  List<LatLng>? routePoints,
}) {
  if (pickup == null && dropoff == null) return null;
  if (pickup == null || dropoff == null) {
    return CameraUpdate.newLatLng(_toLatLng((pickup ?? dropoff)!));
  }
  final points = [_toLatLng(pickup), _toLatLng(dropoff), ...?routePoints];
  var south = points.first.latitude, north = points.first.latitude;
  var west = points.first.longitude, east = points.first.longitude;
  for (final point in points.skip(1)) {
    if (point.latitude < south) south = point.latitude;
    if (point.latitude > north) north = point.latitude;
    if (point.longitude < west) west = point.longitude;
    if (point.longitude > east) east = point.longitude;
  }
  if (north - south < _minBoundsSpan && east - west < _minBoundsSpan) {
    return CameraUpdate.newLatLngZoom(
        LatLng((south + north) / 2, (west + east) / 2), 16);
  }
  return CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(south, west), northeast: LatLng(north, east)),
      56);
}

/// The real map behind the customer and driver route/tracking screens.
/// Mirrors the web app's GoogleMapView.tsx: pickup/dropoff markers, the
/// server's own road-following route when [routePolyline] decodes (the same
/// encoded polyline the backend returns from `/quotes` and orders — see
/// apps/mobile/lib/core/route_polyline.dart), and a pulsing circle while a
/// driver is being found.
///
/// Like the web map it never substitutes an endpoint-to-endpoint line for a
/// missing road route (that is what made routes look "linear"): when a
/// route is requested but the server sent none — for instance under
/// `MAPS_PROVIDER=demo` — it shows a notice, with a retry button when the
/// screen can ask for the route again ([onRetryRoute]). If no Maps key is
/// configured, the native SDK falls back to blank tiles rather than
/// crashing, so no extra fallback UI is needed here.
class LiveMapView extends StatefulWidget {
  const LiveMapView({
    super.key,
    this.pickup,
    this.dropoff,
    this.driverLocation,
    this.routePolyline,
    this.showRoute = false,
    this.pulse = false,
    this.showTruck = false,
    this.myLocationEnabled = false,
    this.onPick,
    this.onRetryRoute,
  });

  final GeoPoint? pickup;
  final GeoPoint? dropoff;
  final GeoPoint? driverLocation;

  /// Google encoded polyline from `Quote.polyline` / `Order.polyline`.
  final String? routePolyline;
  final bool showRoute;
  final bool pulse;
  final bool showTruck;

  /// Shows the OS's own "blue dot" for the device's current position — used
  /// on the driver's own active-order screen, where it's the driver's own
  /// location that matters, not a marker fetched from the server. Needs the
  /// location permission the app already requests for background updates.
  final bool myLocationEnabled;

  /// Allows the customer to choose a drop-off directly on the map.
  final ValueChanged<LatLng>? onPick;

  /// Offered next to the "no road route" notice, for screens that can ask the
  /// server for the route again (the quote screen requotes).
  final VoidCallback? onRetryRoute;

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _controller;
  AnimationController? _pulseController;
  List<LatLng>? _routePoints;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropoffIcon;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _startPulse();
    _routePoints = decodeRoutePolyline(widget.routePolyline);
    _loadMarkerIcons();
  }

  // Match the web's blue pickup dot and orange destination square instead
  // of the SDK's oversized teardrop pins. Draw locally; no asset/network load.
  Future<void> _loadMarkerIcons() async {
    final icons = await Future.wait([_markerIcon(false), _markerIcon(true)]);
    if (!mounted) return;
    setState(() {
      _pickupIcon = icons[0];
      _dropoffIcon = icons[1];
    });
  }

  Future<BitmapDescriptor> _markerIcon(bool destination) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = destination ? brandBlue : Colors.white;
    if (destination) {
      canvas.drawRect(const Rect.fromLTWH(9, 9, 54, 54), paint);
      canvas.drawRect(const Rect.fromLTWH(18, 18, 36, 36),
          paint..color = destinationOrange);
    } else {
      canvas.drawCircle(const Offset(36, 36), 30, paint);
      canvas.drawCircle(const Offset(36, 36), 21, paint..color = brandBlue);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        imagePixelRatio: 3, width: 24, height: 24);
  }

  @override
  void didUpdateWidget(covariant LiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && _pulseController == null) _startPulse();
    if (!widget.pulse && _pulseController != null) {
      _pulseController!.dispose();
      _pulseController = null;
    }
    if (widget.routePolyline != oldWidget.routePolyline) {
      _routePoints = decodeRoutePolyline(widget.routePolyline);
    }
    // Compared by coordinates: a tracking screen rebuilds its order (and so
    // its points) on every status update, and that must not move the camera.
    if (!_samePoint(widget.pickup, oldWidget.pickup) ||
        !_samePoint(widget.dropoff, oldWidget.dropoff) ||
        widget.routePolyline != oldWidget.routePolyline ||
        widget.showRoute != oldWidget.showRoute) {
      _moveCamera();
    }
  }

  void _startPulse() {
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _moveCamera() async {
    final controller = _controller;
    if (controller == null) return;
    final update = planCameraUpdate(
      pickup: widget.pickup,
      dropoff: widget.dropoff,
      routePoints: drawableRoute(
          showRoute: widget.showRoute,
          pickup: widget.pickup,
          dropoff: widget.dropoff,
          routePoints: _routePoints),
    );
    if (update == null) return;
    try {
      await controller.animateCamera(update);
    } catch (_) {
      // The map refuses camera moves until it has a size; the next update
      // (or the map's own creation callback) tries again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickup;
    final dropoff = widget.dropoff;
    final markers = <Marker>{
      if (pickup != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: _toLatLng(pickup),
          icon: _pickupIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
        ),
      if (dropoff != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: _toLatLng(dropoff),
          icon: _dropoffIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
        ),
      if (widget.showTruck && widget.driverLocation != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _toLatLng(widget.driverLocation!),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          zIndexInt: 2,
        ),
    };
    final routePoints = drawableRoute(
        showRoute: widget.showRoute,
        pickup: pickup,
        dropoff: dropoff,
        routePoints: _routePoints);
    final polylines = <Polyline>{
      if (routePoints != null) ...[
        Polyline(
          polylineId: const PolylineId('route-outline'),
          points: routePoints,
          color: Colors.white,
          width: 9,
        ),
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: _routeColor,
          width: 5,
        ),
      ],
    };
    final pulseFraction = _pulseController?.value ?? 0;
    final circles = <Circle>{
      if (widget.pulse && pickup != null)
        Circle(
          circleId: const CircleId('pulse'),
          center: _toLatLng(pickup),
          radius: 40 + pulseFraction * 60,
          fillColor: context.palette.accent
              .withValues(alpha: 0.35 * (1 - pulseFraction)),
          strokeWidth: 0,
        ),
    };
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            // Keep native pan/zoom responsive inside the booking scroll view.
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer()),
            },
            initialCameraPosition: CameraPosition(
                target: pickup != null ? _toLatLng(pickup) : _ulaanbaatarCenter,
                zoom: 14),
            style: Theme.of(context).brightness == Brightness.dark
                ? darkMapStyle
                : lightMapStyle,
            onMapCreated: (controller) {
              _controller = controller;
              _moveCamera();
            },
            markers: markers,
            polylines: polylines,
            circles: circles,
            myLocationEnabled: widget.myLocationEnabled,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onTap: widget.onPick,
          ),
        ),
        if (needsRouteNotice(
            showRoute: widget.showRoute,
            pickup: pickup,
            dropoff: dropoff,
            routePoints: _routePoints))
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: RouteNotice(onRetry: widget.onRetryRoute),
          ),
      ],
    );
  }
}

/// "No road route" status over the map: the web's `map-route-status`.
class RouteNotice extends StatelessWidget {
  const RouteNotice({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 12, vertical: onRetry == null ? 10 : 2),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.line),
          boxShadow: const [
            BoxShadow(
                color: sheetShadowColor, blurRadius: 20, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                Strings.roadUnavailable,
                style: TextStyle(
                    color: p.ink, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text(Strings.retry)),
          ],
        ),
      ),
    );
  }
}
