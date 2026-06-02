-- Usuario conductor de demostración (idempotente).
-- Contraseña: password123
-- Tenant: Auxilio Norte (22222222-0000-0000-0000-000000000001)

SET search_path TO emergencias, public;
SELECT set_config('app.current_tenant', '', false);

\set pwd '\'$2b$12$AbRiYB/AUGX.NbLA.yICd.D4gcMIsZcc.OW.Z/Ir3jhG7JZRjyYBW\''

INSERT INTO usuario (id, tenant_id, rol, nombre, email, telefono, password_hash, email_verificado, activo)
VALUES (
  '44444444-0000-0000-0000-0000000000d1',
  '22222222-0000-0000-0000-000000000001',
  'CONDUCTOR',
  'Usuario Demo Móvil',
  'demo.movil@mail.com',
  '71999999',
  :pwd,
  TRUE,
  TRUE
)
ON CONFLICT (tenant_id, email) DO UPDATE SET
  nombre = EXCLUDED.nombre,
  telefono = EXCLUDED.telefono,
  password_hash = EXCLUDED.password_hash,
  email_verificado = TRUE,
  activo = TRUE;

INSERT INTO vehiculo (id, tenant_id, conductor_id, placa, marca, modelo, anio, color, tipo_combustible)
VALUES (
  '55555555-0000-0000-0000-0000000000d1',
  '22222222-0000-0000-0000-000000000001',
  '44444444-0000-0000-0000-0000000000d1',
  'DEMO01',
  'Hyundai',
  'Tucson',
  2022,
  'Azul',
  'gasolina'
)
ON CONFLICT (conductor_id, placa) DO UPDATE SET
  marca = EXCLUDED.marca,
  modelo = EXCLUDED.modelo,
  anio = EXCLUDED.anio,
  color = EXCLUDED.color,
  tipo_combustible = EXCLUDED.tipo_combustible;
