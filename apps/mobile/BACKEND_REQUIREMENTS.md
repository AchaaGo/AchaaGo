# Mobile app — backend requirements

This file lists backend gaps the mobile app ran into while implementing the
requested flows against the **existing** API contracts in `services/api/`.
Per the task scope, none of these are implemented here — the mobile app
works around each one where it reasonably can, and this file documents the
rest for a future backend change.

## 1. No driver decline/reject endpoint

`services/api/app/main.py` only exposes:

- `POST /driver/orders/{id}/accept` — sets the order to `driver_arriving`.

There is no endpoint for a driver to actively decline/reject an order that
was assigned to them (`POST /admin/orders/{id}/assign` is dispatcher-only,
and once assigned the order stays with that driver until a status change or
a dispatcher cancellation). The task's "accept/decline where supported by
the API" is handled by only implementing **accept** in
`lib/screens/driver/driver_active_order_screen.dart`.

Suggested shape for a future endpoint, mirroring the existing status route:

```
POST /driver/orders/{id}/decline
-> 200 {..order json..}  (order.status back to "pending", order.driver_id cleared)
```

This would need a dispatch-timeout-safe transition added to
`services/api/app/pricing.py`'s `TRANSITIONS` map (currently `assigned` can
only go to `driver_arriving`, `arrived`, or `cancelled`).

## 2. No reverse geocoding for the pickup address

The customer web app labels the pickup point with the fixed string
"Одоогийн байршил" instead of a real street address, because there is no
`GET /places/reverse?lat=&lng=` (or similar) endpoint — only forward search
(`GET /places?q=`) and place-by-id (`GET /places/{id}`) exist, both backed
by `DemoMaps`'s 6 hardcoded Ulaanbaatar landmarks in
`services/api/app/providers.py`. The mobile app does the same thing
(`Strings.currentLocation`), which is consistent with the web app but is
worth revisiting once `MAPS_PROVIDER=google` is configured — the Google
Places SDK does support reverse geocoding, so this may not need a backend
change at all, only wiring on the client once real Maps credentials exist.

## 3. Driver push notifications are not wired up

`POST /driver/push-token` and an `Outbox(kind="push", ...)` row (written in
`services/api/app/orders.py` `change_status` when an order is assigned)
already exist, but `FCM_PROVIDER=console` and `FCM_PROJECT_ID` is empty in
`.env.example` — there is no real Firebase project yet. Per the task's
constraints ("do not implement production push credentials unless they
already exist"), the mobile app does not call `/driver/push-token` or
integrate the `firebase_messaging` plugin. Once a real Firebase project
and `google-services.json`/APNs key exist, this is a client-only addition
(register the FCM token after driver registration/login, refresh it on
`onTokenRefresh`).

## 4. No driver order-history endpoint

`GET /driver/offers` only returns orders in the `ACTIVE` set (see
`services/api/app/pricing.py`), which is exactly what the "assigned-order
view" needs, so nothing is blocked today. If a future "past deliveries"
screen is wanted for drivers, it would need something like
`GET /driver/orders?status=completed` (the customer side already has the
equivalent via `GET /orders`).

## 5. QPay / Google Maps production credentials

Not a gap so much as an explicit non-goal for this change: `QPAY_PROVIDER`
and `MAPS_PROVIDER` default to the demo providers, and no real merchant or
Maps API credentials exist in this environment. The mobile app renders
whatever `POST /orders/{id}/qpay-invoice` returns (demo notice, QR image,
or payment links) so it will pick up real QPay automatically once the
backend is switched to `QPAY_PROVIDER=qpay` with real credentials — no
mobile change should be needed for that switch.
