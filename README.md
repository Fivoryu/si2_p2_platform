# Plataforma de Emergencias Vehiculares — Segunda Parcial

Sistema multi-tenant: **Flutter** (conductor), **Angular** (taller/admin), **FastAPI** + PostgreSQL + Redis.

> **Repos separados:** la raíz es el repo *plataforma* (Docker, BD, docs); `backend/`, `web/` y `mobile/` pueden ser repos independientes enlazados con Git submodules. Guía: [`docs/MULTI_REPO.md`](docs/MULTI_REPO.md).

## Requisitos

- **Docker Desktop** (recomendado: todo el stack con un comando)
- Flutter 3.16+ (app móvil en el host/emulador)

## 1. Todo en Docker (Floci + DB + Redis + API + Web)

```powershell
cd codigo_si2_p2
docker compose up -d --build
# o: .\scripts\docker-up.ps1
```

| Servicio | URL |
|----------|-----|
| **Web (Angular)** | http://localhost:4200 |
| **API (Swagger)** | http://localhost:8000/docs |
| **Floci (AWS local)** | http://localhost:4566 |
| **PostgreSQL** | localhost:5432 |
| **Redis** | localhost:6379 |

El servicio `floci-init` crea automáticamente los buckets S3 `emergencias-evidencias` y `emergencias-web` en Floci. La API sube evidencias a S3 vía `AWS_ENDPOINT_URL=http://floci:4566`; las URLs presignadas usan `http://localhost:4566` para el navegador.

Verificar KPIs:

```powershell
docker compose exec db psql -U postgres -d emergencias_db -c "SELECT tenant_id, total_incidentes FROM emergencias.mv_kpi_resumen_tenant;"
```

Probar Floci S3 desde el host:

```powershell
$env:AWS_ENDPOINT_URL="http://localhost:4566"
$env:AWS_ACCESS_KEY_ID="test"
$env:AWS_SECRET_ACCESS_KEY="test"
aws s3 ls --endpoint-url $env:AWS_ENDPOINT_URL
```

La primera vez carga `database/*.sql` (schema, seed, rol `app_admin`, FCM, passwords).

### Móvil contra Docker

```powershell
cd mobile
flutter run --dart-define=API_URL=http://10.0.2.2:8000 --dart-define=WS_URL=ws://10.0.2.2:8000
```

## 2. Backend local (sin Docker, opcional)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- Swagger: http://localhost:8000/docs
- Health: http://localhost:8000/health

### Usuarios de demo (contraseña `password123`)

| Email | Rol | Tenant |
|-------|-----|--------|
| carlos@mail.com | CONDUCTOR | Auxilio Norte |
| centro@auxilionorte.com | TALLER | Auxilio Norte |
| ana@auxilionorte.com | ADMIN_TENANT | Auxilio Norte |
| admin@plataforma.com | ADMIN_PLATAFORMA | — |

## 3. Web (Angular)

```powershell
cd web
npm install
npm start
```

http://localhost:4200

## 4. Mobile (Flutter)

```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000 --dart-define=WS_URL=ws://10.0.2.2:8000
```

## Funcionalidades obligatorias (parcial)

1. **Multi-tenant** — JWT + RLS (`SET app.current_tenant`)
2. **Tiempo real** — WebSocket `/ws/{tenant_id}/{incident_id}?token=`
3. **Offline + sync** — sqflite + `POST /sync` (idempotente)
4. **KPIs** — `/kpis/*` + dashboard ECharts

## Estructura

```
codigo_si2_p2/
├── database/     # SQL (listo)
├── backend/      # FastAPI
├── web/          # Angular
├── mobile/       # Flutter
├── docs/         # Especificaciones
└── docker-compose.yml
```

## 5. Deploy AWS (EC2 + Docker Compose)

Despliegue rápido del stack completo (backend, web, AcquireMock, OSRM, S3) en una instancia EC2:

```bash
# En EC2 (Amazon Linux 2023)
cp .env.aws.example .env.aws   # configurar PUBLIC_HOST y secretos
bash scripts/deploy-aws-ec2.sh
```

Guía completa: [`docs/08_AWS_EC2_DEPLOY.md`](docs/08_AWS_EC2_DEPLOY.md)

Push de los 4 repos:

```powershell
.\scripts\push-all-repos.ps1 -Message "feat: actualización"
```

Documentación detallada: `docs/00_OVERVIEW.md`, `PlanDeImplementacion.md`.
