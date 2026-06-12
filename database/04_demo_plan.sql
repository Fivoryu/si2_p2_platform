-- =====================================================================
--  Plan demo 1 BOB para pruebas de pago de suscripción
-- ---------------------------------------------------------------------
--  Se ejecuta después de 01_schema.sql, 02_views_kpi.sql y 03_seed.sql
-- =====================================================================

SET search_path TO emergencias, public;

INSERT INTO plan (id, nombre, max_talleres, max_tecnicos, ia_avanzada, precio_mensual) VALUES
 ('11111111-0000-0000-0000-000000000004', 'demo', 3, 10, TRUE, 1.00)
ON CONFLICT (id) DO NOTHING;
