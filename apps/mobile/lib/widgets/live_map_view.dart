import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/point.dart';
import '../theme/app_theme.dart';

const _ulaanbaatarCenter = LatLng(47.9186, 106.9177);

LatLng _toLatLng(GeoPoint point) => LatLng(point.lat, point.lng);

/// The real map behind the customer and driver route/tracking screens,
/// replacing the decorative RouteIllustration now that a Google Maps API
/// key exists (see apps/mobile/README.md). Mirrors the web app's
/// GoogleMapView.tsx: pickup/dropoff markers, a straight line between them
/// (no Directions API — same scope limit as the web app), and a pulsing
/// circle while a driver is being found. If no key is configured, the
/// native Android Maps SDK itself falls back to blank tiles rather than
/// crashing, so no extra fallback UI is needed here.
class LiveMapView extends StatefulWidget {
  const LiveMapView({
    super.key,
    this.pickup,
    this.dropoff,
    this.driverLocation,
    this.showRoute = false,
    this.pulse = false,
    this.showTruck = false,
    this.myLocationEnabled = false,
  });

  final GeoPoint? pickup;
  final GeoPoint? dropoff;
  final GeoPoint? driverLocation;
  final bool showRoute;
  final bool pulse;
  final bool showTruck;

  /// Shows the OS's own "blue dot" for the device's current position — used
  /// on the driver's own active-order screen, where it's the driver's own
  /// location that matters, not a marker fetched from the server. Needs the
  /// location permission the app already requests for background updates.
  final bool myLocationEnabled;

  @override
  State<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends State<LiveMapView> with SingleTickerProviderStateMixin {
  GoogleMapController? _controller;
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _startPulse();
  }

  @override
  void didUpdateWidget(covariant LiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && _pulseController == null) _startPulse();
    if (!widget.pulse && _pulseController != null) {
      _pulseController!.dispose();
      _pulseController = null;
    }
    if (widget.pickup != oldWidget.pickup || widget.dropoff != oldWidget.dropoff) _fitBounds();
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
    final bounds = LatLngBounds(
      southwest: LatLng(
        pickup.lat < dropoff.lat ? pickup.lat : dropoff.lat,
        pickup.lng < dropoff.lng ? pickup.lng : dropoff.lng,
      ),
      northeast: LatLng(
        pickup.lat > dropoff.lat ? pickup.lat : dropoff.lat,
        pickup.lng > dropoff.lng ? pickup.lng : dropoff.lng,
      ),
    );
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
          zIndex: 1,
        ),
      if (dropoff != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: _toLatLng(dropoff),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          zIndex: 1,
        ),
      if (widget.showTruck && widget.driverLocation != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _toLatLng(widget.driverLocation!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          zIndex: 2,
        ),
    };
    final polylines = <Polyline>{
      if (widget.showRoute && pickup != null && dropoff != null)
        Polyline(
          polylineId: const PolylineId('route'),
          points: [_toLatLng(pickup), _toLatLng(dropoff)],
          color: AppColors.ink,
          width: 4,
        ),
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
    );
  }
}
