-- =====================================================================
-- 11. RBAC granular: tablas rol, permisos y asignaciones
-- =====================================================================
-- Extraído de database.sql §3.30–3.33.
-- Aplica después de 01_schema.sql..10_advanced_tracking_pricing_kpis.sql.
-- =====================================================================

-- 1. Tablas de catálogo RBAC
CREATE TABLE IF NOT EXISTS emergencias.rol (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         REFERENCES emergencias.tenant(id) ON DELETE CASCADE,
    nombre      VARCHAR(80)  NOT NULL,
    descripcion TEXT,
    es_base     BOOLEAN      NOT NULL DEFAULT FALSE,
    base_rol    emergencias.rol_usuario,
    activo      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_rol_tenant_nombre UNIQUE (tenant_id, nombre)
);

CREATE TABLE IF NOT EXISTS emergencias.rol_permiso_entidad (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rol_id           UUID        NOT NULL REFERENCES emergencias.rol(id) ON DELETE CASCADE,
    entidad          VARCHAR(60) NOT NULL,
    puede_crear      BOOLEAN     NOT NULL DEFAULT FALSE,
    puede_leer       BOOLEAN     NOT NULL DEFAULT FALSE,
    puede_actualizar BOOLEAN     NOT NULL DEFAULT FALSE,
    puede_eliminar   BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_rol_permiso_entidad UNIQUE (rol_id, entidad)
);

CREATE TABLE IF NOT EXISTS emergencias.rol_permiso_columna (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rol_id       UUID        NOT NULL REFERENCES emergencias.rol(id) ON DELETE CASCADE,
    entidad      VARCHAR(60) NOT NULL,
    columna      VARCHAR(60) NOT NULL,
    puede_ver    BOOLEAN     NOT NULL DEFAULT TRUE,
    puede_editar BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_rol_permiso_columna UNIQUE (rol_id, entidad, columna)
);

CREATE TABLE IF NOT EXISTS emergencias.usuario_rol (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id   UUID        NOT NULL REFERENCES emergencias.usuario(id) ON DELETE CASCADE,
    rol_id       UUID        NOT NULL REFERENCES emergencias.rol(id) ON DELETE CASCADE,
    asignado_por UUID        REFERENCES emergencias.usuario(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_usuario_rol UNIQUE (usuario_id, rol_id)
);

-- 2. Roles base para cada actor del sistema
-- Tenant Auxilio Norte (22222222-0000-0000-0000-000000000001)
INSERT INTO emergencias.rol (id, tenant_id, nombre, descripcion, es_base, base_rol)
VALUES
 ('99999999-0000-0000-0000-000000000001', NULL,
  'Administrador Plataforma', 'Superusuario global', TRUE, 'ADMIN_PLATAFORMA')
ON CONFLICT DO NOTHING;

INSERT INTO emergencias.rol (id, tenant_id, nombre, descripcion, es_base, base_rol)
VALUES
 ('99999999-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001',
  'Administrador Tenant', 'ADT Auxilio Norte', TRUE, 'ADMIN_TENANT'),
 ('99999999-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000001',
  'Conductor', 'Conductor Auxilio Norte', TRUE, 'CONDUCTOR'),
 ('99999999-0000-0000-0000-000000000004', '22222222-0000-0000-0000-000000000001',
  'Taller', 'Taller Auxilio Norte', TRUE, 'TALLER'),
 ('99999999-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000001',
  'Técnico', 'Técnico Auxilio Norte', TRUE, 'TECNICO')
ON CONFLICT DO NOTHING;

-- Tenant RutaSegura (22222222-0000-0000-0000-000000000002)
INSERT INTO emergencias.rol (id, tenant_id, nombre, descripcion, es_base, base_rol)
VALUES
 ('99999999-0000-0000-0000-000000000006', '22222222-0000-0000-0000-000000000002',
  'Administrador Tenant', 'ADT RutaSegura', TRUE, 'ADMIN_TENANT'),
 ('99999999-0000-0000-0000-000000000007', '22222222-0000-0000-0000-000000000002',
  'Conductor', 'Conductor RutaSegura', TRUE, 'CONDUCTOR'),
 ('99999999-0000-0000-0000-000000000008', '22222222-0000-0000-0000-000000000002',
  'Taller', 'Taller RutaSegura', TRUE, 'TALLER')
ON CONFLICT DO NOTHING;

-- 3. Asignar usuarios a sus roles base
INSERT INTO emergencias.usuario_rol (usuario_id, rol_id)
VALUES
 ('44444444-0000-0000-0000-0000000000a0', '99999999-0000-0000-0000-000000000001'),
 ('44444444-0000-0000-0000-0000000000a1', '99999999-0000-0000-0000-000000000002'),
 ('44444444-0000-0000-0000-0000000000a2', '99999999-0000-0000-0000-000000000003'),
 ('44444444-0000-0000-0000-0000000000a3', '99999999-0000-0000-0000-000000000003'),
 ('44444444-0000-0000-0000-0000000000a4', '99999999-0000-0000-0000-000000000004'),
 ('44444444-0000-0000-0000-0000000000a5', '99999999-0000-0000-0000-000000000004'),
 ('44444444-0000-0000-0000-0000000000a6', '99999999-0000-0000-0000-000000000005'),
 ('44444444-0000-0000-0000-0000000000b1', '99999999-0000-0000-0000-000000000006'),
 ('44444444-0000-0000-0000-0000000000b2', '99999999-0000-0000-0000-000000000007'),
 ('44444444-0000-0000-0000-0000000000b4', '99999999-0000-0000-0000-000000000008')
ON CONFLICT DO NOTHING;

-- 4. RLS para tablas RBAC
-- Solo rol tiene tenant_id directo. Las demás heredan tenencia vía rol_id.
ALTER TABLE emergencias.rol ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY pol_rol_tenant ON emergencias.rol
        USING (tenant_id = emergencias.fn_current_tenant()
               OR emergencias.fn_current_tenant() IS NULL)
        WITH CHECK (tenant_id = emergencias.fn_current_tenant()
                   OR emergencias.fn_current_tenant() IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Para las tablas sin tenant_id directo, permitir todo (la seguridad
-- se delega en las FK a rol + la lógica de negocio).
ALTER TABLE emergencias.rol_permiso_entidad ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    CREATE POLICY pol_rpe_open ON emergencias.rol_permiso_entidad FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE emergencias.rol_permiso_columna ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    CREATE POLICY pol_rpc_open ON emergencias.rol_permiso_columna FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE emergencias.usuario_rol ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    CREATE POLICY pol_ur_open ON emergencias.usuario_rol FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 5. Índices
CREATE INDEX IF NOT EXISTS idx_rol_tenant       ON emergencias.rol(tenant_id);
CREATE INDEX IF NOT EXISTS idx_rol_base         ON emergencias.rol(es_base, base_rol) WHERE es_base;
CREATE INDEX IF NOT EXISTS idx_rol_permiso_ent  ON emergencias.rol_permiso_entidad(rol_id, entidad);
CREATE INDEX IF NOT EXISTS idx_rol_permiso_col  ON emergencias.rol_permiso_columna(rol_id, entidad);
CREATE INDEX IF NOT EXISTS idx_usuario_rol_usr  ON emergencias.usuario_rol(usuario_id);
