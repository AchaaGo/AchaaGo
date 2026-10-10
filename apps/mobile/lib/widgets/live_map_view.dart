import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/route_polyline.dart';
import '../models/point.dart';
import '../theme/app_theme.dart';

const _ulaanbaatarCenter = LatLng(47.9186, 106.9177);

LatLng _toLatLng(GeoPoint point) => LatLng(point.lat, point.lng);

/// The real map behind the customer and driver route/tracking screens,
/// replacing the decorative RouteIllustration now that a Google Maps API
/// key exists (see apps/mobile/README.md). Mirrors the web app's
/// GoogleMapView.tsx: pickup/dropoff markers, the server's own road-following
/// route when [routePolyline] decodes (same encoded polyline the backend
/// already returns from `/quotes` and orders — see
/// apps/mobile/lib/core/route_polyline.dart), falling back to a straight
/// line otherwise, and a pulsing circle while a driver is being found. If no
/// key is configured, the native Android Maps SDK itself falls back to
/// blank tiles rather than crashing, so no extra fallback UI is needed here.
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

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> with SingleTickerProviderStateMixin {
  GoogleMapController? _controller;
  AnimationController? _pulseController;
  List<LatLng>? _routePoints;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _startPulse();
    _routePoints = decodeRoutePolyline(widget.routePolyline);
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
    if (widget.pickup != oldWidget.pickup || widget.dropoff != oldWidget.dropoff || widget.routePolyline != oldWidget.routePolyline) {
      _fitBounds();
    }
  }

  void _startPulse() {
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _fitBounds() async {
    final controller = _controller;
    final pickup = widget.pickup;
    final dropoff = widget.dropoff;
    if (controller == null || pickup == null || dropoff == null) return;
    final points = [_toLatLng(pickup), _toLatLng(dropoff), if (widget.showRoute) ...?_routePoints];
    var south = points.first.latitude, north = points.first.latitude;
    var west = points.first.longitude, east = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }
    final bounds = LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east));
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndexInt: 1,
        ),
      if (dropoff != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: _toLatLng(dropoff),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          zIndexInt: 1,
        ),
      if (widget.showTruck && widget.driverLocation != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _toLatLng(widget.driverLocation!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          zIndexInt: 2,
        ),
    };
    final routePoints = _routePoints;
    final polylines = <Polyline>{
      if (widget.showRoute && pickup != null && dropoff != null) ...[
        Polyline(
          polylineId: const PolylineId('route-outline'),
          points: routePoints ?? [_toLatLng(pickup), _toLatLng(dropoff)],
          color: Colors.white,
          width: 9,
        ),
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints ?? [_toLatLng(pickup), _toLatLng(dropoff)],
          color: AppColors.ink,
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
          fillColor: AppColors.accent.withValues(alpha: 0.35 * (1 - pulseFraction)),
          strokeWidth: 0,
        ),
    };
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: pickup != null ? _toLatLng(pickup) : _ulaanbaatarCenter, zoom: 14),
      onMapCreated: (controller) {
        _controller = controller;
        _fitBounds();
      },
      markers: markers,
      polylines: polylines,
      circles: circles,
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      onTap: widget.onPick,
    );
  }
}
