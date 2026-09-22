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
