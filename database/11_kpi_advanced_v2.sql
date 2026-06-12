-- =====================================================================
--  Cierre 100% KPIs avanzados faltantes:
--    Precio promedio por tipo, Relacion precio/calidad, Demanda por zona,
--    Tasa de aceptacion en ranking de talleres.
-- =====================================================================

SET search_path TO emergencias, public;

-- ---------------------------------------------------------------------
-- KPI Avanzado 9 - Precio promedio por tipo de incidente
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_precio_promedio_tipo;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_precio_promedio_tipo AS
SELECT
    i.tenant_id,
    ti.codigo                           AS tipo_codigo,
    ti.nombre                           AS tipo_nombre,
    ROUND(AVG(p.monto)::numeric, 2)     AS precio_promedio,
    ROUND(MIN(p.monto)::numeric, 2)     AS precio_min,
    ROUND(MAX(p.monto)::numeric, 2)     AS precio_max,
    COUNT(p.id)                         AS total_pagos
FROM emergencias.pago p
JOIN emergencias.incidente i     ON i.id = p.incidente_id
JOIN emergencias.tipo_incidente ti ON ti.id = i.tipo_incidente_id
WHERE p.estado = 'COMPLETADO'
GROUP BY i.tenant_id, ti.codigo, ti.nombre;

CREATE INDEX IF NOT EXISTS idx_mv_precio_tipo_tenant
    ON emergencias.mv_kpi_precio_promedio_tipo(tenant_id);

-- ---------------------------------------------------------------------
-- KPI Avanzado 10 - Relacion precio/calidad por taller
--   Muestra si talleres mas caros entregan mejor calidad.
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_precio_calidad;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_precio_calidad AS
WITH precio_taller AS (
    SELECT
        t.tenant_id,
        t.id            AS taller_id,
        t.nombre        AS taller_nombre,
        ROUND(AVG(p.monto)::numeric, 2) AS precio_promedio,
        COUNT(p.id)     AS servicios_pagados
    FROM emergencias.taller t
    JOIN emergencias.asignacion a ON a.taller_id = t.id AND a.estado = 'ACEPTADO'
    JOIN emergencias.pago p       ON p.incidente_id = a.incidente_id AND p.estado = 'COMPLETADO'
    GROUP BY t.tenant_id, t.id, t.nombre
),
rating_taller AS (
    SELECT
        taller_id,
        ROUND(AVG(estrellas)::numeric, 2) AS rating_promedio,
        COUNT(id)                          AS total_calificaciones
    FROM emergencias.calificacion_servicio
    GROUP BY taller_id
)
SELECT
    pt.tenant_id,
    pt.taller_id,
    pt.taller_nombre,
    pt.precio_promedio,
    COALESCE(rt.rating_promedio, 0)           AS rating_servicio,
    pt.servicios_pagados,
    rt.total_calificaciones,
    ROUND(
        CASE
            WHEN COALESCE(rt.rating_promedio, 0) > 0
            THEN (pt.precio_promedio / rt.rating_promedio)::numeric
            ELSE NULL
        END,
        2
    )                                         AS relacion_precio_calidad
FROM precio_taller pt
LEFT JOIN rating_taller rt ON rt.taller_id = pt.taller_id;

CREATE INDEX IF NOT EXISTS idx_mv_precio_calidad_tenant
    ON emergencias.mv_kpi_precio_calidad(tenant_id);

-- ---------------------------------------------------------------------
-- KPI Avanzado 8 - Demanda por zona (serie temporal, ultimos 30 dias)
--   Complementa mv_kpi_zonas (estatico) con evolucion diaria.
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_demanda_zona;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_demanda_zona AS
SELECT
    tenant_id,
    ROUND(latitud,  2)                      AS zona_lat,
    ROUND(longitud, 2)                      AS zona_lng,
    date_trunc('day', reportado_at)::date   AS fecha,
    COUNT(*)                                AS total_incidentes
FROM emergencias.incidente
WHERE latitud IS NOT NULL
  AND longitud IS NOT NULL
  AND reportado_at >= date_trunc('day', now()) - INTERVAL '30 days'
GROUP BY tenant_id, ROUND(latitud, 2), ROUND(longitud, 2), date_trunc('day', reportado_at);

CREATE INDEX IF NOT EXISTS idx_mv_demanda_zona_tenant
    ON emergencias.mv_kpi_demanda_zona(tenant_id, fecha DESC);

-- ---------------------------------------------------------------------
-- Modificar mv_kpi_taller_ranking: agregar tasa de aceptacion
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS emergencias.mv_kpi_taller_ranking;
CREATE MATERIALIZED VIEW emergencias.mv_kpi_taller_ranking AS
SELECT
    t.tenant_id,
    t.id AS taller_id,
    t.nombre AS taller_nombre,
    t.calificacion AS rating_taller,
    COUNT(a.id) FILTER (WHERE a.estado = 'ACEPTADO') AS aceptadas,
    COUNT(a.id) FILTER (WHERE a.estado = 'RECHAZADO') AS rechazadas,
    COALESCE(COUNT(a.id) FILTER (WHERE a.estado = 'ACEPTADO'), 0)
      + COALESCE(COUNT(a.id) FILTER (WHERE a.estado = 'RECHAZADO'), 0) AS total_asignaciones,
    ROUND(
      COALESCE(
        COUNT(a.id) FILTER (WHERE a.estado = 'RECHAZADO')::numeric /
        NULLIF(COUNT(a.id) FILTER (WHERE a.estado IN ('ACEPTADO','RECHAZADO')), 0),
        0
      ),
      4
    ) AS tasa_rechazo,
    ROUND(
      COALESCE(
        COUNT(a.id) FILTER (WHERE a.estado = 'ACEPTADO')::numeric /
        NULLIF(COUNT(a.id) FILTER (WHERE a.estado IN ('ACEPTADO','RECHAZADO')), 0),
        0
      ),
      4
    ) AS tasa_aceptacion,
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

-- ---------------------------------------------------------------------
-- Actualizar refrescar_kpis() con las nuevas vistas
-- ---------------------------------------------------------------------
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
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_precio_promedio_tipo;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_precio_calidad;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_demanda_zona;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- Fin de KPIs avanzados v2
-- =====================================================================
