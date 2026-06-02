Continuamos con la **Captura de Requisitos** siguiendo el formato solicitado (similar a los ejemplos proporcionados). A continuación se presentan:

1. **Identificación de actores** (tabla con ID, actor, descripción).
2. **Listado de casos de uso** (≈46 CU) con ID, nombre, entorno (WEB/MÓVIL/AMBOS) y actores.
3. **Priorización de casos de uso** (Alta / Media / Baja).
4. **Distribución en 5 ciclos**:
   - Ciclos 1, 2 y 3 → corresponden a la funcionalidad del **Primer Parcial** (base: registro, emergencia, IA, asignación, pagos, etc.).
   - Ciclos 4 y 5 → corresponden a las **evoluciones del Segundo Parcial** (tiempo real, offline, KPIs, multi‑tenant).

Todo el contenido es **escalable** y listo para ser modelado en UML.

---

## 2.1 FLUJO DE TRABAJO – CAPTURA DE REQUISITOS

### 2.1.1 Identificar actores y casos de uso

#### 2.1.1.1 Identificar actores

| ID | ACTOR | DESCRIPCIÓN |
|----|-------|-------------|
| A1 | Administrador de plataforma (ADM) | Superusuario del sistema. Crea tenants, asigna administradores de tenant, supervisa KPIs globales, configura SLA y planes de servicio. |
| A2 | Administrador de tenant (ADT) | Responsable de una red de talleres (ej. “Auxilio Norte”). Gestiona los talleres de su organización, usuarios (técnicos) y visualiza KPIs de su tenant. |
| A3 | Conductor / Cliente (CLI) | Usuario final que sufre una emergencia vehicular. Utiliza la app móvil para reportar incidentes, adjuntar fotos/audio, realizar pagos y seguir el auxilio en tiempo real. |
| A4 | Taller (TAL) | Representante del taller mecánico. Utiliza la aplicación web para recibir solicitudes, aceptar/rechazar, actualizar estados del servicio y gestionar disponibilidad. |
| A5 | Técnico de taller (TEC) | Empleado del taller que se desplaza al lugar del incidente. Su ubicación en tiempo real se comparte con el cliente (a través del taller). |
| A6 | Sistema de IA (SIA) | Componente interno que procesa audio (transcripción), imágenes (clasificación de daños) y texto (resumen). También asiste en la generación de cotizaciones automáticas. |
| A7 | Pasarela de pagos (PAG) | Servicio externo (Stripe, Mercado Pago) que procesa las transacciones y devuelve un token de confirmación. |
| A8 | Servicio de mapas (MAP) | API externa (Google Maps, OpenStreetMap) que provee geolocalización, cálculo de rutas y distancias. |

---

### 2.1.1.2 Identificar Casos de Uso

| ID | NOMBRE | ENTORNO | ACTOR(ES) |
|----|--------|---------|-----------|
| CU-01 | Iniciar Sesión | WEB, MÓVIL | CLI, TAL, ADT, ADM |
| CU-02 | Cerrar Sesión | WEB, MÓVIL | CLI, TAL, ADT, ADM |
| CU-03 | Recuperar Contraseña | WEB, MÓVIL | CLI, TAL, ADT, ADM |
| CU-04 | Registrar Cuenta de Conductor | MÓVIL | CLI |
| CU-05 | Registrar Vehículo | MÓVIL | CLI |
| CU-06 | Editar Perfil de Conductor | MÓVIL | CLI |
| CU-07 | Registrar Taller | WEB | ADT |
| CU-08 | Registrar Técnico | WEB | ADT, TAL |
| CU-09 | Gestionar Disponibilidad del Taller | WEB | TAL |
| CU-10 | Reportar Nueva Emergencia | MÓVIL | CLI |
| CU-11 | Adjuntar Imágenes al Reporte | MÓVIL | CLI |
| CU-12 | Adjuntar Audio al Reporte | MÓVIL | CLI |
| CU-13 | Enviar Ubicación GPS al Reportar | MÓVIL | CLI |
| CU-14 | Visualizar Estado Actual de la Emergencia | MÓVIL, WEB | CLI, TAL |
| CU-15 | Cancelar Emergencia (si está pendiente) | MÓVIL | CLI |
| CU-16 | Ver Historial de Emergencias del Conductor | MÓVIL | CLI |
| CU-17 | Transcribir Audio a Texto (IA) | BACKEND | SIA |
| CU-18 | Clasificar Incidente por Imágenes (IA) | BACKEND | SIA |
| CU-19 | Clasificar Incidente por Texto (IA) | BACKEND | SIA |
| CU-20 | Generar Resumen Estructurado del Incidente | BACKEND | SIA |
| CU-21 | Determinar Prioridad del Incidente (Alta/Media/Baja/Incierta) | BACKEND | SIA |
| CU-22 | Buscar Talleres Candidatos (cercanía, tipo, disponibilidad) | BACKEND | SIA, MAP |
| CU-23 | Asignar Taller Óptimo (motor de asignación) | BACKEND | SIA |
| CU-24 | Notificar a Taller sobre Nueva Solicitud (Push) | WEB, MÓVIL | TAL |
| CU-25 | Aceptar Solicitud con Oferta Editable (Taller) | WEB | TAL |
| CU-26 | Rechazar Solicitud (con motivo opcional) | WEB | TAL |
| CU-27 | Generar Oferta/Cotización Competitiva (precio sugerido + precio del taller) | MÓVIL, WEB | CLI, TAL, SIA |
| CU-28 | Calcular Tiempo Estimado de Llegada y Reparación | BACKEND | SIA, TAL, MAP |
| CU-29 | Seleccionar Oferta de Taller (Cliente tipo Uber/InDrive) | MÓVIL | CLI |
| CU-30 | Efectuar Pago del Servicio (Pasarela) | MÓVIL, WEB | CLI, PAG |
| CU-31 | Consultar Comisión del Taller (10% para plataforma) | WEB | TAL, ADT |
| CU-32 | Generar Factura / Comprobante | MÓVIL, WEB | CLI, TAL |
| CU-33 | Conectar a WebSocket para Seguimiento en Vivo | MÓVIL, WEB | CLI, TAL |
| CU-34 | Visualizar Ubicación del Taller en Mapa (Tracking) | MÓVIL | CLI |
| CU-35 | Recibir Notificación Inmediata de Cambio de Estado (aceptado, en camino, finalizado) | MÓVIL, WEB | CLI, TAL |
| CU-36 | Actualizar Estado del Incidente (Taller: en camino, en atención, finalizado) | WEB | TAL |
| CU-37 | Transmitir Llegada del Técnico (Push al cliente) | WEB, MÓVIL | TAL |
| CU-38 | Guardar Emergencia Localmente y Marcar como Pendiente de Sincronización (modo offline) | MÓVIL | CLI |
| CU-40 | Sincronizar Automáticamente al Recuperar Conexión | MÓVIL | CLI, SIA |
| CU-41 | Resolver Conflictos de Sincronización (evitar duplicados) | BACKEND | Sistema |
| CU-42 | Visualizar Dashboard de KPIs (Administrador) | WEB | ADM, ADT |
| CU-43 | Filtrar KPIs por Tenant | WEB | ADM, ADT |
| CU-44 | Exportar Reporte de KPIs (PDF/CSV) | WEB | ADM, ADT |
| CU-45 | Configurar Umbrales de SLA (Acuerdo de Nivel de Servicio) | WEB | ADM |
| CU-46 | Crear Nuevo Tenant | WEB | ADM |
| CU-47 | Asignar Administrador a un Tenant | WEB | ADM |
| CU-48 | Configurar Plan de Servicio por Tenant | WEB | ADM |
| CU-49 | Calificar Servicio Post-Atención | MÓVIL | CLI |

> **Nota:** Se han definido 48 casos de uso. CU-39 fue fusionado con CU-38 por ser la misma acción, y se agregó CU-49 para completar el flujo post-atención.

---

## 2.1.2 Priorización de Casos de Uso

| ID | NOMBRE | ACTOR(ES) | PRIORIDAD |
|----|--------|-----------|-----------|
| CU-01 | Iniciar Sesión | CLI, TAL, ADT, ADM | ALTA |
| CU-02 | Cerrar Sesión | CLI, TAL, ADT, ADM | ALTA |
| CU-03 | Recuperar Contraseña | CLI, TAL, ADT, ADM | MEDIA |
| CU-04 | Registrar Cuenta de Conductor | CLI | ALTA |
| CU-05 | Registrar Vehículo | CLI | ALTA |
| CU-06 | Editar Perfil de Conductor | CLI | MEDIA |
| CU-07 | Registrar Taller | ADT | ALTA |
| CU-08 | Registrar Técnico | ADT, TAL | ALTA |
| CU-09 | Gestionar Disponibilidad del Taller | TAL | ALTA |
| CU-10 | Reportar Nueva Emergencia | CLI | ALTA |
| CU-11 | Adjuntar Imágenes al Reporte | CLI | ALTA |
| CU-12 | Adjuntar Audio al Reporte | CLI | ALTA |
| CU-13 | Enviar Ubicación GPS al Reportar | CLI | ALTA |
| CU-14 | Visualizar Estado Actual de la Emergencia | CLI, TAL | ALTA |
| CU-15 | Cancelar Emergencia | CLI | MEDIA |
| CU-16 | Ver Historial de Emergencias | CLI | MEDIA |
| CU-17 | Transcribir Audio a Texto (IA) | SIA | ALTA |
| CU-18 | Clasificar Incidente por Imágenes | SIA | ALTA |
| CU-19 | Clasificar Incidente por Texto | SIA | ALTA |
| CU-20 | Generar Resumen Estructurado | SIA | ALTA |
| CU-21 | Determinar Prioridad del Incidente | SIA | ALTA |
| CU-22 | Buscar Talleres Candidatos | SIA, MAP | ALTA |
| CU-23 | Asignar Taller Óptimo | SIA | ALTA |
| CU-24 | Notificar a Taller sobre Nueva Solicitud | TAL | ALTA |
| CU-25 | Aceptar Solicitud con Oferta Editable | TAL | ALTA |
| CU-26 | Rechazar Solicitud | TAL | MEDIA |
| CU-27 | Generar Oferta/Cotización Competitiva | CLI, TAL, SIA | ALTA |
| CU-28 | Calcular Tiempo Estimado de Llegada y Reparación | SIA, TAL, MAP | ALTA |
| CU-29 | Seleccionar Oferta de Taller | CLI | ALTA |
| CU-30 | Efectuar Pago del Servicio | CLI, PAG | ALTA |
| CU-31 | Consultar Comisión del Taller | TAL, ADT | MEDIA |
| CU-32 | Generar Factura | CLI, TAL | MEDIA |
| CU-33 | Conectar a WebSocket para Seguimiento | CLI, TAL | ALTA |
| CU-34 | Visualizar Ubicación del Taller en Mapa | CLI | ALTA |
| CU-35 | Recibir Notificación Inmediata de Cambio de Estado | CLI, TAL | ALTA |
| CU-36 | Actualizar Estado del Incidente (Taller) | TAL | ALTA |
| CU-37 | Transmitir Llegada del Técnico | TAL | ALTA |
| CU-38 | Guardar Emergencia Localmente y Marcar como Pendiente (Offline) | CLI | ALTA |
| CU-40 | Sincronizar Automáticamente | CLI, SIA | ALTA |
| CU-41 | Resolver Conflictos de Sincronización | Sistema | MEDIA |
| CU-42 | Visualizar Dashboard de KPIs | ADM, ADT | ALTA |
| CU-43 | Filtrar KPIs por Tenant | ADM, ADT | ALTA |
| CU-44 | Exportar Reporte de KPIs | ADM, ADT | MEDIA |
| CU-45 | Configurar Umbrales de SLA | ADM | ALTA |
| CU-46 | Crear Nuevo Tenant | ADM | ALTA |
| CU-47 | Asignar Administrador a un Tenant | ADM | ALTA |
| CU-48 | Configurar Plan de Servicio por Tenant | ADM | MEDIA |
| CU-49 | Calificar Servicio Post-Atención | CLI | MEDIA |

---

## 2.1.3 Distribución en 5 Ciclos (PUDS)

**Criterio:**  
- **Ciclos 1, 2 y 3** → Funcionalidades del **Primer Parcial** (base: autenticación, registro, reporte de emergencia, IA, asignación de talleres, cotizaciones, pagos, notificaciones push).  
- **Ciclos 4 y 5** → **Segundo Parcial** (tiempo real con WebSockets + tracking, modo offline + sincronización, KPIs, arquitectura multi‑tenant).

### Ciclo #1 (Primer Parcial) – Base de usuarios y vehículos

| ID | NOMBRE | ACTOR(ES) | PRIORIDAD |
|----|--------|-----------|-----------|
| CU-01 | Iniciar Sesión | CLI, TAL, ADT, ADM | ALTA |
| CU-02 | Cerrar Sesión | CLI, TAL, ADT, ADM | ALTA |
| CU-04 | Registrar Cuenta de Conductor | CLI | ALTA |
| CU-05 | Registrar Vehículo | CLI | ALTA |
| CU-06 | Editar Perfil de Conductor | CLI | MEDIA |
| CU-07 | Registrar Taller | ADT | ALTA |
| CU-08 | Registrar Técnico | ADT, TAL | ALTA |
| CU-09 | Gestionar Disponibilidad del Taller | TAL | ALTA |
| CU-03 | Recuperar Contraseña | CLI, TAL, ADT, ADM | MEDIA |

> **Total Ciclo 1:** 9 casos de uso.

### Ciclo #2 (Primer Parcial) – Reporte de emergencia + IA (clasificación y resumen)

| ID | NOMBRE | ACTOR(ES) | PRIORIDAD |
|----|--------|-----------|-----------|
| CU-10 | Reportar Nueva Emergencia | CLI | ALTA |
| CU-11 | Adjuntar Imágenes al Reporte | CLI | ALTA |
| CU-12 | Adjuntar Audio al Reporte | CLI | ALTA |
| CU-13 | Enviar Ubicación GPS al Reportar | CLI | ALTA |
| CU-14 | Visualizar Estado Actual de la Emergencia | CLI, TAL | ALTA |
| CU-15 | Cancelar Emergencia | CLI | MEDIA |
| CU-16 | Ver Historial de Emergencias | CLI | MEDIA |
| CU-17 | Transcribir Audio a Texto (IA) | SIA | ALTA |
| CU-18 | Clasificar Incidente por Imágenes | SIA | ALTA |
| CU-19 | Clasificar Incidente por Texto | SIA | ALTA |
| CU-20 | Generar Resumen Estructurado | SIA | ALTA |
| CU-21 | Determinar Prioridad del Incidente | SIA | ALTA |

> **Total Ciclo 2:** 12 casos de uso.

### Ciclo #3 (Primer Parcial) – Asignación de talleres, cotizaciones, pagos y notificaciones push

| ID | NOMBRE | ACTOR(ES) | PRIORIDAD |
|----|--------|-----------|-----------|
| CU-22 | Buscar Talleres Candidatos | SIA, MAP | ALTA |
| CU-23 | Asignar Taller Óptimo | SIA | ALTA |
| CU-24 | Notificar a Taller sobre Nueva Solicitud | TAL | ALTA |
| CU-25 | Aceptar Solicitud con Oferta Editable | TAL | ALTA |
| CU-26 | Rechazar Solicitud | TAL | MEDIA |
| CU-27 | Generar Oferta/Cotización Competitiva | CLI, TAL, SIA | ALTA |
| CU-28 | Calcular Tiempo Estimado de Llegada y Reparación | SIA, TAL, MAP | ALTA |
| CU-29 | Seleccionar Oferta de Taller | CLI | ALTA |
| CU-30 | Efectuar Pago del Servicio | CLI, PAG | ALTA |
| CU-31 | Consultar Comisión del Taller | TAL, ADT | MEDIA |
| CU-32 | Generar Factura | CLI, TAL | MEDIA |
| CU-49 | Calificar Servicio Post-Atención | CLI | MEDIA |

> **Total Ciclo 3:** 12 casos de uso.

### Ciclo #4 (Segundo Parcial) – Módulo de tiempo real (WebSockets + tracking)

| ID | NOMBRE | ACTOR(ES) | PRIORIDAD |
|----|--------|-----------|-----------|
| CU-33 | Conectar a WebSocket para Seguimiento en Vivo | CLI, TAL | ALTA |
| CU-34 | Visualizar Ubicación del Taller en Mapa | CLI | ALTA |
| CU-35 | Recibir Notificación Inmediata de Cambio de Estado | CLI, TAL | ALTA |
| CU-36 | Actualizar Estado del Incidente (Taller) | TAL | ALTA |
| CU-37 | Transmitir Llegada del Técnico (Push) | TAL | ALTA |

> **Total Ciclo 4:** 5 casos de uso (se pueden complementar con algunos de ciclo 3 ya existentes, pero se listan los nuevos específicos).

### Ciclo #5 (Segundo Parcial) – Modo offline + sincronización + KPIs + multi‑tenant

| ID | NOMBRE | ACTOR(ES) | PRIORIDAD |
|----|--------|-----------|-----------|
| CU-38 | Guardar Emergencia Localmente y Marcar como Pendiente de Sincronización (Offline) | CLI | ALTA |
| CU-40 | Sincronizar Automáticamente al Recuperar Conexión | CLI, SIA | ALTA |
| CU-41 | Resolver Conflictos de Sincronización | Sistema | MEDIA |
| CU-42 | Visualizar Dashboard de KPIs | ADM, ADT | ALTA |
| CU-43 | Filtrar KPIs por Tenant | ADM, ADT | ALTA |
| CU-44 | Exportar Reporte de KPIs | ADM, ADT | MEDIA |
| CU-45 | Configurar Umbrales de SLA | ADM | ALTA |
| CU-46 | Crear Nuevo Tenant | ADM | ALTA |
| CU-47 | Asignar Administrador a un Tenant | ADM | ALTA |
| CU-48 | Configurar Plan de Servicio por Tenant | ADM | MEDIA |

> **Total Ciclo 5:** 10 casos de uso.

---

## Resumen de distribución por ciclo

| Ciclo | Nombre | # Casos de uso | Correspondencia |
|-------|--------|----------------|------------------|
| 1 | Usuarios y vehículos | 9 | Primer Parcial |
| 2 | Reporte e IA (clasificación) | 12 | Primer Parcial |
| 3 | Asignación, cotizaciones, pagos y calificación | 12 | Primer Parcial |
| 4 | Tiempo real (WebSockets + tracking) | 5 | Segundo Parcial |
| 5 | Offline, KPIs, multi‑tenant | 10 | Segundo Parcial |
| **Total** | | **48** | (≈45 CU escalables) |

> **Nota:** Se han definido 48 casos de uso. CU-39 fue fusionado con CU-38 (almacenamiento offline y marcado de pendencia son la misma acción). Se agregó CU-49 (Calificar Servicio) para completar el flujo post-atención.

---

## Próximos pasos

Una vez validada la captura de requisitos, se procederá al **Flujo de Trabajo de Análisis**, donde se desarrollarán:

- **Diagrama de casos de uso** (con actores y relaciones).
- **Descripción detallada** de los 10 casos de uso más críticos (formato tabular).
- **Diagramas de secuencia** para los escenarios principales.

¿Desea que continúe con el **Análisis** (2.2) o prefiere ajustar algún aspecto de los actores, prioridades o ciclos?
