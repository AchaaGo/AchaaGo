# AchaaGo — Project Brief for Coding Agents

Read this whole file before writing code. It explains what we are building, how it should look, and how it should work. The `design/` folder holds the approved visual designs (see "Design reference files" below).

"AchaaGo" is a working name. Keep the brand name in one config value so it is easy to change.

---

## 1. What we are building

An on-demand truck-hire platform for **Ulaanbaatar, Mongolia** — similar to Uber, Lalamove, or Huolala (货拉拉), but for moving goods instead of people.

A customer opens the website, logs in with a phone number, chooses a service, enters a drop-off address, sees the price upfront, and orders. A nearby driver accepts, and the customer tracks the driver live on a map.

We are a team of 3. Keep the architecture simple and avoid over-engineering.

### Core product principles

1. **Simple like Uber.** Few screens, one clear action per screen, no clutter.
2. **Fast registration.** Phone number + SMS code only. No password, no email, no long forms.
3. **No app download required for customers.** Most people need a truck only once or twice a year, so the customer side is a mobile-first **website**. Drivers use a native app.
4. **Price shown before ordering.** No hidden fees. This is our main selling point.
5. **All user-facing text is in Mongolian (Cyrillic).** Code, comments, and docs are in English. Structure the frontend so strings can be translated later (i18n-ready), but ship Mongolian only.

---

## 2. The surfaces (apps) to build

| Surface | Users | Tech | Priority |
|---|---|---|---|
| Customer web app | Customers ordering trucks | Next.js | 1 |
| Dispatcher / admin panel | Our ops team | Next.js (same repo, `/admin` routes) | 1 |
| Backend API | All clients | FastAPI (Python, async) | 1 |
| Driver app | Truck drivers | Flutter (Android first, iOS later) | 2 |
| Marketing landing page | Public visitors | Next.js (same web app, `/` route) | 3 |

**Important — manual dispatch first.** At launch we will not have enough drivers for automatic matching. The customer sees the normal "finding a driver" screen, while a dispatcher assigns a driver by hand in the admin panel. Build assignment so that switching to automatic matching later only changes the backend, not the customer UI.

---

## 3. Tech stack (decided)

1. **Customer web + admin panel:** Next.js (React, TypeScript, App Router). Must work well inside in-app browsers (Facebook, Messenger, Telegram), on slow mobile connections, and on small Android phones.
2. **Styling:** Tailwind CSS, configured with the design tokens in section 5.
3. **Driver app:** Flutter (Dart). Needs background GPS tracking and push notifications.
4. **Backend API:** FastAPI (Python 3.12+). All endpoints `async def`. Pydantic v2 models.
5. **Real-time:** FastAPI's built-in WebSockets for live driver location and order status. Redis pub/sub to fan out events between workers.
6. **Background jobs:** Celery with Redis as the broker (SMS sending, push notifications, invoices).
7. **Database:** PostgreSQL 16 with the **PostGIS** extension (geospatial queries, e.g. "drivers within 3 km").
8. **DB access:** SQLAlchemy 2.x (async) + `asyncpg` + GeoAlchemy2. Migrations with Alembic.
9. **Cache / live state:** Redis — live driver locations (GEO commands), OTP codes, rate limits, Celery broker.
10. **Containers:** Docker + Docker Compose for local dev and first production deploy. **No Kubernetes.**
11. **Maps:** Google Maps Platform (Maps JavaScript API, Places Autocomplete, Directions/Distance Matrix).
12. **Push notifications:** Firebase Cloud Messaging (driver app).
13. **Payments:** QPay API (Mongolian QR payments) + cash option.
14. **SMS (OTP + notifications):** a local Mongolian SMS gateway — **provider not chosen yet.** Put SMS behind an interface (`SmsProvider`) with a console/logging implementation for development.

---

## 4. Repository structure (suggested)

```
achaago/
├── AGENTS.md
├── docker-compose.yml
├── .env.example
├── design/                  # approved designs (reference only, do not ship)
├── apps/
│   ├── web/                 # Next.js: customer app, admin panel, landing page
│   └── driver/              # Flutter driver app
└── services/
    └── api/                 # FastAPI backend
        ├── app/
        │   ├── main.py
        │   ├── core/        # config, security, db session
        │   ├── models/      # SQLAlchemy models
        │   ├── schemas/     # Pydantic schemas
        │   ├── routers/     # auth, services, quotes, orders, drivers, admin, payments, ws
        │   ├── services/    # business logic (pricing, dispatch, sms, qpay)
        │   └── workers/     # Celery tasks
        ├── alembic/
        └── tests/
```

---

## 5. Design system

The approved designs are in `design/`. Match them closely.

### Colors

| Token | Hex | Use |
|---|---|---|
| `ink` | `#14213D` | Primary text, dark panels, primary buttons, map route line |
| `ink-deep` | `#0E1830` | Footer background |
| `ground` | `#F4F1EA` | Page background, cards on white, secondary buttons |
| `surface` | `#FFFFFF` | Bottom sheets, cards, inputs |
| `accent` | `#F2A516` | Highlights, order button, icons on ink tiles. Text on accent is always `ink`, never white |
| `accent-soft` | `#FFF6E0` | Selected option background |
| `line` | `#E2DCCF` | Borders, dividers |
| `line-strong` | `#CFC7B6` | Input borders |
| `muted` | `#4A5263` | Secondary text |
| `muted-2` | `#3E4658` | Body text on ground |
| `disabled-bg` | `#D9D3C6` | Disabled buttons |
| `disabled-fg` | `#5E6472` | Text on disabled buttons |
| `error` | `#B42318` | Error messages |
| `map-bg` | `#ECE7DC` | Map base (design only; real app uses Google Maps with a matching light style) |

### Typography

- **Display / headings:** `Unbounded` (weights 600, 700), Google Fonts. Supports Cyrillic.
- **Body / UI:** `Golos Text` (weights 400, 500, 600, 700), Google Fonts. Cyrillic-first.
- Fallbacks: `'Segoe UI', system-ui, sans-serif`.

### Shape and spacing

- Border radius: buttons and inputs 12–14px, cards 16–20px, bottom sheets 24px top corners, round icon buttons 50%.
- Minimum touch target: **44 × 44 px**.
- Screen padding on mobile: 16–24px.
- Bottom sheet shadow: `0 -8px 28px rgba(20,33,61,0.14)`.
- Floating card shadow: `0 6px 20px rgba(20,33,61,0.15)`.

### Icons

Simple stroke icons (1.8–2px stroke, rounded caps). Lucide icons are a good match. No emoji in the UI.

### Accessibility

Real `<button>`, `<a>`, `<input>` + `<label>` elements. `aria-label` on icon-only buttons. Text contrast at least 4.5:1.

---

## 6. Customer web app — screens and behavior

Mobile-first (design width 390px). On desktop, center the app in a phone-width column or show the map full-width with the sheet as a left panel.

The design file `design/customer-app.dc.html` contains all six screens in one file. Each screen is inside `<sc-if value="{{isLogin}}">`, `{{isCode}}`, `{{isHome}}`, etc.

### Screen 1 — Login (phone number)

- Top: dark `ink` panel with logo and the tagline "Ачаагаа хэдхэн товшилтоор тээвэрлүүл" over a decorative dashed route line.
- Heading: "Утасны дугаараа оруулна уу"
- Subtext: "Бид таны дугаарт 4 оронтой баталгаажуулах код илгээнэ."
- Fixed `+976` prefix box + phone input (`type="tel"`, numeric keypad). Keep digits only, max 8 digits, display formatted as `9911 2233`.
- Button "Үргэлжлүүлэх" — disabled until exactly 8 digits.
- Bottom: "Үргэлжлүүлснээр та үйлчилгээний нөхцөл-ийг зөвшөөрнө." with a link to the terms page.
- On submit: call `POST /auth/otp/request`, go to Screen 2.

### Screen 2 — SMS code

- Back button (returns to Screen 1).
- Heading: "Кодоо оруулна уу"
- Subtext: "+976 {phone} дугаарт илгээсэн 4 оронтой кодыг оруулна уу."
- One large centered input, 4 digits, `autocomplete="one-time-code"` (enables SMS autofill).
- "Код дахин илгээх" link — show a countdown (e.g. 60 s) before it becomes active.
- Button "Баталгаажуулах" — disabled until 4 digits.
- On submit: `POST /auth/otp/verify`. New users are created automatically (name is optional and can be asked later). Go to Screen 3.
- Show a clear error in Mongolian for a wrong or expired code.

### Screen 3 — Home (choose service)

- Full-screen map with the user's current location (blue-ish halo in design uses `accent`).
- Floating round buttons top-left (menu) and top-right (profile).
- Bottom sheet:
  - "Сайн байна уу" (small, muted) + heading "Юу ачуулах вэ?"
  - **Two large service cards side by side: "Амжиргаа" and "Портер".** Each card: ink icon tile with accent icon, service name (Unbounded), short description, "Эхлэх үнэ {base}₮".
  - Tapping a card → Screen 4 with that service selected.
  - Search bar "Хаашаа ачих вэ?" → Screen 4 (default service: Портер).
- Services come from `GET /services` (not hard-coded), so we can add more later.

**Open question:** the exact definition of the "Амжиргаа" service (vehicle type, load size, description) is not decided yet. Its description is a placeholder `[ТАЙЛБАР]`. Keep it configurable in the database.

### Screen 4 — Route and price

- Floating top card: back button, pickup row "Одоогийн байршил" (dot marker, editable later), drop-off input "Хүргэх хаяг" (square accent marker) with Google Places Autocomplete.
- Map shows the route line (ink, with white outline) from pickup to drop-off.
- Bottom sheet:
  - Heading "Машинаа сонго" + "{distance} км · ~{duration} мин" on the right.
  - List of services, each row: icon tile, name, "{eta} · {description}", price on the right. The selected one has `ink` border and `accent-soft` background. Tapping switches service.
  - "Ачигч нэмэх" checkbox row with "+{loader price}₮".
  - Payment: two segment buttons "QPay" and "Бэлэн мөнгө".
  - Main button "{Service} захиалах · {price}₮" (accent background, ink text). Disabled until a drop-off address is set, with the helper text "Захиалахын тулд хүргэх хаягаа оруулна уу."
- Prices come from `POST /quotes` (server calculates; never trust client-side prices).
- On order: `POST /orders` → Screen 5.

### Screen 5 — Finding a driver

- Map with a pulsing accent circle at the pickup point.
- Bottom sheet: "Жолооч хайж байна…", "Ойролцоох {service} жолооч нарт захиалгыг илгээлээ.", progress bar, order summary box (pickup, drop-off, service + loader, payment method, total price), outline button "Захиалга цуцлах".
- Subscribe to the order's WebSocket channel. When the status becomes `assigned`, go to Screen 6.

### Screen 6 — Tracking

- Map with the route and the driver's truck marker moving in real time.
- Bottom sheet:
  - "Жолооч ирэх хүртэл" + large ETA, plate number chip on the right.
  - Driver: avatar (initials if no photo), name, rating star + "{rating} · {service}".
  - Two buttons: "Залгах" (accent, opens `tel:` link) and "Мессеж".
  - Same order summary box as Screen 5.
  - Text button "Захиалга цуцлах" (cancellation rules to be decided — may be free only before pickup).
- After delivery: show a simple completion + rating screen (not designed yet — keep the same visual style).

### Notifications for web customers

Browser push is unreliable (iPhone Safari needs Home Screen install; in-app browsers don't support it). So:

1. **SMS** only for key events: "driver found" (name, plate, tracking link) and "driver arrived".
2. **Live updates** via WebSocket while the page is open (plus sound/vibration when a driver is found).
3. **Web push** as an optional extra — ask for permission only after an order is placed.
4. Every order has a shareable tracking link (`/t/{token}`) that works without logging in.

---

## 7. Pricing logic

Calculated on the server only:

```
subtotal = service.base_fare
         + service.per_km_rate * distance_km
         + (loader_count * loader_rate)
         + (floors_without_elevator * floor_rate * max(loader_count, 1))   # later
total = subtotal * (1 + night_surcharge_pct/100 if night hours 22:00–07:00)
total = round to nearest 500 ₮
```

- Distance from Google Distance Matrix / Directions (driving).
- **All rates are placeholders** and must be editable in the admin panel. Example values used in the designs: Амжиргаа 10,000₮ + 1,500₮/km; Портер 30,000₮ + 2,000₮/km; loader 25,000₮; night +20%.
- Store the full price breakdown on the order at creation time (prices can change later; old orders keep their price).
- Currency: MNT (₮), integers only. Format with thousands separators: `46,000₮`.

---

## 8. Data model (first version)

- **users** — id, phone (unique, E.164 `+976XXXXXXXX`), name (nullable), role (`customer` | `driver` | `dispatcher` | `admin`), created_at.
- **drivers** — user_id, license info, status (`pending` | `approved` | `suspended`), rating, is_online, fcm_token.
- **vehicles** — id, driver_id, service_id, plate_number, model, capacity_kg, photo.
- **services** — id, code (`amjirgaa`, `porter`), name_mn, description_mn, icon, base_fare, per_km_rate, is_active, sort_order.
- **pricing_settings** — loader_rate, floor_rate, night_surcharge_pct, night hours.
- **orders** — id, customer_id, service_id, driver_id (nullable), status, pickup_point (PostGIS Point), pickup_address, dropoff_point, dropoff_address, distance_km, loaders, payment_method (`qpay` | `cash`), price_breakdown (JSONB), total_price, tracking_token, scheduled_for (nullable), timestamps.
- **order_events** — order_id, status, actor, created_at (audit trail for every status change).
- **payments** — order_id, provider (`qpay` | `cash`), amount, status, provider_invoice_id, raw webhook payload (JSONB).
- **Redis only:** OTP codes (hashed, 5 min TTL), OTP rate limits, live driver locations (GEO set), WebSocket pub/sub channels.

### Order status flow

```
pending (searching) → assigned → driver_arriving → arrived → picked_up → delivered → completed
         ↘ cancelled (by customer, driver, or dispatcher, with reason)
         ↘ no_driver_found (timeout)
```

Every change writes an `order_events` row and publishes to Redis so WebSocket clients update.

---

## 9. API (first version)

Auth: short-lived JWT access token + refresh token after OTP verification.

**Auth**
- `POST /auth/otp/request` — `{phone}` → sends SMS. Rate limit: max 3 per phone per 10 min, max per IP too.
- `POST /auth/otp/verify` — `{phone, code}` → `{access_token, refresh_token, user}`. Creates user if new. Max 5 wrong attempts per code.
- `POST /auth/refresh`

**Customer**
- `GET /services` — active services with base prices.
- `POST /quotes` — `{pickup, dropoff, loaders}` → price per service + distance + duration.
- `POST /orders` — create order (re-calculates price on the server).
- `GET /orders/{id}`, `GET /orders` (my orders), `POST /orders/{id}/cancel`
- `GET /t/{tracking_token}` — public tracking data (no auth, limited fields).
- `WS /ws/orders/{id}` — status changes + driver location.

**Driver** (Flutter app)
- `POST /driver/online`, `POST /driver/offline`
- `POST /driver/location` (or over WebSocket every ~5 s while online)
- `GET /driver/offers`, `POST /driver/orders/{id}/accept`
- `POST /driver/orders/{id}/status` — arrived, picked_up, delivered

**Dispatcher / admin**
- `GET /admin/orders` (filter by status), `GET /admin/drivers` (online, with locations)
- `POST /admin/orders/{id}/assign` — `{driver_id}` (manual dispatch)
- CRUD for services and pricing settings; driver approval.

**Payments**
- `POST /payments/qpay/invoice` — creates QPay invoice/QR for an order.
- `POST /payments/qpay/webhook` — QPay callback; verify it, mark payment paid. Must be idempotent.

---

## 10. Admin / dispatcher panel (Next.js, `/admin`)

Not designed yet — use the same colors and fonts, desktop layout.

1. **Live map** of online drivers and open orders.
2. **Order list** with status filters; order detail with timeline (`order_events`).
3. **Manual assign:** pick an order → see nearest online drivers (PostGIS distance) → assign.
4. **Create order by phone:** dispatcher enters an order for a customer who called.
5. **Drivers:** approve/suspend, vehicle info.
6. **Services & pricing:** edit rates.

Access only for users with role `dispatcher` or `admin`.

---

## 11. Marketing landing page

Designs: `design/landing-desktop.dc.html` (1440px) and `design/landing-mobile.dc.html` (390px). Sections: header, hero with price calculator, vehicle types, how it works, services, order form, driver sign-up, FAQ, footer. Text in `[SQUARE BRACKETS]` is placeholder content to be filled in later. Lower priority than the customer app — the "order" buttons should link into the customer app flow.

---

## 12. Development rules

- `docker compose up` must start everything locally (api, worker, postgres+postgis, redis, web).
- All secrets in environment variables; provide `.env.example`. Never commit secrets or API keys.
- External services (SMS, QPay, Google Maps, FCM) behind interfaces with fake/dev implementations so the app runs locally without real accounts. In dev, log OTP codes to the console.
- Write tests for pricing, OTP flow, order status transitions, and the QPay webhook.
- Validate all input on the server. Never trust prices or status changes from clients.
- Phone numbers: store in E.164 (`+976` + 8 digits).
- Times: store UTC, display in `Asia/Ulaanbaatar`.
- Keep UI strings in one place per app (e.g. a `mn.json` messages file).

---

## 13. Build order (milestones)

1. **Foundation:** repo, Docker Compose, FastAPI skeleton, DB + PostGIS + Alembic, Next.js skeleton with design tokens.
2. **Auth:** phone OTP login (Screens 1–2) with dev SMS provider.
3. **Ordering:** services, quotes, pricing, Screens 3–4, create order.
4. **Dispatch + tracking:** admin panel manual assign, order status flow, WebSockets, Screens 5–6, public tracking link, SMS notifications.
5. **Driver app (Flutter):** login, go online, location updates, accept order, status updates, push notifications.
6. **Payments:** QPay integration.
7. **Automatic matching:** offer orders to nearest online drivers (PostGIS), with dispatcher fallback.
8. **Landing page.**

---

## 14. Open questions (do not guess — leave configurable or ask)

- What exactly is the **Амжиргаа** service (vehicle, capacity, description, icon)?
- Which **SMS provider** in Mongolia?
- Real **prices** (will come from pilot deliveries).
- **Cancellation** rules and fees.
- **Hosting** region / data residency requirements.
- Driver **commission** and payout schedule.
- Final **brand name** (AchaaGo is temporary).

---

## Design reference files

`design/*.dc.html` are HTML design prototypes exported from our design tool. They are **reference only** — do not copy them into the app as-is. Rebuild them as proper Next.js components.

How to read them:

- Everything inside `<x-dc> ... </x-dc>` is the visual markup. All styles are inline `style="..."` — read them for exact sizes, colors, spacing, and fonts.
- `{{name}}` is a template placeholder filled from the `renderVals()` function in the `<script data-dc-script>` block at the bottom of the file. That script shows the demo logic (screen switching, validation, price formula).
- `<sc-if value="{{x}}">` means "show only when x is true". `<sc-for list="{{items}}" as="item">` means "repeat for each item".
- `data-props` on the script tag lists adjustable design values (accent color, example prices).
- The map in the designs is a drawn illustration; the real app uses Google Maps with a light style matching `map-bg`.
- Names, plate numbers, ETAs and prices in the designs are sample data.