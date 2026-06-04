-- =====================================================================
--  Plataforma de Emergencias Vehiculares - Vistas analíticas y KPIs
--  Cubre CU-42 (Dashboard), CU-43 (filtro por tenant) y CU-45 (SLA).
-- ---------------------------------------------------------------------
--  Todos los KPIs se calculan con SQL agregado sobre datos REALES
--  (no valores fijos), tal como exige el enunciado (Análisis 3.3).
--  Las vistas materializadas se refrescan periódicamente o bajo demanda:
--      SELECT emergencias.refrescar_kpis();
-- =====================================================================

SET search_path TO emergencias, public;

-- ---------------------------------------------------------------------
-- Vista base: métricas por incidente (tiempos derivados en minutos)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_incidente_metricas AS
SELECT
    i.id,
    i.tenant_id,
    i.tipo_incidente_id,
    ti.codigo                                   AS tipo_codigo,
    ti.nombre                                   AS tipo_nombre,
    i.estado,
    i.prioridad,
    i.latitud,
    i.longitud,
    i.reportado_at,
    i.asignado_at,
    i.aceptado_at,
    i.atendido_at,
    i.finalizado_at,
    -- Tiempo de asignación: creación -> asignación de taller.
    EXTRACT(EPOCH FROM (i.asignado_at  - i.reportado_at)) / 60.0 AS min_asignacion,
    -- Tiempo de llegada: asignación -> técnico en el lugar.
    EXTRACT(EPOCH FROM (i.atendido_at  - i.asignado_at))  / 60.0 AS min_llegada,
    -- Tiempo de respuesta del taller: asignación -> aceptación.
    EXTRACT(EPOCH FROM (i.aceptado_at  - i.asignado_at))  / 60.0 AS min_respuesta_taller,
    -- Tiempo total de atención: creación -> finalización.
    EXTRACT(EPOCH FROM (i.finalizado_at - i.reportado_at)) / 60.0 AS min_total,
    (i.estado = 'CANCELADO')   AS es_cancelado,
    (i.estado = 'NO_ATENDIDO') AS es_no_atendido
FROM incidente i
LEFT JOIN tipo_incidente ti ON ti.id = i.tipo_incidente_id;

COMMENT ON VIEW vw_incidente_metricas IS 'Tiempos por incidente (minutos) usados por todos los KPIs.';

-- =====================================================================
-- KPI 1 - Resumen operacional por tenant
--   tiempo promedio de asignación / llegada, totales y cancelaciones.
-- =====================================================================
CREATE MATERIALIZED VIEW mv_kpi_resumen_tenant AS
SELECT
    tenant_id,
    COUNT(*)                                          AS total_incidentes,
    COUNT(*) FILTER (WHERE estado = 'FINALIZADO' OR estado = 'PAGADO') AS total_finalizados,
    COUNT(*) FILTER (WHERE es_cancelado)              AS total_cancelados,
    COUNT(*) FILTER (WHERE es_no_atendido)            AS total_no_atendidos,
    ROUND(AVG(min_asignacion)::numeric, 2)            AS prom_min_asignacion,
    ROUND(AVG(min_llegada)::numeric, 2)               AS prom_min_llegada,
    ROUND(AVG(min_respuesta_taller)::numeric, 2)      AS prom_min_respuesta_taller,
    ROUND(AVG(min_total)::numeric, 2)                 AS prom_min_total,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE es_cancelado) / NULLIF(COUNT(*), 0), 2
    )                                                 AS pct_cancelacion
FROM vw_incidente_metricas
GROUP BY tenant_id;

CREATE UNIQUE INDEX uq_mv_kpi_resumen ON mv_kpi_resumen_tenant(tenant_id);

-- =====================================================================
-- KPI 2 - Incidentes por tipo (batería, llanta, motor, choque, otros)
-- =====================================================================
CREATE MATERIALIZED VIEW mv_kpi_incidentes_por_tipo AS
SELECT
    tenant_id,
    COALESCE(tipo_codigo, 'SIN_CLASIFICAR') AS tipo_codigo,
    COALESCE(tipo_nombre, 'Sin clasificar') AS tipo_nombre,
    COUNT(*)                                AS total,
    ROUND(AVG(min_total)::numeric, 2)       AS prom_min_total
FROM vw_incidente_metricas
GROUP BY tenant_id, tipo_codigo, tipo_nombre;

CREATE INDEX idx_mv_tipo_tenant ON mv_kpi_incidentes_por_tipo(tenant_id);

-- =====================================================================
-- KPI 3 - Talleres más eficientes
--   ranking por tiempo de respuesta, tiempo de finalización y rechazos.
-- =====================================================================
CREATE MATERIALIZED VIEW mv_kpi_talleres_eficientes AS
SELECT
    t.tenant_id,
    t.id                                       AS taller_id,
    t.nombre                                   AS taller_nombre,
    t.calificacion,
    COUNT(a.id) FILTER (WHERE a.estado = 'ACEPTADO')  AS servicios_aceptados,
    COUNT(a.id) FILTER (WHERE a.estado = 'RECHAZADO') AS servicios_rechazados,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (a.respondido_at - a.asignado_at)) / 60.0
    ) FILTER (WHERE a.estado = 'ACEPTADO')::numeric, 2) AS prom_min_respuesta,
    ROUND(AVG(m.min_total) FILTER (WHERE i.estado IN ('FINALIZADO','PAGADO'))::numeric, 2) AS prom_min_finalizacion
FROM taller t
LEFT JOIN asignacion a ON a.taller_id = t.id
LEFT JOIN incidente  i ON i.id = a.incidente_id
LEFT JOIN vw_incidente_metricas m ON m.id = i.id
GROUP BY t.tenant_id, t.id, t.nombre, t.calificacion;

CREATE INDEX idx_mv_talleres_tenant ON mv_kpi_talleres_eficientes(tenant_id);

-- =====================================================================
-- KPI 4 - Zonas con más incidentes
--   agrupa por celdas geográficas (~1.1 km redondeando a 2 decimales).
-- =====================================================================
CREATE MATERIALIZED VIEW mv_kpi_zonas AS
SELECT
    tenant_id,
    ROUND(latitud,  2) AS zona_lat,
    ROUND(longitud, 2) AS zona_lng,
    COUNT(*)           AS total_incidentes
FROM vw_incidente_metricas
WHERE latitud IS NOT NULL AND longitud IS NOT NULL
GROUP BY tenant_id, ROUND(latitud, 2), ROUND(longitud, 2);

CREATE INDEX idx_mv_zonas_tenant ON mv_kpi_zonas(tenant_id);

-- =====================================================================
-- KPI 5 - Cumplimiento de SLA por tipo de incidente (CU-45)
--   compara el tiempo real de atención contra el umbral configurado.
-- =====================================================================
CREATE MATERIALIZED VIEW mv_kpi_sla AS
SELECT
    m.tenant_id,
    m.tipo_codigo,
    m.tipo_nombre,
    s.tiempo_max_min,
    COUNT(*)                                                   AS total_evaluados,
    COUNT(*) FILTER (WHERE m.min_total <= s.tiempo_max_min)    AS dentro_sla,
    COUNT(*) FILTER (WHERE m.min_total >  s.tiempo_max_min)    AS fuera_sla,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE m.min_total <= s.tiempo_max_min)
        / NULLIF(COUNT(*), 0), 2
    )                                                          AS pct_cumplimiento
FROM vw_incidente_metricas m
JOIN sla_config s
  ON s.tenant_id = m.tenant_id
 AND s.tipo_incidente_id = m.tipo_incidente_id
WHERE m.min_total IS NOT NULL
GROUP BY m.tenant_id, m.tipo_codigo, m.tipo_nombre, s.tiempo_max_min;

CREATE INDEX idx_mv_sla_tenant ON mv_kpi_sla(tenant_id);

-- =====================================================================
-- KPI 6 - Reporte de comisiones por taller (CU-31)
-- =====================================================================
CREATE MATERIALIZED VIEW mv_kpi_comisiones AS
SELECT
    p.tenant_id,
    a.taller_id,
    t.nombre                          AS taller_nombre,
    COUNT(p.id)                       AS total_pagos,
    ROUND(SUM(p.monto)::numeric, 2)               AS total_cobrado,
    ROUND(SUM(p.comision_plataforma)::numeric, 2) AS total_comision_plataforma,
    ROUND(SUM(p.monto_taller)::numeric, 2)        AS total_neto_taller
FROM pago p
JOIN asignacion a ON a.incidente_id = p.incidente_id AND a.estado = 'ACEPTADO'
JOIN taller t     ON t.id = a.taller_id
WHERE p.estado = 'COMPLETADO'
GROUP BY p.tenant_id, a.taller_id, t.nombre;

CREATE INDEX idx_mv_comisiones_tenant ON mv_kpi_comisiones(tenant_id);

-- =====================================================================
-- Función de refresco de todas las vistas materializadas (bajo demanda
-- o vía cron/pg_cron cada 15 min, según Análisis 3.3).
-- =====================================================================
CREATE OR REPLACE FUNCTION emergencias.refrescar_kpis()
RETURNS void AS $$
BEGIN
    -- CONCURRENTLY donde hay índice único (no bloquea lecturas).
    REFRESH MATERIALIZED VIEW CONCURRENTLY emergencias.mv_kpi_resumen_tenant;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_incidentes_por_tipo;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_talleres_eficientes;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_zonas;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_sla;
    REFRESH MATERIALIZED VIEW emergencias.mv_kpi_comisiones;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- Fin de vistas/KPIs. Ejecutar a continuación 03_seed.sql
-- =====================================================================
