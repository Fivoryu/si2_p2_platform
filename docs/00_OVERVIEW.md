# 00 — Project Overview & Build Contract

> **Audience:** an autonomous coding agent (or developer) implementing the platform from zero.
> **Source of truth for data:** `database/01_schema.sql`, `database/02_views_kpi.sql`, `database/03_seed.sql`.
> Read these docs in order: `00` → `01` → `02` → `03` → `04` → `05` → `06` → `07`.
> Cloud target is **AWS**, emulated locally with **Floci**; see `07_AWS_FLOCI.md`.

## 1. What we are building

A multi-tenant SaaS for **vehicle emergency assistance**:

- **Drivers** (Flutter mobile) report breakdowns/accidents with photos, audio, GPS; pay; track help live; works offline.
- **Workshops** (Angular web) receive requests, accept/reject, update status, see KPIs.
- **Backend** (FastAPI + PostgreSQL + Redis) exposes REST + WebSockets, runs AI, an assignment engine, payments, and offline sync.

### Mandatory graded features (never cut)

1. **Real-time** (WebSockets): live status + technician location.
2. **Offline + sync**: report offline, auto-sync, no duplicates.
3. **KPIs dashboard**: assignment time, arrival time, incidents by type, efficient workshops, SLA.
4. **Multi-tenant isolation**: a user of tenant A never sees tenant B's data.

## 2. Repository layout (create exactly this)

```
codigo_si2_p2/
├── database/                 # DONE — SQL schema, views, seed
├── backend/                  # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── core/             # config, db, security, deps
│   │   ├── models/           # SQLAlchemy ORM (mirror DB)
│   │   ├── schemas/          # Pydantic DTOs
│   │   ├── api/              # routers (auth, incidentes, talleres, kpi, ...)
│   │   ├── services/         # assignment, ai, payments, sync, kpi
│   │   └── ws/               # websocket manager + routes (Redis pub/sub)
│   ├── tests/
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .env
├── mobile/                   # Flutter (lib/ structure in doc 04)
├── web/                      # Angular (src/app structure in doc 05)
├── docs/                     # these specs
│   ├── 00_OVERVIEW.md
│   ├── 01_BACKEND_SPEC.md
│   ├── 02_REALTIME_WEBSOCKETS.md
│   ├── 03_AI_ASSIGNMENT_SYNC.md
│   ├── 04_MOBILE_FLUTTER_SPEC.md
│   ├── 05_WEB_ANGULAR_SPEC.md
│   ├── 06_TESTING_DEPLOY.md
│   └── 07_AWS_FLOCI.md       # AWS deploy + Floci local emulation
├── infra/                    # floci-init.sh, ecs-taskdef.json, lambda_kpis
├── docker-compose.yml
└── PlanDeImplementacion.md   # high-level roadmap & schedule
```

## 3. Architecture diagram (logical)

```
            ┌───────────────────────┐         ┌──────────────────────┐
            │   Flutter (driver)    │         │   Angular (workshop)  │
            │  REST + WS + sqflite  │         │   REST + WS + ECharts │
            └───────────┬───────────┘         └───────────┬──────────┘
                        │  HTTPS / WSS                     │
                        └──────────────┬───────────────────┘
                                       ▼
                        ┌──────────────────────────────┐
                        │        FastAPI backend        │
                        │  REST routers │ WS manager     │
                        │  services: ai, assignment,     │
                        │  payments, sync, kpi           │
                        └───────┬───────────────┬────────┘
                                │               │
                     ┌──────────▼───┐     ┌─────▼─────┐
                     │ PostgreSQL   │     │   Redis   │  (WS pub/sub + cache)
                     │ schema:      │     └───────────┘
                     │ emergencias  │
                     │ + RLS + mv_* │
                     └──────────────┘
        AWS: S3 (evidence) │ RDS (db) │ ElastiCache (redis) │ ECS/ECR │ SNS (push)
        External: OpenAI (AI) │ Stripe (pay) │ FCM (push) │ Google Maps (ETA)
        Local dev: Floci emulates the AWS services (endpoint :4566)
```

## 4. Global conventions (all layers must follow)

- **IDs**: UUID v4 strings everywhere (DB uses `gen_random_uuid()`).
- **Timestamps**: ISO-8601 UTC (`2026-06-01T14:30:00Z`).
- **JSON casing**: `snake_case` keys (matches DB columns) to avoid mapping bugs.
- **Enums** are sent as the exact DB uppercase strings. Canonical values:
  - `rol_usuario`: `ADMIN_PLATAFORMA | ADMIN_TENANT | CONDUCTOR | TALLER | TECNICO`
  - `estado_incidente`: `PENDIENTE | BUSCANDO_TALLER | TALLER_ASIGNADO | EN_CAMINO | EN_ATENCION | FINALIZADO | PAGADO | CANCELADO | NO_ATENDIDO`
  - `prioridad_incidente`: `ALTA | MEDIA | BAJA | INCIERTA`
  - `estado_asignacion`: `PROPUESTO | ASIGNADO | ACEPTADO | RECHAZADO | REASIGNADO`
  - `estado_cotizacion`: `PENDIENTE | ACEPTADA | RECHAZADA | EXPIRADA`
  - `estado_pago`: `PENDIENTE | COMPLETADO | FALLIDO | REEMBOLSADO`
  - `tipo_evidencia`: `IMAGEN | AUDIO | TEXTO`
  - `estado_sync`: `PENDIENTE | SINCRONIZADO | ERROR`
  - `canal_notificacion`: `PUSH | WEBSOCKET | EMAIL | SMS`
- **Auth**: `Authorization: Bearer <jwt>` on every protected request.
- **Tenant scoping**: the backend extracts `tenant` from the JWT and runs `SET app.current_tenant = '<tenant_id>'` on the DB session (RLS does the rest). Clients never send `tenant_id` in bodies; the server derives it.
- **Errors**: JSON `{ "detail": "<message>" }` with proper HTTP status (FastAPI default). Validation errors are 422.
- **Pagination**: `?limit=20&offset=0`; responses `{ "items": [...], "total": <int> }`.
- **Money**: decimal strings with 2 decimals; currency `BOB` default.
- **Cloud**: deploy on **AWS**; develop locally against **Floci** (AWS emulator on `:4566`). Code is identical — only `AWS_ENDPOINT_URL` differs (set locally, unset in AWS). See `07_AWS_FLOCI.md`.
- **File storage**: evidence photos/audio go to **S3** (bucket `emergencias-evidencias`); the DB stores only the object key in `evidencia.url`, served to clients via presigned URLs.

## 5. Incident state machine (enforce in backend)

```
PENDIENTE ──(AI classified / search)──► BUSCANDO_TALLER ──(assign)──► TALLER_ASIGNADO
   │                                          │                            │
   └──(driver cancels)──► CANCELADO           │                  (workshop accepts) ▼
                                              │                            EN_CAMINO
                       (no workshop) ► NO_ATENDIDO                          │
                                                                 (technician arrives) ▼
                                                                          EN_ATENCION
                                                                            │
                                                                  (service done) ▼
                                                                          FINALIZADO ──(pay)──► PAGADO
```

Allowed transitions (reject anything else with 409):

- `PENDIENTE` → `BUSCANDO_TALLER`, `CANCELADO`
- `BUSCANDO_TALLER` → `TALLER_ASIGNADO`, `NO_ATENDIDO`, `CANCELADO`
- `TALLER_ASIGNADO` → `EN_CAMINO` (accept), `BUSCANDO_TALLER` (reject)
- `EN_CAMINO` → `EN_ATENCION`
- `EN_ATENCION` → `FINALIZADO`
- `FINALIZADO` → `PAGADO`
- Cancel allowed only from `PENDIENTE` / `BUSCANDO_TALLER`.

The DB trigger `fn_incidente_estado` auto-writes `incidente_estado_historial` and stamps `asignado_at/aceptado_at/atendido_at/finalizado_at`. The backend only sets `estado`.

## 6. Environment variables (single source)

`backend/.env`:

```
DATABASE_URL=postgresql+psycopg2://postgres:postgres@localhost:5432/emergencias_db
DATABASE_URL_ADMIN=postgresql+psycopg2://app_admin:postgres@localhost:5432/emergencias_db  # BYPASSRLS role
JWT_SECRET=replace-with-64-char-random
JWT_ALGORITHM=HS256
ACCESS_TOKEN_MINUTES=120
REDIS_URL=redis://localhost:6379/0
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
FCM_SERVER_KEY=xxx
OPENAI_API_KEY=sk-xxx
MAPS_API_KEY=xxx
CORS_ORIGINS=http://localhost:4200,http://localhost:8100
# --- AWS / Floci (see 07_AWS_FLOCI.md) ---
AWS_ENDPOINT_URL=http://localhost:4566   # Floci locally; leave EMPTY in real AWS
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test                    # "test" for Floci; IAM task role in AWS
AWS_SECRET_ACCESS_KEY=test
S3_BUCKET_EVIDENCIAS=emergencias-evidencias
SNS_TOPIC_PUSH=
```

`web/src/environments/environment.ts`:

```ts
export const environment = {
  production: false,
  apiUrl: 'http://localhost:8000',
  wsUrl: 'ws://localhost:8000',
};
```

Flutter `lib/core/config.dart`:

```dart
class Config {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');
  static const wsUrl  = String.fromEnvironment('WS_URL',  defaultValue: 'ws://10.0.2.2:8000');
}
// run: flutter run --dart-define=API_URL=http://<host>:8000
```

## 7. docker-compose.yml (root)

```yaml
services:
  floci:                       # AWS emulator (S3, SNS, ECR/ECS, ...). See 07_AWS_FLOCI.md
    image: floci/floci:latest
    ports: ["4566:4566"]
    volumes: ["./.floci-data:/app/data"]
  db:
    image: postgres:16
    environment:
      POSTGRES_DB: emergencias_db
      POSTGRES_PASSWORD: postgres
    ports: ["5432:5432"]
    volumes:
      - ./database:/docker-entrypoint-initdb.d   # runs 01,02,03 alphabetically on first boot
      - pgdata:/var/lib/postgresql/data
  redis:
    image: redis:7
    ports: ["6379:6379"]
volumes:
  pgdata:
```

> In real AWS, `db` → **RDS PostgreSQL**, `redis` → **ElastiCache**, `floci` services → the real
> AWS services. Provision local Floci resources with `bash infra/floci-init.sh` (doc 07 §3.3).

Bring it up and verify the DB before writing any backend code:

```bash
docker compose up -d
docker compose exec db psql -U postgres -d emergencias_db -c "SELECT tenant_id, total_incidentes, prom_min_asignacion FROM emergencias.mv_kpi_resumen_tenant;"
```

Expected: two rows (Auxilio Norte, RutaSegura) with non-null averages → DB layer OK.

## 8. Create the BYPASSRLS admin role (run once)

The platform admin must see all tenants. Create a dedicated DB role:

```sql
-- run as postgres
CREATE ROLE app_admin LOGIN PASSWORD 'postgres' BYPASSRLS;
GRANT ALL ON SCHEMA emergencias TO app_admin;
GRANT ALL ON ALL TABLES IN SCHEMA emergencias TO app_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA emergencias TO app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA emergencias GRANT ALL ON TABLES TO app_admin;
```

Backend uses `DATABASE_URL` (RLS-enforced) for normal users and `DATABASE_URL_ADMIN` only when the JWT role is `ADMIN_PLATAFORMA`.

## 9. Definition of Done (per feature) — used in doc 06

A feature is "done" only when: endpoint(s) implemented + client UI wired + the acceptance test in `06_TESTING_DEPLOY.md` passes + a screenshot is saved in `docs/screenshots/`.