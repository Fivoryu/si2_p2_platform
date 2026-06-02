# Implementation Plan — Smart Vehicle Emergency Assistance Platform (Second Partial)

> Solo developer. Target deadline: **June 7–9, 2026**. Start: **May 29, 2026** (~10 working days).
> The database is already built (`database/01_schema.sql`, `02_views_kpi.sql`, `03_seed.sql`).
> This plan prioritizes the **mandatory second-partial features**: real-time (WebSockets),
> offline + sync, KPIs, and multi-tenant isolation.

---

## Detailed technical specifications (build from these)

This file is the high-level roadmap. The **build-ready, code-level specs** live in `docs/`
and are detailed enough for another developer/AI to implement each part directly:

| Doc | Scope |
|-----|-------|
| [`docs/00_OVERVIEW.md`](docs/00_OVERVIEW.md) | Architecture, repo layout, global conventions, enums, state machine, env vars, docker-compose, BYPASSRLS role. |
| [`docs/01_BACKEND_SPEC.md`](docs/01_BACKEND_SPEC.md) | FastAPI: full REST API contract, auth/JWT, tenant-scoped DB session (RLS core), models/DTOs, build order. |
| [`docs/02_REALTIME_WEBSOCKETS.md`](docs/02_REALTIME_WEBSOCKETS.md) | WebSocket endpoint, auth, JSON message protocol, Redis pub/sub manager, FCM push. |
| [`docs/03_AI_ASSIGNMENT_SYNC.md`](docs/03_AI_ASSIGNMENT_SYNC.md) | AI pipeline, assignment engine + scoring SQL, offline `/sync` (idempotent, last-write-wins). |
| [`docs/04_MOBILE_FLUTTER_SPEC.md`](docs/04_MOBILE_FLUTTER_SPEC.md) | Flutter: structure, sqflite offline DB, sync service, WS client, GPS, push, screens. |
| [`docs/05_WEB_ANGULAR_SPEC.md`](docs/05_WEB_ANGULAR_SPEC.md) | Angular: auth, real-time inbox, status updates, ECharts KPI dashboard, admin. |
| [`docs/06_TESTING_DEPLOY.md`](docs/06_TESTING_DEPLOY.md) | Acceptance tests for the 4 mandatory features, pytest, deployment summary, PDF/QR submission. |
| [`docs/07_AWS_FLOCI.md`](docs/07_AWS_FLOCI.md) | **AWS deployment** (RDS, ElastiCache, S3, ECR, ECS Fargate, CloudFront, EventBridge) developed/tested locally with **Floci** (AWS emulator); boto3 client, S3 evidence storage. |

Each doc ends with **acceptance criteria**. A feature is "done" only when its acceptance test passes.

---

## 0. Guiding strategy (read this first)

You cannot build 48 use cases perfectly alone in 10 days. The strategy is:

1. **Make the mandatory second-partial features bullet-proof** (real-time, offline, KPIs, multi-tenant). These are what the exam grades hardest.
2. **Reuse the database you already have** — it covers everything; you only build the slices you have time for.
3. **Vertical slices, not horizontal layers.** Build one feature end-to-end (DB → API → app) before moving on, so you always have a demoable product.
4. **Demo > completeness.** A working demo + QR + PDF beats half-finished code.

Repo structure to create at the root:

```
codigo_si2_p2/
├── database/            # already done
├── backend/             # FastAPI
├── mobile/              # Flutter
├── web/                 # Angular
├── docs/                # PDF, diagrams, screenshots
└── docker-compose.yml   # postgres + redis (local dev)
```

---

## 1. Project roadmap — implementation sprints

Your 5 cycles map onto **6 short sprints**. Each sprint ends with something demoable.

| Sprint | Days | Goal | Key deliverable |
|--------|------|------|-----------------|
| **S0 — Setup** | Day 1 (May 29) | Repos, Docker, DB running, skeleton apps | `docker-compose up` runs Postgres+Redis; FastAPI `/health` returns 200; Flutter & Angular blank apps run. |
| **S1 — Auth + Multi-tenant** | Day 2 | JWT login with `tenant_id` claim, RLS middleware, roles | Login works on web + mobile; requests are tenant-scoped. |
| **S2 — Core CRUD** | Day 3 | Drivers, vehicles, workshops, technicians, incident creation | Driver reports an incident (text+location); workshop sees it. |
| **S3 — Real-time + Assignment** | Days 4–5 | WebSocket tracking, status updates, assignment engine, push (FCM) | Live status + technician location on a map; workshop accept/reject. |
| **S4 — Offline + Sync** | Days 6–7 | sqflite local store, connectivity detection, `/sync` endpoint, conflict resolution | Report offline → reconnect → auto-sync with no duplicates. |
| **S5 — KPIs + Payments** | Day 8 | KPI dashboard (ECharts), SLA config, Stripe/Mercado Pago + 10% commission | Admin dashboard with real charts; test payment registered. |
| **S6 — Polish/Deploy/Docs** | Days 9–10 | Deploy, AI integration, screenshots, PDF, QR | Public URLs, recorded demo, final PDF. |

**AI modules** (transcription, image/text classification, summary, priority) are integrated opportunistically in S2–S3 and finished in S6. Use **external APIs first** (fast), swap to local models only if time allows.

---

## 2. Technology setup

### 2.1 Local infrastructure — `docker-compose.yml` (root)

```yaml
services:
  floci:                       # AWS emulator (S3, SNS, ECR/ECS...) — mirrors prod AWS locally
    image: floci/floci:latest
    ports: ["4566:4566"]
    volumes: ["./.floci-data:/app/data"]
  db:                          # → RDS PostgreSQL in AWS
    image: postgres:16
    environment:
      POSTGRES_DB: emergencias_db
      POSTGRES_PASSWORD: postgres
    ports: ["5432:5432"]
    volumes:
      - ./database:/docker-entrypoint-initdb.d   # auto-runs 01,02,03 on first boot
      - pgdata:/var/lib/postgresql/data
  redis:                       # → ElastiCache in AWS
    image: redis:7
    ports: ["6379:6379"]
volumes:
  pgdata:
```

> Postgres runs `*.sql` in `/docker-entrypoint-initdb.d` alphabetically on first boot → your `01_schema.sql`, `02_views_kpi.sql`, `03_seed.sql` load automatically.

Commands:
```bash
docker compose up -d
docker compose exec db psql -U postgres -d emergencias_db -c "SELECT * FROM emergencias.mv_kpi_resumen_tenant;"
```

### 2.2 Backend — FastAPI

```bash
mkdir backend && cd backend
python -m venv .venv && .venv\Scripts\activate      # Windows
pip install fastapi "uvicorn[standard]" sqlalchemy psycopg2-binary alembic \
            "python-jose[cryptography]" "passlib[bcrypt]" python-multipart \
            pydantic-settings redis websockets httpx
pip freeze > requirements.txt
```

Key libraries:
- `sqlalchemy` 2.x + `psycopg2-binary` — DB access.
- `python-jose` + `passlib[bcrypt]` — JWT + password hashing.
- `redis` — WebSocket pub/sub across workers and broadcast rooms.
- `httpx` — call AI/maps/payment external APIs.
- `alembic` — migrations (optional; your SQL is the source of truth, but init alembic for future changes).

`.env` (backend):
```
DATABASE_URL=postgresql+psycopg2://postgres:postgres@localhost:5432/emergencias_db
JWT_SECRET=change-me
JWT_ALGORITHM=HS256
REDIS_URL=redis://localhost:6379/0
STRIPE_SECRET_KEY=sk_test_...
FCM_SERVER_KEY=...
OPENAI_API_KEY=...            # or Google Speech / HF token for AI
MAPS_API_KEY=...
```

### 2.3 Mobile — Flutter

```bash
flutter create mobile
cd mobile
flutter pub add dio flutter_riverpod go_router sqflite path \
    connectivity_plus geolocator image_picker record \
    web_socket_channel google_maps_flutter flutter_secure_storage \
    firebase_core firebase_messaging uuid intl
```

- `dio` — HTTP client (interceptor adds JWT).
- `sqflite` + `path` — offline DB.
- `connectivity_plus` — detect online/offline.
- `geolocator` — GPS.
- `image_picker` + `record` — camera & audio.
- `web_socket_channel` — WS client.
- `google_maps_flutter` — live tracking map.
- `flutter_secure_storage` — store JWT.
- `firebase_messaging` — push.

### 2.4 Web — Angular

```bash
npm i -g @angular/cli
ng new web --routing --style=scss
cd web
npm i echarts ngx-echarts @stomp/stompjs socket.io-client \
      @angular/google-maps jwt-decode
ng add @angular/material        # forms, tables, dialogs
```

- `ngx-echarts` + `echarts` — KPI charts.
- `@angular/material` — tables/forms/dialogs.
- native `WebSocket` (or `socket.io-client`) — real-time table.
- `@angular/google-maps` — map (optional on web).

### 2.5 External services to register (free tiers)

- **Firebase** project → enable Cloud Messaging (push). Download `google-services.json` (Flutter Android).
- **Stripe** test account → test keys (use Stripe over Mercado Pago; simpler test cards).
- **AI**: OpenAI (Whisper for audio, GPT-4o-mini for text classification/summary) OR Google Speech-to-Text + Hugging Face. Start with OpenAI to save time.
- **Maps**: Google Maps API key (Distance Matrix for ETA, Maps SDK for Flutter).
- **AWS** (deployment target for the parcial): account for ECS Fargate, RDS, ElastiCache, S3, ECR, CloudFront. Locally, emulate all of it with **Floci** (`docker compose` service on `:4566`) — see `docs/07_AWS_FLOCI.md`. Install the AWS CLI.

---

## 3. Database design (already implemented — how to use it)

The schema is in `database/`. Summary of what matters for the exam:

- **Multi-tenant**: every business table has `tenant_id` referencing `tenant`. **Row Level Security** policies filter by the session variable. Your backend MUST run, per request:
  ```sql
  SET app.current_tenant = '<tenant_id from JWT>';
  ```
  The admin role uses `BYPASSRLS` (create a DB role for the platform admin).
- **UUID PKs**: enable offline `external_id` (= `id_local`) deduplication.
- **Timestamps sealed by trigger** on `incidente` (`asignado_at`, `aceptado_at`, `atendido_at`, `finalizado_at`) → these power the KPIs. You don't compute them manually.
- **KPIs are materialized views** (`mv_kpi_*`). Refresh with `SELECT emergencias.refrescar_kpis();` (call after batch changes or on a 15-min schedule with `pg_cron` or a FastAPI background task).
- **10% commission** auto-computed by trigger on `pago`.

ER overview (core relationships):
```
plan 1───* tenant 1───* usuario
tenant 1───* vehiculo *───1 usuario(conductor)
tenant 1───* taller 1───* tecnico
taller *───* tipo_incidente (taller_servicio)
incidente *───1 vehiculo, *───1 usuario(conductor), *───1 tipo_incidente
incidente 1───* evidencia / clasificacion_ia / incidente_estado_historial
incidente 1───* taller_candidato, 1───* asignacion *───1 taller
incidente 1───* cotizacion 1───* pago 1───1 factura
incidente 1───* conexion_ws / ubicacion_tracking / notificacion
incidente 1───1 sync_mapping (external_id)
tenant 1───* sla_config *───1 tipo_incidente
```

**Critical RLS test for the exam**: log in as tenant A, query incidents → you must NOT see tenant B's rows.

---

## 4. Backend implementation steps (build order)

Build endpoints in this order. Folder layout (`backend/app/`):

```
app/
├── main.py
├── core/        config.py, security.py (JWT), db.py (engine+session+SET tenant)
├── models/      SQLAlchemy models (mirror the SQL tables)
├── schemas/     Pydantic DTOs
├── api/         routers per module
├── services/    assignment.py, ai.py, payments.py, kpi.py, sync.py
└── ws/          manager.py (Redis pub/sub), routes.py
```

1. **DB session with tenant injection** (`core/db.py`): dependency that opens a session and runs `SET app.current_tenant = :tid` using the JWT claim. This is the heart of multi-tenant enforcement.
2. **Auth** (`api/auth.py`): `POST /auth/register` (driver), `POST /auth/login` (returns JWT with `sub`, `rol`, `tenant`), `POST /auth/logout` (insert `jti` into `token_revocado`), `POST /auth/forgot-password`. (CU-01..CU-04)
3. **Users/vehicles/workshops/technicians** CRUD (`api/`): standard routers. Enforce role checks with a `require_role(...)` dependency. (CU-05..CU-09)
4. **Incidents** (`api/incidentes.py`): `POST /incidentes` (create, status PENDIENTE), `GET /incidentes` (paginated, tenant-filtered), `GET /incidentes/{id}`, `PATCH /incidentes/{id}/estado` (validate transitions), `POST /incidentes/{id}/cancelar`. Upload evidence → `POST /incidentes/{id}/evidencias`. (CU-10..CU-16)
5. **AI service** (`services/ai.py`): functions `transcribe(audio)`, `classify_image(img)`, `classify_text(text)`, `summarize(incident)`, `priority(incident)`. Call OpenAI; store results in `clasificacion_ia` + update `incidente.tipo_incidente_id`, `prioridad`, `resumen_ia`. Trigger asynchronously after incident creation (FastAPI `BackgroundTasks`). (CU-17..CU-21)
6. **Assignment engine** (`services/assignment.py`):
   - Query available workshops of the tenant offering the required `tipo_incidente`.
   - Compute distance: `earthdistance` in SQL (`ll_to_earth`) or Google Distance Matrix for ETA.
   - Score = `w1*(1/distance) + w2*(1/active_jobs) + w3*calificacion`. Pick top.
   - Insert `taller_candidato` rows + create `asignacion` (ASIGNADO) + set incident `TALLER_ASIGNADO` + notify. On reject, pick next candidate. (CU-22..CU-29)
7. **WebSocket** (`ws/`): endpoint `/ws/{tenant_id}/{incident_id}`. Validate JWT + that user belongs to tenant + owns/serves incident. Use **Redis pub/sub** so status changes and technician GPS broadcast to all clients in the incident "room". (CU-33..CU-37)
8. **Payments** (`services/payments.py`): `POST /pagos/intent` (create Stripe PaymentIntent), webhook `POST /pagos/webhook` (on success insert `pago` → trigger computes 10% commission → set incident PAGADO → create `factura`). (CU-30..CU-32)
9. **Sync** (`services/sync.py`): `POST /sync` accepts a batch of offline incidents with `id_local`. For each: look up `sync_mapping` by `external_id`; if exists return existing `incidente_id` (no duplicate), else create + insert mapping. Conflict rule: last-write-wins by client timestamp. (CU-38..CU-41)
10. **KPIs** (`api/kpi.py`): `GET /kpis/resumen`, `/kpis/por-tipo`, `/kpis/talleres`, `/kpis/zonas`, `/kpis/sla`, `/kpis/comisiones` — each just `SELECT * FROM emergencias.mv_kpi_* WHERE tenant_id=...` (admin can pass `?tenant_id=`). `POST /kpis/refresh` calls `refrescar_kpis()`. SLA config CRUD. (CU-42..CU-45)
11. **Tenant admin** (`api/tenants.py`, admin-only, BYPASSRLS role): create tenant, assign admin, set plan. (CU-46..CU-48)

---

## 5. Mobile app (Flutter) steps

Screens (`lib/screens/`): `login`, `register`, `home_map`, `new_incident`, `incident_tracking`, `history`, `profile`, `vehicles`.

Build order:
1. **Auth + secure token storage**: login screen → store JWT in `flutter_secure_storage`; `dio` interceptor attaches `Authorization: Bearer`.
2. **Vehicles + profile** CRUD.
3. **New incident** (`new_incident.dart`): form + `geolocator` for GPS + `image_picker` (photos) + `record` (audio ≤60s). On submit → POST to backend.
4. **Offline layer** (`lib/data/local_db.dart`): `sqflite` table `incidente_local(id_local TEXT PK, payload TEXT, estado_sync TEXT, created_at)`. On submit, **always write locally first**, then try to POST.
5. **Connectivity + sync** (`lib/services/sync_service.dart`): `connectivity_plus` listener; when online, read `estado_sync='PENDIENTE'`, POST to `/sync`, store returned `id_servidor`, mark `SINCRONIZADO`. Retry with exponential backoff. (CU-38..CU-41)
6. **Live tracking** (`incident_tracking.dart`): connect `web_socket_channel` to `/ws/{tenant}/{incident}`; show incident status; render technician marker on `google_maps_flutter`, moving as GPS messages arrive. (CU-33, CU-34)
7. **Push** (`firebase_messaging`): request permission, get FCM token, send to backend; handle foreground/background notifications for status changes. (CU-35)
8. **Payment**: open Stripe Checkout (webview) or `flutter_stripe`; on success the backend webhook records the payment. (CU-30)

> Offline-first rule: the UI reads from sqflite, and the network layer reconciles. Pending incidents show a clock icon (CU-38).

---

## 6. Web app (Angular) steps

Modules (`src/app/`): `auth`, `dashboard`, `requests` (workshop inbox), `kpis`, `settings` (SLA/availability), `admin` (tenants).

Build order:
1. **Auth + JWT interceptor + role guards** (`core/auth.interceptor.ts`, `auth.guard.ts`). Decode tenant/role with `jwt-decode`.
2. **Workshop inbox** (`requests/`): Material table of incoming incidents (tenant-filtered by backend). Buttons **Accept / Reject** → PATCH status. Availability toggle (CU-09, CU-25, CU-26).
3. **Real-time table**: open a `WebSocket` per active incident (or one tenant-level channel); update rows live when status changes. Show incoming requests instantly. (CU-24, CU-36)
4. **Status update form**: dropdown of valid transitions (en camino → en atención → finalizado) → PATCH; backend broadcasts via WS. (CU-36, CU-37)
5. **KPI dashboard** (`kpis/`): `ngx-echarts` charts:
   - Bar: incidents by type (`/kpis/por-tipo`).
   - Gauge/number cards: avg assignment & arrival time (`/kpis/resumen`).
   - Bar: SLA compliance % (`/kpis/sla`).
   - Table: efficient workshops (`/kpis/talleres`).
   - Heat/scatter on map: zones (`/kpis/zonas`).
   - Date-range filter; admin tenant dropdown (CU-42, CU-43). Export button → CSV/PDF (CU-44).
6. **Admin module** (platform admin): create tenant, assign admin, set plan (CU-46..CU-48).

---

## 7. Integration & testing

Focus testing on the **four mandatory features** — these are your demo script.

1. **Multi-tenant isolation** (most important):
   - Seed has tenants *Auxilio Norte* and *RutaSegura*. Log in as each; confirm each only sees its own incidents/KPIs.
   - SQL proof: `SET app.current_tenant='<A>'; SELECT count(*) FROM emergencias.incidente;` then switch to B.
2. **Offline sync**:
   - Airplane mode → create 2 incidents → they appear as "pending" locally.
   - Re-enable network → confirm both upload, get server IDs, no duplicates. Re-trigger sync to prove idempotency (`external_id` unique).
3. **WebSocket broadcast**:
   - Open web (workshop) + mobile (driver) for the same incident. Change status on web → driver sees update instantly. Send technician GPS → marker moves.
4. **KPI calculation**:
   - Run `SELECT emergencias.refrescar_kpis();` then hit `/kpis/*`. Verify avg times match the seeded timestamps.
5. **Payment flow**:
   - Use Stripe test card `4242 4242 4242 4242`. Confirm `pago` row created with `comision_plataforma = monto*0.10` and a `factura`.

Test tooling: `pytest` + `httpx` for backend endpoints; a Postman collection for manual demo; Flutter `integration_test` for the offline flow if time permits.

---

## 8. Deployment & documentation

### Deployment — AWS (rehearsed locally on Floci) — full steps in `docs/07_AWS_FLOCI.md`
- **Backend**: container → **ECR** → run on **ECS Fargate** behind an **ALB** (public URL). `Dockerfile` below.
- **Database**: **RDS PostgreSQL 16** — run the three SQL files once + create the `app_admin BYPASSRLS` role.
- **Cache / WS pub-sub**: **ElastiCache (Redis)** → `REDIS_URL`.
- **Evidence files**: **S3** (`emergencias-evidencias`); DB stores the object key, served via presigned URL.
- **Web (Angular)**: `ng build` → **S3 + CloudFront** (HTTPS).
- **Mobile (Flutter)**: `flutter build apk --release` against the ALB URL → distribute APK + QR.
- **KPI refresh**: `pg_cron` on RDS or **EventBridge + Lambda**.
- **Local rehearsal**: `docker compose up -d` starts **Floci** (`:4566`); run the same `aws` commands with `--endpoint-url $AWS_ENDPOINT_URL`, then drop the flag for real AWS. Code is identical — only `AWS_ENDPOINT_URL` differs.

`backend/Dockerfile`:
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Final PDF / URL / QR (what to submit)
- **PDF** (in `docs/`): cover, theoretical foundation (you have it), requirements + 48 use cases, analysis diagrams, **DB ER diagram** (export from DBeaver/dbdiagram.io using your schema), architecture diagram, screenshots of each mandatory feature, and the deployment URLs.
- **URLs**: backend Swagger (`/docs`), Angular web app, APK download link.
- **QR codes**: one for the web app, one for the APK. Generate at qr-code-generator.com and paste in the PDF.
- **Demo video** (3–5 min): record the four mandatory features. Add the link to the PDF.

---

## 9. Time estimate & schedule (solo, ~10 days)

Estimated effort by section (hours):

| Section | Hours |
|---------|-------|
| S0 Setup (docker, repos, skeletons) | 5 |
| S1 Auth + multi-tenant + RLS middleware | 8 |
| S2 Core CRUD + incident creation + evidence | 12 |
| S3 WebSocket + assignment engine + push | 16 |
| S4 Offline + sync (Flutter sqflite + `/sync`) | 14 |
| S5 KPIs dashboard + payments | 12 |
| AI integration (external APIs) | 8 |
| S6 Deploy + docs + PDF + video | 10 |
| **Total** | **≈ 85 h** |

Suggested calendar (deadline June 7–9):

| Date | Focus | Done when… |
|------|-------|-----------|
| **May 29 (Fri)** | S0 setup + DB up + skeletons | `docker compose up`, FastAPI `/health`, Flutter & Angular run |
| **May 30 (Sat)** | S1 auth + JWT + RLS dependency | login on web+mobile, tenant scoping verified |
| **May 31 (Sun)** | S2 CRUD + incident create + evidence upload | driver reports incident, workshop lists it |
| **Jun 1 (Mon)** | S3a WebSocket infra (Redis rooms) + live status | status change pushes to driver live |
| **Jun 2 (Tue)** | S3b assignment engine + accept/reject + FCM | auto-assign + workshop accept + push |
| **Jun 3 (Wed)** | S4a Flutter offline (sqflite) + connectivity | offline incidents stored locally |
| **Jun 4 (Thu)** | S4b `/sync` endpoint + conflict resolution | reconnect → auto-sync, no duplicates |
| **Jun 5 (Fri)** | S5 KPI dashboard (ECharts) + SLA + payments | dashboard charts + test payment + commission |
| **Jun 6 (Sat)** | AI modules + map tracking polish | transcription/classification/summary working |
| **Jun 7 (Sun)** | Deploy to AWS (ECS/RDS/ElastiCache/S3/CloudFront), rehearsed on Floci, + bug-fix | public URLs live |
| **Jun 8 (Mon)** | Docs: ER diagram, screenshots, PDF, QR, video | submission package complete |
| **Jun 9 (Tue)** | Buffer / contingency | final review & submit |

### If you fall behind — cut in this order (keep mandatory features):
1. Drop **PDF/CSV export** (CU-44) → show on-screen charts only.
2. Drop **forgot-password** (CU-03) and **invoice PDF** (CU-32).
3. Replace **local AI models** with external API only (already the default).
4. Simplify **payment** to "register a payment + compute commission" without full Stripe webhook (mock the success callback).
5. Use **Google Distance Matrix optional** → fall back to `earthdistance` straight-line distance for assignment.

**Never cut**: multi-tenant isolation, WebSocket real-time, offline sync, KPI dashboard. Those are the graded core of the second partial.

---

## 10. Day-1 checklist (do this today)

```bash
# 1. repo skeleton
mkdir backend web mobile docs infra
# 2. infra up: Floci (AWS emulator) + DB (auto-loads your 3 SQL files) + Redis
docker compose up -d
docker compose exec db psql -U postgres -d emergencias_db -c "SELECT * FROM emergencias.mv_kpi_resumen_tenant;"
# 2b. provision Floci AWS resources (S3 bucket, SNS topic) — see docs/07_AWS_FLOCI.md
export AWS_ENDPOINT_URL=http://localhost:4566 AWS_DEFAULT_REGION=us-east-1 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
aws s3 mb s3://emergencias-evidencias --endpoint-url $AWS_ENDPOINT_URL
# 3. backend
cd backend && python -m venv .venv && .venv\Scripts\activate
pip install fastapi "uvicorn[standard]" sqlalchemy psycopg2-binary "python-jose[cryptography]" "passlib[bcrypt]" redis httpx python-multipart pydantic-settings boto3
# create app/main.py with a /health route, then:
uvicorn app.main:app --reload
# 4. web
cd ../ && ng new web --routing --style=scss
# 5. mobile
flutter create mobile
```

If the `mv_kpi_resumen_tenant` query returns rows for both tenants, your database layer is fully working and you can start S1.
