# Postman — Ciclo 1 (Usuarios y vehículos)

## Importar

1. Abre Postman → **Import** → selecciona:
   - `SI2_Ciclo1.postman_collection.json`
   - `SI2_Ciclo1.postman_environment.json`
2. Activa el environment **SI2 Local Docker**.
3. Asegúrate de tener el stack arriba: `docker compose up -d`
4. Ejecuta la carpeta **Ciclo 1** con **Run collection**.

## Postman MCP (Cursor)

Para usar el MCP de Postman desde Cursor necesitas configurar tu API key:

1. Postman → Settings → API Keys → Generate
2. En Cursor: configurar el plugin Postman con esa key
3. Luego puedes sincronizar esta colección con `createCollection` / import manual

> El MCP de Postman **no ejecuta** requests contra `localhost` desde la nube; usa **Collection Runner** local o el script `backend/tests/test_ciclo1_api.py`.

## Casos de uso cubiertos

| CU | Request |
|----|---------|
| CU-01 | Login conductor / taller / ADT |
| CU-02 | Logout |
| CU-03 | Forgot password |
| CU-04 | Register + login |
| CU-05 | POST/GET vehiculos |
| CU-06 | GET/PATCH usuarios/me |
| CU-07 | POST talleres |
| CU-08 | POST tecnicos |
| CU-09 | PATCH talleres/{id}/disponibilidad |
