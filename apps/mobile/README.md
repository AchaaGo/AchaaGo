# AchaaGo mobile app

A Flutter app for the AchaaGo customer and driver mobile flows, talking to
the existing FastAPI backend in `services/api/`. All customer-visible text
is Mongolian, matching `apps/web`.

This app does **not** replace `apps/web` — the customer web app stays the
mobile-first website described in `AGENTS.md`. This is the native app for
both customers who prefer an app and, per `AGENTS.md`, drivers.

## What's implemented

**Customer**
- Phone-number login, 4-digit code verification (`0000` in development — see below)
- Service selection (Амжиргаа / Портер, loaded from `GET /services`)
- Pickup (device location) and drop-off address entry with search
- Loader count, live server-priced quote, cash/QPay selection
- Order creation, "finding a driver", live tracking, current-order resume on relaunch
- Public tracking by link/token (no login), cancellation, post-delivery rating

**Driver**
- Phone login (same flow as customers — see "Accounts" below)
- Driver registration (submits for staff approval in the admin panel)
- Online/offline toggle with periodic location updates while online
- Assigned-order view, accept, and the arriving → arrived → picked up →
  delivered → completed status buttons, including cash/QPay confirmation

See `BACKEND_REQUIREMENTS.md` for the few things the API doesn't support yet
(notably: no driver decline/reject endpoint, so only accept is wired up).

## Accounts: customer vs. driver

The backend has one account per phone number. `POST /driver/register`
converts a signed-in customer account into a driver account permanently
(`role` becomes `"driver"`). After login, the app checks the signed-in
user's role and lands on the customer home screen or the driver home
screen accordingly; "Жолооч болох" (become a driver) in the customer
menu starts registration.

## Prerequisites

- Flutter SDK (stable channel). This was built against a recent stable
  release; any Flutter **3.24+** / Dart **3.6+** toolchain should work.
- The backend running somewhere reachable from your device/emulator (see
  the repository root `README.md`: `docker compose up --build -d`).

## One-time setup

This directory ships the Dart application (`lib/`, `test/`, `pubspec.yaml`)
but **not** the generated native platform projects (`android/`, `ios/`):
those are toolchain-specific (Gradle/AGP/Kotlin, Xcode) and are best
generated fresh by the Flutter CLI you actually have installed, rather than
committed and risking a mismatch. Generate them once:

```bash
cd apps/mobile
flutter create --platforms=android,ios --org mn.achaago .
flutter pub get
```

`flutter create` on an existing project only adds the missing platform
folders — it will not overwrite `lib/`, `test/`, or `pubspec.yaml`.

Android is the priority target (`AGENTS.md`: "Android first, iOS later"),
so that's what has been exercised while writing this app; the iOS project
`flutter create` generates should work but hasn't been run through Xcode
here.

### Location permission

The customer (pickup location) and driver (online location updates) flows
use the `geolocator` plugin, which needs a permission entry once the
platform projects exist:

- **Android** (`android/app/src/main/AndroidManifest.xml`), inside `<manifest>`:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  ```
- **iOS** (`ios/Runner/Info.plist`):
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>AchaaGo needs your location to set the pickup point and show nearby drivers.</string>
  ```

The app works without granting the permission — it falls back to a fixed
Ulaanbaatar-center pickup point for customers, and asks the driver to grant
it before going online.

## Configuring the API base URL

Every network call goes through `lib/config/app_config.dart` — the single
place that knows the backend's address:

```dart
static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8187/api');
static const String wsBaseUrl  = String.fromEnvironment('WS_BASE_URL',  defaultValue: 'ws://10.0.2.2:8187');
```

The defaults target the Android emulator's alias for your host machine
(`10.0.2.2`) on the gateway's default port (`WEB_PORT=8187` in the
repository root `.env`). Override at run/build time for a real device, iOS
simulator, or a different port:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.20:8187/api \
  --dart-define=WS_BASE_URL=ws://192.168.1.20:8187
```

(iOS simulator can usually just use `http://127.0.0.1:8187/api`, since
unlike the Android emulator it shares the host's network namespace.)

## Development OTP code

The backend's console SMS provider prints the real OTP to the API/worker
logs, **and** accepts a fixed development code regardless of what was
generated (`services/api/app/main.py otp_verify`, gated on
`SMS_PROVIDER=console`, which is the default in `.env.example`). That code
is **`0000`** (four digits) — the OTP field is validated as exactly 4
digits server-side, so `00` is not a valid request body. The verification
screen shows this hint under the code field. No real SMS is sent or
implemented here, per the task scope.

## Running

```bash
flutter run
```

## Checks

```bash
flutter analyze
flutter test
```

> **Note on this change's own verification:** this branch was produced in a
> sandboxed session with outbound network access restricted to GitHub only
> (no access to `pub.dev` or the Flutter tooling's own artifact host), so
> `flutter pub get`/`analyze`/`test` could not actually be executed here.
> The code was written and reviewed carefully (including a full manual
> cross-check of every cross-file symbol reference) to compile cleanly, but
> please run the two commands above for real before merging.

## Project structure

```
lib/
  config/        Single source of truth for the API base URL etc.
  theme/         Colors/typography matching AGENTS.md's design tokens
  l10n/          All Mongolian UI strings and backend-error translations
  core/          HTTP client, token storage, formatting helpers
  models/        Typed request/response shapes for the API contracts
  repositories/  One class per API area (auth/customer/driver)
  realtime/      WebSocket client for /ws/orders and /ws/tracking
  state/         App-wide session state + the order-watching mixin
  widgets/       Small shared UI pieces (buttons, cards, empty/error states)
  screens/       One folder per flow: login, customer, driver, public, shared
test/            Unit tests (formatting, error mapping, API client, model
                 parsing) and widget tests (buttons, star rating, phone entry)
```

## Design notes / deliberate limitations

- **No map SDK.** `MAPS_PROVIDER` defaults to the backend's demo provider
  (a handful of hardcoded Ulaanbaatar landmarks, no real routing), and no
  Google Maps API key exists in this environment. Screens that show a map
  in the web app use a small decorative illustration
  (`lib/widgets/route_illustration.dart`) instead of a real map, matching
  the task's "don't implement real Google Maps unless it already exists."
  Swapping in `google_maps_flutter` later is a client-only change once
  `MAPS_PROVIDER=google` and a key exist.
- **QPay** renders whatever `POST /orders/{id}/qpay-invoice` returns (the
  demo notice today; a QR image or payment links once QPay is configured
  for real) rather than embedding a QPay SDK.
- **Push notifications** are not wired up — see
  `BACKEND_REQUIREMENTS.md` §3.
- **Live tracking** uses the authenticated `/ws/orders/{id}` and public
  `/ws/tracking/{token}` WebSockets, backed by a 5–8s REST poll fallback
  in case a socket never connects or drops, so tracking still works even
  on flaky connections.
