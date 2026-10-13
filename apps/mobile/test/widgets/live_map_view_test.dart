import 'package:achaago_mobile/l10n/strings.dart';
import 'package:achaago_mobile/models/point.dart';
import 'package:achaago_mobile/theme/app_theme.dart';
import 'package:achaago_mobile/widgets/live_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const pickup = GeoPoint(lat: 47.9186, lng: 106.9177, address: 'A');
const dropoff = GeoPoint(lat: 47.8832, lng: 106.9157, address: 'B');
const road = [
  LatLng(47.9186, 106.9177),
  LatLng(47.9000, 106.9500),
  LatLng(47.8832, 106.9157),
];

void main() {
  group('drawableRoute', () {
    test('is the server road geometry when a route is asked for', () {
      expect(
        drawableRoute(
            showRoute: true, pickup: pickup, dropoff: dropoff, routePoints: road),
        road,
      );
    });

    test('is never an endpoint-to-endpoint line', () {
      expect(
        drawableRoute(showRoute: true, pickup: pickup, dropoff: dropoff),
        isNull,
      );
    });

    test('is nothing before a route is asked for or an endpoint is set', () {
      expect(
        drawableRoute(
            showRoute: false, pickup: pickup, dropoff: dropoff, routePoints: road),
        isNull,
      );
      expect(
        drawableRoute(showRoute: true, dropoff: dropoff, routePoints: road),
        isNull,
      );
      expect(
        drawableRoute(showRoute: true, pickup: pickup, routePoints: road),
        isNull,
      );
    });
  });

  group('needsRouteNotice', () {
    test('is true when a route is asked for but has no road geometry', () {
      expect(
        needsRouteNotice(showRoute: true, pickup: pickup, dropoff: dropoff),
        isTrue,
      );
    });

    test('is false once the road route is there', () {
      expect(
        needsRouteNotice(
            showRoute: true, pickup: pickup, dropoff: dropoff, routePoints: road),
        isFalse,
      );
    });

    test('is false while no route is asked for or an endpoint is missing', () {
      expect(
        needsRouteNotice(showRoute: false, pickup: pickup, dropoff: dropoff),
        isFalse,
      );
      expect(needsRouteNotice(showRoute: true, pickup: pickup), isFalse);
      expect(needsRouteNotice(showRoute: true, dropoff: dropoff), isFalse);
    });
  });

  group('planCameraUpdate', () {
    test('does nothing without an endpoint', () {
      expect(planCameraUpdate(), isNull);
    });

    test('pans to a lone pickup, so a late GPS fix recentres the map', () {
      expect(
        planCameraUpdate(pickup: pickup)!.toJson(),
        CameraUpdate.newLatLng(const LatLng(47.9186, 106.9177)).toJson(),
      );
    });

    test('pans to a lone drop-off', () {
      expect(
        planCameraUpdate(dropoff: dropoff)!.toJson(),
        CameraUpdate.newLatLng(const LatLng(47.8832, 106.9157)).toJson(),
      );
    });

    test('fits both endpoints', () {
      expect(
        planCameraUpdate(pickup: pickup, dropoff: dropoff)!.toJson(),
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
              southwest: const LatLng(47.8832, 106.9157),
              northeast: const LatLng(47.9186, 106.9177)),
          56,
        ).toJson(),
      );
    });

    test('fits the whole road route, not only its endpoints', () {
      expect(
        planCameraUpdate(pickup: pickup, dropoff: dropoff, routePoints: road)!
            .toJson(),
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
              southwest: const LatLng(47.8832, 106.9157),
              northeast: const LatLng(47.9186, 106.9500)),
          56,
        ).toJson(),
      );
    });

    test('centres, instead of zooming to the maximum, on one place twice', () {
      expect(
        planCameraUpdate(pickup: pickup, dropoff: pickup)!.toJson(),
        CameraUpdate.newLatLngZoom(const LatLng(47.9186, 106.9177), 16).toJson(),
      );
    });
  });

  group('RouteNotice', () {
    Future<void> pump(WidgetTester tester, Widget notice,
        {Brightness brightness = Brightness.light}) {
      return tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(brightness),
        home: Scaffold(body: Center(child: notice)),
      ));
    }

    testWidgets('says no road route was found', (tester) async {
      await pump(tester, const RouteNotice());

      expect(find.text(Strings.roadUnavailable), findsOneWidget);
    });

    testWidgets('has no retry button unless the screen can retry',
        (tester) async {
      await pump(tester, const RouteNotice());

      expect(find.text(Strings.retry), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('retry button asks the screen again (${brightness.name})',
          (tester) async {
        var retries = 0;
        await pump(tester, RouteNotice(onRetry: () => retries++),
            brightness: brightness);

        await tester.tap(find.text(Strings.retry));

        expect(retries, 1);
      });
    }
  });
}
