# AchaaGo

Mobile-first truck ordering for Ulaanbaatar. The repository contains a Next.js customer/admin web app and an async FastAPI API with PostgreSQL/PostGIS, Redis, Celery, WebSockets, QPay and provider interfaces.

## Start

```bash
python3 scripts/bootstrap_env.py http://localhost:8187
docker compose up --build -d
curl http://localhost:8187/api/health
```

Development OTP codes are printed by the worker (`docker compose logs worker`). The bootstrap admin phone is configured in `.env`; logging in with that phone opens `/admin`. The default map, SMS, QPay and push implementations are development providers. `APP_ENV=production` refuses to start until real providers and HTTPS are configured.

Only the gateway publishes a host port (`WEB_PORT`, default `8187`). API, PostgreSQL and Redis stay on the project network.

## Checks

```bash
cd services/api && pip install -r requirements-dev.txt && pytest && ruff check app tests
cd apps/web && npm ci && npm run typecheck && npm run build
```

All customer-visible strings are Mongolian. Undecided product values remain configurable: the Амжиргаа description, prices, cancellation statuses, dispatch timeout and external providers.

## Google Maps (web)

The customer web app shows a real interactive Google Map (pickup/drop-off
markers, tap-to-choose on the route screen) once a browser API key is
configured. Without one, it falls back to the same decorative map it always
had — nothing else in the app changes either way.

### Create and restrict a key

1. In [Google Cloud Console](https://console.cloud.google.com/), pick or
   create a project, then **APIs & Services → Library** and enable
   **Maps JavaScript API** only (the web app doesn't call Places,
   Directions, or Geocoding — no need to enable or pay for those).
2. **APIs & Services → Credentials → Create Credentials → API key.**
3. Click the new key to edit it, then under **Application restrictions**
   choose **Websites** and add the HTTP referrers that should be allowed to
   use it, one per line, for example:
   - `https://your-production-domain.mn/*` (once the real domain exists)
   - `http://64.119.31.106:8187/*` — temporary, for testing against this
     environment's IP; remove it once a real domain is in place
   - `http://localhost:8187/*` and `http://127.0.0.1:8187/*` for local dev
4. Under **API restrictions**, restrict the key to **Maps JavaScript API**
   only.
5. Copy the key into `.env` as `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=...` (leave
   `GOOGLE_MAPS_API_KEY` — the separate server-side key used by
   `services/api`'s optional Google-backed place search/routing — alone
   unless you're also switching `MAPS_PROVIDER` away from `demo`).
6. Rebuild and restart the web container so the key gets baked into the
   client bundle at build time:
   ```bash
   docker compose up --build -d web
   ```

**Never commit a real key.** `.env` is git-ignored; only `.env.example`
(with empty values) is committed. This key is restricted by HTTP referrer,
not secret-secret, but an unrestricted key on a public repo/domain can
still be abused for billable requests — always set the referrer
restriction above before using a key beyond local testing.
