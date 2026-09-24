# AchaaGo

Mobile-first truck ordering for Ulaanbaatar. The repository contains a Next.js customer/admin web app and an async FastAPI API with PostgreSQL/PostGIS, Redis, Celery, WebSockets, QPay and provider interfaces.

## Start

Create a `.env` in the repo root (never commit it) with at least:

```
POSTGRES_PASSWORD=<random>
JWT_SECRET=<random, 32+ characters>
BOOTSTRAP_ADMIN_PHONE=+97699000001
```

Everything else has a development default — see `services/api/app/config.py` for the full list (SMS/maps/QPay/push providers, ports, etc.).

```bash
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



