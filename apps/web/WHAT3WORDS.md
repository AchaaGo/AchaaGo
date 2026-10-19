# Optional what3words address entry

Google Maps remains the default for both endpoints. The compact selector applies
to the active pickup/destination editor, and each endpoint remembers its own
choice. Switching methods preserves selected coordinates and the current quote.
Draft what3words text does not replace a location until conversion succeeds.

`What3WordsInput` debounces AutoSuggest by 350 ms after two words and at least one
letter of the third. Suggestions are clipped to Mongolia and show the nearby
place. Enter or the select button calls convert-to-coordinates. Only provider
coordinates are used; no coordinates are guessed from the words. Cancellation and
request generations prevent old searches from updating another endpoint.

The final location is the existing `{lat, lng, address}` Point. Its address is the
canonical `///word.word.word`; method choice/drafts are separate UI state. Both
methods call the same `applyPlace`, quote, traffic-routing and order logic. No
backend contract or database change is required. A map tap continues to select a
normal Google location and returns that endpoint to Google mode.

## Configuration before an approved deployment

Supply `WHAT3WORDS_API_KEY` to the **web service's runtime environment**, using the
existing deployment secrets/configuration mechanism. Do not prefix it with
`NEXT_PUBLIC_`. The current Compose file does not pass this variable: merely
adding it to a root `.env` file will not inject it into the web container. An
explicitly approved deployment configuration step is needed to pass it through.
This change does not edit environment files, Compose, nginx, ports or secrets.

The key must permit AutoSuggest and convert-to-coordinates. A what3words account
plan with conversion access is needed; missing configuration, unavailable features,
quota errors and timeouts show Mongolian messages with a return to Google Maps.

The existing Next.js server handles POST `/address/what3words`. This path avoids
the gateway's existing `/api/*` routing to FastAPI, so no proxy configuration
change is needed. The handler validates origin/input, authenticates the existing
`ag_access` session with `/auth/me`, and applies a bounded per-user in-process
rate limit. The browser can renew an expired session via the existing refresh
flow. Only the server sends `X-Api-Key` to the fixed what3words HTTPS origin;
provider error messages/keys are never returned or logged. Responses are no-store.

No new dependency is installed. No separate map or routing provider is added.

## Validation

```sh
npm run typecheck
npm run build
node --test tests/what3words.cjs tests/traffic-routes.cjs tests/road-route.cjs
node tests/what3words-ui.cjs
```

Tests use fixtures, not a real key/account or live services. Real conversion and
subscription access must be checked once the private runtime key is configured.

Provider reference: https://developer.what3words.com/public-api/docs
