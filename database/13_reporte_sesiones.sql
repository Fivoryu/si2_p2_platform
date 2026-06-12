-- Tabla para sesiones de reportes guardados
CREATE TABLE IF NOT EXISTS emergencias.reporte_sesion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES emergencias.tenant(id) ON DELETE CASCADE,
    usuario_id UUID NOT NULL REFERENCES emergencias.usuario(id) ON DELETE CASCADE,
    nombre VARCHAR(120) NOT NULL,
    widgets_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reporte_sesion_tenant ON emergencias.reporte_sesion(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reporte_sesion_usuario ON emergencias.reporte_sesion(usuario_id);
