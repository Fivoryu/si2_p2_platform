# Base de Datos — Plataforma Inteligente de Atención de Emergencias Vehiculares

Modelo relacional **PostgreSQL 14+** para la plataforma SaaS **multi-tenant** descrita en
`PerfilDelProyecto.md`, `CapturaDeRequisitos.md`, `DetalleCasosDeUso.md` y `Analisis.md`.
Cubre los **48 casos de uso** (CU-01 a CU-48).

## Archivos

| Orden | Archivo | Contenido |
|-------|---------|-----------|
| 1 | `01_schema.sql` | Extensiones, tipos enumerados, tablas, índices, constraints, triggers y Row Level Security. |
| 2 | `02_views_kpi.sql` | Vista base de métricas + 6 vistas materializadas de KPIs y función de refresco. |
| 3 | `03_seed.sql` | Datos de demostración (2 tenants, usuarios, talleres, incidentes, pagos…). |

## Requisitos

- PostgreSQL 14 o superior.
- Extensiones (se crean automáticamente): `pgcrypto`, `citext`, `cube`, `earthdistance`.

## Instalación

### Opción A — con `psql`

```bash
createdb emergencias_db
psql -d emergencias_db -f database/01_schema.sql
psql -d emergencias_db -f database/02_views_kpi.sql
psql -d emergencias_db -f database/03_seed.sql
```

### Opción B — con Docker

```bash
docker run --name pg-emergencias -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
docker cp database pg-emergencias:/database
docker exec -u postgres pg-emergencias psql -c "CREATE DATABASE emergencias_db;"
docker exec -u postgres pg-emergencias psql -d emergencias_db -f /database/01_schema.sql
docker exec -u postgres pg-emergencias psql -d emergencias_db -f /database/02_views_kpi.sql
docker exec -u postgres pg-emergencias psql -d emergencias_db -f /database/03_seed.sql
```

Todos los objetos viven en el esquema `emergencias`.

## Decisiones de diseño (resumen senior)

- **Multi-tenancy por tabla compartida + `tenant_id`** (Análisis 4.2), reforzado con
  **Row Level Security**. El backend (FastAPI) ejecuta por request:

  ```sql
  SET app.current_tenant = '<tenant_id del JWT>';
  ```

  Las políticas RLS filtran automáticamente cada fila al tenant activo. El
  `ADMIN_PLATAFORMA` usa un rol con `BYPASSRLS` (o no fija la variable) para ver datos globales.

- **Claves primarias UUID**: facilitan el modo offline (`external_id` = `id_local` del
  dispositivo) y la resolución de conflictos sin duplicados (CU-38 a CU-41).

- **Catálogo `tipo_incidente`** como tabla (no enum) para permitir tarifas y SLA por tenant.

- **Bitácora de estados** (`incidente_estado_historial`) y **timestamps sellados por trigger**
  (`asignado_at`, `aceptado_at`, `atendido_at`, `finalizado_at`): son la fuente de verdad de
  los KPIs (CU-42).

- **Comisión del 10%** calculada por trigger en cada `pago` (CU-31), configurable por tenant.

- **KPIs como vistas materializadas** (Análisis 3.3), refrescables con:

  ```sql
  SELECT emergencias.refrescar_kpis();
  ```

## KPIs disponibles (CU-42, CU-43, CU-45)

| Vista materializada | KPI |
|---------------------|-----|
| `mv_kpi_resumen_tenant`      | Tiempo promedio de asignación/llegada, totales, % cancelación. |
| `mv_kpi_incidentes_por_tipo` | Incidentes por tipo (batería, llanta, motor, choque, otros). |
| `mv_kpi_talleres_eficientes` | Ranking de talleres por respuesta, finalización y rechazos. |
| `mv_kpi_zonas`               | Zonas geográficas con más incidentes. |
| `mv_kpi_sla`                 | % de cumplimiento de SLA por tipo de incidente. |
| `mv_kpi_comisiones`          | Total cobrado, comisión de plataforma y neto del taller. |

Todas incluyen `tenant_id`, por lo que el filtrado por tenant (CU-43) es un simple `WHERE`.

## Mapa Caso de Uso → Tablas

| Módulo (paquete) | Casos de uso | Tablas principales |
|------------------|--------------|--------------------|
| Usuarios y acceso | CU-01..CU-03 | `usuario`, `token_recuperacion`, `token_revocado` |
| Clientes y vehículos | CU-04..CU-09 | `usuario`, `vehiculo`, `taller`, `tecnico`, `taller_servicio` |
| Incidentes y evidencias | CU-10..CU-16 | `incidente`, `evidencia`, `incidente_estado_historial` |
| Procesamiento IA | CU-17..CU-21 | `clasificacion_ia`, `evidencia`, `tipo_incidente` |
| Asignación | CU-22..CU-29 | `taller_candidato`, `asignacion`, `cotizacion`, `tarifa` |
| Pagos y facturación | CU-30..CU-32 | `pago`, `factura` |
| Tiempo real | CU-33..CU-37 | `conexion_ws`, `ubicacion_tracking`, `notificacion` |
| Offline / sync | CU-38..CU-41 | `incidente.external_id`, `sync_mapping` |
| Analítica / KPIs | CU-42..CU-45 | vistas `mv_kpi_*`, `sla_config` |
| Multi-tenant | CU-46..CU-48 | `tenant`, `plan`, RLS |

## Credenciales de demostración

Usuarios sembrados con la contraseña `password123` (hash bcrypt de ejemplo, **reemplazar en producción**):

| Rol | Email |
|-----|-------|
| Admin plataforma | `admin@plataforma.com` |
| Admin tenant (Auxilio Norte) | `ana@auxilionorte.com` |
| Conductor | `carlos@mail.com` |
| Taller | `centro@auxilionorte.com` |
