-- Ciclo 3: ofertas competitivas, precio sugerido, tiempo estimado y calificacion.

ALTER TABLE emergencias.cotizacion
    ADD COLUMN IF NOT EXISTS asignacion_id UUID REFERENCES emergencias.asignacion(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS precio_sugerido NUMERIC(10,2) CHECK (precio_sugerido IS NULL OR precio_sugerido >= 0),
    ADD COLUMN IF NOT EXISTS tiempo_estimado_min INTEGER CHECK (tiempo_estimado_min IS NULL OR tiempo_estimado_min >= 0),
    ADD COLUMN IF NOT EXISTS tiempo_llegada_min INTEGER CHECK (tiempo_llegada_min IS NULL OR tiempo_llegada_min >= 0),
    ADD COLUMN IF NOT EXISTS dificultad VARCHAR(20),
    ADD COLUMN IF NOT EXISTS comentario_taller TEXT;

ALTER TABLE emergencias.taller_candidato
    ADD COLUMN IF NOT EXISTS precio_sugerido NUMERIC(10,2) CHECK (precio_sugerido IS NULL OR precio_sugerido >= 0),
    ADD COLUMN IF NOT EXISTS dificultad VARCHAR(20);

CREATE UNIQUE INDEX IF NOT EXISTS uq_cotizacion_asignacion
    ON emergencias.cotizacion(asignacion_id)
    WHERE asignacion_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS emergencias.calificacion_servicio (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES emergencias.tenant(id) ON DELETE CASCADE,
    incidente_id UUID NOT NULL REFERENCES emergencias.incidente(id) ON DELETE CASCADE,
    taller_id UUID NOT NULL REFERENCES emergencias.taller(id) ON DELETE CASCADE,
    conductor_id UUID NOT NULL REFERENCES emergencias.usuario(id) ON DELETE CASCADE,
    estrellas INTEGER NOT NULL CHECK (estrellas BETWEEN 1 AND 5),
    comentario TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_calificacion_incidente UNIQUE (incidente_id)
);

CREATE INDEX IF NOT EXISTS idx_calificacion_taller
    ON emergencias.calificacion_servicio(taller_id);
