# Enunciado Completo - Segundo Parcial

## Plataforma Inteligente de Atencion de Emergencias Vehiculares

### 1. Contexto general

La plataforma desarrollada en el primer parcial permite conectar conductores con talleres mecanicos mediante una aplicacion movil, una aplicacion web, un backend en FastAPI, una base de datos PostgreSQL, geolocalizacion, procesamiento de evidencias, inteligencia artificial para clasificacion preliminar de incidentes, asignacion de talleres, notificaciones y trazabilidad del servicio.

En el segundo parcial, el sistema no debe rehacerse desde cero. Debe evolucionar la solucion existente hacia una plataforma mas cercana a un producto real en produccion, incorporando capacidades avanzadas de operacion: seguimiento en tiempo real, funcionamiento offline con sincronizacion, analitica operacional basada en datos reales y arquitectura SaaS multi-tenant.

La segunda fase debe demostrar que los nuevos modulos afectan el flujo principal del sistema. No se aceptan pantallas decorativas, datos fijos o funcionalidades aisladas.

### 2. Objetivo general

Evolucionar la Plataforma Inteligente de Atencion de Emergencias Vehiculares incorporando modulos de tiempo real, modo offline, sincronizacion, analitica operacional y arquitectura multi-tenant, garantizando trazabilidad, separacion de datos, continuidad operativa y soporte a decisiones administrativas basadas en informacion real.

### 3. Objetivos especificos

- Implementar seguimiento en tiempo real de incidentes mediante WebSockets y actualizacion de estados.
- Permitir que el conductor registre emergencias sin conexion y que estas se sincronicen automaticamente al recuperar internet.
- Evitar duplicados y resolver conflictos durante la sincronizacion de emergencias.
- Incorporar un dashboard de KPIs operacionales calculados desde registros reales de la base de datos.
- Permitir filtrar indicadores por tenant y restringir el acceso segun el rol autenticado.
- Implementar una arquitectura multi-tenant donde usuarios, talleres, incidentes, pagos, evidencias y metricas pertenezcan a una organizacion.
- Mantener integrados los modulos existentes del primer parcial: IA, asignacion, cotizaciones, pagos, notificaciones y trazabilidad.
- Generar documentacion PUDS/UML completa para requisitos, analisis, diseno, implementacion y pruebas.

### 4. Alcance funcional del segundo parcial

El segundo parcial se organiza en dos ciclos PUDS adicionales:

| Ciclo | Nombre | Proposito |
|------|--------|-----------|
| Ciclo 4 | Tiempo real, WebSockets y tracking | Permitir seguimiento en vivo del incidente, ubicacion del tecnico/taller y cambios de estado inmediatos. |
| Ciclo 5 | Offline, sincronizacion, KPIs y multi-tenant | Permitir continuidad sin conexion, analitica operacional y aislamiento de datos por organizacion. |

Los ciclos 1, 2 y 3 del primer parcial siguen siendo la base del sistema y deben integrarse con los nuevos modulos. El segundo parcial no reemplaza los flujos anteriores; los extiende.

## 5. Modulos obligatorios

### 5.1 Modulo de tiempo real: WebSockets y tracking

**Objetivo:** permitir que cliente, taller y sistema reciban actualizaciones en vivo durante la atencion de una emergencia.

**Casos de uso relacionados:**

- CU-33 Conectar a WebSocket para Seguimiento en Vivo.
- CU-34 Visualizar Ubicacion del Taller en Mapa.
- CU-35 Recibir Notificacion Inmediata de Cambio de Estado.
- CU-36 Actualizar Estado del Incidente.
- CU-37 Transmitir Llegada del Tecnico.

**Funcionalidades minimas:**

- El cliente debe poder abrir el seguimiento de una emergencia activa.
- El sistema debe establecer un canal WebSocket asociado a `tenant_id` e `incident_id`.
- El backend debe validar token, rol y pertenencia al tenant antes de aceptar la conexion.
- El taller debe actualizar estados reales del incidente desde la web.
- El cliente debe ver automaticamente los cambios de estado sin refrescar la pantalla.
- El tecnico o taller debe enviar ubicacion durante el estado `en camino`.
- El cliente debe visualizar la ubicacion del tecnico/taller en un mapa.
- El sistema debe notificar eventos clave: solicitud aceptada, solicitud rechazada, taller en camino, llegada del tecnico, atencion iniciada, servicio finalizado o cancelado.

**Estados sugeridos del incidente:**

- `pendiente`
- `buscando_taller`
- `taller_asignado`
- `en_camino`
- `en_atencion`
- `finalizado`
- `cancelado`

**Criterios de aceptacion:**

- Un cambio de estado realizado por el taller se refleja en la app movil del cliente en tiempo real.
- Si el tecnico actualiza su ubicacion, el marcador del mapa cambia sin recargar la pantalla.
- El WebSocket no permite acceso a incidentes de otro tenant.
- Si el cliente no esta conectado, se conserva la notificacion para mostrarla posteriormente.

### 5.2 Modulo offline y sincronizacion

**Objetivo:** permitir que la aplicacion movil registre emergencias aunque no exista conexion estable, y sincronizarlas automaticamente cuando vuelva internet.

**Casos de uso relacionados:**

- CU-38 Guardar Emergencia Localmente y Marcar como Pendiente de Sincronizacion.
- CU-40 Sincronizar Automaticamente al Recuperar Conexion.
- CU-41 Resolver Conflictos de Sincronizacion.

**Funcionalidades minimas:**

- La app movil debe detectar ausencia de conexion.
- Cuando no haya internet, el reporte de emergencia debe guardarse en SQLite/local storage con un `id_local` unico.
- La emergencia offline debe mostrarse en el historial con estado visual `pendiente de sincronizacion`.
- Al recuperar conexion, el servicio de sincronizacion debe enviar las emergencias pendientes al backend.
- El backend debe recibir lotes de sincronizacion mediante un endpoint como `POST /sync`.
- El backend debe registrar el incidente solo una vez aunque se reenvie el mismo lote.
- La app debe actualizar el estado local a `SINCRONIZADO` cuando el backend confirme la recepcion.
- Si ocurre error de sincronizacion, debe marcarse como `ERROR` y reintentarse posteriormente.

**Datos minimos a guardar localmente:**

- `id_local`
- `tenant_id`
- `usuario_id`
- `vehiculo_id`
- descripcion del incidente
- ubicacion
- evidencias referenciadas
- fecha/hora local
- estado de sincronizacion

**Criterios de aceptacion:**

- En modo avion, el conductor puede registrar una emergencia.
- La emergencia aparece como pendiente en el historial.
- Al recuperar internet, la emergencia se envia al backend y recibe `id_servidor`.
- Reenviar el mismo lote no duplica incidentes.
- El backend responde con estados como `CREATED`, `DUPLICATE` o `UPDATED`.

### 5.3 Modulo de cotizaciones, seleccion y pagos

**Objetivo:** consolidar el flujo operativo entre cliente y taller, permitiendo oferta editable, seleccion de taller, estimacion de tiempos y pago del servicio.

**Casos de uso relacionados:**

- CU-27 Generar Oferta/Cotizacion Competitiva.
- CU-28 Calcular Tiempo Estimado de Llegada y Reparacion.
- CU-29 Seleccionar Oferta de Taller.
- CU-30 Efectuar Pago del Servicio.
- CU-31 Consultar Comision del Taller.
- CU-32 Generar Factura / Comprobante.
- CU-49 Calificar Servicio Post-Atencion.

**Funcionalidades minimas:**

- El sistema debe sugerir una cotizacion base en funcion del tipo de incidente.
- El taller debe poder editar o confirmar su oferta.
- El cliente debe poder comparar y seleccionar una oferta.
- El sistema debe calcular un tiempo estimado de llegada y reparacion.
- El cliente debe pagar mediante pasarela de pagos.
- La plataforma debe registrar la comision del 10% correspondiente al taller.
- Al finalizar el servicio, el cliente debe poder calificar la atencion.

**Criterios de aceptacion:**

- Una oferta queda asociada a un incidente y a un taller.
- El cliente no puede pagar una oferta inexistente o vencida.
- El pago confirmado cambia el estado financiero del servicio.
- El comprobante queda disponible para cliente y taller.
- La calificacion actualiza el promedio del taller.

### 5.4 Modulo de analitica operacional y KPIs

**Objetivo:** entregar informacion operacional a administradores de plataforma y administradores de tenant, usando datos reales registrados en la base de datos.

**Casos de uso relacionados:**

- CU-42 Visualizar Dashboard de KPIs.
- CU-43 Filtrar KPIs por Tenant.
- CU-44 Exportar Reporte de KPIs.
- CU-45 Configurar Umbrales de SLA.

**KPIs obligatorios:**

| KPI | Descripcion |
|-----|-------------|
| Tiempo promedio de asignacion | Tiempo entre reporte y taller asignado. |
| Tiempo promedio de llegada | Tiempo entre asignacion y llegada del tecnico. |
| Incidentes por tipo | Bateria, llanta, motor, choque, otros. |
| Talleres mas eficientes | Ranking por respuesta, finalizacion y calificacion. |
| Zonas con mas incidentes | Agrupacion por ubicacion geografica. |
| Casos cancelados | Emergencias canceladas o no atendidas. |
| Cumplimiento SLA | Porcentaje de servicios atendidos dentro del tiempo esperado. |

**Funcionalidades minimas:**

- Dashboard web con tarjetas, graficos y tabla resumen.
- Filtro por tenant para administrador de plataforma.
- Filtro automatico por tenant para administrador de tenant.
- Exportacion de reporte en CSV o PDF.
- Configuracion de umbrales SLA por tipo de incidente.
- Refresco de KPIs desde datos reales, no desde valores estaticos.

**Criterios de aceptacion:**

- El dashboard muestra datos derivados de incidentes, talleres, pagos y estados reales.
- Un administrador de tenant no puede ver KPIs de otro tenant.
- Un administrador de plataforma puede seleccionar tenant y comparar resultados.
- El archivo exportado coincide con los datos mostrados en pantalla.
- Cambiar un SLA modifica el calculo de cumplimiento.

### 5.5 Modulo multi-tenant SaaS

**Objetivo:** preparar el sistema para ser usado por multiples redes de talleres u organizaciones sin mezclar datos.

**Casos de uso relacionados:**

- CU-46 Crear Nuevo Tenant.
- CU-47 Asignar Administrador a un Tenant.
- CU-48 Configurar Plan de Servicio por Tenant.
- CU-43 Filtrar KPIs por Tenant.

**Funcionalidades minimas:**

- Incorporar entidad `tenant`.
- Asociar usuarios, talleres, tecnicos, vehiculos, incidentes, evidencias, pagos, metricas y SLA a un tenant.
- El backend debe filtrar la informacion segun el tenant autenticado.
- El administrador de plataforma debe crear tenants.
- El administrador de plataforma debe asignar administradores de tenant.
- Cada tenant debe tener un plan de servicio.
- Los limites del plan deben afectar la operacion, por ejemplo cantidad maxima de talleres, tecnicos o acceso a IA avanzada.

**Roles principales:**

| Rol | Alcance |
|-----|---------|
| Administrador de plataforma | Gestiona tenants, planes, administradores y KPIs globales. |
| Administrador de tenant | Gestiona talleres, tecnicos y KPIs de su tenant. |
| Taller | Atiende solicitudes dentro de su tenant. |
| Conductor / Cliente | Reporta emergencias y consulta sus servicios. |
| Sistema IA | Procesa evidencias y apoya clasificacion/asignacion. |
| Pasarela de pagos | Procesa pagos externos. |
| Servicio de mapas | Calcula ubicacion, rutas y distancias. |

**Criterios de aceptacion:**

- Tenant A no puede ver datos de Tenant B.
- El token JWT contiene rol y tenant.
- Los endpoints aplican filtro por tenant.
- Los KPIs se separan por tenant.
- Un nuevo tenant aparece disponible en listados y filtros del administrador de plataforma.

## 6. Integracion con la plataforma base

Los modulos del segundo parcial deben integrarse con los flujos del primer parcial:

- El reporte de emergencia (CU-10) debe poder continuar aunque no haya conexion mediante modo offline.
- El pipeline de IA debe seguir clasificando audio, imagen y texto cuando el incidente llegue al backend.
- La asignacion de talleres debe alimentar el seguimiento en tiempo real.
- Las ofertas y pagos deben depender del taller seleccionado y del estado real del incidente.
- Las notificaciones deben dispararse por cambios reales de estado.
- Los KPIs deben calcularse desde incidentes, asignaciones, tiempos, pagos y calificaciones.
- Todos los datos deben respetar tenant.

## 7. Arquitectura tecnica esperada

### 7.1 Aplicacion movil Flutter

- Registro e inicio de sesion de conductor.
- Registro de vehiculos.
- Reporte de emergencia con texto, fotos, audio y ubicacion.
- Modo offline para registrar emergencias.
- Historial con estado de sincronizacion.
- Seguimiento en vivo con mapa y WebSocket.
- Seleccion de oferta, pago y calificacion.

### 7.2 Aplicacion web Angular

- Login para taller, administrador de tenant y administrador de plataforma.
- Bandeja de solicitudes para taller.
- Aceptacion/rechazo de solicitudes.
- Gestion de disponibilidad y estados del servicio.
- Panel de KPIs.
- Gestion de SLA.
- Gestion de tenants, administradores y planes.

### 7.3 Backend FastAPI

- Autenticacion y autorizacion con JWT.
- Middleware de tenant.
- APIs REST para usuarios, talleres, incidentes, ofertas, pagos, KPIs, SLA y tenants.
- WebSocket para seguimiento en vivo.
- Endpoint de sincronizacion offline.
- Motor de asignacion de talleres.
- Integracion con IA, mapas y pasarela de pagos.

### 7.4 Base de datos PostgreSQL

Debe contemplar al menos:

- `tenant`
- `plan`
- `usuario`
- `taller`
- `tecnico`
- `vehiculo`
- `incidente`
- `evidencia`
- `clasificacion_ia`
- `oferta`
- `pago`
- `factura`
- `estado_incidente`
- `historial_estado`
- `sync_mapping`
- `sla_config`
- vistas o tablas para KPIs

Debe garantizar:

- integridad referencial;
- trazabilidad por incidente;
- separacion por tenant;
- no duplicidad en sincronizacion;
- consultas agregadas para KPIs.

## 8. Documentacion requerida PUDS/UML

El documento del segundo parcial debe continuar los ciclos PUDS, especialmente ciclo 4 y ciclo 5.

### 8.1 Perfil

- Introduccion.
- Objetivo general.
- Objetivos especificos.
- Descripcion del problema.
- Alcance del segundo parcial.
- Justificacion de la evolucion del sistema.

### 8.2 Captura de requisitos

- Identificacion de actores.
- Listado de casos de uso.
- Priorizacion.
- Distribucion por ciclos.
- Enfoque en CU-33 a CU-48 y CU-49.
- Criterios de aceptacion por modulo.

### 8.3 Analisis

- Paquetes de analisis.
- Relacion de paquetes con casos de uso.
- Diagramas de casos de uso por ciclo.
- Diagrama general de casos de uso.
- Diagramas de comunicacion de casos relevantes:
  - CU-10 Reportar Nueva Emergencia.
  - CU-23 Asignar Taller Optimo.
  - CU-25 Aceptar Solicitud.
  - CU-33 Conectar a WebSocket.
  - CU-36 Actualizar Estado del Incidente.
  - CU-40 Sincronizar Automaticamente.
  - CU-42 Visualizar Dashboard KPIs.
  - CU-46 Crear Nuevo Tenant.
- Analisis de paquetes.

### 8.4 Diseno

- Diagrama de despliegue.
- Diseno logico organizado por capas.
- Diagrama de clases de diseno.
- Modelo relacional o esquema de base de datos.
- Diseno de APIs REST.
- Diseno de WebSocket.
- Diseno de sincronizacion offline.
- Diseno de seguridad multi-tenant.

### 8.5 Implementacion

- Backend FastAPI funcional.
- Web Angular funcional.
- App movil Flutter funcional.
- Migraciones o scripts SQL.
- Seed de datos para al menos dos tenants.
- Integracion IA, mapas y pagos, aunque sea con modo simulado controlado si no hay credenciales reales.

### 8.6 Pruebas

- Pruebas unitarias o funcionales de endpoints principales.
- Pruebas de WebSocket.
- Pruebas de sincronizacion offline.
- Pruebas de aislamiento por tenant.
- Pruebas de dashboard con datos reales.
- Evidencias con capturas, logs o resultados de consultas.

## 9. Escenarios obligatorios para defensa

### Escenario 1: Emergencia con seguimiento en vivo

1. Cliente inicia sesion.
2. Reporta emergencia con ubicacion.
3. Sistema clasifica o asigna tipo de incidente.
4. Taller acepta solicitud.
5. Estado cambia a `en camino`.
6. Cliente visualiza estado y ubicacion en tiempo real.
7. Taller marca llegada y finaliza servicio.

### Escenario 2: Emergencia offline

1. Cliente activa modo avion o pierde conexion.
2. Registra emergencia.
3. App guarda localmente y marca pendiente.
4. Cliente recupera conexion.
5. App sincroniza automaticamente.
6. Backend registra el incidente sin duplicarlo.
7. Historial cambia de pendiente a sincronizado.

### Escenario 3: KPIs por tenant

1. Administrador de tenant ingresa al dashboard.
2. Visualiza solo datos de su tenant.
3. Administrador de plataforma ingresa al dashboard.
4. Selecciona otro tenant.
5. Los graficos cambian.
6. Exporta reporte CSV/PDF.

### Escenario 4: Multi-tenant

1. Administrador de plataforma crea un tenant.
2. Asigna un administrador de tenant.
3. El nuevo administrador inicia sesion.
4. Registra o consulta recursos de su tenant.
5. No puede acceder a recursos de otro tenant.

### Escenario 5: Cotizacion y pago

1. Taller genera o edita oferta.
2. Cliente selecciona oferta.
3. Sistema calcula ETA y tiempo estimado de reparacion.
4. Cliente efectua pago.
5. Sistema registra comision del taller.
6. Cliente recibe comprobante y califica el servicio.

## 10. Reglas clave de evaluacion

- Tiempo real debe actualizar estados reales.
- Offline debe guardar y sincronizar datos reales.
- KPIs deben calcularse desde base de datos, no desde numeros fijos.
- Multi-tenant debe aislar datos de verdad.
- Las funcionalidades nuevas deben integrarse con el flujo de emergencia.
- La documentacion UML debe coincidir con lo implementado.
- La defensa debe demostrar casos completos, no solo pantallas sueltas.
- Deben existir datos de prueba suficientes para mostrar tenants, talleres, incidentes, pagos, estados y KPIs.

## 11. Criterios sugeridos para obtener 100%

| Area | Evidencia esperada |
|------|--------------------|
| Requisitos | Actores, CU, prioridades, ciclos 4 y 5 completos, criterios de aceptacion. |
| Analisis UML | Casos de uso por ciclo, general, paquetes, comunicacion y trazabilidad. |
| Diseno UML | Despliegue, capas, clases, base de datos, APIs y WebSocket. |
| Implementacion | App movil, web, backend y BD integrados. |
| Tiempo real | WebSocket funcionando con estados y tracking. |
| Offline | SQLite/local storage, cola pendiente, sync, idempotencia. |
| KPIs | Dashboard con datos reales, filtros, exportacion y SLA. |
| Multi-tenant | Aislamiento por tenant, roles, filtros backend y datos separados. |
| Pruebas | Evidencias de escenarios obligatorios y consultas de verificacion. |
| Defensa | Flujo completo demostrado con datos preparados y explicacion tecnica. |

## 12. Entregables finales

- Documento del segundo parcial en formato PUDS/UML.
- Codigo fuente del backend, web y movil.
- Base de datos con scripts y datos de prueba.
- Diagramas UML generados en Enterprise Architect.
- Capturas o evidencias de ejecucion.
- URL, QR o instrucciones de despliegue local.
- Conclusiones, recomendaciones y bibliografia.

## 13. Frase oficial del alcance

La segunda fase no consiste en crear un nuevo sistema, sino en evolucionar la plataforma existente hacia una solucion profesional, escalable, trazable y orientada a operacion real, incorporando capacidades de tiempo real, funcionamiento offline, analitica operacional y arquitectura SaaS multi-tenant.
