-- =====================================================================
-- 12. RBAC permissions seed: permisos por defecto para cada rol base
-- =====================================================================
-- Se ejecuta después de 11_rbac.sql.
-- Si ya existen permisos, se saltan (idempotente).
-- =====================================================================

DO $$ BEGIN
-- ADMIN_TENANT: acceso completo CRUD a entidades de su tenant
INSERT INTO emergencias.rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar)
SELECT r.id, e.entidad, TRUE, TRUE, TRUE, TRUE
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('incidente'), ('asignacion'), ('cotizacion'), ('pago'),
  ('vehiculo'), ('taller'), ('tecnico'), ('notificacion'),
  ('usuario'), ('especialidad_taller'), ('tarifa'),
  ('rol'), ('rol_permiso_entidad'), ('rol_permiso_columna'), ('usuario_rol')
) AS e(entidad)
WHERE r.base_rol = 'ADMIN_TENANT' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_entidad rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
-- TALLER: leer incidentes, actualizar asignaciones que le pertenecen,
-- CRUD de su taller y técnicos, leer notificaciones
INSERT INTO emergencias.rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar)
SELECT r.id, e.entidad, e.c, e.r, e.u, e.d
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('incidente',        FALSE, TRUE,  TRUE,  FALSE),
  ('asignacion',       FALSE, TRUE,  TRUE,  FALSE),
  ('cotizacion',       FALSE, TRUE,  TRUE,  FALSE),
  ('vehiculo',         FALSE, TRUE,  FALSE, FALSE),
  ('taller',           FALSE, TRUE,  TRUE,  FALSE),
  ('tecnico',          TRUE,  TRUE,  TRUE,  TRUE),
  ('notificacion',     FALSE, TRUE,  FALSE, FALSE),
  ('especialidad_taller', FALSE, TRUE, FALSE, FALSE)
) AS e(entidad, c, r, u, d)
WHERE r.base_rol = 'TALLER' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_entidad rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
-- TECNICO: leer incidentes, actualizar ubicación, leer notificaciones
INSERT INTO emergencias.rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar)
SELECT r.id, e.entidad, e.c, e.r, e.u, e.d
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('incidente',    FALSE, TRUE,  TRUE,  FALSE),
  ('ubicacion_tracking', TRUE, TRUE, FALSE, FALSE),
  ('notificacion', FALSE, TRUE,  FALSE, FALSE),
  ('vehiculo',     FALSE, TRUE,  FALSE, FALSE),
  ('asignacion',   FALSE, TRUE,  FALSE, FALSE)
) AS e(entidad, c, r, u, d)
WHERE r.base_rol = 'TECNICO' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_entidad rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
-- CONDUCTOR: crear incidentes, leer historial, calificar, leer taller
INSERT INTO emergencias.rol_permiso_entidad (rol_id, entidad, puede_crear, puede_leer, puede_actualizar, puede_eliminar)
SELECT r.id, e.entidad, e.c, e.r, e.u, e.d
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('incidente',        TRUE,  TRUE,  FALSE, FALSE),
  ('evidencia',        TRUE,  TRUE,  FALSE, FALSE),
  ('vehiculo',         TRUE,  TRUE,  TRUE,  TRUE),
  ('calificacion_servicio', TRUE, TRUE, FALSE, FALSE),
  ('taller',           FALSE, TRUE,  FALSE, FALSE),
  ('cotizacion',       FALSE, TRUE,  TRUE,  FALSE),
  ('pago',             TRUE,  TRUE,  FALSE, FALSE)
) AS e(entidad, c, r, u, d)
WHERE r.base_rol = 'CONDUCTOR' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_entidad rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Permisos por columna: ADMIN_TENANT puede ver todo
DO $$ BEGIN
INSERT INTO emergencias.rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar)
SELECT r.id, 'incidente', col.columna, TRUE, TRUE
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('descripcion'), ('latitud'), ('longitud'), ('direccion'),
  ('prioridad'), ('estado'), ('tipo_incidente_id'), ('resumen_ia')
) AS col(columna)
WHERE r.base_rol = 'ADMIN_TENANT' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_columna rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
-- TALLER: no puede ver resumen_ia ni latitud/longitud exactas del conductor
INSERT INTO emergencias.rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar)
SELECT r.id, 'incidente', col.columna, col.ver, col.editar
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('descripcion',       TRUE,  TRUE),
  ('direccion',         TRUE,  FALSE),
  ('prioridad',         TRUE,  FALSE),
  ('estado',            TRUE,  TRUE),
  ('tipo_incidente_id', TRUE,  FALSE),
  ('latitud',           FALSE, FALSE),
  ('longitud',          FALSE, FALSE),
  ('resumen_ia',        FALSE, FALSE)
) AS col(columna, ver, editar)
WHERE r.base_rol = 'TALLER' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_columna rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
-- CONDUCTOR: puede ver todo de sus incidentes
INSERT INTO emergencias.rol_permiso_columna (rol_id, entidad, columna, puede_ver, puede_editar)
SELECT r.id, 'incidente', col.columna, TRUE, FALSE
FROM emergencias.rol r
CROSS JOIN (VALUES
  ('descripcion'), ('latitud'), ('longitud'), ('direccion'),
  ('prioridad'), ('estado'), ('tipo_incidente_id'), ('resumen_ia')
) AS col(columna)
WHERE r.base_rol = 'CONDUCTOR' AND r.es_base = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM emergencias.rol_permiso_columna rp WHERE rp.rol_id = r.id
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
