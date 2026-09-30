import 'dart:convert';

import 'package:achaago_mobile/core/api_client.dart';
import 'package:achaago_mobile/core/session_store.dart';
import 'package:achaago_mobile/l10n/errors_mn.dart';
import 'package:achaago_mobile/l10n/strings.dart';
import 'package:achaago_mobile/screens/login/otp_verify_screen.dart';
import 'package:achaago_mobile/state/app_scope.dart';
import 'package:achaago_mobile/state/app_state.dart';
import 'package:achaago_mobile/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final role in ['customer', 'driver']) {
    for (final failFirstLoad in [false, true]) {
      testWidgets(
        '00 login opens $role home${failFirstLoad ? ' after retry' : ''}',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          FlutterSecureStorage.setMockInitialValues({});
          final store = SessionStore();
          var homeLoads = 0;
          final requests = <String>[];
          final client = MockClient((request) async {
            final path = request.url.path;
            requests.add(path);
            if (path.endsWith('/auth/otp/verify')) {
              expect(jsonDecode(request.body), {
                'phone': '+97699112233',
                'code': '00',
              });
              return http.Response(
                jsonEncode({
                  'access_token': 'test-access',
                  'refresh_token': 'test-refresh',
                  'user': {
                    'id': 'user-1',
                    'phone': '+97699112233',
                    'role': role,
                  },
                }),
                200,
              );
            }
            expect(request.headers['Authorization'], 'Bearer test-access');
            if (path.endsWith('/services') || path.endsWith('/driver/me')) {
              homeLoads++;
              if (failFirstLoad && homeLoads == 1) {
                return http.Response('{"detail":"SERVICE_UNAVAILABLE"}', 503);
              }
              if (role == 'driver') {
                return http.Response(
                  jsonEncode({
                    'id': 'driver-1',
                    'status': 'approved',
                    'is_online': false,
                  }),
                  200,
                );
              }
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode([
                    {
                      'id': 'service-1',
                      'code': 'porter',
                      'name_mn': 'Портер',
                      'description_mn': 'Ачаа тээвэр',
                      'base_fare': 30000,
                      'per_km_rate': 2000,
                    },
                  ]),
                ),
                200,
              );
            }
            if (path.endsWith('/orders') || path.endsWith('/driver/offers')) {
              return http.Response('[]', 200);
            }
            fail('Unexpected request: $path');
          });
          final state = AppState(
            api: ApiClient(client: client, sessionStore: store),
            sessionStore: store,
          );
          addTearDown(client.close);
          addTearDown(state.dispose);
          await tester.pumpWidget(
            AppScope(
              state: state,
              child: const MaterialApp(
                home: OtpVerifyScreen(localPhone: '99112233'),
              ),
            ),
          );
          await tester.enterText(find.byType(TextField), '00');
          await tester.pump();
          await tester.tap(find.text(Strings.otpVerify));
          // A bounded settle turns an endless loading spinner into a test failure.
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
          expect(tester.takeException(), isNull);
          expect(state.status, AuthStatus.signedIn);
          expect(find.byType(OtpVerifyScreen), findsNothing);
          expect(find.byType(LoadingView), findsNothing);
          if (failFirstLoad) {
            expect(
              find.text(describeError('SERVICE_UNAVAILABLE')),
              findsOneWidget,
            );
            await tester.tap(find.text(Strings.retry));
            await tester.pumpAndSettle();
          }
          expect(
            find.text(
              role == 'customer'
                  ? Strings.homeHeading
                  : Strings.driverOfflinePrompt,
            ),
            findsOneWidget,
          );
          expect(homeLoads, failFirstLoad ? 2 : 1);
          expect(
            requests,
            contains(role == 'customer' ? '/api/orders' : '/api/driver/offers'),
          );
          expect(tester.takeException(), isNull);
          // Remove the tree before disposing its shared state.
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
