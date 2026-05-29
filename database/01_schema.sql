-- =====================================================================
--  Plataforma Inteligente de Atención de Emergencias Vehiculares
--  Esquema relacional principal (PostgreSQL 14+)
-- ---------------------------------------------------------------------
--  Arquitectura : SaaS multi-tenant (tabla compartida con tenant_id)
--  Aislamiento  : tenant_id en cada tabla de negocio + Row Level Security
--  Identificadores: UUID (gen_random_uuid) para soportar sincronización
--                   offline (CU-38..CU-41) y escalado horizontal.
--  Cobertura    : CU-01 a CU-48 (ver DetalleCasosDeUso.md)
--
--  Orden de ejecución:
--    1) database/01_schema.sql      <-- este archivo
--    2) database/02_views_kpi.sql   <-- vistas y KPIs
--    3) database/03_seed.sql        <-- datos de demostración
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Extensiones y configuración base
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;      -- emails case-insensitive
CREATE EXTENSION IF NOT EXISTS cube;        -- requerido por earthdistance
CREATE EXTENSION IF NOT EXISTS earthdistance; -- cálculo de distancias geográficas

CREATE SCHEMA IF NOT EXISTS emergencias;
SET search_path TO emergencias, public;

-- =====================================================================
-- 1. TIPOS ENUMERADOS (dominios del negocio)
-- =====================================================================

-- Roles del sistema (CU-01, CU-04, CU-07, CU-08, CU-46, CU-47)
CREATE TYPE rol_usuario AS ENUM (
    'ADMIN_PLATAFORMA',  -- ADM: superusuario, gestiona tenants
    'ADMIN_TENANT',      -- ADT: gestiona su red de talleres
    'CONDUCTOR',         -- CLI: cliente final
    'TALLER',            -- TAL: representante del taller
    'TECNICO'            -- TEC: empleado que atiende en ruta
);

-- Estados del ciclo de vida del incidente (CU-10, CU-15, CU-25, CU-36, CU-37)
CREATE TYPE estado_incidente AS ENUM (
    'PENDIENTE',         -- recién creado
    'BUSCANDO_TALLER',   -- en motor de asignación
    'TALLER_ASIGNADO',   -- esperando aceptación
    'EN_CAMINO',         -- taller aceptó, técnico en ruta
    'EN_ATENCION',       -- técnico llegó al lugar
    'FINALIZADO',        -- servicio completado
    'PAGADO',            -- pago confirmado
    'CANCELADO',         -- cancelado por el conductor
    'NO_ATENDIDO'        -- ningún taller disponible / rechazado
);

-- Prioridad asignada por la IA (CU-21)
CREATE TYPE prioridad_incidente AS ENUM ('ALTA', 'MEDIA', 'BAJA', 'INCIERTA');

-- Estado de cada asignación taller<->incidente (CU-23, CU-25, CU-26)
CREATE TYPE estado_asignacion AS ENUM (
    'PROPUESTO',   -- candidato sugerido por el motor
    'ASIGNADO',    -- notificado, esperando respuesta
    'ACEPTADO',    -- taller aceptó
    'RECHAZADO',   -- taller rechazó
    'REASIGNADO'   -- liberado para otro taller
);

-- Estado de la cotización (CU-27)
CREATE TYPE estado_cotizacion AS ENUM ('PENDIENTE', 'ACEPTADA', 'RECHAZADA', 'EXPIRADA');

-- Estado del pago (CU-30)
CREATE TYPE estado_pago AS ENUM ('PENDIENTE', 'COMPLETADO', 'FALLIDO', 'REEMBOLSADO');

-- Tipo de evidencia adjunta (CU-11, CU-12, texto)
CREATE TYPE tipo_evidencia AS ENUM ('IMAGEN', 'AUDIO', 'TEXTO');

-- Origen de una clasificación de IA (CU-18, CU-19)
CREATE TYPE fuente_clasificacion AS ENUM ('IMAGEN', 'TEXTO', 'COMBINADA');

-- Estado de sincronización offline (CU-38, CU-39, CU-40)
CREATE TYPE estado_sync AS ENUM ('PENDIENTE', 'SINCRONIZADO', 'ERROR');

-- Canal por el que se entrega una notificación (CU-24, CU-35)
CREATE TYPE canal_notificacion AS ENUM ('PUSH', 'WEBSOCKET', 'EMAIL', 'SMS');

-- Quién origina una cotización (CU-27)
CREATE TYPE origen_cotizacion AS ENUM ('TALLER', 'IA');

-- =====================================================================
-- 2. FUNCIONES UTILITARIAS Y TRIGGERS GENÉRICOS
-- =====================================================================

-- Mantiene actualizado el campo updated_at en cada UPDATE.
CREATE OR REPLACE FUNCTION emergencias.fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Devuelve el tenant activo de la sesión (lo inyecta el middleware de FastAPI
-- mediante: SET app.current_tenant = '<uuid>'). Base de la Row Level Security.
CREATE OR REPLACE FUNCTION emergencias.fn_current_tenant()
RETURNS UUID AS $$
DECLARE
    v_tenant TEXT;
BEGIN
    v_tenant := current_setting('app.current_tenant', true);
    IF v_tenant IS NULL OR v_tenant = '' THEN
        RETURN NULL;
    END IF;
    RETURN v_tenant::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- =====================================================================
-- 3. MÓDULO: MULTI-TENANT Y PLANES (CU-46, CU-47, CU-48)
-- =====================================================================

-- Catálogo de planes contratables y sus límites (CU-48).
CREATE TABLE plan (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre              VARCHAR(60)  NOT NULL UNIQUE,   -- básico, profesional, enterprise
    max_talleres        INTEGER      NOT NULL DEFAULT 5  CHECK (max_talleres   > 0),
    max_tecnicos        INTEGER      NOT NULL DEFAULT 20 CHECK (max_tecnicos   > 0),
    ia_avanzada         BOOLEAN      NOT NULL DEFAULT FALSE,
    precio_mensual      NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (precio_mensual >= 0),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Organización inquilina (red de talleres). Raíz del aislamiento (CU-46).
CREATE TABLE tenant (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre              VARCHAR(120) NOT NULL,
    dominio             VARCHAR(120) UNIQUE,            -- ej. auxilionorte.com
    plan_id             UUID NOT NULL REFERENCES plan(id),
    comision_plataforma NUMERIC(5,4) NOT NULL DEFAULT 0.10 CHECK (comision_plataforma BETWEEN 0 AND 1), -- 10% (CU-31)
    activo              BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_inicio        DATE         NOT NULL DEFAULT CURRENT_DATE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_tenant_nombre UNIQUE (nombre)
);

COMMENT ON TABLE tenant IS 'Organizaciones (tenants). El tenant_id de las demás tablas referencia aquí.';
COMMENT ON COLUMN tenant.comision_plataforma IS 'Fracción que retiene la plataforma por servicio (0.10 = 10%).';

-- =====================================================================
-- 4. MÓDULO: USUARIOS Y ACCESO (CU-01, CU-02, CU-03, CU-04, CU-06)
-- =====================================================================

CREATE TABLE usuario (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- ADMIN_PLATAFORMA puede no pertenecer a ningún tenant (NULL).
    tenant_id           UUID REFERENCES tenant(id) ON DELETE CASCADE,
    rol                 rol_usuario  NOT NULL,
    nombre              VARCHAR(120) NOT NULL,
    email               CITEXT       NOT NULL,
    telefono            VARCHAR(30),
    password_hash       VARCHAR(255) NOT NULL,          -- bcrypt/argon2 (nunca texto plano)
    email_verificado    BOOLEAN      NOT NULL DEFAULT FALSE,
    activo              BOOLEAN      NOT NULL DEFAULT TRUE,  -- usuario inhabilitado (CU-01 excepción)
    ultimo_acceso       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- El email es único dentro de un mismo tenant (un conductor del tenant
    -- público y un taller de otro tenant podrían repetir correo en teoría).
    CONSTRAINT uq_usuario_email_tenant UNIQUE (tenant_id, email),
    -- Coherencia: solo el ADMIN_PLATAFORMA puede tener tenant nulo.
    CONSTRAINT chk_usuario_tenant CHECK (
        (rol = 'ADMIN_PLATAFORMA') OR (tenant_id IS NOT NULL)
    )
);

COMMENT ON COLUMN usuario.tenant_id IS 'NULL solo para ADMIN_PLATAFORMA (superusuario global).';

-- Tokens de recuperación de contraseña (CU-03).
CREATE TABLE token_recuperacion (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id          UUID NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    token_hash          VARCHAR(255) NOT NULL,
    expira_en           TIMESTAMPTZ  NOT NULL,
    usado               BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Lista negra de tokens JWT invalidados al cerrar sesión (CU-02).
CREATE TABLE token_revocado (
    jti                 VARCHAR(64)  PRIMARY KEY,        -- claim jti del JWT
    usuario_id          UUID NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    revocado_en         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expira_en           TIMESTAMPTZ  NOT NULL            -- permite limpiar la tabla
);

-- =====================================================================
-- 5. MÓDULO: CLIENTES Y VEHÍCULOS (CU-05)
-- =====================================================================

CREATE TABLE vehiculo (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    conductor_id        UUID NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    placa               VARCHAR(15)  NOT NULL,
    marca               VARCHAR(60)  NOT NULL,
    modelo              VARCHAR(60)  NOT NULL,
    anio                SMALLINT     CHECK (anio BETWEEN 1900 AND 2100),
    color               VARCHAR(40),
    tipo_combustible    VARCHAR(30),                    -- gasolina, diésel, eléctrico, GNV...
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- La placa no se repite para el mismo conductor (CU-05 excepción).
    CONSTRAINT uq_vehiculo_placa_conductor UNIQUE (conductor_id, placa)
);

-- =====================================================================
-- 6. MÓDULO: CATÁLOGO DE TIPOS DE INCIDENTE
-- =====================================================================

-- Catálogo de tipos de daño (batería, llanta, motor, choque, otros).
-- Se modela como tabla (no enum) para que cada tenant defina tarifas/SLA.
CREATE TABLE tipo_incidente (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo              VARCHAR(30)  NOT NULL UNIQUE,   -- BATERIA, LLANTA, MOTOR, CHOQUE, OTROS
    nombre              VARCHAR(80)  NOT NULL,
    prioridad_sugerida  prioridad_incidente NOT NULL DEFAULT 'MEDIA',
    activo              BOOLEAN      NOT NULL DEFAULT TRUE
);

-- =====================================================================
-- 7. MÓDULO: TALLERES Y TÉCNICOS (CU-07, CU-08, CU-09)
-- =====================================================================

CREATE TABLE taller (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    -- Usuario con rol TALLER que opera el taller (credenciales, CU-07).
    usuario_id          UUID UNIQUE REFERENCES usuario(id) ON DELETE SET NULL,
    nombre              VARCHAR(120) NOT NULL,
    direccion           VARCHAR(255),
    latitud             NUMERIC(9,6) NOT NULL CHECK (latitud  BETWEEN -90  AND 90),
    longitud            NUMERIC(9,6) NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    telefono            VARCHAR(30),
    horario_apertura    TIME,
    horario_cierre      TIME,
    -- Gestión de disponibilidad (CU-09).
    disponible          BOOLEAN      NOT NULL DEFAULT TRUE,
    capacidad_max       SMALLINT     NOT NULL DEFAULT 3 CHECK (capacidad_max > 0),
    -- Calificación promedio usada por el motor de asignación (CU-23).
    calificacion        NUMERIC(3,2) NOT NULL DEFAULT 5.0 CHECK (calificacion BETWEEN 0 AND 5),
    activo              BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Servicios (tipos de incidente) que ofrece cada taller (CU-07, CU-22).
CREATE TABLE taller_servicio (
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    tipo_incidente_id   UUID NOT NULL REFERENCES tipo_incidente(id) ON DELETE CASCADE,
    PRIMARY KEY (taller_id, tipo_incidente_id)
);

-- Tarifas de referencia por taller y tipo de incidente (CU-27, CU-28).
CREATE TABLE tarifa (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    tipo_incidente_id   UUID NOT NULL REFERENCES tipo_incidente(id) ON DELETE CASCADE,
    precio_base         NUMERIC(10,2) NOT NULL CHECK (precio_base >= 0),
    tiempo_base_min     INTEGER       NOT NULL DEFAULT 60 CHECK (tiempo_base_min > 0),
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_tarifa UNIQUE (taller_id, tipo_incidente_id)
);

CREATE TABLE tecnico (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    -- Usuario con rol TECNICO (opcional: acceso limitado, CU-08).
    usuario_id          UUID UNIQUE REFERENCES usuario(id) ON DELETE SET NULL,
    nombre              VARCHAR(120) NOT NULL,
    telefono            VARCHAR(30),
    especialidad        VARCHAR(80),
    disponible          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_tecnico_telefono_tenant UNIQUE (tenant_id, telefono)
);

-- =====================================================================
-- 8. MÓDULO: INCIDENTES Y EVIDENCIAS (CU-10 a CU-21)
-- =====================================================================

CREATE TABLE incidente (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    conductor_id        UUID NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT,
    vehiculo_id         UUID NOT NULL REFERENCES vehiculo(id) ON DELETE RESTRICT,
    tipo_incidente_id   UUID REFERENCES tipo_incidente(id),       -- NULL hasta clasificar (CU-18/19)

    estado              estado_incidente    NOT NULL DEFAULT 'PENDIENTE',
    prioridad           prioridad_incidente NOT NULL DEFAULT 'INCIERTA',

    -- Ubicación del incidente (CU-13).
    latitud             NUMERIC(9,6) CHECK (latitud  BETWEEN -90  AND 90),
    longitud            NUMERIC(9,6) CHECK (longitud BETWEEN -180 AND 180),
    direccion           VARCHAR(255),

    descripcion         TEXT,                                     -- texto del conductor
    resumen_ia          TEXT,                                     -- resumen estructurado (CU-20)
    motivo_cancelacion  TEXT,                                     -- (CU-15)

    -- Estimación de reparación (CU-28).
    tiempo_estimado_min INTEGER CHECK (tiempo_estimado_min >= 0),

    -- Sincronización offline (CU-38, CU-40, CU-41).
    -- external_id = id_local generado en el dispositivo; único por tenant
    -- para evitar duplicados al reintentar la sincronización.
    external_id         UUID,
    estado_sincronizacion estado_sync NOT NULL DEFAULT 'SINCRONIZADO',
    dispositivo_origen  VARCHAR(120),

    reportado_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),       -- t0 para KPIs
    asignado_at         TIMESTAMPTZ,                               -- t de asignación (KPI)
    aceptado_at         TIMESTAMPTZ,                               -- t de aceptación
    en_camino_at        TIMESTAMPTZ,
    atendido_at         TIMESTAMPTZ,                               -- llegada del técnico
    finalizado_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_incidente_external UNIQUE (tenant_id, external_id)
);

COMMENT ON COLUMN incidente.external_id IS 'id_local del dispositivo (CU-41): impide duplicados en la sincronización.';
COMMENT ON COLUMN incidente.reportado_at IS 'Instante de creación: base para el KPI de tiempo de asignación.';

-- Evidencias multimedia: imágenes, audio y texto (CU-11, CU-12).
CREATE TABLE evidencia (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    tipo                tipo_evidencia NOT NULL,
    url                 TEXT,                  -- ruta en storage (S3/local)
    contenido_texto     TEXT,                  -- texto libre o base64 pequeño
    transcripcion       TEXT,                  -- resultado de speech-to-text (CU-17)
    mime_type           VARCHAR(60),
    tamano_bytes        BIGINT CHECK (tamano_bytes >= 0),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Resultados de clasificación de IA por imagen/texto (CU-18, CU-19, CU-21).
CREATE TABLE clasificacion_ia (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    fuente              fuente_clasificacion NOT NULL,
    tipo_incidente_id   UUID REFERENCES tipo_incidente(id),
    etiqueta            VARCHAR(80),
    confianza           NUMERIC(5,4) CHECK (confianza BETWEEN 0 AND 1),
    prioridad_sugerida  prioridad_incidente,
    modelo              VARCHAR(80),           -- nombre/versión del modelo
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Bitácora de cambios de estado del incidente (CU-14, CU-36) -> fuente de KPIs.
CREATE TABLE incidente_estado_historial (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    estado_anterior     estado_incidente,
    estado_nuevo        estado_incidente NOT NULL,
    comentario          TEXT,
    cambiado_por        UUID REFERENCES usuario(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =====================================================================
-- 9. MÓDULO: ASIGNACIÓN DE TALLERES (CU-22 a CU-29)
-- =====================================================================

-- Candidatos calculados por el motor de asignación (CU-22).
CREATE TABLE taller_candidato (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    distancia_km        NUMERIC(7,2) CHECK (distancia_km >= 0),
    tiempo_llegada_min  INTEGER CHECK (tiempo_llegada_min >= 0),
    puntaje             NUMERIC(7,4),          -- score del motor (mayor = mejor)
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidato UNIQUE (incidente_id, taller_id)
);

-- Asignación efectiva incidente<->taller (CU-23, CU-25, CU-26).
CREATE TABLE asignacion (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE RESTRICT,
    tecnico_id          UUID REFERENCES tecnico(id) ON DELETE SET NULL,
    estado              estado_asignacion NOT NULL DEFAULT 'ASIGNADO',
    asignacion_automatica BOOLEAN NOT NULL DEFAULT TRUE,  -- FALSE si la eligió el cliente (CU-29)
    motivo_rechazo      TEXT,                              -- (CU-26)
    asignado_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    respondido_at       TIMESTAMPTZ,                       -- aceptado/rechazado
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Solo puede haber una asignación ACEPTADA por incidente.
CREATE UNIQUE INDEX uq_asignacion_aceptada
    ON asignacion (incidente_id)
    WHERE estado = 'ACEPTADO';

-- Cotizaciones del daño (CU-27).
CREATE TABLE cotizacion (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    origen              origen_cotizacion NOT NULL DEFAULT 'TALLER',
    monto               NUMERIC(10,2) NOT NULL CHECK (monto >= 0),
    detalle             TEXT,
    estado              estado_cotizacion NOT NULL DEFAULT 'PENDIENTE',
    valida_hasta        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =====================================================================
-- 10. MÓDULO: PAGOS, COMISIONES Y FACTURACIÓN (CU-30, CU-31, CU-32)
-- =====================================================================

CREATE TABLE pago (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE RESTRICT,
    cotizacion_id       UUID REFERENCES cotizacion(id) ON DELETE SET NULL,
    monto               NUMERIC(10,2) NOT NULL CHECK (monto >= 0),
    -- Comisión retenida por la plataforma (10%, CU-31). Se calcula por trigger.
    comision_plataforma NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (comision_plataforma >= 0),
    monto_taller        NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (monto_taller >= 0),
    moneda              CHAR(3)       NOT NULL DEFAULT 'BOB',
    metodo              VARCHAR(40),                 -- tarjeta, transferencia...
    pasarela            VARCHAR(40),                 -- stripe, mercadopago, paypal
    token_transaccion   VARCHAR(255),                -- token devuelto por la pasarela
    estado              estado_pago   NOT NULL DEFAULT 'PENDIENTE',
    pagado_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

COMMENT ON COLUMN pago.comision_plataforma IS 'monto * tenant.comision_plataforma (CU-31).';

CREATE TABLE factura (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    pago_id             UUID NOT NULL UNIQUE REFERENCES pago(id) ON DELETE CASCADE,
    numero              VARCHAR(40)  NOT NULL,
    url_pdf             TEXT,
    emitida_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_factura_numero UNIQUE (tenant_id, numero)
);

-- =====================================================================
-- 11. MÓDULO: NOTIFICACIONES Y TIEMPO REAL (CU-24, CU-33 a CU-37)
-- =====================================================================

CREATE TABLE notificacion (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    usuario_id          UUID NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    incidente_id        UUID REFERENCES incidente(id) ON DELETE CASCADE,
    canal               canal_notificacion NOT NULL DEFAULT 'PUSH',
    titulo              VARCHAR(160) NOT NULL,
    mensaje             TEXT,
    enviada             BOOLEAN      NOT NULL DEFAULT FALSE,  -- para reintentos (CU-24)
    leida               BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    enviada_at          TIMESTAMPTZ
);

-- Conexiones WebSocket activas para seguimiento en vivo (CU-33).
CREATE TABLE conexion_ws (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    usuario_id          UUID NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    conectado_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    desconectado_at     TIMESTAMPTZ
);

-- Tracking de ubicación del técnico en ruta (CU-34, CU-37).
CREATE TABLE ubicacion_tracking (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    tecnico_id          UUID REFERENCES tecnico(id) ON DELETE SET NULL,
    latitud             NUMERIC(9,6) NOT NULL CHECK (latitud  BETWEEN -90  AND 90),
    longitud            NUMERIC(9,6) NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =====================================================================
-- 12. MÓDULO: OFFLINE / SINCRONIZACIÓN (CU-38 a CU-41)
-- =====================================================================

-- Mapa id_local (dispositivo) <-> incidente (servidor) para evitar
-- duplicados y resolver conflictos "última escritura gana" (CU-41).
CREATE TABLE sync_mapping (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    external_id         UUID NOT NULL,                 -- id_local del dispositivo
    incidente_id        UUID NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    dispositivo         VARCHAR(120),
    last_write_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_sync_external UNIQUE (tenant_id, external_id)
);

-- =====================================================================
-- 13. MÓDULO: SLA Y CONFIGURACIÓN (CU-45)
-- =====================================================================

-- Umbral de tiempo máximo aceptable por tipo de incidente y tenant (CU-45).
CREATE TABLE sla_config (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    tipo_incidente_id   UUID NOT NULL REFERENCES tipo_incidente(id) ON DELETE CASCADE,
    tiempo_max_min      INTEGER NOT NULL CHECK (tiempo_max_min > 0),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_sla UNIQUE (tenant_id, tipo_incidente_id)
);

-- =====================================================================
-- 14. AUDITORÍA (transversal, buena práctica de seguridad)
-- =====================================================================

CREATE TABLE auditoria (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id           UUID,
    usuario_id          UUID,
    accion              VARCHAR(80)  NOT NULL,    -- LOGIN, CREATE_INCIDENTE, PAGO_OK...
    entidad             VARCHAR(60),
    entidad_id          UUID,
    detalle             JSONB,
    ip                  INET,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- =====================================================================
-- 15. ÍNDICES (rendimiento de consultas y KPIs)
-- =====================================================================

-- Filtros multi-tenant (presentes en casi todas las consultas).
CREATE INDEX idx_usuario_tenant            ON usuario(tenant_id);
CREATE INDEX idx_vehiculo_tenant           ON vehiculo(tenant_id);
CREATE INDEX idx_vehiculo_conductor        ON vehiculo(conductor_id);
CREATE INDEX idx_taller_tenant             ON taller(tenant_id);
CREATE INDEX idx_taller_disponible         ON taller(tenant_id, disponible) WHERE disponible;
CREATE INDEX idx_tecnico_taller            ON tecnico(taller_id);

-- Incidentes: consultas por tenant, conductor, estado y rango temporal (KPIs).
CREATE INDEX idx_incidente_tenant          ON incidente(tenant_id);
CREATE INDEX idx_incidente_conductor       ON incidente(conductor_id);
CREATE INDEX idx_incidente_estado          ON incidente(tenant_id, estado);
CREATE INDEX idx_incidente_tipo            ON incidente(tipo_incidente_id);
CREATE INDEX idx_incidente_reportado       ON incidente(tenant_id, reportado_at);
CREATE INDEX idx_incidente_sync            ON incidente(estado_sincronizacion) WHERE estado_sincronizacion = 'PENDIENTE';
-- Agrupación geográfica para "zonas con más incidentes" (CU-42).
CREATE INDEX idx_incidente_geo             ON incidente(latitud, longitud);

CREATE INDEX idx_evidencia_incidente       ON evidencia(incidente_id);
CREATE INDEX idx_clasif_incidente          ON clasificacion_ia(incidente_id);
CREATE INDEX idx_historial_incidente       ON incidente_estado_historial(incidente_id);

CREATE INDEX idx_candidato_incidente       ON taller_candidato(incidente_id);
CREATE INDEX idx_asignacion_incidente      ON asignacion(incidente_id);
CREATE INDEX idx_asignacion_taller         ON asignacion(taller_id, estado);
CREATE INDEX idx_cotizacion_incidente      ON cotizacion(incidente_id);

CREATE INDEX idx_pago_tenant               ON pago(tenant_id, estado);
CREATE INDEX idx_pago_incidente            ON pago(incidente_id);

CREATE INDEX idx_notif_usuario             ON notificacion(usuario_id, leida);
CREATE INDEX idx_notif_pendiente           ON notificacion(tenant_id) WHERE NOT enviada;
CREATE INDEX idx_ws_incidente              ON conexion_ws(incidente_id) WHERE desconectado_at IS NULL;
CREATE INDEX idx_tracking_incidente        ON ubicacion_tracking(incidente_id, created_at DESC);

CREATE INDEX idx_auditoria_tenant          ON auditoria(tenant_id, created_at DESC);

-- =====================================================================
-- 16. TRIGGERS
-- =====================================================================

-- 16.1 updated_at automático en todas las tablas con esa columna.
DO $$
DECLARE
    t TEXT;
    tablas TEXT[] := ARRAY[
        'plan','tenant','usuario','vehiculo','taller','tarifa','tecnico',
        'incidente','asignacion','cotizacion','pago','sla_config'
    ];
BEGIN
    FOREACH t IN ARRAY tablas LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_updated_at
               BEFORE UPDATE ON emergencias.%1$s
               FOR EACH ROW EXECUTE FUNCTION emergencias.fn_set_updated_at();', t);
    END LOOP;
END $$;

-- 16.2 Cálculo automático de comisión de la plataforma en cada pago (CU-31).
CREATE OR REPLACE FUNCTION emergencias.fn_calcular_comision()
RETURNS TRIGGER AS $$
DECLARE
    v_comision NUMERIC(5,4);
BEGIN
    SELECT comision_plataforma INTO v_comision FROM emergencias.tenant WHERE id = NEW.tenant_id;
    v_comision := COALESCE(v_comision, 0.10);
    NEW.comision_plataforma := ROUND(NEW.monto * v_comision, 2);
    NEW.monto_taller        := NEW.monto - NEW.comision_plataforma;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pago_comision
    BEFORE INSERT OR UPDATE OF monto ON pago
    FOR EACH ROW EXECUTE FUNCTION emergencias.fn_calcular_comision();

-- 16.3 Registro automático de transiciones de estado del incidente
--      y sello de timestamps usados por los KPIs (CU-36, CU-42).
CREATE OR REPLACE FUNCTION emergencias.fn_incidente_estado()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO emergencias.incidente_estado_historial
            (tenant_id, incidente_id, estado_anterior, estado_nuevo)
        VALUES (NEW.tenant_id, NEW.id, NULL, NEW.estado);
        RETURN NEW;
    END IF;

    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
        INSERT INTO emergencias.incidente_estado_historial
            (tenant_id, incidente_id, estado_anterior, estado_nuevo)
        VALUES (NEW.tenant_id, NEW.id, OLD.estado, NEW.estado);

        -- Sella los hitos temporales si aún no estaban marcados.
        CASE NEW.estado
            WHEN 'TALLER_ASIGNADO' THEN NEW.asignado_at   := COALESCE(NEW.asignado_at, now());
            WHEN 'EN_CAMINO'       THEN NEW.aceptado_at    := COALESCE(NEW.aceptado_at, now());
                                        NEW.en_camino_at   := COALESCE(NEW.en_camino_at, now());
            WHEN 'EN_ATENCION'     THEN NEW.atendido_at    := COALESCE(NEW.atendido_at, now());
            WHEN 'FINALIZADO'      THEN NEW.finalizado_at  := COALESCE(NEW.finalizado_at, now());
            ELSE NULL;
        END CASE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_incidente_estado_ins
    AFTER INSERT ON incidente
    FOR EACH ROW EXECUTE FUNCTION emergencias.fn_incidente_estado();

CREATE TRIGGER trg_incidente_estado_upd
    BEFORE UPDATE ON incidente
    FOR EACH ROW EXECUTE FUNCTION emergencias.fn_incidente_estado();

-- =====================================================================
-- 17. ROW LEVEL SECURITY (aislamiento multi-tenant reforzado)
-- ---------------------------------------------------------------------
--  El backend ejecuta al inicio de cada request:
--      SET app.current_tenant = '<tenant_id_del_jwt>';
--  Las políticas garantizan que solo se vean filas del tenant activo.
--  El ADMIN_PLATAFORMA usa un rol de BD BYPASSRLS o no fija la variable.
-- =====================================================================

DO $$
DECLARE
    t TEXT;
    tablas TEXT[] := ARRAY[
        'usuario','vehiculo','taller','taller_servicio','tarifa','tecnico',
        'incidente','evidencia','clasificacion_ia','incidente_estado_historial',
        'taller_candidato','asignacion','cotizacion','pago','factura',
        'notificacion','conexion_ws','ubicacion_tracking','sync_mapping','sla_config'
    ];
BEGIN
    FOREACH t IN ARRAY tablas LOOP
        -- taller_servicio no tiene tenant_id directo: se omite del RLS por tenant.
        IF t = 'taller_servicio' THEN
            CONTINUE;
        END IF;
        EXECUTE format('ALTER TABLE emergencias.%I ENABLE ROW LEVEL SECURITY;', t);
        EXECUTE format(
            'CREATE POLICY pol_%1$s_tenant ON emergencias.%1$s
                USING (tenant_id = emergencias.fn_current_tenant()
                       OR emergencias.fn_current_tenant() IS NULL)
                WITH CHECK (tenant_id = emergencias.fn_current_tenant()
                       OR emergencias.fn_current_tenant() IS NULL);', t);
    END LOOP;
END $$;

-- =====================================================================
-- Fin del esquema. Ejecutar a continuación 02_views_kpi.sql
-- =====================================================================
