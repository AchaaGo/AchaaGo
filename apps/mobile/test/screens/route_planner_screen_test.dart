import 'dart:async';
import 'dart:convert';

import 'package:achaago_mobile/core/api_client.dart';
import 'package:achaago_mobile/l10n/strings.dart';
import 'package:achaago_mobile/models/point.dart';
import 'package:achaago_mobile/models/service.dart';
import 'package:achaago_mobile/screens/customer/route_planner_screen.dart';
import 'package:achaago_mobile/state/app_scope.dart';
import 'package:achaago_mobile/state/app_state.dart';
import 'package:achaago_mobile/theme/app_theme.dart';
import 'package:achaago_mobile/widgets/live_map_view.dart';
import 'package:achaago_mobile/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Stub only the native view. Real production widgets and their HTTP calls,
// debounce, selection, pricing and stale-response guards run unchanged.
class TestMapsPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const ColoredBox(color: Color(0xFF182130));
}

const pickup = GeoPoint(lat: 47.9186, lng: 106.9177, address: 'Авах хаяг');
const destination = 'Шангри-Ла, Улаанбаатар';
const service = ServiceOption(
    id: 'porter',
    code: 'porter',
    nameMn: 'Портер',
    descriptionMn: 'Ачааны машин · 1 тн хүртэл',
    icon: 'truck',
    baseFare: 30000,
    perKmRate: 2000,
    isActive: true,
    sortOrder: 1);
const polyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

http.Response json(Object value, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), status,
        headers: {'content-type': 'application/json'});

Map<String, Object> quoteJson({int total = 39000}) => {
      'distance_km': 1.31,
      'duration_minutes': 5,
      'loader_rate': 25000,
      'quote_token': 'signed-quote',
      'polyline': polyline,
      'approximate': false,
      'prices': [
        {
          'service': {
            'id': 'porter',
            'code': 'porter',
            'name_mn': 'Портер',
            'description_mn': service.descriptionMn,
            'base_fare': 30000,
            'per_km_rate': 2000
          },
          'breakdown': {'total': total}
        }
      ],
    };

Future<void> showPlanner(
    WidgetTester tester, Future<http.Response> Function(http.Request) handler,
    {Brightness brightness = Brightness.dark}) async {
  final app = AppState(api: ApiClient(client: MockClient(handler)));
  addTearDown(app.dispose);
  await tester.pumpWidget(AppScope(
      state: app,
      child: MaterialApp(
        theme: buildAppTheme(brightness),
        home: const RoutePlannerScreen(
            initialServiceId: 'porter',
            services: [service],
            initialPickup: pickup),
      )));
  await tester.pump();
}

final searchField = find.byKey(const ValueKey('address-search'));

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(searchField, query);
  await tester.pump(const Duration(milliseconds: 301));
  await tester.pump();
  await tester.pump();
}

void main() {
  late GoogleMapsFlutterPlatform originalPlatform;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    originalPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = TestMapsPlatform();
  });
  tearDown(() => GoogleMapsFlutterPlatform.instance = originalPlatform);

  testWidgets('typing debounces and ignores an old response after clearing',
      (tester) async {
    final pending = Completer<http.Response>();
    final requests = <http.Request>[];
    await showPlanner(tester, (request) {
      requests.add(request);
      return pending.future;
    });
    await tester.enterText(searchField, 'Ша');
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, isEmpty);
    await tester.enterText(searchField, 'Шанг');
    await tester.pump(const Duration(milliseconds: 299));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(requests.single.url.queryParameters['q'], 'Шанг');
    await tester.enterText(searchField, '');
    pending.complete(json([
      {'id': 'old', 'address': destination}
    ]));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('suggestion-old')), findsNothing);
  });

  testWidgets('selection gets place details and the signed backend route/price',
      (tester) async {
    final requests = <http.Request>[];
    await showPlanner(tester, (request) async {
      requests.add(request);
      if (request.url.path.endsWith('/places')) {
        return json([
          {'id': 'google-place', 'address': destination}
        ]);
      }
      if (request.url.path.endsWith('/places/google-place')) {
        return json({'lat': 47.91, 'lng': 106.92, 'address': destination});
      }
      return json(quoteJson());
    });
    await search(tester, 'Шанг');
    await tester.tap(find.byKey(const ValueKey('suggestion-google-place')));
    await tester.pumpAndSettle();
    expect(requests[0].url.queryParameters['session'], isNotEmpty);
    expect(requests[1].url.queryParameters['session'],
        requests[0].url.queryParameters['session']);
    final payload = jsonDecode(requests[2].body) as Map;
    expect(requests[2].url.path, endsWith('/quotes'));
    expect(payload['pickup'], pickup.toJson());
    expect(payload['dropoff']['address'], destination);
    expect(find.byKey(const ValueKey('selected-destination')), findsOneWidget);
    expect(find.text('1.31 км · ~5 мин'), findsOneWidget);
    final map = tester.widget<LiveMapView>(find.byType(LiveMapView));
    expect(map.routePolyline, polyline);
    expect(map.showRoute, isTrue);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a late quote cannot restore a cleared destination or enable ordering',
      (tester) async {
    final pendingQuote = Completer<http.Response>();
    var quotes = 0;
    await showPlanner(tester, (request) async {
      if (request.url.path.endsWith('/geocode')) {
        return json({'address': destination});
      }
      if (request.url.path.endsWith('/quotes')) {
        return ++quotes == 1 ? json(quoteJson()) : pendingQuote.future;
      }
      return json([]);
    });
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    map.onTap!(const LatLng(47.91, 106.92));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump();
    expect(quotes, 2);
    await tester.ensureVisible(searchField);
    await tester.enterText(searchField, '');
    pendingQuote.complete(json(quoteJson(total: 64000)));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull);
    expect(tester.widget<LiveMapView>(find.byType(LiveMapView)).showRoute,
        isFalse);
    expect(find.byKey(const ValueKey('selected-destination')), findsNothing);
  });

  testWidgets('ordering sends the signed quote and refreshes an expired quote',
      (tester) async {
    http.Request? orderRequest;
    var quotes = 0;
    await showPlanner(tester, (request) async {
      if (request.url.path.endsWith('/geocode')) {
        return json({'address': destination});
      }
      if (request.url.path.endsWith('/orders')) {
        orderRequest = request;
        return json({'detail': 'QUOTE_CHANGED'}, 409);
      }
      quotes++;
      return json(quoteJson());
    });
    tester
        .widget<GoogleMap>(find.byType(GoogleMap))
        .onTap!(const LatLng(47.91, 106.92));
    await tester.pumpAndSettle();
    final button = find.byType(PrimaryButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final body = jsonDecode(orderRequest!.body) as Map;
    expect(body['expected_total'], 39000);
    expect(body['quote_token'], 'signed-quote');
    expect(body['service_id'], 'porter');
    expect(body['payment_method'], 'qpay');
    expect(orderRequest!.headers['Idempotency-Key'], isNotEmpty);
    expect(quotes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map selection resolves the edited pickup and requotes with it',
      (tester) async {
    final requests = <http.Request>[];
    await showPlanner(tester, (request) async {
      requests.add(request);
      if (request.url.path.endsWith('/geocode')) {
        return json({'address': destination});
      }
      return json(quoteJson());
    });
    tester
        .widget<GoogleMap>(find.byType(GoogleMap))
        .onTap!(const LatLng(47.91, 106.92));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Strings.pickupTab));
    await tester.pump();
    tester
        .widget<GoogleMap>(find.byType(GoogleMap))
        .onTap!(const LatLng(47.92, 106.93));
    await tester.pumpAndSettle();
    final body = jsonDecode(requests.last.body) as Map;
    expect(body['pickup']['lat'], 47.92);
    expect(body['pickup']['lng'], 106.93);
    expect(body['dropoff']['lat'], 47.91);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed pricing leaves ordering disabled with a retry',
      (tester) async {
    await showPlanner(tester, (request) async {
      if (request.url.path.endsWith('/geocode')) {
        return json({'address': destination});
      }
      return json({'detail': 'ROUTE_NOT_FOUND'}, 422);
    });
    tester
        .widget<GoogleMap>(find.byType(GoogleMap))
        .onTap!(const LatLng(47.91, 106.92));
    await tester.pumpAndSettle();
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull);
    expect(find.text(Strings.retryQuote), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('booking fits a small screen and keyboard (${brightness.name})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await showPlanner(tester, (_) async => json([]), brightness: brightness);
      await search(tester, 'Шанг');
      expect(tester.takeException(), isNull);
      expect(find.text(Strings.searchPlacesEmpty), findsOneWidget);
    });
  }
}
