-- Especialidades por taller y asignación a técnicos (CU-08)
SET search_path TO emergencias, public;

CREATE TABLE IF NOT EXISTS especialidad_taller (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenant(id) ON DELETE CASCADE,
    taller_id           UUID NOT NULL REFERENCES taller(id) ON DELETE CASCADE,
    nombre              VARCHAR(80) NOT NULL,
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_especialidad_taller_nombre UNIQUE (taller_id, nombre)
);

CREATE TABLE IF NOT EXISTS tecnico_especialidad (
    tecnico_id          UUID NOT NULL REFERENCES tecnico(id) ON DELETE CASCADE,
    especialidad_id     UUID NOT NULL REFERENCES especialidad_taller(id) ON DELETE CASCADE,
    PRIMARY KEY (tecnico_id, especialidad_id)
);

CREATE INDEX IF NOT EXISTS idx_especialidad_taller ON especialidad_taller(taller_id);
CREATE INDEX IF NOT EXISTS idx_especialidad_tenant ON especialidad_taller(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tecnico_especialidad_esp ON tecnico_especialidad(especialidad_id);

DROP TRIGGER IF EXISTS trg_especialidad_taller_updated_at ON emergencias.especialidad_taller;
CREATE TRIGGER trg_especialidad_taller_updated_at
    BEFORE UPDATE ON emergencias.especialidad_taller
    FOR EACH ROW EXECUTE FUNCTION emergencias.fn_set_updated_at();

ALTER TABLE emergencias.especialidad_taller ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'emergencias' AND tablename = 'especialidad_taller'
          AND policyname = 'pol_especialidad_taller_tenant'
    ) THEN
        CREATE POLICY pol_especialidad_taller_tenant ON emergencias.especialidad_taller
            USING (tenant_id = emergencias.fn_current_tenant()
                   OR emergencias.fn_current_tenant() IS NULL)
            WITH CHECK (tenant_id = emergencias.fn_current_tenant()
                   OR emergencias.fn_current_tenant() IS NULL);
    END IF;
END $$;
