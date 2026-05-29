# 06 — Testing, Deployment & Submission

## 1. Local run order
```bash
# 1. infra: Floci (AWS emulator) + DB (auto-loads database/01,02,03) + Redis
docker compose up -d
bash infra/floci-init.sh        # create S3 bucket + SNS topic on Floci (doc 07 §3.3)
# 2. backend
cd backend && .venv\Scripts\activate && uvicorn app.main:app --reload   # http://localhost:8000/docs
# 3. web
cd web && ng serve                                                      # http://localhost:4200
# 4. mobile
cd mobile && flutter run --dart-define=API_URL=http://10.0.2.2:8000 --dart-define=WS_URL=ws://10.0.2.2:8000
```

## 2. Acceptance tests for the 4 mandatory features

### 2.1 Multi-tenant isolation (highest priority)
SQL proof:
```sql
SET app.current_tenant = '22222222-0000-0000-0000-000000000001';  -- Auxilio Norte
SELECT count(*) FROM emergencias.incidente;     -- only its rows
SET app.current_tenant = '22222222-0000-0000-0000-000000000002';  -- RutaSegura
SELECT count(*) FROM emergencias.incidente;     -- different set
```
API proof: login as `ana@auxilionorte.com` and `beto@rutasegura.com`; `GET /incidentes` returns disjoint sets. A forged request with another tenant's id in the body must NOT leak data (server ignores body tenant; RLS blocks).

### 2.2 Offline sync (no duplicates)
```bash
# simulate: POST the same batch twice
curl -X POST localhost:8000/sync -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d @batch.json
curl -X POST localhost:8000/sync -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d @batch.json
# 1st: status CREATED, 2nd: status DUPLICATE/UPDATED. Row count unchanged.
psql ... -c "SELECT count(*) FROM emergencias.incidente WHERE external_id IS NOT NULL;"
```
Flutter test: airplane mode → create 2 → reconnect → both SINCRONIZADO, server has 2.

### 2.3 WebSocket broadcast
- Terminal A: `websocat "ws://localhost:8000/ws/<tenant>/<incident>?token=<JWT>"` → receives `STATE_SNAPSHOT`.
- Terminal B: `PATCH /incidentes/<incident>/estado {estado:"EN_CAMINO"}` → Terminal A receives `STATUS_CHANGED` within ~1s.
- Cross-tenant: connect with tenant A token to tenant B incident → closed `4403`.

### 2.4 KPI calculation
```sql
SELECT emergencias.refrescar_kpis();
SELECT * FROM emergencias.mv_kpi_resumen_tenant;        -- avg times match seed
SELECT * FROM emergencias.mv_kpi_sla;                   -- % compliance per type
```
API: `GET /kpis/resumen`, `/kpis/por-tipo`, `/kpis/sla` return the same numbers; web charts render them.

### 2.5 Payment + 10% commission
- Stripe test card `4242 4242 4242 4242`, any future expiry, any CVC.
- After webhook: `SELECT monto, comision_plataforma, monto_taller FROM emergencias.pago ORDER BY created_at DESC LIMIT 1;`
  → `comision_plataforma = monto * 0.10`, incident `PAGADO`, a `factura` row exists.

## 3. Backend automated tests (`backend/tests/`)
```python
# tests/test_auth_tenant.py
def test_login_returns_tenant(client):
    r = client.post("/auth/login", json={"email":"ana@auxilionorte.com","password":"password123"})
    assert r.status_code == 200 and r.json()["tenant_id"]

def test_tenant_isolation(client, login):
    h_a = login("ana@auxilionorte.com"); h_b = login("beto@rutasegura.com")
    ids_a = {i["id"] for i in client.get("/incidentes", headers=h_a).json()["items"]}
    ids_b = {i["id"] for i in client.get("/incidentes", headers=h_b).json()["items"]}
    assert ids_a.isdisjoint(ids_b)

def test_sync_idempotent(client, login_driver):
    body = {...}  # one incident with external_id
    r1 = client.post("/sync", json=body, headers=login_driver)
    r2 = client.post("/sync", json=body, headers=login_driver)
    assert r1.json()["results"][0]["status"] == "CREATED"
    assert r2.json()["results"][0]["status"] in ("DUPLICATE","UPDATED")
```
Run: `pytest -q`. Use a throwaway Postgres (the docker one) seeded with `03_seed.sql`.

## 4. Postman collection (for the live demo)
Create `docs/postman_collection.json` with folders: Auth, Incidents, Assignment, Payments, KPIs. Set a collection variable `{{jwt}}` populated by the Login request's test script:
```js
pm.collectionVariables.set("jwt", pm.response.json().access_token);
```

## 5. Deployment — AWS (emulated locally with Floci)

> Cloud target is **AWS**. Develop/test against **Floci** (`AWS_ENDPOINT_URL=http://localhost:4566`),
> then deploy the same artifacts to real AWS by **unsetting** `AWS_ENDPOINT_URL`.
> **Full step-by-step (RDS, ElastiCache, S3, ECR, ECS Fargate, CloudFront, EventBridge) is in
> [`07_AWS_FLOCI.md`](07_AWS_FLOCI.md).** Summary:

| Layer | AWS service | Command ref |
|-------|-------------|-------------|
| Backend image | ECR | `docker push <acct>.dkr.ecr...:latest` (doc 07 §5.4) |
| Backend runtime | ECS Fargate + ALB | `aws ecs create-service ...` (doc 07 §5.5) — public URL = ALB DNS |
| Database | RDS PostgreSQL 16 | run `database/01,02,03.sql` + create `app_admin BYPASSRLS` (doc 07 §5.1) |
| Cache / WS pub-sub | ElastiCache Redis | `REDIS_URL=redis://<elasticache>:6379/0` (doc 07 §5.2) |
| Evidence files | S3 | bucket `emergencias-evidencias` (doc 07 §5.3) |
| Web (Angular) | S3 + CloudFront | `ng build` → `aws s3 sync dist/web/browser s3://emergencias-web` (doc 07 §5.7) |
| Mobile (APK) | S3 / Drive + QR | `flutter build apk` against the ALB URL (doc 07 §5.8) |
| KPI refresh | EventBridge + Lambda **or** `pg_cron` on RDS | doc 07 §5.6 |

`backend/Dockerfile` (used for ECR/ECS and for local Floci ECS):
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8000"]
```

**Rehearse on Floci first** (doc 07 §6): `docker compose up -d` (starts Floci), `bash infra/floci-init.sh`,
then run every `aws ...` command with `--endpoint-url $AWS_ENDPOINT_URL`. When it works on Floci,
the identical commands without the flag target real AWS.

KPI refresh in production: enable `pg_cron` on the RDS parameter group, or schedule a Lambda via
EventBridge (doc 07 §5.6). The dashboard "Refresh" button (`POST /kpis/refresh`) is the manual fallback.

## 6. Final submission package (PDF + URL + QR)

`docs/` PDF must contain, in order:
1. Cover (project, author, course, date).
2. Part I — Theoretical foundation (from `PerfilDelProyecto.md`).
3. Part II — Requirements: actors, 48 use cases, prioritization, 5 cycles (`CapturaDeRequisitos.md`, `DetalleCasosDeUso.md`).
4. Analysis: packages, collaboration diagrams (`Analisis.md`).
5. **Design**: ER diagram (export from DBeaver or recreate in dbdiagram.io from `database/01_schema.sql`), architecture diagram annotated with **AWS services** (ECS Fargate, RDS, ElastiCache, S3, CloudFront, ALB, EventBridge — doc 07 §7), state machine (doc 00 §5). Note that local dev uses **Floci** to emulate AWS.
6. **Implementation evidence**: screenshots of each mandatory feature working:
   - tenant A vs tenant B (isolation),
   - offline pending → synced,
   - live WS status + map marker,
   - KPI dashboard charts,
   - payment with 10% commission row.
7. **Deployment**: URLs (API `/docs`, web app, APK), env var list (no secrets).
8. **QR codes**: web app URL, APK download.
9. Demo video link (3–5 min, screen recording of the 4 mandatory features).

### Checklist before submitting
- [ ] `docker compose up` boots Floci + DB (seed) + Redis; KPIs return rows.
- [ ] `bash infra/floci-init.sh` provisions S3/SNS on Floci; evidence upload works against Floci S3.
- [ ] All 4 mandatory acceptance tests pass.
- [ ] AWS deploy rehearsed on Floci (same `aws` commands with `--endpoint-url`), then run on real AWS.
- [ ] Backend on ECS Fargate, ALB `/health` + `/docs` reachable publicly.
- [ ] RDS loaded with schema + `app_admin BYPASSRLS`; ElastiCache reachable; S3 bucket has evidence objects.
- [ ] Web on S3+CloudFront, points to the ALB API (`https`/`wss`).
- [ ] APK built against the ALB URL; QR works on a phone.
- [ ] PDF complete with screenshots + diagrams (incl. AWS architecture) + URLs + QR.
- [ ] Demo video recorded and linked.
