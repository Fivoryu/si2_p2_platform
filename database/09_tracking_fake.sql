-- CU-34/CU-37: permite distinguir ubicaciones reales de puntos de simulacion.

ALTER TABLE emergencias.ubicacion_tracking
    ADD COLUMN IF NOT EXISTS es_fake BOOLEAN NOT NULL DEFAULT FALSE;
