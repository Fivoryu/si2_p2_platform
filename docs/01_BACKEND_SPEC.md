# 01 — Backend Spec (FastAPI)

> Implement in the order of section 4. Every protected endpoint requires a JWT and is tenant-scoped via RLS (doc 00 §4).

## 1. Dependencies — `backend/requirements.txt`

```
fastapi==0.115.*
uvicorn[standard]==0.32.*
sqlalchemy==2.0.*
psycopg2-binary==2.9.*
pydantic==2.9.*
pydantic-settings==2.6.*
python-jose[cryptography]==3.3.*
passlib[bcrypt]==1.7.*
python-multipart==0.0.*
redis==5.2.*
httpx==0.27.*
stripe==11.*
boto3==1.35.*          # AWS SDK (S3 evidence, SNS); works against Floci locally
pytest==8.*
```

## 2. Core files

### 2.1 `app/core/config.py`
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    database_url_admin: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 120
    redis_url: str = "redis://localhost:6379/0"
    stripe_secret_key: str = ""
    stripe_webhook_secret: str = ""
    fcm_server_key: str = ""
    openai_api_key: str = ""
    maps_api_key: str = ""
    cors_origins: str = "http://localhost:4200"

    class Config:
        env_file = ".env"

settings = Settings()
```
> Add the AWS/Floci settings fields (`aws_region`, `aws_endpoint_url`, `s3_bucket_evidencias`, …)
> and the `app/core/aws.py` client factory from `07_AWS_FLOCI.md` §4.2–§4.3.

### 2.2 `app/core/db.py` — engines + tenant-scoped session (THE multi-tenant core)
```python
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from .config import settings

engine       = create_engine(settings.database_url, pool_pre_ping=True)        # RLS enforced
engine_admin = create_engine(settings.database_url_admin, pool_pre_ping=True)  # BYPASSRLS

SessionLocal      = sessionmaker(bind=engine, autoflush=False, autocommit=False)
SessionLocalAdmin = sessionmaker(bind=engine_admin, autoflush=False, autocommit=False)

def make_session(tenant_id: str | None, is_platform_admin: bool):
    """Yield a DB session with the tenant set for RLS.
       Platform admin uses the BYPASSRLS engine."""
    if is_platform_admin:
        db = SessionLocalAdmin()
    else:
        db = SessionLocal()
        # Set tenant for Row Level Security for this connection/transaction.
        db.execute(text("SELECT set_config('app.current_tenant', :tid, true)"),
                   {"tid": tenant_id or ""})
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
```

### 2.3 `app/core/security.py` — passwords + JWT
```python
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext
from .config import settings

pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(p: str) -> str: return pwd.hash(p)
def verify_password(p: str, h: str) -> bool: return pwd.verify(p, h)

def create_access_token(*, sub: str, rol: str, tenant: str | None, jti: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": sub, "rol": rol, "tenant": tenant, "jti": jti,
        "iat": now, "exp": now + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as e:
        raise ValueError("invalid token") from e
```

### 2.4 `app/core/deps.py` — auth dependency + role guard + DB
```python
import uuid
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import text
from .security import decode_token
from .db import make_session

bearer = HTTPBearer()

class CurrentUser:
    def __init__(self, id, rol, tenant):
        self.id, self.rol, self.tenant = id, rol, tenant
    @property
    def is_platform_admin(self): return self.rol == "ADMIN_PLATAFORMA"

def get_current_user(cred: HTTPAuthorizationCredentials = Depends(bearer)) -> CurrentUser:
    try:
        claims = decode_token(cred.credentials)
    except ValueError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    return CurrentUser(claims["sub"], claims["rol"], claims.get("tenant"))

def get_db(user: CurrentUser = Depends(get_current_user)):
    # Reject revoked tokens could be added here (check token_revocado by jti).
    yield from make_session(user.tenant, user.is_platform_admin)

def require_roles(*roles):
    def _guard(user: CurrentUser = Depends(get_current_user)):
        if user.rol not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden for role")
        return user
    return _guard
```

### 2.5 `app/main.py`
```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .core.config import settings
from .api import auth, usuarios, vehiculos, talleres, tecnicos, incidentes, \
                  asignaciones, cotizaciones, pagos, kpi, tenants, sync
from .ws import routes as ws_routes

app = FastAPI(title="Emergencias Vehiculares API", version="1.0")
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins.split(","),
                   allow_methods=["*"], allow_headers=["*"], allow_credentials=True)

@app.get("/health")
def health(): return {"status": "ok"}

for r in (auth, usuarios, vehiculos, talleres, tecnicos, incidentes,
          asignaciones, cotizaciones, pagos, kpi, tenants, sync):
    app.include_router(r.router)
app.include_router(ws_routes.router)
```

## 3. Models & schemas approach

You can either write SQLAlchemy ORM classes mirroring the tables, or use **SQLAlchemy Core + raw SQL** (faster to ship). Recommended: lightweight ORM with `__table_args__ = {"schema": "emergencias"}`. Minimum models to define: `Usuario, Vehiculo, Taller, Tecnico, TallerServicio, Tarifa, TipoIncidente, Incidente, Evidencia, ClasificacionIA, TallerCandidato, Asignacion, Cotizacion, Pago, Factura, Notificacion, SlaConfig, SyncMapping, Tenant, Plan`.

Pydantic DTO pattern (example `schemas/incidente.py`):
```python
from pydantic import BaseModel
from datetime import datetime
import uuid

class IncidenteCreate(BaseModel):
    vehiculo_id: uuid.UUID
    descripcion: str | None = None
    latitud: float | None = None
    longitud: float | None = None
    direccion: str | None = None
    external_id: uuid.UUID | None = None   # id_local for offline

class IncidenteOut(BaseModel):
    id: uuid.UUID
    estado: str
    prioridad: str
    tipo_incidente_id: uuid.UUID | None
    latitud: float | None
    longitud: float | None
    resumen_ia: str | None
    reportado_at: datetime
    class Config: from_attributes = True
```

> **Rule:** never accept `tenant_id` from the client. On insert, set `tenant_id = current_user.tenant`.

---

## 4. REST API contract (build in this order)

Base URL `/`. All times ISO-8601. `🔒` = requires JWT.

### 4.1 Auth — `app/api/auth.py`  (CU-01..CU-04)

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/auth/register` | `{nombre,email,telefono,password}` | `201 {id}` — creates `CONDUCTOR` in public tenant `22222222-...0000` |
| POST | `/auth/login` | `{email,password,tenant_id?}` | `200 {access_token, token_type, rol, tenant_id, usuario_id}` |
| POST | `/auth/logout` 🔒 | – | `204` — insert `jti` into `token_revocado` |
| POST | `/auth/forgot-password` | `{email}` | `202` — create `token_recuperacion`, email link (mock OK) |
| POST | `/auth/reset-password` | `{token,new_password}` | `204` |

Login logic:
```python
# validate user by email (+ tenant if provided), verify_password,
# reject if not activo (403 "user disabled"),
# jti = uuid4(); token = create_access_token(sub=user.id, rol=user.rol, tenant=user.tenant_id, jti=jti)
# update ultimo_acceso; audit LOGIN
```

### 4.2 Users & profile — `usuarios.py` (CU-06)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/usuarios/me` 🔒 | current profile |
| PATCH | `/usuarios/me` 🔒 | update nombre/telefono/email/password |

### 4.3 Vehicles — `vehiculos.py` (CU-05)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/vehiculos` 🔒 | conductor's vehicles |
| POST | `/vehiculos` 🔒 | `{placa,marca,modelo,anio,color,tipo_combustible}`; 409 if placa dup for user |
| PATCH | `/vehiculos/{id}` 🔒 | |
| DELETE | `/vehiculos/{id}` 🔒 | |

### 4.4 Workshops & technicians — `talleres.py`, `tecnicos.py` (CU-07..CU-09)
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/talleres` 🔒 | ADMIN_TENANT | create + create TALLER user with temp password |
| GET | `/talleres` 🔒 | any tenant user | list tenant workshops |
| PATCH | `/talleres/{id}/disponibilidad` 🔒 | TALLER | `{disponible, capacidad_max}` |
| POST | `/talleres/{id}/servicios` 🔒 | ADMIN_TENANT/TALLER | set offered `tipo_incidente` ids |
| POST | `/tecnicos` 🔒 | ADMIN_TENANT/TALLER | `{taller_id,nombre,telefono,especialidad}` |
| GET | `/tecnicos` 🔒 | | |

### 4.5 Incidents — `incidentes.py` (CU-10..CU-16, CU-36)
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/incidentes` 🔒 | CONDUCTOR | create (PENDIENTE) → enqueue AI (BackgroundTasks) |
| GET | `/incidentes` 🔒 | any | tenant-filtered, `?estado=&limit=&offset=`; CONDUCTOR sees own, TALLER sees assigned |
| GET | `/incidentes/{id}` 🔒 | | full detail incl. evidences, classification, assignment |
| POST | `/incidentes/{id}/evidencias` 🔒 | CONDUCTOR | multipart: `tipo`, `file`/`texto` → upload file to **S3**, store object key in `evidencia.url` (doc 07 §4.4) |
| PATCH | `/incidentes/{id}/estado` 🔒 | TALLER/SYSTEM | `{estado, comentario?}`; validate transition (doc 00 §5); broadcast WS + push |
| POST | `/incidentes/{id}/cancelar` 🔒 | CONDUCTOR | `{motivo?}`; only PENDIENTE/BUSCANDO_TALLER |
| GET | `/incidentes/{id}/historial` 🔒 | | from `incidente_estado_historial` |

`POST /incidentes` response `201`:
```json
{ "id":"...", "estado":"PENDIENTE", "prioridad":"INCIERTA", "reportado_at":"2026-06-01T14:00:00Z" }
```

### 4.6 Assignment & quotes — `asignaciones.py`, `cotizaciones.py` (CU-22..CU-29)
| Method | Path | Role | Notes |
|--------|------|------|-------|
| POST | `/incidentes/{id}/buscar-talleres` 🔒 | SYSTEM/CONDUCTOR | runs engine → returns candidates (doc 03) |
| POST | `/incidentes/{id}/asignar` 🔒 | SYSTEM | auto-assign best; sets TALLER_ASIGNADO; notify |
| POST | `/incidentes/{id}/asignar-manual` 🔒 | CONDUCTOR | `{taller_id}` (CU-29) |
| POST | `/asignaciones/{id}/aceptar` 🔒 | TALLER | `{tecnico_id?}` → EN_CAMINO; broadcast |
| POST | `/asignaciones/{id}/rechazar` 🔒 | TALLER | `{motivo?}` → reassign next candidate |
| POST | `/incidentes/{id}/cotizaciones` 🔒 | TALLER/SYSTEM | `{monto,detalle,origen}` |
| POST | `/cotizaciones/{id}/aceptar` 🔒 | CONDUCTOR | |

### 4.7 Payments — `pagos.py` (CU-30..CU-32)
| Method | Path | Notes |
|--------|------|-------|
| POST | `/pagos/intent` 🔒 | `{incidente_id, cotizacion_id}` → Stripe PaymentIntent → `{client_secret, pago_id}` |
| POST | `/pagos/webhook` | Stripe webhook (no JWT, verify signature) → on success: insert `pago` (trigger computes 10%), set incident PAGADO, create `factura` |
| GET | `/pagos/comisiones` 🔒 | TALLER/ADT | from `mv_kpi_comisiones` (CU-31) |
| GET | `/pagos/{id}/factura` 🔒 | returns factura url (CU-32) |

### 4.8 KPIs — `kpi.py` (CU-42..CU-45)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/kpis/resumen` 🔒 | `mv_kpi_resumen_tenant` |
| GET | `/kpis/por-tipo` 🔒 | `mv_kpi_incidentes_por_tipo` |
| GET | `/kpis/talleres` 🔒 | `mv_kpi_talleres_eficientes` |
| GET | `/kpis/zonas` 🔒 | `mv_kpi_zonas` |
| GET | `/kpis/sla` 🔒 | `mv_kpi_sla` |
| GET | `/kpis/comisiones` 🔒 | `mv_kpi_comisiones` |
| POST | `/kpis/refresh` 🔒 | ADM/ADT → `SELECT emergencias.refrescar_kpis()` |
| GET/POST/PATCH | `/sla` 🔒 | ADM CRUD `sla_config` (CU-45) |

All KPI endpoints: for `ADMIN_PLATAFORMA` accept `?tenant_id=` (uses admin engine); for `ADMIN_TENANT` force their own tenant (CU-43).

KPI handler example:
```python
@router.get("/kpis/resumen")
def kpis_resumen(tenant_id: str | None = None,
                 user=Depends(get_current_user), db=Depends(get_db)):
    tid = tenant_id if user.is_platform_admin else user.tenant
    rows = db.execute(text("""
        SELECT * FROM emergencias.mv_kpi_resumen_tenant
        WHERE (:tid IS NULL OR tenant_id = :tid)
    """), {"tid": tid}).mappings().all()
    return [dict(r) for r in rows]
```

### 4.9 Tenants (platform admin) — `tenants.py` (CU-46..CU-48)
| Method | Path | Notes |
|--------|------|-------|
| POST | `/tenants` 🔒 | ADM | `{nombre,dominio,plan_id}` |
| POST | `/tenants/{id}/admin` 🔒 | ADM | `{email,nombre}` → create/assign ADMIN_TENANT |
| PATCH | `/tenants/{id}/plan` 🔒 | ADM | `{plan_id}` (enforce plan limits on workshop/tech creation) |

### 4.10 Sync — `sync.py` (CU-38..CU-41) — full spec in doc 03.

---

## 5. Background AI trigger on incident creation
```python
from fastapi import BackgroundTasks
@router.post("/incidentes", status_code=201)
def crear_incidente(body: IncidenteCreate, bg: BackgroundTasks,
                    user=Depends(require_roles("CONDUCTOR")), db=Depends(get_db)):
    inc = Incidente(tenant_id=user.tenant, conductor_id=user.id, **body.model_dump(exclude_none=True))
    db.add(inc); db.flush()
    bg.add_task(run_ai_pipeline, str(inc.id), user.tenant)  # doc 03
    return IncidenteOut.model_validate(inc)
```

## 6. Audit & token revocation (quick wins)
- On login/logout/payment, insert into `auditoria` (`accion`, `entidad`, `entidad_id`, `detalle` JSONB).
- In `get_current_user`, optionally check `token_revocado` by `jti` and reject (CU-02).

## 7. Acceptance (this layer) — see doc 06 for full tests
- `GET /health` → 200.
- Login as `ana@auxilionorte.com` / `password123` returns a JWT whose `tenant` = Auxilio Norte id.
- `GET /incidentes` as that user returns only Auxilio Norte incidents (RLS proof).
