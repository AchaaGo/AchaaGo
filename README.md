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

## Production

`APP_ENV=production` refuses to start until HTTPS, a real SMS gateway, Google Maps and QPay are configured.

### HTTPS

1. Buy a domain and point its DNS **A record** at the server. Open ports 80 and 443.
2. In `.env`, set `DOMAIN=achaago.mn` (your domain), `PUBLIC_URL=https://achaago.mn` and `GATEWAY_BIND=127.0.0.1`.
3. Run `docker compose --profile https up -d`. Caddy gets the Let's Encrypt certificate on its own, renews it, and redirects `http://` to `https://`.

Login cookies become `Secure` automatically once `PUBLIC_URL` starts with `https://`. Rebuild the mobile apps with `API_BASE_URL=https://<domain>/api` and `WS_BASE_URL=wss://<domain>`.

### SMS

`SMS_PROVIDER=http` sends through any HTTP SMS gateway. Describe the gateway's API with the `SMS_HTTP_*` settings. The placeholders `{phone}`, `{message}`, `{sender}` and `{api_key}` are filled in, URL-encoded in the URL and JSON-escaped in the body. For example, for a gateway that takes a JSON POST with a bearer key:

```env
SMS_PROVIDER=http
SMS_HTTP_URL=https://sms.example.mn/v1/send
SMS_HTTP_HEADERS={"Authorization": "Bearer {api_key}"}
SMS_HTTP_BODY={"from": "{sender}", "to": "{phone}", "text": "{message}"}
SMS_API_KEY=...
SMS_SENDER=AchaaGo
SMS_PHONE_FORMAT=local
```

- Use `SMS_HTTP_METHOD=GET` with the placeholders in the URL for gateways that take query parameters.
- Use `SMS_HTTP_BODY_FORMAT=form` for form-encoded bodies.
- `SMS_PHONE_FORMAT` is `local` (99112233), `international` (97699112233) or `e164` (+97699112233).
- A send counts as failed unless the gateway answers 2xx and, if `SMS_HTTP_SUCCESS_TEXT` is set, the response contains that text. Failed SMS are retried for about 20 minutes, without holding up other messages.
- The fixed test code `00` stops working as soon as `SMS_PROVIDER` is no longer `console`, and the web login then asks for the 4-digit code.

### Backups

The `backup` service writes a `pg_dump` to `.data/backups/` once a day and keeps `BACKUP_KEEP_DAYS` days (default 14). The files are on the same disk as the database, so copy that folder off the server regularly. To restore one:

```bash
docker compose stop api worker beat
docker compose exec -T postgres pg_restore -U achaago -d achaago --clean --if-exists < .data/backups/achaago-YYYYMMDD-HHMMSS.dump
docker compose start api worker beat
```

### Alerts and health checks

- **Telegram alerts:** Create a bot with @BotFather, add it to the team's group, and set `ALERT_PROVIDER=telegram`, `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`. Unhandled API errors, failed background tasks, dropped SMS and a stopped background worker each post a message, at most once per 10 minutes per problem.
- **Uptime monitoring:** `GET /api/health/full` checks the database, Redis and the background worker, and returns 503 if any is down. Point a free uptime monitor such as UptimeRobot at `https://<domain>/api/health/full`: it also covers the case where the whole server is down, which no alert from inside it can report.
- **Liveness:** `/api/health` checks only that the API and database are up; Docker uses it at startup.

## Checks

```bash
cd services/api && pip install -r requirements-dev.txt && pytest && ruff check app tests
cd apps/web && npm ci && npm run typecheck && npm run build
```

All customer-visible strings are Mongolian. Undecided product values remain configurable: the Амжиргаа description, prices, cancellation statuses, dispatch timeout and external providers.



