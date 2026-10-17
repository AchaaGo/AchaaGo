# Customer traffic routing

The booking screen uses the existing Google Maps JavaScript `routes` library
(`Route.computeRoutes`). React state stores selected pickup/dropoff coordinates;
`useTrafficRoutes` supplies typed route options to the map and compact sheet summary.
Tracking and backend quote/order calculation retain their existing behavior.

## Configuration

Use the existing `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` build-time configuration. This
is a browser Maps key, not a private server credential. Restrict it to approved
website referrers and required APIs in Google Cloud. Never use a private server
key here. No environment files, Google settings, or deployment files are changed.

The Cloud project needs billing, Maps JavaScript API and Routes API enabled:
https://developers.google.com/maps/documentation/javascript/routes/start
Keep existing Places/Geocoding permissions for address selection.
No new proxy, backend endpoint, SDK dependency, or server key is required.

## Behavior

- Driving requests use `TRAFFIC_AWARE_OPTIMAL`, alternative routes, and
  `TRAFFIC_ON_POLYLINE`. Departure time is omitted deliberately: Google's default
  is the request time (now), without risking a past timestamp on slow connections.
- Routes with valid road geometry are ranked by `durationMillis`; the shortest
  duration is selected initially. Selecting another route changes map/summary
  only. It does not change backend fares, order payloads or the driver's route.
- Delay is max(0, traffic duration - static duration), only when both exist.
  Unknown durations/distances are omitted, not replaced with example values.
- Alternatives are gray; selected geometry retains the navy/white outline.
  Valid Google speed segments add amber/red sections and a textual legend.
- Each request stage has an eight-second timeout. Traffic failures try ordinary
  routing once; provider fallback responses are not represented as live traffic.
  If all routing fails, an existing quote polyline can still render without an
  invented ETA. Ordering remains governed by the existing backend quote.
- In-flight work is shared by exact coordinate pair. Successful traffic results
  are cached in memory for two minutes, fallback results for 30 seconds, failures
  for 15 seconds. Settled cache entries are bounded to roughly 20 pairs. Nothing
  persists across refresh; there is no background polling. Expired entries are
  refreshed on a new selection/request, not ordinary React renders.
- Stale requests cannot overwrite newly selected endpoints. Editing/typing alone
  never requests routes until both endpoints are valid again.

## Local validation

From `apps/web`:

```sh
npm run typecheck
npm run build
node --test tests/road-route.cjs tests/traffic-routes.cjs
node tests/traffic-ui.cjs
```

The UI test intercepts every request and serves the local production `.next`
output at a fake origin. Build with a nonempty fixture Maps key to exercise Maps
code during offline tests. Never deploy that fixture build. The test uses Chrome
by default (`BOOKING_BROWSER` overrides the channel).

These tests do not validate live traffic coverage in Ulaanbaatar, Cloud billing,
key restrictions, or API availability. Confirm those with an approved environment
before deployment. No live server or service is needed for these tests.
