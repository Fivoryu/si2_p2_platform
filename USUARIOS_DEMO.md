# Usuarios de demostración

Referencia de credenciales para desarrollo y pruebas. Todos los usuarios listados usan la misma contraseña:

| Campo | Valor |
|-------|-------|
| **Contraseña** | `password123` |

> Hash bcrypt de ejemplo. **Reemplazar en producción.**

---

## Fuentes SQL

| Archivo | Descripción |
|---------|-------------|
| `database/03_seed.sql` | Seed principal: tenants, usuarios base, talleres, incidentes y KPIs |
| `database/seeds/usuario_conductor_movil.sql` | Conductor adicional para pruebas móviles (idempotente) |

Para cargar el usuario móvil sobre una BD ya existente:

```powershell
.\scripts\seed-usuario.ps1
```

---

## Tenants

| ID | Nombre | Dominio | Plan |
|----|--------|---------|------|
| `22222222-0000-0000-0000-000000000000` | Público | — | básico |
| `22222222-0000-0000-0000-000000000001` | Auxilio Norte | auxilionorte.com | profesional |
| `22222222-0000-0000-0000-000000000002` | RutaSegura | rutasegura.com | enterprise |

---

## Usuarios (`database/03_seed.sql`)

### Plataforma (sin tenant)

| Rol | Nombre | Email | Teléfono | ID |
|-----|--------|-------|----------|-----|
| `ADMIN_PLATAFORMA` | Super Admin | `admin@plataforma.com` | 70000000 | `44444444-0000-0000-0000-0000000000a0` |

### Auxilio Norte

| Rol | Nombre | Email | Teléfono | ID |
|-----|--------|-------|----------|-----|
| `ADMIN_TENANT` | Ana Gerente | `ana@auxilionorte.com` | 71000001 | `44444444-0000-0000-0000-0000000000a1` |
| `CONDUCTOR` | Carlos Pérez | `carlos@mail.com` | 71000002 | `44444444-0000-0000-0000-0000000000a2` |
| `CONDUCTOR` | Diana López | `diana@mail.com` | 71000003 | `44444444-0000-0000-0000-0000000000a3` |
| `TALLER` | Taller Centro | `centro@auxilionorte.com` | 71000004 | `44444444-0000-0000-0000-0000000000a4` |
| `TALLER` | Taller Sur | `sur@auxilionorte.com` | 71000005 | `44444444-0000-0000-0000-0000000000a5` |
| `TECNICO` | Luis Mecánico | `luis@auxilionorte.com` | 71000006 | `44444444-0000-0000-0000-0000000000a6` |

**Vehículos de conductores (Auxilio Norte)**

| Conductor | Placa | Marca / modelo | Año |
|-----------|-------|----------------|-----|
| Carlos Pérez | ABC123 | Toyota Corolla | 2018 |
| Diana López | XYZ789 | Nissan Versa | 2020 |

### RutaSegura

| Rol | Nombre | Email | Teléfono | ID |
|-----|--------|-------|----------|-----|
| `ADMIN_TENANT` | Beto Jefe | `beto@rutasegura.com` | 72000001 | `44444444-0000-0000-0000-0000000000b1` |
| `CONDUCTOR` | Elena Ruiz | `elena@mail.com` | 72000002 | `44444444-0000-0000-0000-0000000000b2` |
| `TALLER` | Taller Rápido | `rapido@rutasegura.com` | 72000004 | `44444444-0000-0000-0000-0000000000b4` |

**Vehículo de conductor (RutaSegura)**

| Conductor | Placa | Marca / modelo | Año |
|-----------|-------|----------------|-----|
| Elena Ruiz | RUT456 | Volkswagen Gol | 2019 |

---

## Usuarios (`database/seeds/`)

### `usuario_conductor_movil.sql`

Conductor pensado para la app móvil. Se puede ejecutar varias veces sin duplicar datos (`ON CONFLICT`).

| Rol | Nombre | Email | Teléfono | Tenant | ID |
|-----|--------|-------|----------|--------|-----|
| `CONDUCTOR` | Usuario Demo Móvil | `demo.movil@mail.com` | 71999999 | Auxilio Norte | `44444444-0000-0000-0000-0000000000d1` |

**Vehículo asociado**

| Placa | Marca / modelo | Año | Color | Combustible |
|-------|----------------|-----|-------|-------------|
| DEMO01 | Hyundai Tucson | 2022 | Azul | gasolina |

---

## Resumen rápido por rol

| Rol | Emails |
|-----|--------|
| Admin plataforma | `admin@plataforma.com` |
| Admin tenant | `ana@auxilionorte.com`, `beto@rutasegura.com` |
| Conductor | `carlos@mail.com`, `diana@mail.com`, `elena@mail.com`, `demo.movil@mail.com` |
| Taller | `centro@auxilionorte.com`, `sur@auxilionorte.com`, `rapido@rutasegura.com` |
| Técnico | `luis@auxilionorte.com` |

---

## Notas

- Los técnicos **Pedro Llantas** y **Mario Motor** existen en `tecnico` pero **no** tienen usuario de login asociado (`usuario_id` es `NULL`).
- El usuario `demo.movil@mail.com` no está en `03_seed.sql`; hay que aplicar `database/seeds/usuario_conductor_movil.sql` o el script `scripts/seed-usuario.ps1`.
