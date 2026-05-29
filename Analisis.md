Perfecto. Rehago la sección **2.2 FLUJO DE TRABAJO – ANÁLISIS** con un enfoque más sencillo, siguiendo el formato de tus ejemplos (sin IDs de paquete, con nombres claros, diagramas de colaboración simples, y análisis de paquete solo con relaciones básicas).

---

## 2.2 FLUJO DE TRABAJO – ANÁLISIS

### 2.2.1 Análisis de Arquitectura

#### 2.2.1.1 Identificar Paquetes

| Paquete | Descripción |
|---------|-------------|
| Usuarios y acceso | Gestión de autenticación (login, logout, recuperar contraseña) y control de acceso basado en roles (conductor, taller, administrador). |
| Clientes y vehículos | Registro de conductores, sus vehículos, edición de perfiles y gestión de técnicos/talleres. |
| Incidentes y evidencias | Reporte de emergencias, adjuntar fotos, audio, ubicación, consultar estado, cancelar y ver historial. |
| Talleres y atención del servicio | Gestión de disponibilidad de talleres, aceptar/rechazar solicitudes, actualizar estados del servicio (en camino, en atención, finalizado). |
| Procesamiento inteligente y asignación | Transcripción de audio, clasificación de imágenes/texto, generación de resúmenes, priorización, búsqueda de talleres candidatos y asignación óptima. |
| Pagos, notificaciones y repartos | Pasarela de pagos, facturación, comisión del 10%, notificaciones push, y envío de mensajes en tiempo real (WebSockets). |
| Offline y sincronización | Almacenamiento local de emergencias (SQLite), sincronización automática al recuperar conexión, resolución de conflictos. |
| Analítica y KPIs | Dashboard con indicadores (tiempos, incidentes por tipo, talleres eficientes, SLA) calculados desde la base de datos. |
| Multi‑tenant | Aislamiento de datos por organización (tenant), filtrado automático en todas las consultas, creación de tenants y asignación de administradores. |

#### 2.2.1.2 Relacionar Paquetes y Casos de Uso

| Paquete | Casos de uso |
|---------|--------------|
| Usuarios y acceso | CU-01, CU-02, CU-03 |
| Clientes y vehículos | CU-04, CU-05, CU-06, CU-07, CU-08, CU-09 |
| Incidentes y evidencias | CU-10, CU-11, CU-12, CU-13, CU-14, CU-15, CU-16 |
| Procesamiento inteligente y asignación | CU-17, CU-18, CU-19, CU-20, CU-21, CU-22, CU-23, CU-24, CU-25, CU-26, CU-27, CU-28, CU-29 |
| Pagos, notificaciones y repartos | CU-30, CU-31, CU-32, CU-33, CU-34, CU-35, CU-36, CU-37 |
| Offline y sincronización | CU-38, CU-39, CU-40, CU-41 |
| Analítica y KPIs | CU-42, CU-43, CU-44, CU-45 |
| Multi‑tenant | CU-46, CU-47, CU-48 |

---

### 2.2.2 Análisis de Casos de Uso

#### 2.2.2.1 Diagramas de Colaboración / Comunicación (casos relevantes)

Se muestran solo los casos de uso más importantes del sistema, con interacciones simples entre **Actor → Interfaz → Controlador → Modelo**.

---

**CU-10. Reportar Nueva Emergencia**

1: Reportar() →  
**Conductor** → **PantallaEmergencia**  
1.1: GuardarDatos() →  
**PantallaEmergencia** → **ControladorEmergencia**  
1.2: AlmacenarIncidente() →  
**ControladorEmergencia** → **Incidente**  
1.3: ProcesarIA() →  
**ControladorEmergencia** → **SistemaIA**

---

**CU-23. Asignar Taller Óptimo**

1: BuscarTalleres() →  
**ControladorAsignacion** → **ServicioMapas**  
1.1: CalcularDistancia() →  
**ServicioMapas** → **ControladorAsignacion**  
1.2: SeleccionarMejorTaller() →  
**ControladorAsignacion** → **Taller**  
1.3: NotificarTaller() →  
**ControladorAsignacion** → **ServicioPush**

---

**CU-25. Aceptar Solicitud (Taller)**

1: Aceptar() →  
**Taller** → **PantallaSolicitud**  
1.1: CambiarEstado() →  
**PantallaSolicitud** → **ControladorServicio**  
1.2: ActualizarIncidente() →  
**ControladorServicio** → **Incidente**  
1.3: EnviarNotificacion() →  
**ControladorServicio** → **Cliente**

---

**CU-33. Conectar a WebSocket (Tiempo Real)**

1: Conectar() →  
**Cliente** → **PantallaSeguimiento**  
1.1: AbrirSocket() →  
**PantallaSeguimiento** → **ControladorWebSocket**  
1.2: ValidarToken() →  
**ControladorWebSocket** → **Seguridad**  
1.3: RegistrarConexion() →  
**ControladorWebSocket** → **GestorSesiones**

---

**CU-36. Actualizar Estado del Incidente (Taller)**

1: ActualizarEstado() →  
**Taller** → **PantallaServicio**  
1.1: CambiarA() →  
**PantallaServicio** → **ControladorServicio**  
1.2: GuardarEstado() →  
**ControladorServicio** → **Incidente**  
1.3: BroadcastWebSocket() →  
**ControladorServicio** → **GestorWebSocket**

---

**CU-40. Sincronizar Automáticamente (Offline)**

1: ConexionRestaurada() →  
**Sistema** → **DetectorConectividad**  
1.1: ObtenerPendientes() →  
**DetectorConectividad** → **RepositorioLocal**  
1.2: EnviarAlServidor() →  
**RepositorioLocal** → **ControladorSincronizacion**  
1.3: ConfirmarSync() →  
**ControladorSincronizacion** → **RepositorioLocal**

---

**CU-42. Visualizar Dashboard KPIs**

1: SolicitarKPIs() →  
**Administrador** → **PanelWeb**  
1.1: CalcularIndicadores() →  
**PanelWeb** → **ControladorKPI**  
1.2: LeerMetricas() →  
**ControladorKPI** → **BaseDatos**  
1.3: MostrarGraficos() →  
**ControladorKPI** → **PanelWeb**

---

#### 2.2.2.2 Análisis de Paquete

Relaciones simples entre paquetes (solo “usa” o “depende de” implícito, sin descripciones largas). Se muestra como en la imagen enviada:

```
pkg Análisis de paquetes

Usuarios y acceso  ──usa──→  Clientes y vehículos
       │                           │
       │                           │
       ▼                           ▼
Incidentes y evidencias  ←──  Talleres y atención del servicio
       │                           │
       │                           │
       ▼                           ▼
Procesamiento inteligente y asignación ──→ Pagos, notificaciones y repartos
       │                           │
       │                           │
       ▼                           ▼
Offline y sincronización  ←──  Multi‑tenant
       │
       │
       ▼
Analítica y KPIs
```

**En texto (lista de relaciones):**

- Usuarios y acceso → Clientes y vehículos  
- Usuarios y acceso → Incidentes y evidencias  
- Clientes y vehículos → Incidentes y evidencias  
- Talleres y atención del servicio → Incidentes y evidencias  
- Incidentes y evidencias → Procesamiento inteligente y asignación  
- Procesamiento inteligente y asignación → Pagos, notificaciones y repartos  
- Pagos, notificaciones y repartos → Offline y sincronización  
- Todos los paquetes → Multi‑tenant  
- Analítica y KPIs ← Incidentes y evidencias  
- Analítica y KPIs ← Talleres y atención del servicio  
- Analítica y KPIs ← Pagos, notificaciones y repartos  

---

¿Deseas que continúe con el **Flujo de Trabajo de Diseño (2.3)** o prefieres ajustar algo más del análisis?