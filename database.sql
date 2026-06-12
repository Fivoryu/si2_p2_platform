-- ================================================================
--  Plataforma Emergencias Vehiculares - Base de datos consolidada
--  PostgreSQL 14+ | Schema: emergencias | CU-01 a CU-49
-- ================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

CREATE SCHEMA IF NOT EXISTS emergencias;
SET search_path TO emergencias, public;

-- ================================================================
-- 1. ENUMS
-- ================================================================
CREATE TYPE rol_usuario            AS ENUM ('ADMIN_PLATAFORMA','ADMIN_TENANT','CONDUCTOR','TALLER','TECNICO');
CREATE TYPE estado_incidente       AS ENUM ('PENDIENTE','BUSCANDO_TALLER','TALLER_ASIGNADO','EN_CAMINO','EN_ATENCION','FINALIZADO','PAGADO','CANCELADO','NO_ATENDIDO');
CREATE TYPE prioridad_incidente    AS ENUM ('ALTA','MEDIA','BAJA','INCIERTA');
CREATE TYPE estado_asignacion      AS ENUM ('PROPUESTO','ASIGNADO','ACEPTADO','RECHAZADO','REASIGNADO');
CREATE TYPE estado_cotizacion      AS ENUM ('PENDIENTE','ACEPTADA','RECHAZADA','EXPIRADA');
CREATE TYPE estado_pago            AS ENUM ('PENDIENTE','COMPLETADO','FALLIDO','REEMBOLSADO');
CREATE TYPE tipo_evidencia         AS ENUM ('IMAGEN','AUDIO','TEXTO');
CREATE TYPE fuente_clasificacion   AS ENUM ('IMAGEN','TEXTO','COMBINADA');
CREATE TYPE estado_sync            AS ENUM ('PENDIENTE','SINCRONIZADO','ERROR');
CREATE TYPE canal_notificacion     AS ENUM ('PUSH','WEBSOCKET','EMAIL','SMS');
CREATE TYPE origen_cotizacion      AS ENUM ('TALLER','IA');

-- ================================================================
-- 2. FUNCIONES UTILITARIAS
-- ================================================================
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_current_tenant()
RETURNS UUID AS $$
DECLARE v_tenant TEXT;
BEGIN
  v_tenant := current_setting('app.current_tenant', true);
  IF v_tenant IS NULL OR v_tenant = '' THEN RETURN NULL; END IF;
  RETURN v_tenant::UUID;
END; $$ LANGUAGE plpgsql STABLE;

-- ================================================================
-- 3. TABLAS
-- ================================================================

-- 3.1 plan (CU-48)
CREATE TABLE plan (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          VARCHAR(60)    NOT NULL UNIQUE,
    max_talleres    INTEGER        NOT NULL DEFAULT 5   CHECK (max_talleres   > 0),
    max_tecnicos    INTEGER        NOT NULL DEFAULT 20  CHECK (max_tecnicos   > 0),
    ia_avanzada     BOOLEAN        NOT NULL DEFAULT FALSE,
    precio_mensual  NUMERIC(10,2)  NOT NULL DEFAULT 0   CHECK (precio_mensual >= 0),
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- 3.2 tenant (CU-46, CU-47)
CREATE TABLE tenant (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre              VARCHAR(120)   NOT NULL UNIQUE,
    dominio             VARCHAR(120)   UNIQUE,
    plan_id             UUID           NOT NULL REFERENCES plan(id),
    comision_plataforma NUMERIC(5,4)   NOT NULL DEFAULT 0.10 CHECK (comision_plataforma BETWEEN 0 AND 1),
    activo              BOOLEAN        NOT NULL DEFAULT TRUE,
    fecha_inicio        DATE           NOT NULL DEFAULT CURRENT_DATE,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- 3.3 usuario (CU-01..CU-04, CU-06) + fcm_token (CU-24)
CREATE TABLE usuario (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID           REFERENCES tenant(id) ON DELETE CASCADE,
    rol              rol_usuario    NOT NULL,
    nombre           VARCHAR(120)   NOT NULL,
    email            CITEXT         NOT NULL,
    telefono         VARCHAR(30),
    password_hash    VARCHAR(255)   NOT NULL,
    email_verificado BOOLEAN        NOT NULL DEFAULT FALSE,
    activo           BOOLEAN        NOT NULL DEFAULT TRUE,
    ultimo_acceso    TIMESTAMPTZ,
    fcm_token        VARCHAR(512),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_usuario_email_tenant UNIQUE (tenant_id, email),
    CONSTRAINT chk_usuario_tenant CHECK ((rol IN ('ADMIN_PLATAFORMA', 'CONDUCTOR')) OR (tenant_id IS NOT NULL))
);

-- 3.4 token_recuperacion (CU-03)
CREATE TABLE token_recuperacion (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id  UUID           NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255)   NOT NULL,
    expira_en   TIMESTAMPTZ    NOT NULL,
    usado       BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- 3.5 token_revocado (CU-02)
CREATE TABLE token_revocado (
    jti         VARCHAR(64)  PRIMARY KEY,
    usuario_id  UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    revocado_en TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expira_en   TIMESTAMPTZ  NOT NULL
);

-- 3.6 vehiculo (CU-05)
CREATE TABLE vehiculo (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID           REFERENCES tenant(id) ON DELETE CASCADE,
    conductor_id     UUID           NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    placa            VARCHAR(15)    NOT NULL,
    marca            VARCHAR(60)    NOT NULL,
    modelo           VARCHAR(60)    NOT NULL,
    anio             SMALLINT       CHECK (anio BETWEEN 1900 AND 2100),
    color            VARCHAR(40),
    tipo_combustible VARCHAR(30),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_vehiculo_placa_conductor UNIQUE (conductor_id, placa)
);

-- 3.7 tipo_incidente
CREATE TABLE tipo_incidente (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo             VARCHAR(30)           NOT NULL UNIQUE,
    nombre             VARCHAR(80)           NOT NULL,
    prioridad_sugerida prioridad_incidente   NOT NULL DEFAULT 'MEDIA',
    activo             BOOLEAN               NOT NULL DEFAULT TRUE
);

-- 3.8 taller (CU-07, CU-09)
CREATE TABLE taller (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID           NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    usuario_id       UUID           UNIQUE REFERENCES usuario(id) ON DELETE SET NULL,
    nombre           VARCHAR(120)   NOT NULL,
    direccion        VARCHAR(255),
    latitud          NUMERIC(9,6)   NOT NULL CHECK (latitud  BETWEEN -90  AND 90),
    longitud         NUMERIC(9,6)   NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    telefono         VARCHAR(30),
    horario_apertura TIME,
    horario_cierre   TIME,
    disponible       BOOLEAN        NOT NULL DEFAULT TRUE,
    capacidad_max    SMALLINT       NOT NULL DEFAULT 3 CHECK (capacidad_max > 0),
    calificacion     NUMERIC(3,2)   NOT NULL DEFAULT 5.0 CHECK (calificacion BETWEEN 0 AND 5),
    activo           BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- 3.9 taller_servicio (M:N taller ↔ tipo_incidente)
CREATE TABLE taller_servicio (
    taller_id         UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    tipo_incidente_id UUID NOT NULL REFERENCES tipo_incidente(id) ON DELETE CASCADE,
    PRIMARY KEY (taller_id, tipo_incidente_id)
);

-- 3.10 tarifa (CU-27, CU-28)
CREATE TABLE tarifa (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID           NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    taller_id         UUID           NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    tipo_incidente_id UUID           NOT NULL REFERENCES tipo_incidente(id) ON DELETE CASCADE,
    precio_base       NUMERIC(10,2)  NOT NULL CHECK (precio_base     >= 0),
    tiempo_base_min   INTEGER        NOT NULL DEFAULT 60 CHECK (tiempo_base_min > 0),
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_tarifa UNIQUE (taller_id, tipo_incidente_id)
);

-- 3.11 especialidad_taller (CU-08)
CREATE TABLE especialidad_taller (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    taller_id  UUID         NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    nombre     VARCHAR(80)  NOT NULL,
    activo     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_especialidad_taller_nombre UNIQUE (taller_id, nombre)
);

-- 3.12 tecnico (CU-08)
CREATE TABLE tecnico (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID           NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    taller_id     UUID           NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    usuario_id    UUID           UNIQUE REFERENCES usuario(id) ON DELETE SET NULL,
    nombre        VARCHAR(120)   NOT NULL,
    telefono      VARCHAR(30),
    especialidad  VARCHAR(80),
    disponible    BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_tecnico_telefono_tenant UNIQUE (tenant_id, telefono)
);

-- 3.13 tecnico_especialidad (M:N tecnico ↔ especialidad_taller)
CREATE TABLE tecnico_especialidad (
    tecnico_id       UUID NOT NULL REFERENCES tecnico(id) ON DELETE CASCADE,
    especialidad_id  UUID NOT NULL REFERENCES especialidad_taller(id) ON DELETE CASCADE,
    PRIMARY KEY (tecnico_id, especialidad_id)
);

-- 3.14 incidente (CU-10..CU-21, CU-38..CU-41)
CREATE TABLE incidente (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id              UUID                  REFERENCES tenant(id) ON DELETE CASCADE,
    conductor_id           UUID                  NOT NULL REFERENCES usuario(id) ON DELETE RESTRICT,
    vehiculo_id            UUID                  NOT NULL REFERENCES vehiculo(id) ON DELETE RESTRICT,
    tipo_incidente_id      UUID                  REFERENCES tipo_incidente(id),
    estado                 estado_incidente      NOT NULL DEFAULT 'PENDIENTE',
    prioridad              prioridad_incidente   NOT NULL DEFAULT 'INCIERTA',
    latitud                NUMERIC(9,6)          CHECK (latitud  BETWEEN -90  AND 90),
    longitud               NUMERIC(9,6)          CHECK (longitud BETWEEN -180 AND 180),
    direccion              VARCHAR(255),
    descripcion            TEXT,
    resumen_ia             TEXT,
    motivo_cancelacion     TEXT,
    tiempo_estimado_min    INTEGER               CHECK (tiempo_estimado_min >= 0),
    external_id            UUID,
    estado_sincronizacion  estado_sync           NOT NULL DEFAULT 'SINCRONIZADO',
    dispositivo_origen     VARCHAR(120),
    reportado_at           TIMESTAMPTZ           NOT NULL DEFAULT now(),
    asignado_at            TIMESTAMPTZ,
    aceptado_at            TIMESTAMPTZ,
    en_camino_at           TIMESTAMPTZ,
    atendido_at            TIMESTAMPTZ,
    finalizado_at          TIMESTAMPTZ,
    created_at             TIMESTAMPTZ           NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ           NOT NULL DEFAULT now(),
    CONSTRAINT uq_incidente_external UNIQUE (tenant_id, external_id)
);

-- 3.15 evidencia (CU-11, CU-12)
CREATE TABLE evidencia (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID            NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id    UUID            NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    tipo            tipo_evidencia  NOT NULL,
    url             TEXT,
    contenido_texto TEXT,
    transcripcion   TEXT,
    mime_type       VARCHAR(60),
    tamano_bytes    BIGINT          CHECK (tamano_bytes >= 0),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- 3.16 clasificacion_ia (CU-18, CU-19, CU-21)
CREATE TABLE clasificacion_ia (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          UUID                  NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id       UUID                  NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    fuente             fuente_clasificacion  NOT NULL,
    tipo_incidente_id  UUID                  REFERENCES tipo_incidente(id),
    etiqueta           VARCHAR(80),
    confianza          NUMERIC(5,4)          CHECK (confianza BETWEEN 0 AND 1),
    prioridad_sugerida prioridad_incidente,
    modelo             VARCHAR(80),
    created_at         TIMESTAMPTZ           NOT NULL DEFAULT now()
);

-- 3.17 incidente_estado_historial (CU-14, CU-36)
CREATE TABLE incidente_estado_historial (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id        UUID               NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id     UUID               NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    estado_anterior  estado_incidente,
    estado_nuevo     estado_incidente   NOT NULL,
    comentario       TEXT,
    cambiado_por     UUID               REFERENCES usuario(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ        NOT NULL DEFAULT now()
);

-- 3.18 taller_candidato (CU-22) + ciclo3 cols
CREATE TABLE taller_candidato (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID           NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id      UUID           NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id         UUID           NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    distancia_km      NUMERIC(7,2)   CHECK (distancia_km >= 0),
    tiempo_llegada_min INTEGER        CHECK (tiempo_llegada_min >= 0),
    puntaje           NUMERIC(7,4),
    precio_sugerido   NUMERIC(10,2)  CHECK (precio_sugerido IS NULL OR precio_sugerido >= 0),
    dificultad        VARCHAR(20),
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidato UNIQUE (incidente_id, taller_id)
);

-- 3.19 asignacion (CU-23, CU-25, CU-26)
CREATE TABLE asignacion (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id              UUID               NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id           UUID               NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id              UUID               NOT NULL REFERENCES taller(id) ON DELETE RESTRICT,
    tecnico_id             UUID               REFERENCES tecnico(id) ON DELETE SET NULL,
    estado                 estado_asignacion  NOT NULL DEFAULT 'ASIGNADO',
    asignacion_automatica  BOOLEAN            NOT NULL DEFAULT TRUE,
    motivo_rechazo         TEXT,
    asignado_at            TIMESTAMPTZ        NOT NULL DEFAULT now(),
    respondido_at          TIMESTAMPTZ,
    created_at             TIMESTAMPTZ        NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ        NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_asignacion_aceptada ON asignacion(incidente_id) WHERE estado = 'ACEPTADO';

-- 3.20 cotizacion (CU-27) + ciclo3 cols
CREATE TABLE cotizacion (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID              NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID              NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id           UUID              NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    asignacion_id       UUID              REFERENCES asignacion(id) ON DELETE SET NULL,
    origen              origen_cotizacion NOT NULL DEFAULT 'TALLER',
    monto               NUMERIC(10,2)     NOT NULL CHECK (monto >= 0),
    precio_sugerido     NUMERIC(10,2)     CHECK (precio_sugerido IS NULL OR precio_sugerido >= 0),
    tiempo_estimado_min INTEGER           CHECK (tiempo_estimado_min IS NULL OR tiempo_estimado_min >= 0),
    tiempo_llegada_min  INTEGER           CHECK (tiempo_llegada_min  IS NULL OR tiempo_llegada_min  >= 0),
    dificultad          VARCHAR(20),
    detalle             TEXT,
    comentario_taller   TEXT,
    estado              estado_cotizacion NOT NULL DEFAULT 'PENDIENTE',
    valida_hasta        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ       NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cotizacion_asignacion ON cotizacion(asignacion_id) WHERE asignacion_id IS NOT NULL;

-- 3.21 pago (CU-30, CU-31)
CREATE TABLE pago (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID           NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id        UUID           NOT NULL REFERENCES incidente(id) ON DELETE RESTRICT,
    cotizacion_id       UUID           REFERENCES cotizacion(id) ON DELETE SET NULL,
    monto               NUMERIC(10,2)  NOT NULL CHECK (monto >= 0),
    comision_plataforma NUMERIC(10,2)  NOT NULL DEFAULT 0 CHECK (comision_plataforma >= 0),
    monto_taller        NUMERIC(10,2)  NOT NULL DEFAULT 0 CHECK (monto_taller        >= 0),
    moneda              CHAR(3)        NOT NULL DEFAULT 'BOB',
    metodo              VARCHAR(40),
    pasarela            VARCHAR(40),
    token_transaccion   VARCHAR(255),
    estado              estado_pago    NOT NULL DEFAULT 'PENDIENTE',
    pagado_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- 3.22 factura (CU-32)
CREATE TABLE factura (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    pago_id     UUID         NOT NULL UNIQUE REFERENCES pago(id) ON DELETE CASCADE,
    numero      VARCHAR(40)  NOT NULL,
    url_pdf     TEXT,
    emitida_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_factura_numero UNIQUE (tenant_id, numero)
);

-- 3.23 notificacion (CU-24, CU-35)
CREATE TABLE notificacion (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID                NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    usuario_id    UUID                NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    incidente_id  UUID                REFERENCES incidente(id) ON DELETE CASCADE,
    canal         canal_notificacion  NOT NULL DEFAULT 'PUSH',
    titulo        VARCHAR(160)        NOT NULL,
    mensaje       TEXT,
    enviada       BOOLEAN             NOT NULL DEFAULT FALSE,
    leida         BOOLEAN             NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ         NOT NULL DEFAULT now(),
    enviada_at    TIMESTAMPTZ
);

-- 3.24 conexion_ws (CU-33)
CREATE TABLE conexion_ws (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id     UUID         NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    usuario_id       UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    conectado_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    desconectado_at  TIMESTAMPTZ
);

-- 3.25 ubicacion_tracking (CU-34, CU-37)
CREATE TABLE ubicacion_tracking (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id     UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id  UUID         NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    tecnico_id    UUID         REFERENCES tecnico(id) ON DELETE SET NULL,
    latitud       NUMERIC(9,6) NOT NULL CHECK (latitud  BETWEEN -90  AND 90),
    longitud      NUMERIC(9,6) NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    es_fake       BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 3.26 sync_mapping (CU-41)
CREATE TABLE sync_mapping (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    external_id    UUID         NOT NULL,
    incidente_id   UUID         NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    dispositivo    VARCHAR(120),
    last_write_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_sync_external UNIQUE (tenant_id, external_id)
);

-- 3.27 sla_config (CU-45)
CREATE TABLE sla_config (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    tipo_incidente_id  UUID         NOT NULL REFERENCES tipo_incidente(id) ON DELETE CASCADE,
    tiempo_max_min     INTEGER      NOT NULL CHECK (tiempo_max_min > 0),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_sla UNIQUE (tenant_id, tipo_incidente_id)
);

-- 3.28 calificacion_servicio (CU-49)
CREATE TABLE calificacion_servicio (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID         NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    incidente_id  UUID         NOT NULL REFERENCES incidente(id) ON DELETE CASCADE,
    taller_id     UUID         NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    conductor_id  UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    estrellas     INTEGER      NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
    comentario    TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_calificacion_incidente UNIQUE (incidente_id)
);

-- 3.29 auditoria
CREATE TABLE auditoria (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   UUID,
    usuario_id  UUID,
    accion      VARCHAR(80)  NOT NULL,
    entidad     VARCHAR(60),
    entidad_id  UUID,
    detalle     JSONB,
    ip          INET,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 3.30 rol (catálogo de roles — base + personalizados por tenant)
CREATE TABLE rol (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         REFERENCES tenant(id) ON DELETE CASCADE,
    nombre      VARCHAR(80)  NOT NULL,
    descripcion TEXT,
    es_base     BOOLEAN      NOT NULL DEFAULT FALSE,
    base_rol    rol_usuario,
    activo      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_rol_tenant_nombre UNIQUE (tenant_id, nombre)
);

-- 3.31 rol_permiso_entidad (CRUD por entidad para cada rol)
CREATE TABLE rol_permiso_entidad (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rol_id           UUID        NOT NULL REFERENCES rol(id) ON DELETE CASCADE,
    entidad          VARCHAR(60) NOT NULL,
    puede_crear      BOOLEAN     NOT NULL DEFAULT FALSE,
    puede_leer       BOOLEAN     NOT NULL DEFAULT FALSE,
    puede_actualizar BOOLEAN     NOT NULL DEFAULT FALSE,
    puede_eliminar   BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_rol_permiso_entidad UNIQUE (rol_id, entidad)
);

-- 3.32 rol_permiso_columna (visibilidad/edición por columna)
CREATE TABLE rol_permiso_columna (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rol_id       UUID        NOT NULL REFERENCES rol(id) ON DELETE CASCADE,
    entidad      VARCHAR(60) NOT NULL,
    columna      VARCHAR(60) NOT NULL,
    puede_ver    BOOLEAN     NOT NULL DEFAULT TRUE,
    puede_editar BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_rol_permiso_columna UNIQUE (rol_id, entidad, columna)
);

-- 3.33 usuario_rol (asignación de roles a usuarios)
CREATE TABLE usuario_rol (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id   UUID        NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    rol_id       UUID        NOT NULL REFERENCES rol(id) ON DELETE CASCADE,
    asignado_por UUID        REFERENCES usuario(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_usuario_rol UNIQUE (usuario_id, rol_id)
);

-- ================================================================
-- 4. INDICES
-- ================================================================
CREATE INDEX idx_usuario_tenant            ON usuario(tenant_id);
CREATE INDEX idx_vehiculo_tenant           ON vehiculo(tenant_id);
CREATE INDEX idx_vehiculo_conductor        ON vehiculo(conductor_id);
CREATE INDEX idx_taller_tenant             ON taller(tenant_id);
CREATE INDEX idx_taller_disponible         ON taller(tenant_id, disponible) WHERE disponible;
CREATE INDEX idx_tecnico_taller            ON tecnico(taller_id);
CREATE INDEX idx_especialidad_taller       ON especialidad_taller(taller_id);
CREATE INDEX idx_especialidad_tenant       ON especialidad_taller(tenant_id);
CREATE INDEX idx_tecnico_especialidad_esp  ON tecnico_especialidad(especialidad_id);
CREATE INDEX idx_incidente_tenant          ON incidente(tenant_id);
CREATE INDEX idx_incidente_conductor       ON incidente(conductor_id);
CREATE INDEX idx_incidente_estado          ON incidente(tenant_id, estado);
CREATE INDEX idx_incidente_tipo            ON incidente(tipo_incidente_id);
CREATE INDEX idx_incidente_reportado       ON incidente(tenant_id, reportado_at);
CREATE INDEX idx_incidente_sync            ON incidente(estado_sincronizacion) WHERE estado_sincronizacion = 'PENDIENTE';
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
CREATE INDEX idx_calificacion_taller       ON calificacion_servicio(taller_id);
CREATE INDEX idx_rol_tenant                ON rol(tenant_id);
CREATE INDEX idx_permiso_entidad_rol       ON rol_permiso_entidad(rol_id);
CREATE INDEX idx_permiso_columna_rol       ON rol_permiso_columna(rol_id);
CREATE INDEX idx_usuario_rol_usuario       ON usuario_rol(usuario_id);
CREATE INDEX idx_usuario_rol_rol           ON usuario_rol(rol_id);

-- ================================================================
-- 5. TRIGGERS
-- ================================================================
DO $$ DECLARE t TEXT; tablas TEXT[] := ARRAY[
    'plan','tenant','usuario','vehiculo','taller','tarifa','especialidad_taller','tecnico',
    'incidente','asignacion','cotizacion','pago','sla_config','rol'];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON emergencias.%1$s FOR EACH ROW EXECUTE FUNCTION emergencias.fn_set_updated_at();', t);
  END LOOP;
END $$;

-- comision automatica en pago (CU-31)
CREATE OR REPLACE FUNCTION fn_calcular_comision()
RETURNS TRIGGER AS $$
DECLARE v_comision NUMERIC(5,4);
BEGIN
  SELECT comision_plataforma INTO v_comision FROM tenant WHERE id = NEW.tenant_id;
  v_comision := COALESCE(v_comision, 0.10);
  NEW.comision_plataforma := ROUND(NEW.monto * v_comision, 2);
  NEW.monto_taller        := NEW.monto - NEW.comision_plataforma;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pago_comision BEFORE INSERT OR UPDATE OF monto ON pago FOR EACH ROW EXECUTE FUNCTION fn_calcular_comision();

-- historial de estados + timestamps (CU-36, CU-42)
CREATE OR REPLACE FUNCTION fn_incidente_estado()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO incidente_estado_historial (tenant_id, incidente_id, estado_anterior, estado_nuevo)
    VALUES (NEW.tenant_id, NEW.id, NULL, NEW.estado);
    RETURN NEW;
  END IF;
  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    INSERT INTO incidente_estado_historial (tenant_id, incidente_id, estado_anterior, estado_nuevo)
    VALUES (NEW.tenant_id, NEW.id, OLD.estado, NEW.estado);
    CASE NEW.estado
      WHEN 'TALLER_ASIGNADO' THEN NEW.asignado_at  := COALESCE(NEW.asignado_at,  now());
      WHEN 'EN_CAMINO'       THEN NEW.aceptado_at   := COALESCE(NEW.aceptado_at,   now());
                                   NEW.en_camino_at  := COALESCE(NEW.en_camino_at,  now());
      WHEN 'EN_ATENCION'     THEN NEW.atendido_at   := COALESCE(NEW.atendido_at,   now());
      WHEN 'FINALIZADO'      THEN NEW.finalizado_at := COALESCE(NEW.finalizado_at, now());
      ELSE NULL;
    END CASE;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_incidente_estado_ins AFTER INSERT ON incidente FOR EACH ROW EXECUTE FUNCTION fn_incidente_estado();
CREATE TRIGGER trg_incidente_estado_upd BEFORE UPDATE ON incidente FOR EACH ROW EXECUTE FUNCTION fn_incidente_estado();

-- ================================================================
-- 6. ROW LEVEL SECURITY
-- ================================================================
DO $$ DECLARE t TEXT; tablas TEXT[] := ARRAY[
    'usuario','vehiculo','taller','tarifa','especialidad_taller','tecnico',
    'incidente','evidencia','clasificacion_ia','incidente_estado_historial',
    'taller_candidato','asignacion','cotizacion','pago','factura',
    'notificacion','conexion_ws','ubicacion_tracking','sync_mapping','sla_config'];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    EXECUTE format('ALTER TABLE emergencias.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format(
      'CREATE POLICY pol_%1$s_tenant ON emergencias.%1$s
         USING (tenant_id = emergencias.fn_current_tenant() OR emergencias.fn_current_tenant() IS NULL)
         WITH CHECK (tenant_id = emergencias.fn_current_tenant() OR emergencias.fn_current_tenant() IS NULL);', t);
  END LOOP;
END $$;

-- Tablas RBAC sin tenant_id — NO aplicar RLS (el aislamiento se logra vía RLS de "rol")
ALTER TABLE emergencias.rol_permiso_entidad DISABLE ROW LEVEL SECURITY;
ALTER TABLE emergencias.rol_permiso_columna DISABLE ROW LEVEL SECURITY;
ALTER TABLE emergencias.usuario_rol DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_rol_permiso_entidad_tenant ON emergencias.rol_permiso_entidad;
DROP POLICY IF EXISTS pol_rol_permiso_columna_tenant ON emergencias.rol_permiso_columna;
DROP POLICY IF EXISTS pol_usuario_rol_tenant ON emergencias.usuario_rol;

-- RLS especial para incidente: permite leer incidentes con tenant_id NULL (conductores sin taller)
ALTER TABLE emergencias.incidente ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_incidente_tenant ON emergencias.incidente;
CREATE POLICY pol_incidente_tenant ON emergencias.incidente
  USING (
    tenant_id IS NULL
    OR tenant_id = emergencias.fn_current_tenant()
    OR emergencias.fn_current_tenant() IS NULL
  )
  WITH CHECK (
    tenant_id = emergencias.fn_current_tenant()
    OR emergencias.fn_current_tenant() IS NULL
  );

-- RLS especial para vehiculo: permite leer vehículos con tenant_id NULL (conductores sin taller)
ALTER TABLE emergencias.vehiculo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_vehiculo_tenant ON emergencias.vehiculo;
CREATE POLICY pol_vehiculo_tenant ON emergencias.vehiculo
  USING (
    tenant_id IS NULL
    OR tenant_id = emergencias.fn_current_tenant()
    OR emergencias.fn_current_tenant() IS NULL
  )
  WITH CHECK (
    tenant_id = emergencias.fn_current_tenant()
    OR emergencias.fn_current_tenant() IS NULL
  );

-- ================================================================
-- 7. VISTAS Y KPIs (CU-42, CU-43, CU-45)
-- ================================================================
CREATE OR REPLACE VIEW vw_incidente_metricas AS
SELECT i.id, i.tenant_id, i.tipo_incidente_id, ti.codigo AS tipo_codigo, ti.nombre AS tipo_nombre, i.estado, i.prioridad, i.latitud, i.longitud,
       i.reportado_at, i.asignado_at, i.aceptado_at, i.atendido_at, i.finalizado_at,
       EXTRACT(EPOCH FROM (i.asignado_at  - i.reportado_at)) / 60.0 AS min_asignacion,
       EXTRACT(EPOCH FROM (i.atendido_at  - i.asignado_at))  / 60.0 AS min_llegada,
       EXTRACT(EPOCH FROM (i.aceptado_at  - i.asignado_at))  / 60.0 AS min_respuesta_taller,
       EXTRACT(EPOCH FROM (i.finalizado_at - i.reportado_at)) / 60.0 AS min_total,
       (i.estado = 'CANCELADO') AS es_cancelado,
       (i.estado = 'NO_ATENDIDO') AS es_no_atendido
FROM incidente i LEFT JOIN tipo_incidente ti ON ti.id = i.tipo_incidente_id;

CREATE MATERIALIZED VIEW mv_kpi_resumen_tenant AS
SELECT tenant_id, COUNT(*) total_incidentes,
       COUNT(*) FILTER (WHERE estado IN ('FINALIZADO','PAGADO')) total_finalizados,
       COUNT(*) FILTER (WHERE es_cancelado) total_cancelados,
       COUNT(*) FILTER (WHERE es_no_atendido) total_no_atendidos,
       ROUND(AVG(min_asignacion)::numeric,2) prom_min_asignacion,
       ROUND(AVG(min_llegada)::numeric,2)    prom_min_llegada,
       ROUND(AVG(min_respuesta_taller)::numeric,2) prom_min_respuesta_taller,
       ROUND(AVG(min_total)::numeric,2)      prom_min_total,
       ROUND(100.0*COUNT(*) FILTER (WHERE es_cancelado)/NULLIF(COUNT(*),0),2) pct_cancelacion
FROM vw_incidente_metricas GROUP BY tenant_id;
CREATE UNIQUE INDEX uq_mv_kpi_resumen ON mv_kpi_resumen_tenant(tenant_id);

CREATE MATERIALIZED VIEW mv_kpi_incidentes_por_tipo AS
SELECT tenant_id, COALESCE(tipo_codigo,'SIN_CLASIFICAR') tipo_codigo, COALESCE(tipo_nombre,'Sin clasificar') tipo_nombre,
       COUNT(*) total, ROUND(AVG(min_total)::numeric,2) prom_min_total
FROM vw_incidente_metricas GROUP BY tenant_id, tipo_codigo, tipo_nombre;
CREATE INDEX idx_mv_tipo_tenant ON mv_kpi_incidentes_por_tipo(tenant_id);

CREATE MATERIALIZED VIEW mv_kpi_talleres_eficientes AS
SELECT t.tenant_id, t.id taller_id, t.nombre taller_nombre, t.calificacion,
       COUNT(a.id) FILTER (WHERE a.estado='ACEPTADO') servicios_aceptados,
       COUNT(a.id) FILTER (WHERE a.estado='RECHAZADO') servicios_rechazados,
       ROUND(AVG(EXTRACT(EPOCH FROM (a.respondido_at-a.asignado_at))/60.0) FILTER (WHERE a.estado='ACEPTADO')::numeric,2) prom_min_respuesta,
       ROUND(AVG(m.min_total) FILTER (WHERE i.estado IN ('FINALIZADO','PAGADO'))::numeric,2) prom_min_finalizacion
FROM taller t LEFT JOIN asignacion a ON a.taller_id=t.id
LEFT JOIN incidente i ON i.id=a.incidente_id LEFT JOIN vw_incidente_metricas m ON m.id=i.id
GROUP BY t.tenant_id, t.id, t.nombre, t.calificacion;
CREATE INDEX idx_mv_talleres_tenant ON mv_kpi_talleres_eficientes(tenant_id);

CREATE MATERIALIZED VIEW mv_kpi_zonas AS
SELECT tenant_id, ROUND(latitud,2) zona_lat, ROUND(longitud,2) zona_lng, COUNT(*) total_incidentes
FROM vw_incidente_metricas WHERE latitud IS NOT NULL AND longitud IS NOT NULL
GROUP BY tenant_id, ROUND(latitud,2), ROUND(longitud,2);
CREATE INDEX idx_mv_zonas_tenant ON mv_kpi_zonas(tenant_id);

CREATE MATERIALIZED VIEW mv_kpi_sla AS
SELECT m.tenant_id, m.tipo_codigo, m.tipo_nombre, s.tiempo_max_min, COUNT(*) total_evaluados,
       COUNT(*) FILTER (WHERE m.min_total <= s.tiempo_max_min) dentro_sla,
       COUNT(*) FILTER (WHERE m.min_total >  s.tiempo_max_min) fuera_sla,
       ROUND(100.0*COUNT(*) FILTER (WHERE m.min_total<=s.tiempo_max_min)/NULLIF(COUNT(*),0),2) pct_cumplimiento
FROM vw_incidente_metricas m JOIN sla_config s ON s.tenant_id=m.tenant_id AND s.tipo_incidente_id=m.tipo_incidente_id
WHERE m.min_total IS NOT NULL GROUP BY m.tenant_id, m.tipo_codigo, m.tipo_nombre, s.tiempo_max_min;
CREATE INDEX idx_mv_sla_tenant ON mv_kpi_sla(tenant_id);

CREATE MATERIALIZED VIEW mv_kpi_comisiones AS
SELECT p.tenant_id, a.taller_id, t.nombre taller_nombre, COUNT(p.id) total_pagos,
       ROUND(SUM(p.monto)::numeric,2) total_cobrado,
       ROUND(SUM(p.comision_plataforma)::numeric,2) total_comision_plataforma,
       ROUND(SUM(p.monto_taller)::numeric,2) total_neto_taller
FROM pago p JOIN asignacion a ON a.incidente_id=p.incidente_id AND a.estado='ACEPTADO'
JOIN taller t ON t.id=a.taller_id WHERE p.estado='COMPLETADO'
GROUP BY p.tenant_id, a.taller_id, t.nombre;
CREATE INDEX idx_mv_comisiones_tenant ON mv_kpi_comisiones(tenant_id);

CREATE OR REPLACE FUNCTION refrescar_kpis() RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_kpi_resumen_tenant;
  REFRESH MATERIALIZED VIEW mv_kpi_incidentes_por_tipo;
  REFRESH MATERIALIZED VIEW mv_kpi_talleres_eficientes;
  REFRESH MATERIALIZED VIEW mv_kpi_zonas;
  REFRESH MATERIALIZED VIEW mv_kpi_sla;
  REFRESH MATERIALIZED VIEW mv_kpi_comisiones;
END; $$ LANGUAGE plpgsql;

-- ================================================================
-- 8. ROL ADMIN Y PERMISOS (BYPASSRLS)
-- ================================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_admin') THEN
    CREATE ROLE app_admin LOGIN PASSWORD 'postgres' BYPASSRLS;
  END IF;
END $$;
GRANT ALL ON SCHEMA emergencias TO app_admin;
GRANT ALL ON ALL TABLES    IN SCHEMA emergencias TO app_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA emergencias TO app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA emergencias GRANT ALL ON TABLES TO app_admin;

-- ================================================================
-- 9. SEED - Datos de demostración
--    Hash bcrypt de 'password123' = $2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW
-- ================================================================
SELECT set_config('app.current_tenant', '', false);

INSERT INTO plan (id, nombre, max_talleres, max_tecnicos, ia_avanzada, precio_mensual) VALUES
 ('11111111-0000-0000-0000-000000000001','basico',      5,   20, FALSE,   0.00),
 ('11111111-0000-0000-0000-000000000002','profesional', 25, 100, TRUE,  199.00),
 ('11111111-0000-0000-0000-000000000003','enterprise', 500,5000, TRUE,  999.00);

INSERT INTO tenant (id, nombre, dominio, plan_id, comision_plataforma) VALUES
 ('22222222-0000-0000-0000-000000000001','Auxilio Norte','auxilionorte.com','11111111-0000-0000-0000-000000000002',0.10),
 ('22222222-0000-0000-0000-000000000002','RutaSegura',  'rutasegura.com', '11111111-0000-0000-0000-000000000003',0.10),
 ('22222222-0000-0000-0000-000000000000','Publico',     NULL,             '11111111-0000-0000-0000-000000000001',0.10);

INSERT INTO tipo_incidente (id, codigo, nombre, prioridad_sugerida) VALUES
 ('33333333-0000-0000-0000-000000000001','BATERIA_CARGADOR', 'Problema en cargador/alternador','MEDIA'),
 ('33333333-0000-0000-0000-000000000002','BATERIA_DESCARGADA','Bateria descargada','MEDIA'),
 ('33333333-0000-0000-0000-000000000003','LLANTA_PRESION',   'Baja presion de llanta','MEDIA'),
 ('33333333-0000-0000-0000-000000000004','LLANTA_PINCHAZO',  'Llanta pinchada','MEDIA'),
 ('33333333-0000-0000-0000-000000000005','FRENOS',           'Falla en sistema de frenos','ALTA'),
 ('33333333-0000-0000-0000-000000000006','MOTOR',            'Falla en motor','ALTA'),
 ('33333333-0000-0000-0000-000000000007','SUSPENSION',       'Problema de suspension/ESP','MEDIA'),
 ('33333333-0000-0000-0000-000000000008','AIRBAG',           'Airbag o cinturon de seguridad','ALTA'),
 ('33333333-0000-0000-0000-000000000009','COLISION_DENT',    'Abolladura por colision','ALTA'),
 ('33333333-0000-0000-0000-000000000010','COLISION_SCRATCH', 'Rayadura/aranazo','ALTA'),
 ('33333333-0000-0000-0000-000000000011','COLISION_CRAK',    'Grieta o quebrado','ALTA'),
 ('33333333-0000-0000-0000-000000000012','VIDRIOS_LUCES',    'Vidrio o lampara rota','ALTA'),
 ('33333333-0000-0000-0000-000000000013','OTROS',            'Otros','BAJA');

INSERT INTO usuario (id, tenant_id, rol, nombre, email, telefono, password_hash, email_verificado) VALUES
 ('44444444-0000-0000-0000-0000000000a0',NULL,'ADMIN_PLATAFORMA','Super Admin', 'admin@plataforma.com','70000000','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000a1','22222222-0000-0000-0000-000000000001','ADMIN_TENANT','Ana Gerente',  'ana@auxilionorte.com','71000001','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000a2',NULL,'CONDUCTOR','Carlos Perez', 'carlos@mail.com',     '71000002','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000a3',NULL,'CONDUCTOR','Diana Lopez',  'diana@mail.com',      '71000003','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000a4','22222222-0000-0000-0000-000000000001','TALLER',      'Taller Centro','centro@auxilionorte.com','71000004','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000a5','22222222-0000-0000-0000-000000000001','TALLER',      'Taller Sur',   'sur@auxilionorte.com','71000005','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000a6','22222222-0000-0000-0000-000000000001','TECNICO',     'Luis Mecanico','luis@auxilionorte.com','71000006','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000b1','22222222-0000-0000-0000-000000000002','ADMIN_TENANT','Beto Jefe',    'beto@rutasegura.com', '72000001','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000b2',NULL,'CONDUCTOR','Elena Ruiz',   'elena@mail.com',      '72000002','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE),
 ('44444444-0000-0000-0000-0000000000b4','22222222-0000-0000-0000-000000000002','TALLER',      'Taller Rapido', 'rapido@rutasegura.com','72000004','$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW',TRUE);

INSERT INTO vehiculo (id, tenant_id, conductor_id, placa, marca, modelo, anio, color, tipo_combustible) VALUES
 ('55555555-0000-0000-0000-000000000001',NULL,'44444444-0000-0000-0000-0000000000a2','ABC123','Toyota','Corolla',2018,'Blanco','gasolina'),
 ('55555555-0000-0000-0000-000000000002',NULL,'44444444-0000-0000-0000-0000000000a3','XYZ789','Nissan','Versa',2020,'Gris','gasolina'),
 ('55555555-0000-0000-0000-000000000003',NULL,'44444444-0000-0000-0000-0000000000b2','RUT456','Volkswagen','Gol',2019,'Rojo','gasolina');

INSERT INTO taller (id, tenant_id, usuario_id, nombre, direccion, latitud, longitud, telefono, disponible, capacidad_max, calificacion) VALUES
 ('66666666-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001','44444444-0000-0000-0000-0000000000a4','Taller Centro','Av. Canoto 100', -17.783300,-63.182100,'33445566',TRUE,5,4.7),
 ('66666666-0000-0000-0000-000000000002','22222222-0000-0000-0000-000000000001','44444444-0000-0000-0000-0000000000a5','Taller Sur',   'Av. Santos 500', -17.810000,-63.170000,'33447788',TRUE,3,4.2),
 ('66666666-0000-0000-0000-000000000003','22222222-0000-0000-0000-000000000002','44444444-0000-0000-0000-0000000000b4','Taller Rapido', 'Av. Banzer 999', -17.750000,-63.160000,'33449900',TRUE,4,4.9);

INSERT INTO taller_servicio (taller_id, tipo_incidente_id) VALUES
 ('66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000001'),
 ('66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000002'),
 ('66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000004'),
 ('66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000006'),
 ('66666666-0000-0000-0000-000000000002','33333333-0000-0000-0000-000000000001'),
 ('66666666-0000-0000-0000-000000000002','33333333-0000-0000-0000-000000000004'),
 ('66666666-0000-0000-0000-000000000002','33333333-0000-0000-0000-000000000009'),
 ('66666666-0000-0000-0000-000000000003','33333333-0000-0000-0000-000000000002'),
 ('66666666-0000-0000-0000-000000000003','33333333-0000-0000-0000-000000000009');

INSERT INTO especialidad_taller (id, tenant_id, taller_id, nombre) VALUES
 ('88888888-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','Charging System Issue'),
 ('88888888-0000-0000-0000-000000000002','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','Check Engine'),
 ('88888888-0000-0000-0000-000000000003','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','SRS-Airbag'),
 ('88888888-0000-0000-0000-000000000004','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000002','tire flat'),
 ('88888888-0000-0000-0000-000000000005','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000002','dent'),
 ('88888888-0000-0000-0000-0000-000000000006','22222222-0000-0000-0000-000000000002','66666666-0000-0000-0000-000000000003','scratch'),
 ('88888888-0000-0000-0000-000000000007','22222222-0000-0000-0000-000000000002','66666666-0000-0000-0000-000000000003','crack');

INSERT INTO tarifa (tenant_id, taller_id, tipo_incidente_id, precio_base, tiempo_base_min) VALUES
 ('22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000001',50.00,20),
 ('22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000002',40.00,30),
 ('22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000003',250.00,90),
 ('22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000002','33333333-0000-0000-0000-000000000004',300.00,120),
 ('22222222-0000-0000-0000-000000000002','66666666-0000-0000-0000-000000000003','33333333-0000-0000-0000-000000000004',320.00,110);

INSERT INTO tecnico (id, tenant_id, taller_id, usuario_id, nombre, telefono, especialidad) VALUES
 ('77777777-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','44444444-0000-0000-0000-0000000000a6','Luis Mecanico','71000006','Electricidad'),
 ('77777777-0000-0000-0000-000000000002','22222222-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000002',NULL,                              'Pedro Llantas','71000007','Neumaticos'),
 ('77777777-0000-0000-0000-000000000003','22222222-0000-0000-0000-000000000002','66666666-0000-0000-0000-000000000003',NULL,                              'Mario Motor',  '72000007','Mecanica general');

INSERT INTO tecnico_especialidad (tecnico_id, especialidad_id) VALUES
 ('77777777-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001'),
 ('77777777-0000-0000-0000-000000000002','88888888-0000-0000-0000-000000000004'),
 ('77777777-0000-0000-0000-000000000003','88888888-0000-0000-0000-000000000006'),
 ('77777777-0000-0000-0000-000000000003','88888888-0000-0000-0000-000000000007');

INSERT INTO sla_config (tenant_id, tipo_incidente_id, tiempo_max_min) VALUES
 ('22222222-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000001',30),
 ('22222222-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000002',45),
 ('22222222-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000003',90),
 ('22222222-0000-0000-0000-000000000001','33333333-0000-0000-0000-000000000004',60),
 ('22222222-0000-0000-0000-000000000002','33333333-0000-0000-0000-000000000004',60);

INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, direccion, descripcion, resumen_ia, tiempo_estimado_min,
        reportado_at, asignado_at, aceptado_at, en_camino_at, atendido_at, finalizado_at) VALUES
 ('88888888-0000-0000-0000-000000000001',NULL,'44444444-0000-0000-0000-0000000000a2','55555555-0000-0000-0000-000000000001',
  '33333333-0000-0000-0000-000000000001','PAGADO','MEDIA',
  -17.784000,-63.181000,'Av. Canoto y 2do anillo','No arranca, creo que es la bateria.',
  'Incidente tipo BATERIA reportado en Av. Canoto. Vehiculo Toyota Corolla.',20,
  now()-interval '3 hours',now()-interval '2 hours 52 minutes',now()-interval '2 hours 50 minutes',
  now()-interval '2 hours 49 minutes',now()-interval '2 hours 40 minutes',now()-interval '2 hours 25 minutes');

INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, direccion, descripcion,
        reportado_at, asignado_at, aceptado_at, en_camino_at) VALUES
 ('88888888-0000-0000-0000-000000000002',NULL,'44444444-0000-0000-0000-0000000000a3','55555555-0000-0000-0000-000000000002',
  '33333333-0000-0000-0000-000000000004','EN_CAMINO','ALTA',
  -17.809000,-63.171000,'Av. Santos Dumont 6to anillo','Choque leve, dano en parachoques.',
  now()-interval '40 minutes',now()-interval '34 minutes',now()-interval '30 minutes',now()-interval '30 minutes');

INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, estado, prioridad,
        latitud, longitud, direccion, descripcion, reportado_at) VALUES
 ('88888888-0000-0000-0000-000000000003',NULL,'44444444-0000-0000-0000-0000000000a2','55555555-0000-0000-0000-000000000001',
  'PENDIENTE','INCIERTA',-17.790000,-63.185000,'Tercer anillo interno','Ruido extrano en el motor.',now()-interval '5 minutes');

INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, descripcion, motivo_cancelacion, reportado_at) VALUES
 ('88888888-0000-0000-0000-000000000004',NULL,'44444444-0000-0000-0000-0000000000a3','55555555-0000-0000-0000-000000000002',
  '33333333-0000-0000-0000-000000000002','CANCELADO','MEDIA',-17.795000,-63.175000,'Llanta baja, pero pude inflarla.',
  'El conductor resolvio por su cuenta.',now()-interval '1 day');

INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, direccion, descripcion, tiempo_estimado_min,
        reportado_at, asignado_at, aceptado_at, en_camino_at, atendido_at, finalizado_at) VALUES
 ('88888888-0000-0000-0000-000000000005',NULL,'44444444-0000-0000-0000-0000000000b2','55555555-0000-0000-0000-000000000003',
  '33333333-0000-0000-0000-000000000004','FINALIZADO','ALTA',
  -17.751000,-63.161000,'Av. Banzer 4to anillo','Colision en interseccion.',110,
  now()-interval '6 hours',now()-interval '5 hours 56 minutes',now()-interval '5 hours 54 minutes',
  now()-interval '5 hours 53 minutes',now()-interval '5 hours 30 minutes',now()-interval '4 hours 20 minutes');

INSERT INTO evidencia (tenant_id, incidente_id, tipo, url, transcripcion) VALUES
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','IMAGEN','s3://demo/bat1.jpg',NULL),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','AUDIO','s3://demo/bat1.aac','El auto no enciende, las luces estan debiles.'),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000002','IMAGEN','s3://demo/choque1.jpg',NULL);

INSERT INTO clasificacion_ia (tenant_id, incidente_id, fuente, tipo_incidente_id, etiqueta, confianza, prioridad_sugerida, modelo) VALUES
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','COMBINADA','33333333-0000-0000-0000-000000000001','bateria',0.93,'MEDIA','cnn-v1+bart'),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000002','IMAGEN',   '33333333-0000-0000-0000-000000000004','choque', 0.88,'ALTA', 'cnn-v1');

INSERT INTO taller_candidato (tenant_id, incidente_id, taller_id, distancia_km, tiempo_llegada_min, puntaje) VALUES
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001',1.20,6,0.95),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000002',3.40,12,0.70),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000002','66666666-0000-0000-0000-000000000002',0.90,5,0.97);

INSERT INTO asignacion (tenant_id, incidente_id, taller_id, tecnico_id, estado, asignacion_automatica, asignado_at, respondido_at) VALUES
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','77777777-0000-0000-0000-000000000001','ACEPTADO',TRUE, now()-interval '2 hours 52 minutes',now()-interval '2 hours 50 minutes'),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000002','66666666-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000002','ACEPTADO',TRUE, now()-interval '34 minutes',         now()-interval '30 minutes'),
 ('22222222-0000-0000-0000-000000000002','88888888-0000-0000-0000-000000000005','66666666-0000-0000-0000-000000000003','77777777-0000-0000-0000-000000000003','ACEPTADO',FALSE,now()-interval '5 hours 56 minutes', now()-interval '5 hours 54 minutes');

INSERT INTO cotizacion (id, tenant_id, incidente_id, taller_id, origen, monto, detalle, estado, valida_hasta) VALUES
 ('99999999-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','66666666-0000-0000-0000-000000000001','TALLER',50.00, 'Cambio de bateria estandar.','ACEPTADA',now()+interval '1 day'),
 ('99999999-0000-0000-0000-000000000005','22222222-0000-0000-0000-000000000002','88888888-0000-0000-0000-000000000005','66666666-0000-0000-0000-000000000003','TALLER',320.00,'Reparacion de parachoques y pintura.','ACEPTADA',now()+interval '1 day');

INSERT INTO pago (id, tenant_id, incidente_id, cotizacion_id, monto, metodo, pasarela, token_transaccion, estado, pagado_at) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000001',50.00,'tarjeta','stripe','tok_demo_001','COMPLETADO',now()-interval '2 hours 20 minutes'),
 ('aaaaaaaa-0000-0000-0000-000000000005','22222222-0000-0000-0000-000000000002','88888888-0000-0000-0000-000000000005','99999999-0000-0000-0000-000000000005',320.00,'transferencia','mercadopago','tok_demo_005','COMPLETADO',now()-interval '4 hours 15 minutes');

INSERT INTO factura (tenant_id, pago_id, numero, url_pdf) VALUES
 ('22222222-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','FAC-2026-0001','s3://demo/fac0001.pdf'),
 ('22222222-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000005','FAC-2026-0005','s3://demo/fac0005.pdf');

INSERT INTO notificacion (tenant_id, usuario_id, incidente_id, canal, titulo, mensaje, enviada, leida, enviada_at) VALUES
 ('22222222-0000-0000-0000-000000000001','44444444-0000-0000-0000-0000000000a4','88888888-0000-0000-0000-000000000001','PUSH','Nueva solicitud','Tiene una emergencia de bateria asignada.',TRUE,TRUE,now()-interval '2 hours 52 minutes'),
 ('22222222-0000-0000-0000-000000000001','44444444-0000-0000-0000-0000000000a3','88888888-0000-0000-0000-000000000002','WEBSOCKET','Tecnico en camino','El tecnico va en camino a su ubicacion.',TRUE,FALSE,now()-interval '30 minutes');

INSERT INTO ubicacion_tracking (tenant_id, incidente_id, tecnico_id, latitud, longitud, created_at) VALUES
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000002',-17.810500,-63.169500,now()-interval '28 minutes'),
 ('22222222-0000-0000-0000-000000000001','88888888-0000-0000-0000-000000000002','77777777-0000-0000-0000-000000000002',-17.809500,-63.170500,now()-interval '20 minutes');

SELECT emergencias.refrescar_kpis();

-- ================================================================
-- 10. SEED RBAC — Roles base + permisos + restricciones por columna
-- ================================================================

-- 10.1 Roles base (1 global + 4 por tenant activo)
-- ADMIN_PLATAFORMA: global, sin tenant
INSERT INTO rol (id, tenant_id, nombre, descripcion, es_base, base_rol) VALUES
 ('aaaa0000-0000-0000-0000-000000000001', NULL, 'Admin Plataforma',
  'Superusuario global. Control total sobre todos los tenants, usuarios y configuraciones.',
  TRUE, 'ADMIN_PLATAFORMA');

-- Tenant Auxilio Norte
INSERT INTO rol (id, tenant_id, nombre, descripcion, es_base, base_rol) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a1', '22222222-0000-0000-0000-000000000001',
  'Admin Tenant', 'Administrador de la red de talleres. Control total dentro de su tenant.',
  TRUE, 'ADMIN_TENANT'),
 ('aaaa0000-0000-0000-0000-0000000000a2', '22222222-0000-0000-0000-000000000001',
  'Conductor', 'Cliente que reporta emergencias y gestiona su cuenta.',
  TRUE, 'CONDUCTOR'),
 ('aaaa0000-0000-0000-0000-0000000000a3', '22222222-0000-0000-0000-000000000001',
  'Taller', 'Representante del taller mecánico. Gestiona asignaciones y cotizaciones.',
  TRUE, 'TALLER'),
 ('aaaa0000-0000-0000-0000-0000000000a4', '22222222-0000-0000-0000-000000000001',
  'Técnico', 'Empleado que se desplaza al lugar del incidente. Comparte ubicación.',
  TRUE, 'TECNICO');

-- Tenant RutaSegura
INSERT INTO rol (id, tenant_id, nombre, descripcion, es_base, base_rol) VALUES
 ('aaaa0000-0000-0000-0000-0000000000b1', '22222222-0000-0000-0000-000000000002',
  'Admin Tenant', 'Administrador de la red de talleres.',
  TRUE, 'ADMIN_TENANT'),
 ('aaaa0000-0000-0000-0000-0000000000b2', '22222222-0000-0000-0000-000000000002',
  'Conductor', 'Cliente que reporta emergencias.',
  TRUE, 'CONDUCTOR'),
 ('aaaa0000-0000-0000-0000-0000000000b3', '22222222-0000-0000-0000-000000000002',
  'Taller', 'Representante del taller.',
  TRUE, 'TALLER'),
 ('aaaa0000-0000-0000-0000-0000000000b4', '22222222-0000-0000-0000-000000000002',
  'Técnico', 'Empleado que atiende en ruta.',
  TRUE, 'TECNICO');

-- 10.2 Permisos CRUD por entidad por rol — ADMIN_PLATAFORMA (todo CRUD)
-- Se insertan como template del admin global; los otros roles se copian después.
-- Formato: (rol_id, entidad, crear, leer, actualizar, eliminar)

-- ADMIN_PLATAFORMA: CRUD absoluto en TODAS las entidades
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-000000000001', 'plan',                      TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'tenant',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'usuario',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'vehiculo',                  TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'taller',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'tecnico',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'especialidad_taller',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'tipo_incidente',            TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'incidente',                 TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'evidencia',                 TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'clasificacion_ia',          TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'incidente_estado_historial',TRUE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-000000000001', 'taller_candidato',          TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'asignacion',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'cotizacion',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'pago',                      TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'factura',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'notificacion',              TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'conexion_ws',               TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'ubicacion_tracking',        TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'sync_mapping',              TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'sla_config',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'calificacion_servicio',     TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'auditoria',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-000000000001', 'rol',                       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'rol_permiso_entidad',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'rol_permiso_columna',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'usuario_rol',               TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'tarifa',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'taller_servicio',           TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'token_recuperacion',        TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'token_revocado',            TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-000000000001', 'tecnico_especialidad',      TRUE,TRUE,TRUE,TRUE);

-- 10.3 ADMIN_TENANT (Auxilio Norte) — CRUD dentro de su tenant, auditoría solo lectura
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a1', 'plan',                      FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'tenant',                    FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'usuario',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'vehiculo',                  TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'taller',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'tecnico',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'especialidad_taller',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'incidente',                 TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'evidencia',                 TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'clasificacion_ia',          TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'incidente_estado_historial',FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'taller_candidato',          TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'asignacion',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'cotizacion',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'pago',                      TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'factura',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'notificacion',              TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'conexion_ws',               TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'ubicacion_tracking',        TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'sync_mapping',              TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'sla_config',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'calificacion_servicio',     TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'auditoria',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'rol',                       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'rol_permiso_entidad',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'rol_permiso_columna',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'usuario_rol',               TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'tarifa',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'taller_servicio',           TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'token_recuperacion',        TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'token_revocado',            TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a1', 'tecnico_especialidad',      TRUE,TRUE,TRUE,TRUE);

-- 10.4 CONDUCTOR (Auxilio Norte) — CRUD propio, lectura limitada
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a2', 'plan',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'tenant',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'usuario',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'vehiculo',                  TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'taller',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'tecnico',                   FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'especialidad_taller',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'incidente',                 TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'evidencia',                 TRUE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'clasificacion_ia',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'incidente_estado_historial',FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'taller_candidato',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'asignacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'cotizacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'pago',                      TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'factura',                   FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'notificacion',              FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'conexion_ws',               FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'ubicacion_tracking',        FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'sync_mapping',              TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'sla_config',                FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'calificacion_servicio',     TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'auditoria',                 FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'rol',                       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'rol_permiso_entidad',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'rol_permiso_columna',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'usuario_rol',               FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'tarifa',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'taller_servicio',           FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'token_recuperacion',        FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'token_revocado',            FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'tecnico_especialidad',      FALSE,FALSE,FALSE,FALSE);

-- 10.5 TALLER (Auxilio Norte) — RU propio, lectura limitada, gestiona cotizaciones
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a3', 'plan',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'tenant',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'usuario',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'vehiculo',                  FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'taller',                    FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'tecnico',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'especialidad_taller',       FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'incidente',                 FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'evidencia',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'clasificacion_ia',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'incidente_estado_historial',FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'taller_candidato',          FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'asignacion',                FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'cotizacion',                TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'pago',                      FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'factura',                   FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'notificacion',              FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'conexion_ws',               FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'ubicacion_tracking',        FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'sync_mapping',              FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'sla_config',                FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'calificacion_servicio',     FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'auditoria',                 FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'rol',                       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'rol_permiso_entidad',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'rol_permiso_columna',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'usuario_rol',               FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'tarifa',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'taller_servicio',           FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'token_recuperacion',        FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'token_revocado',            FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'tecnico_especialidad',      FALSE,TRUE,FALSE,FALSE);

-- 10.6 TECNICO (Auxilio Norte) — R propio, RU ubicación, lectura limitada
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a4', 'plan',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'tenant',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'usuario',                   FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'vehiculo',                  FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'taller',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'tecnico',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'especialidad_taller',       FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'incidente',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'evidencia',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'clasificacion_ia',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'incidente_estado_historial',FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'taller_candidato',          FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'asignacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'cotizacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'pago',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'factura',                   FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'notificacion',              FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'conexion_ws',               FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'ubicacion_tracking',        TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'sync_mapping',              FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'sla_config',                FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'calificacion_servicio',     FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'auditoria',                 FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'rol',                       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'rol_permiso_entidad',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'rol_permiso_columna',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'usuario_rol',               FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'tarifa',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'taller_servicio',           FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'token_recuperacion',        FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'token_revocado',            FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'tecnico_especialidad',      FALSE,TRUE,FALSE,FALSE);

-- 10.7 Repetir para Tenant RutaSegura (roles b1-b4) — misma matriz
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000b1', 'plan',                      FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'tenant',                    FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'usuario',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'vehiculo',                  TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'taller',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'tecnico',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'especialidad_taller',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'incidente',                 TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'evidencia',                 TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'clasificacion_ia',          TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'incidente_estado_historial',FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'taller_candidato',          TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'asignacion',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'cotizacion',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'pago',                      TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'factura',                   TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'notificacion',              TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'conexion_ws',               TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'ubicacion_tracking',        TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'sync_mapping',              TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'sla_config',                TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'calificacion_servicio',     TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'auditoria',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'rol',                       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'rol_permiso_entidad',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'rol_permiso_columna',       TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'usuario_rol',               TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'tarifa',                    TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'taller_servicio',           TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'token_recuperacion',        TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'token_revocado',            TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b1', 'tecnico_especialidad',      TRUE,TRUE,TRUE,TRUE);

-- CONDUCTOR RutaSegura (b2)
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000b2', 'plan',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'tenant',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'usuario',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'vehiculo',                  TRUE,TRUE,TRUE,TRUE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'taller',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'tecnico',                   FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'especialidad_taller',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'incidente',                 TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'evidencia',                 TRUE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'clasificacion_ia',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'incidente_estado_historial',FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'taller_candidato',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'asignacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'cotizacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'pago',                      TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'factura',                   FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'notificacion',              FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'conexion_ws',               FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'ubicacion_tracking',        FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'sync_mapping',              TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'sla_config',                FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'calificacion_servicio',     TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'auditoria',                 FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'rol',                       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'rol_permiso_entidad',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'rol_permiso_columna',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'usuario_rol',               FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'tarifa',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'taller_servicio',           FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'token_recuperacion',        FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'token_revocado',            FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'tecnico_especialidad',      FALSE,FALSE,FALSE,FALSE);

-- TALLER RutaSegura (b3)
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000b3', 'plan',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'tenant',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'usuario',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'vehiculo',                  FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'taller',                    FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'tecnico',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'especialidad_taller',       FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'incidente',                 FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'evidencia',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'clasificacion_ia',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'incidente_estado_historial',FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'taller_candidato',          FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'asignacion',                FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'cotizacion',                TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'pago',                      FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'factura',                   FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'notificacion',              FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'conexion_ws',               FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'ubicacion_tracking',        FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'sync_mapping',              FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'sla_config',                FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'calificacion_servicio',     FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'auditoria',                 FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'rol',                       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'rol_permiso_entidad',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'rol_permiso_columna',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'usuario_rol',               FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'tarifa',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'taller_servicio',           FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'token_recuperacion',        FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'token_revocado',            FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'tecnico_especialidad',      FALSE,TRUE,FALSE,FALSE);

-- TECNICO RutaSegura (b4)
INSERT INTO rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000b4', 'plan',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'tenant',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'usuario',                   FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'vehiculo',                  FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'taller',                    FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'tecnico',                   FALSE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'especialidad_taller',       FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'tipo_incidente',            FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'incidente',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'evidencia',                 FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'clasificacion_ia',          FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'incidente_estado_historial',FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'taller_candidato',          FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'asignacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'cotizacion',                FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'pago',                      FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'factura',                   FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'notificacion',              FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'conexion_ws',               FALSE,TRUE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'ubicacion_tracking',        TRUE,TRUE,TRUE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'sync_mapping',              FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'sla_config',                FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'calificacion_servicio',     FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'auditoria',                 FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'rol',                       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'rol_permiso_entidad',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'rol_permiso_columna',       FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'usuario_rol',               FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'tarifa',                    FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'taller_servicio',           FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'token_recuperacion',        FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'token_revocado',            FALSE,FALSE,FALSE,FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'tecnico_especialidad',      FALSE,TRUE,FALSE,FALSE);

-- 10.8 Restricciones por columna — TECNICO no ve email/password_hash de usuarios
-- Auxilio Norte (a4) + RutaSegura (b4)
INSERT INTO rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a4', 'usuario', 'email',         FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'usuario', 'password_hash', FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'usuario', 'fcm_token',     FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'incidente', 'external_id',               FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'incidente', 'estado_sincronizacion',      FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a4', 'incidente', 'dispositivo_origen',         FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'usuario', 'email',         FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'usuario', 'password_hash', FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'usuario', 'fcm_token',     FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'incidente', 'external_id',               FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'incidente', 'estado_sincronizacion',      FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b4', 'incidente', 'dispositivo_origen',         FALSE, FALSE);

-- 10.9 Restricciones — TALLER no ve comision_plataforma ni monto_taller de pago
INSERT INTO rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a3', 'pago', 'comision_plataforma', FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'pago', 'monto_taller',       FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'pago', 'comision_plataforma', FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'pago', 'monto_taller',       FALSE, FALSE);

-- 10.10 Restricciones — CONDUCTOR no ve password_hash de otros usuarios
INSERT INTO rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a2', 'usuario', 'password_hash', FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a2', 'usuario', 'fcm_token',     FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'usuario', 'password_hash', FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b2', 'usuario', 'fcm_token',     FALSE, FALSE);

-- 10.11 Restricciones — TALLER no ve external_id ni estado_sincronizacion
INSERT INTO rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar) VALUES
 ('aaaa0000-0000-0000-0000-0000000000a3', 'incidente', 'external_id',               FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'incidente', 'estado_sincronizacion',      FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000a3', 'incidente', 'dispositivo_origen',         FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'incidente', 'external_id',               FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'incidente', 'estado_sincronizacion',      FALSE, FALSE),
 ('aaaa0000-0000-0000-0000-0000000000b3', 'incidente', 'dispositivo_origen',         FALSE, FALSE);

-- 10.12 Asignar roles base a los usuarios existentes del seed
INSERT INTO usuario_rol (usuario_id, rol_id, asignado_por) VALUES
 -- Super Admin (tiene el rol global Admin Plataforma)
 ('44444444-0000-0000-0000-0000000000a0', 'aaaa0000-0000-0000-0000-000000000001', NULL),
 -- Tenant Auxilio Norte
 ('44444444-0000-0000-0000-0000000000a1', 'aaaa0000-0000-0000-0000-0000000000a1', '44444444-0000-0000-0000-0000000000a0'),
 ('44444444-0000-0000-0000-0000000000a2', 'aaaa0000-0000-0000-0000-0000000000a2', '44444444-0000-0000-0000-0000000000a1'),
 ('44444444-0000-0000-0000-0000000000a3', 'aaaa0000-0000-0000-0000-0000000000a2', '44444444-0000-0000-0000-0000000000a1'),
 ('44444444-0000-0000-0000-0000000000a4', 'aaaa0000-0000-0000-0000-0000000000a3', '44444444-0000-0000-0000-0000000000a1'),
 ('44444444-0000-0000-0000-0000000000a5', 'aaaa0000-0000-0000-0000-0000000000a3', '44444444-0000-0000-0000-0000000000a1'),
 ('44444444-0000-0000-0000-0000000000a6', 'aaaa0000-0000-0000-0000-0000000000a4', '44444444-0000-0000-0000-0000000000a1'),
 -- Tenant RutaSegura
 ('44444444-0000-0000-0000-0000000000b1', 'aaaa0000-0000-0000-0000-0000000000b1', '44444444-0000-0000-0000-0000000000a0'),
 ('44444444-0000-0000-0000-0000000000b2', 'aaaa0000-0000-0000-0000-0000000000b2', '44444444-0000-0000-0000-0000000000b1'),
 ('44444444-0000-0000-0000-0000000000b4', 'aaaa0000-0000-0000-0000-0000000000b3', '44444444-0000-0000-0000-0000000000b1');