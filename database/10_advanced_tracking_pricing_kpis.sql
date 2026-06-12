-- Cierre 100%: tracking completo, scoring, pagos idempotentes y KPIs avanzados.

ALTER TABLE emergencias.ubicacion_tracking
    ADD COLUMN IF NOT EXISTS velocidad_kmh NUMERIC(7,2) CHECK (velocidad_kmh IS NULL OR velocidad_kmh >= 0),
    ADD COLUMN IF NOT EXISTS precision_m NUMERIC(8,2) CHECK (precision_m IS NULL OR precision_m >= 0),
    ADD COLUMN IF NOT EXISTS fuente VARCHAR(20) NOT NULL DEFAULT 'REAL';

ALTER TABLE emergencias.taller_candidato
    ADD COLUMN IF NOT EXISTS razones_json JSONB,
    ADD COLUMN IF NOT EXISTS rechazo_penalty NUMERIC(5,4) CHECK (rechazo_penalty IS NULL OR rechazo_penalty BETWEEN 0 AND 1),
    ADD COLUMN IF NOT EXISTS eficiencia_score NUMERIC(5,4) CHECK (eficiencia_score IS NULL OR eficiencia_score BETWEEN 0 AND 1),
    ADD COLUMN IF NOT EXISTS sla_score NUMERIC(5,4) CHECK (sla_score IS NULL OR sla_score BETWEEN 0 AND 1);

ALTER TABLE emergencias.cotizacion
    ADD COLUMN IF NOT EXISTS precio_min_recomendado NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS precio_max_recomendado NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS desglose_precio JSONB;

CREATE TABLE IF NOT EXISTS emergencias.pago_webhook_evento (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES emergencias.tenant(id) ON DELETE CASCADE,
    pasarela VARCHAR(40) NOT NULL,
    event_id VARCHAR(180) NOT NULL,
    pago_id UUID REFERENCES emergencias.pago(id) ON DELETE SET NULL,
    tipo VARCHAR(120),
    payload JSONB,
    procesado_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_pago_webhook_evento UNIQUE (pasarela, event_id)
);

CREATE INDEX IF NOT EXISTS idx_tracking_incidente_created
    ON emergencias.ubicacion_tracking(incidente_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_asignacion_rechazo_taller
    ON emergencias.asignacion(taller_id, respondido_at DESC)
    WHERE estado = 'RECHAZADO';

DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_taller_ranking;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_taller_ranking AS
SELECT
    t.tenant_id,
    t.id AS taller_id,
    t.nombre AS taller_nombre,
    t.calificacion AS rating_taller,
    COUNT(a.id) FILTER (WHERE a.estado = 'ACEPTADO') AS aceptadas,
    COUNT(a.id) FILTER (WHERE a.estado = 'RECHAZADO') AS rechazadas,
    ROUND(
      COALESCE(
        COUNT(a.id) FILTER (WHERE a.estado = 'RECHAZADO')::numeric /
        NULLIF(COUNT(a.id) FILTER (WHERE a.estado IN ('ACEPTADO','RECHAZADO')), 0),
        0
      ),
      4
    ) AS tasa_rechazo,
    ROUND(AVG(EXTRACT(EPOCH FROM (i.atendido_at - i.en_camino_at)) / 60.0)
      FILTER (WHERE i.atendido_at IS NOT NULL AND i.en_camino_at IS NOT NULL), 2) AS prom_llegada_min,
    COUNT(i.id) FILTER (WHERE i.estado IN ('FINALIZADO', 'PAGADO')) AS servicios_finalizados,
    ROUND(AVG(cs.estrellas), 2) AS rating_servicio
FROM emergencias.taller t
LEFT JOIN emergencias.asignacion a ON a.taller_id = t.id
LEFT JOIN emergencias.incidente i ON i.id = a.incidente_id
LEFT JOIN emergencias.calificacion_servicio cs ON cs.taller_id = t.id
GROUP BY t.tenant_id, t.id, t.nombre, t.calificacion;

CREATE INDEX IF NOT EXISTS idx_mv_taller_ranking_tenant
    ON emergencias.mv_kpi_taller_ranking(tenant_id);

DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_tecnico_ranking;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_tecnico_ranking AS
SELECT
    tec.tenant_id,
    tec.id AS tecnico_id,
    tec.taller_id,
    tec.nombre AS tecnico_nombre,
    COUNT(a.id) FILTER (WHERE a.estado = 'ACEPTADO') AS asignaciones_aceptadas,
    COUNT(i.id) FILTER (WHERE i.estado IN ('FINALIZADO', 'PAGADO')) AS servicios_finalizados,
    ROUND(AVG(EXTRACT(EPOCH FROM (i.atendido_at - i.en_camino_at)) / 60.0)
      FILTER (WHERE i.atendido_at IS NOT NULL AND i.en_camino_at IS NOT NULL), 2) AS prom_llegada_min
FROM emergencias.tecnico tec
LEFT JOIN emergencias.asignacion a ON a.tecnico_id = tec.id
LEFT JOIN emergencias.incidente i ON i.id = a.incidente_id
GROUP BY tec.tenant_id, tec.id, tec.taller_id, tec.nombre;

CREATE INDEX IF NOT EXISTS idx_mv_tecnico_ranking_tenant
    ON emergencias.mv_kpi_tecnico_ranking(tenant_id);

DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_demanda_hora;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_demanda_hora AS
SELECT
    tenant_id,
    date_trunc('hour', reportado_at) AS hora,
    COUNT(*) AS total_incidentes,
    ROUND(AVG(EXTRACT(EPOCH FROM (asignado_at - reportado_at)) / 60.0), 2) AS prom_asignacion_min
FROM emergencias.incidente
GROUP BY tenant_id, date_trunc('hour', reportado_at);

CREATE INDEX IF NOT EXISTS idx_mv_demanda_hora_tenant
    ON emergencias.mv_kpi_demanda_hora(tenant_id, hora DESC);

CREATE OR REPLACE FUNCTION emergencias.refrescar_kpis()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY emergencias.mv_kpi_resumen_tenant;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_incidentes_por_tipo;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_talleres_eficientes;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_zonas;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_sla;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_comisiones;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_taller_ranking;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_tecnico_ranking;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_demanda_hora;
END;
$$ LANGUAGE plpgsql;
