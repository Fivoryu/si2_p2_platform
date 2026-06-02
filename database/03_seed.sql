-- =====================================================================
--  Plataforma de Emergencias Vehiculares - Datos de demostración
-- ---------------------------------------------------------------------
--  Crea 2 tenants ("Auxilio Norte" y "RutaSegura") + tenant público,
--  usuarios de cada rol, vehículos, talleres, técnicos, incidentes en
--  distintos estados, cotizaciones, pagos y configuración de SLA.
--  Permite ver KPIs reales tras: SELECT emergencias.refrescar_kpis();
--
--  NOTA: las contraseñas son hashes bcrypt de demostración del texto
--        'password123' (reemplazar en producción).
-- =====================================================================

SET search_path TO emergencias, public;

-- Ejecuta el seed como propietario, sin filtro de tenant activo
-- (las políticas RLS permiten acceso total cuando app.current_tenant es NULL).
SELECT set_config('app.current_tenant', '', false);

-- Hash bcrypt de 'password123' (passlib/bcrypt).
\set pwd '\'$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW\''

-- ---------------------------------------------------------------------
-- 1. Planes
-- ---------------------------------------------------------------------
INSERT INTO plan (id, nombre, max_talleres, max_tecnicos, ia_avanzada, precio_mensual) VALUES
 ('11111111-0000-0000-0000-000000000001', 'basico',       5,  20, FALSE,  0.00),
 ('11111111-0000-0000-0000-000000000002', 'profesional', 25, 100, TRUE,  199.00),
 ('11111111-0000-0000-0000-000000000003', 'enterprise',  500, 5000, TRUE, 999.00);

-- ---------------------------------------------------------------------
-- 2. Tenants
-- ---------------------------------------------------------------------
INSERT INTO tenant (id, nombre, dominio, plan_id, comision_plataforma) VALUES
 ('22222222-0000-0000-0000-000000000001', 'Auxilio Norte', 'auxilionorte.com',
        '11111111-0000-0000-0000-000000000002', 0.10),
 ('22222222-0000-0000-0000-000000000002', 'RutaSegura',    'rutasegura.com',
        '11111111-0000-0000-0000-000000000003', 0.10),
 ('22222222-0000-0000-0000-000000000000', 'Público',       NULL,
        '11111111-0000-0000-0000-000000000001', 0.10);

-- ---------------------------------------------------------------------
-- 3. Tipos de incidente (catálogo global - alineado con etiquetas YOLO)
-- ---------------------------------------------------------------------
INSERT INTO tipo_incidente (id, codigo, nombre, prioridad_sugerida) VALUES
 ('33333333-0000-0000-0000-000000000001', 'BATERIA_CARGADOR',   'Problema en cargador/alternador',       'MEDIA'),
 ('33333333-0000-0000-0000-000000000002', 'BATERIA_DESCARGADA', 'Batería descargada',                  'MEDIA'),
 ('33333333-0000-0000-0000-000000000003', 'LLANTA_PRESION',     'Baja presión de llanta',               'MEDIA'),
 ('33333333-0000-0000-0000-000000000004', 'LLANTA_PINCHAZO',    'Llanta pinchada',                      'MEDIA'),
 ('33333333-0000-0000-0000-000000000005', 'FRENOS',             'Falla en sistema de frenos',           'ALTA'),
 ('33333333-0000-0000-0000-000000000006', 'MOTOR',              'Falla en motor',                       'ALTA'),
 ('33333333-0000-0000-0000-000000000007', 'SUSPENSION',         'Problema de suspensión/ESP',           'MEDIA'),
 ('33333333-0000-0000-0000-000000000008', 'AIRBAG',             'Airbag o cinturón de seguridad',       'ALTA'),
 ('33333333-0000-0000-0000-000000000009', 'COLISION_DENT',      'Abolladura por colisión',             'ALTA'),
 ('33333333-0000-0000-0000-000000000010', 'COLISION_SCRATCH',   'Rayadura/arañazo',                    'ALTA'),
 ('33333333-0000-0000-0000-000000000011', 'COLISION_CRAK',      'Grieta o quebrado',                   'ALTA'),
 ('33333333-0000-0000-0000-000000000012', 'VIDRIOS_LUCES',      'Vidrio o lampara rota',               'ALTA'),
 ('33333333-0000-0000-0000-000000000013', 'OTROS',              'Otros',                               'BAJA');

-- ---------------------------------------------------------------------
-- 4. Usuarios (1 ADM global + por tenant: ADT, conductores, talleres, técnicos)
--    Hash bcrypt de 'password123'.
-- ---------------------------------------------------------------------
INSERT INTO usuario (id, tenant_id, rol, nombre, email, telefono, password_hash, email_verificado) VALUES
 -- Administrador de plataforma (sin tenant)
 ('44444444-0000-0000-0000-0000000000a0', NULL, 'ADMIN_PLATAFORMA', 'Super Admin', 'admin@plataforma.com', '70000000', :pwd, TRUE),

 -- Tenant Auxilio Norte
 ('44444444-0000-0000-0000-0000000000a1', '22222222-0000-0000-0000-000000000001', 'ADMIN_TENANT', 'Ana Gerente',   'ana@auxilionorte.com',  '71000001', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000a2', '22222222-0000-0000-0000-000000000001', 'CONDUCTOR',    'Carlos Pérez',  'carlos@mail.com',       '71000002', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000a3', '22222222-0000-0000-0000-000000000001', 'CONDUCTOR',    'Diana López',   'diana@mail.com',        '71000003', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000a4', '22222222-0000-0000-0000-000000000001', 'TALLER',       'Taller Centro', 'centro@auxilionorte.com','71000004', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000a5', '22222222-0000-0000-0000-000000000001', 'TALLER',       'Taller Sur',    'sur@auxilionorte.com',  '71000005', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000a6', '22222222-0000-0000-0000-000000000001', 'TECNICO',      'Luis Mecánico', 'luis@auxilionorte.com', '71000006', :pwd, TRUE),

 -- Tenant RutaSegura
 ('44444444-0000-0000-0000-0000000000b1', '22222222-0000-0000-0000-000000000002', 'ADMIN_TENANT', 'Beto Jefe',     'beto@rutasegura.com',   '72000001', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000b2', '22222222-0000-0000-0000-000000000002', 'CONDUCTOR',    'Elena Ruiz',    'elena@mail.com',        '72000002', :pwd, TRUE),
 ('44444444-0000-0000-0000-0000000000b4', '22222222-0000-0000-0000-000000000002', 'TALLER',       'Taller Rápido', 'rapido@rutasegura.com', '72000004', :pwd, TRUE);

-- ---------------------------------------------------------------------
-- 5. Vehículos
-- ---------------------------------------------------------------------
INSERT INTO vehiculo (id, tenant_id, conductor_id, placa, marca, modelo, anio, color, tipo_combustible) VALUES
 ('55555555-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a2', 'ABC123', 'Toyota',     'Corolla', 2018, 'Blanco', 'gasolina'),
 ('55555555-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a3', 'XYZ789', 'Nissan',     'Versa',   2020, 'Gris',   'gasolina'),
 ('55555555-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000002', '44444444-0000-0000-0000-0000000000b2', 'RUT456', 'Volkswagen', 'Gol',     2019, 'Rojo',   'gasolina');

-- ---------------------------------------------------------------------
-- 6. Talleres (coordenadas de Santa Cruz, Bolivia como referencia)
-- ---------------------------------------------------------------------
INSERT INTO taller (id, tenant_id, usuario_id, nombre, direccion, latitud, longitud, telefono, disponible, capacidad_max, calificacion) VALUES
 ('66666666-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a4', 'Taller Centro', 'Av. Cañoto 100',  -17.783300, -63.182100, '33445566', TRUE, 5, 4.7),
 ('66666666-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a5', 'Taller Sur',    'Av. Santos 500',  -17.810000, -63.170000, '33447788', TRUE, 3, 4.2),
 ('66666666-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000002', '44444444-0000-0000-0000-0000000000b4', 'Taller Rápido', 'Av. Banzer 999',  -17.750000, -63.160000, '33449900', TRUE, 4, 4.9);

-- Servicios que ofrece cada taller (actualizado a nuevos tipos)
INSERT INTO taller_servicio (taller_id, tipo_incidente_id) VALUES
 ('66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001'),
 ('66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000002'),
 ('66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000004'),
 ('66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000006'),
 ('66666666-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000001'),
 ('66666666-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000004'),
 ('66666666-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000009'),
 ('66666666-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000002'),
 ('66666666-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000009');

-- Especialidades por taller (nombres de etiquetas YOLO)
INSERT INTO especialidad_taller (id, tenant_id, taller_id, nombre) VALUES
 ('88888888-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Charging System Issue'),
 ('88888888-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'Check Engine'),
 ('88888888-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'SRS-Airbag'),
 ('88888888-0000-0000-0000-000000000004', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000002', 'tire flat'),
 ('88888888-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000002', 'dent'),
 ('88888888-0000-0000-0000-0000-000000000006', '22222222-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000003', 'scratch'),
 ('88888888-0000-0000-0000-000000000007', '22222222-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000003', 'crack');

-- Tarifas de referencia
INSERT INTO tarifa (tenant_id, taller_id, tipo_incidente_id, precio_base, tiempo_base_min) VALUES
 ('22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001',  50.00, 20),
 ('22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000002',  40.00, 30),
 ('22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000003', 250.00, 90),
 ('22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000004', 300.00, 120),
 ('22222222-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000004', 320.00, 110);

-- Técnicos
INSERT INTO tecnico (id, tenant_id, taller_id, usuario_id, nombre, telefono, especialidad) VALUES
 ('77777777-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a6', 'Luis Mecánico', '71000006', 'Electricidad'),
 ('77777777-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000002', NULL, 'Pedro Llantas', '71000007', 'Neumáticos'),
 ('77777777-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000003', NULL, 'Mario Motor',   '72000007', 'Mecánica general');

-- Asignación de especialidades a técnicos (catálogo del taller)
INSERT INTO tecnico_especialidad (tecnico_id, especialidad_id) VALUES
 ('77777777-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001'),
 ('77777777-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000004'),
 ('77777777-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000006'),
 ('77777777-0000-0000-0000-000000000003', '88888888-0000-0000-0000-000000000007');

-- ---------------------------------------------------------------------
-- 7. Configuración SLA por tenant (CU-45)
-- ---------------------------------------------------------------------
INSERT INTO sla_config (tenant_id, tipo_incidente_id, tiempo_max_min) VALUES
 ('22222222-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', 30),
 ('22222222-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000002', 45),
 ('22222222-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000003', 90),
 ('22222222-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000004', 60),
 ('22222222-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000004', 60);

-- ---------------------------------------------------------------------
-- 8. Incidentes en distintos estados (datos reales para KPIs)
--    Los timestamps se fijan explícitamente para simular historia.
-- ---------------------------------------------------------------------

-- 8.1 Incidente FINALIZADO + PAGADO (dentro de SLA) - batería
INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, direccion, descripcion, resumen_ia, tiempo_estimado_min,
        reportado_at, asignado_at, aceptado_at, en_camino_at, atendido_at, finalizado_at)
VALUES
 ('88888888-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001',
  '44444444-0000-0000-0000-0000000000a2', '55555555-0000-0000-0000-000000000001',
  '33333333-0000-0000-0000-000000000001', 'PAGADO', 'MEDIA',
  -17.784000, -63.181000, 'Av. Cañoto y 2do anillo', 'No arranca, creo que es la batería.',
  'Incidente tipo BATERIA reportado en Av. Cañoto. Vehículo Toyota Corolla.', 20,
  now() - interval '3 hours',
  now() - interval '2 hours 52 minutes',
  now() - interval '2 hours 50 minutes',
  now() - interval '2 hours 49 minutes',
  now() - interval '2 hours 40 minutes',
  now() - interval '2 hours 25 minutes');

-- 8.2 Incidente EN_CAMINO - choque (fuera de SLA potencial)
INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, direccion, descripcion,
        reportado_at, asignado_at, aceptado_at, en_camino_at)
VALUES
 ('88888888-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001',
  '44444444-0000-0000-0000-0000000000a3', '55555555-0000-0000-0000-000000000002',
  '33333333-0000-0000-0000-000000000004', 'EN_CAMINO', 'ALTA',
  -17.809000, -63.171000, 'Av. Santos Dumont 6to anillo', 'Choque leve, daño en parachoques.',
  now() - interval '40 minutes',
  now() - interval '34 minutes',
  now() - interval '30 minutes',
  now() - interval '30 minutes');

-- 8.3 Incidente PENDIENTE (recién reportado, sin clasificar aún) - Auxilio Norte
INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, estado, prioridad,
        latitud, longitud, direccion, descripcion, reportado_at)
VALUES
 ('88888888-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000001',
  '44444444-0000-0000-0000-0000000000a2', '55555555-0000-0000-0000-000000000001',
  'PENDIENTE', 'INCIERTA',
  -17.790000, -63.185000, 'Tercer anillo interno', 'Ruido extraño en el motor.',
  now() - interval '5 minutes');

-- 8.4 Incidente CANCELADO - Auxilio Norte
INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, descripcion, motivo_cancelacion, reportado_at)
VALUES
 ('88888888-0000-0000-0000-000000000004', '22222222-0000-0000-0000-000000000001',
  '44444444-0000-0000-0000-0000000000a3', '55555555-0000-0000-0000-000000000002',
  '33333333-0000-0000-0000-000000000002', 'CANCELADO', 'MEDIA',
  -17.795000, -63.175000, 'Llanta baja, pero pude inflarla.', 'El conductor resolvió por su cuenta.',
  now() - interval '1 day');

-- 8.5 Incidente FINALIZADO (RutaSegura) - choque dentro de SLA
INSERT INTO incidente (id, tenant_id, conductor_id, vehiculo_id, tipo_incidente_id, estado, prioridad,
        latitud, longitud, direccion, descripcion, tiempo_estimado_min,
        reportado_at, asignado_at, aceptado_at, en_camino_at, atendido_at, finalizado_at)
VALUES
 ('88888888-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000002',
  '44444444-0000-0000-0000-0000000000b2', '55555555-0000-0000-0000-000000000003',
  '33333333-0000-0000-0000-000000000004', 'FINALIZADO', 'ALTA',
  -17.751000, -63.161000, 'Av. Banzer 4to anillo', 'Colisión en intersección.', 110,
  now() - interval '6 hours',
  now() - interval '5 hours 56 minutes',
  now() - interval '5 hours 54 minutes',
  now() - interval '5 hours 53 minutes',
  now() - interval '5 hours 30 minutes',
  now() - interval '4 hours 20 minutes');

-- ---------------------------------------------------------------------
-- 9. Evidencias y clasificación de IA
-- ---------------------------------------------------------------------
INSERT INTO evidencia (tenant_id, incidente_id, tipo, url, transcripcion) VALUES
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'IMAGEN', 's3://demo/bat1.jpg', NULL),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'AUDIO',  's3://demo/bat1.aac', 'El auto no enciende, las luces están débiles.'),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', 'IMAGEN', 's3://demo/choque1.jpg', NULL);

INSERT INTO clasificacion_ia (tenant_id, incidente_id, fuente, tipo_incidente_id, etiqueta, confianza, prioridad_sugerida, modelo) VALUES
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', 'COMBINADA', '33333333-0000-0000-0000-000000000001', 'bateria', 0.93, 'MEDIA', 'cnn-v1+bart'),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', 'IMAGEN',    '33333333-0000-0000-0000-000000000004', 'choque',  0.88, 'ALTA',  'cnn-v1');

-- ---------------------------------------------------------------------
-- 10. Candidatos y asignaciones
-- ---------------------------------------------------------------------
INSERT INTO taller_candidato (tenant_id, incidente_id, taller_id, distancia_km, tiempo_llegada_min, puntaje) VALUES
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 1.20, 6, 0.95),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000002', 3.40, 12, 0.70),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002', 0.90, 5, 0.97);

INSERT INTO asignacion (tenant_id, incidente_id, taller_id, tecnico_id, estado, asignacion_automatica, asignado_at, respondido_at) VALUES
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000001', 'ACEPTADO', TRUE,  now() - interval '2 hours 52 minutes', now() - interval '2 hours 50 minutes'),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002', '77777777-0000-0000-0000-000000000002', 'ACEPTADO', TRUE,  now() - interval '34 minutes',          now() - interval '30 minutes'),
 ('22222222-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000005', '66666666-0000-0000-0000-000000000003', '77777777-0000-0000-0000-000000000003', 'ACEPTADO', FALSE, now() - interval '5 hours 56 minutes',  now() - interval '5 hours 54 minutes');

-- ---------------------------------------------------------------------
-- 11. Cotizaciones, pagos y facturas
-- ---------------------------------------------------------------------
INSERT INTO cotizacion (id, tenant_id, incidente_id, taller_id, origen, monto, detalle, estado, valida_hasta) VALUES
 ('99999999-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'TALLER', 50.00, 'Cambio de batería estándar.', 'ACEPTADA', now() + interval '1 day'),
 ('99999999-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000005', '66666666-0000-0000-0000-000000000003', 'TALLER', 320.00,'Reparación de parachoques y pintura.', 'ACEPTADA', now() + interval '1 day');

-- Pagos (la comisión 10% se calcula automáticamente por trigger).
INSERT INTO pago (id, tenant_id, incidente_id, cotizacion_id, monto, metodo, pasarela, token_transaccion, estado, pagado_at) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001',  50.00, 'tarjeta',      'stripe',      'tok_demo_001', 'COMPLETADO', now() - interval '2 hours 20 minutes'),
 ('aaaaaaaa-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000005', '99999999-0000-0000-0000-000000000005', 320.00, 'transferencia','mercadopago', 'tok_demo_005', 'COMPLETADO', now() - interval '4 hours 15 minutes');

INSERT INTO factura (tenant_id, pago_id, numero, url_pdf) VALUES
 ('22222222-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'FAC-2026-0001', 's3://demo/fac0001.pdf'),
 ('22222222-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000005', 'FAC-2026-0005', 's3://demo/fac0005.pdf');

-- ---------------------------------------------------------------------
-- 12. Notificaciones y tracking
-- ---------------------------------------------------------------------
INSERT INTO notificacion (tenant_id, usuario_id, incidente_id, canal, titulo, mensaje, enviada, leida, enviada_at) VALUES
 ('22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a4', '88888888-0000-0000-0000-000000000001', 'PUSH', 'Nueva solicitud', 'Tiene una emergencia de batería asignada.', TRUE, TRUE,  now() - interval '2 hours 52 minutes'),
 ('22222222-0000-0000-0000-000000000001', '44444444-0000-0000-0000-0000000000a3', '88888888-0000-0000-0000-000000000002', 'WEBSOCKET', 'Técnico en camino', 'El técnico va en camino a su ubicación.', TRUE, FALSE, now() - interval '30 minutes');

INSERT INTO ubicacion_tracking (tenant_id, incidente_id, tecnico_id, latitud, longitud, created_at) VALUES
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', '77777777-0000-0000-0000-000000000002', -17.810500, -63.169500, now() - interval '28 minutes'),
 ('22222222-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002', '77777777-0000-0000-0000-000000000002', -17.809500, -63.170500, now() - interval '20 minutes');

-- ---------------------------------------------------------------------
-- 13. Refrescar KPIs con los datos sembrados
-- ---------------------------------------------------------------------
SELECT emergencias.refrescar_kpis();

-- =====================================================================
-- Verificación rápida (opcional): descomentar para revisar KPIs.
-- ---------------------------------------------------------------------
-- SELECT * FROM emergencias.mv_kpi_resumen_tenant;
-- SELECT * FROM emergencias.mv_kpi_incidentes_por_tipo;
-- SELECT * FROM emergencias.mv_kpi_sla;
-- SELECT * FROM emergencias.mv_kpi_comisiones;
-- =====================================================================
