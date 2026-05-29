-- Rol de administrador de plataforma (BYPASSRLS) — doc 00 §8
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_admin') THEN
    CREATE ROLE app_admin LOGIN PASSWORD 'postgres' BYPASSRLS;
  END IF;
END
$$;
GRANT ALL ON SCHEMA emergencias TO app_admin;
GRANT ALL ON ALL TABLES IN SCHEMA emergencias TO app_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA emergencias TO app_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA emergencias GRANT ALL ON TABLES TO app_admin;
