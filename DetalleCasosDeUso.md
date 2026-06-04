## 2.1.3 Especificación de Casos de Uso

A continuación se detalla cada caso de uso siguiendo el formato requerido. Se han organizado por ciclo (1 a 5) según la priorización previa. Los actores se identifican con sus códigos: ADM (Administrador de plataforma), ADT (Administrador de tenant), CLI (Conductor/Cliente), TAL (Taller), TEC (Técnico), SIA (Sistema de IA), PAG (Pasarela de pagos), MAP (Servicio de mapas).

---

### Ciclo #1 – Usuarios y vehículos (Primer Parcial)

#### CU-01. Iniciar Sesión

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir que los usuarios registrados (cliente, taller, administradores) accedan al sistema mediante credenciales válidas. |
| **Actores** | CLI, TAL, ADT, ADM |
| **Actor iniciador** | Cualquier usuario no autenticado |
| **Precondición** | El usuario debe tener una cuenta registrada previamente (CU-04, CU-07). |
| **Flujo principal** | 1. El usuario abre la app móvil o web. 2. Ingresa email y contraseña. 3. El sistema valida formato y envía credenciales al backend. 4. El backend verifica contra la base de datos y genera un token JWT con rol y tenant_id. 5. El sistema redirige al panel correspondiente (cliente: mapa de emergencias; taller: bandeja de solicitudes; admin: dashboard de KPIs). |
| **Postcondición** | El usuario queda autenticado con una sesión activa representada por un token JWT válido. |
| **Excepción** | Email no registrado, contraseña incorrecta, usuario inhabilitado, error de conexión, token expirado (si ya tenía sesión). |

#### CU-02. Cerrar Sesión

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Finalizar la sesión de forma segura, invalidando el token de autenticación. |
| **Actores** | CLI, TAL, ADT, ADM |
| **Actor iniciador** | Usuario autenticado |
| **Precondición** | CU-01 completado (sesión activa). |
| **Flujo principal** | 1. Usuario selecciona "Cerrar Sesión" en el menú. 2. El sistema envía solicitud al backend para invalidar el token (opcional: agregar token a lista negra). 3. El backend elimina la sesión de la caché (si aplica). 4. El sistema redirige a la pantalla de inicio de sesión. |
| **Postcondición** | El token queda invalidado; el usuario no puede acceder a recursos protegidos. |
| **Excepción** | Error de conexión (se fuerza cierre local), token ya expirado. |

#### CU-03. Recuperar Contraseña

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir al usuario restablecer su contraseña olvidada mediante un enlace enviado a su correo electrónico. |
| **Actores** | CLI, TAL, ADT, ADM |
| **Actor iniciador** | Usuario no autenticado |
| **Precondición** | El usuario debe tener una cuenta registrada con un email válido. |
| **Flujo principal** | 1. Usuario hace clic en "¿Olvidó su contraseña?". 2. Ingresa su email. 3. El sistema verifica que el email exista. 4. Genera un token de restablecimiento y envía un enlace al correo. 5. Usuario accede al enlace, ingresa nueva contraseña. 6. El sistema actualiza la contraseña y notifica el cambio. |
| **Postcondición** | La contraseña se actualiza; el usuario puede iniciar sesión con la nueva credencial. |
| **Excepción** | Email no registrado, token expirado (el enlace tiene validez limitada), error en el envío del correo. |

#### CU-04. Registrar Cuenta de Conductor

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir a un conductor crear una cuenta en la plataforma para poder solicitar auxilio vehicular. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor (nuevo usuario) |
| **Precondición** | No existe cuenta con el mismo email o teléfono. |
| **Flujo principal** | 1. Conductor accede a la app móvil y selecciona "Registrarse". 2. Ingresa nombre, email, teléfono, contraseña. 3. Acepta términos y condiciones. 4. El sistema valida los datos y crea el usuario en la base de datos con rol "conductor" y tenant_id por defecto (tenant público). 5. Envía correo de verificación (opcional). 6. Muestra mensaje de éxito y redirige a iniciar sesión. |
| **Postcondición** | Se crea una nueva cuenta de conductor en el sistema. |
| **Excepción** | Email ya registrado, formato de email inválido, contraseña débil, error de conexión. |

#### CU-05. Registrar Vehículo

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Asociar uno o más vehículos al perfil del conductor para facilitar la atención de emergencias. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor autenticado |
| **Precondición** | CU-01 (conductor autenticado) y CU-04 (cuenta creada). |
| **Flujo principal** | 1. Conductor accede a "Mis Vehículos" → "Agregar Vehículo". 2. Ingresa placa, marca, modelo, año, color, tipo de combustible. 3. El sistema valida que la placa no esté duplicada para el mismo conductor. 4. Guarda el vehículo asociado al conductor actual. 5. Muestra la lista actualizada. |
| **Postcondición** | El vehículo queda registrado y disponible para ser seleccionado en futuras emergencias. |
| **Excepción** | Placa ya registrada para el mismo usuario, campos obligatorios vacíos, error de conexión. |

#### CU-06. Editar Perfil de Conductor

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Modificar los datos personales del conductor (nombre, teléfono, email, contraseña, etc.). |
| **Actores** | CLI |
| **Actor iniciador** | Conductor autenticado |
| **Precondición** | CU-01 y CU-04 completados. |
| **Flujo principal** | 1. Conductor accede a "Mi Perfil". 2. Modifica los campos deseados. 3. El sistema valida los nuevos datos (ej. formato de email, unicidad). 4. Actualiza la base de datos. 5. Muestra mensaje de éxito. |
| **Postcondición** | Los datos del conductor se actualizan. |
| **Excepción** | Email duplicado (otro usuario ya lo usa), contraseña nueva no cumple requisitos, error de conexión. |

#### CU-07. Registrar Taller

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir que un administrador de tenant registre un nuevo taller mecánico dentro de su red. |
| **Actores** | ADT |
| **Actor iniciador** | Administrador de tenant |
| **Precondición** | ADT autenticado (CU-01) y tenant ya creado (CU-46). |
| **Flujo principal** | 1. ADT accede al panel "Talleres" → "Registrar Taller". 2. Ingresa nombre, dirección, coordenadas (lat/lng), teléfono, tipos de servicio (batería, llanta, etc.), horario de atención. 3. El sistema asigna el taller al tenant del ADT. 4. Genera credenciales de acceso para el taller (usuario y contraseña temporal). 5. Envía notificación al taller. |
| **Postcondición** | El taller queda registrado y puede iniciar sesión en la aplicación web. |
| **Excepción** | Dirección inválida (geocodificación falla), campos obligatorios vacíos, error de conexión. |

#### CU-08. Registrar Técnico

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Asociar un técnico (empleado) a un taller, para poder asignarle servicios de auxilio en ruta. |
| **Actores** | ADT, TAL |
| **Actor iniciador** | Administrador de tenant o representante del taller |
| **Precondición** | CU-07 (taller registrado) y usuario autenticado como ADT o TAL. |
| **Flujo principal** | 1. Usuario accede a "Técnicos" → "Registrar Técnico". 2. Ingresa nombre, teléfono, especialidad, disponibilidad horaria. 3. El sistema asigna el técnico al taller seleccionado (dentro del mismo tenant). 4. Genera credenciales de acceso para el técnico (opcional: rol limitado). |
| **Postcondición** | El técnico queda registrado y puede ser asignado a emergencias. |
| **Excepción** | Teléfono duplicado, taller no existe, error de conexión. |

#### CU-09. Gestionar Disponibilidad del Taller

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir al taller indicar si está disponible para recibir nuevas solicitudes de auxilio (horarios, capacidad máxima, etc.). |
| **Actores** | TAL |
| **Actor iniciador** | Taller autenticado |
| **Precondición** | CU-07 (taller registrado) y CU-01. |
| **Flujo principal** | 1. Taller accede a "Disponibilidad". 2. Marca "Disponible" o "No disponible". 3. Opcionalmente define capacidad máxima de servicios simultáneos. 4. El sistema actualiza el estado del taller. 5. El motor de asignación considera solo talleres disponibles. |
| **Postcondición** | El estado de disponibilidad se actualiza en la base de datos. |
| **Excepción** | Error de conexión. |

---

### Ciclo #2 – Reporte de emergencia + IA (Primer Parcial)

#### CU-10. Reportar Nueva Emergencia

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir al conductor crear una solicitud de auxilio vehicular, enviando información inicial (ubicación, fotos, audio, texto). |
| **Actores** | CLI, SIA |
| **Actor iniciador** | Conductor autenticado |
| **Precondición** | CU-01 (conductor autenticado) y CU-05 (al menos un vehículo registrado). |
| **Flujo principal** | 1. Conductor abre la app y selecciona "Nueva Emergencia". 2. Elige el vehículo afectado. 3. Opcionalmente adjunta fotos (CU-11), audio (CU-12) y texto. 4. El sistema obtiene la ubicación GPS actual (CU-13). 5. Al enviar, se crea un incidente con estado "pendiente". 6. El backend dispara `run_ai_pipeline()` como background task: transcription (CU-17), clasificación por texto (CU-19), clasificación por imágenes (CU-18), fusión, resumen (CU-20), prioridad (CU-21), y finalmente asignación (CU-22/CU-23). 7. Se asigna un UUID local y se envía al backend si hay conexión; si no, se activa modo offline (CU-38). 8. El sistema muestra el ID de la emergencia y el estado actual. |
| **Postcondición** | Se crea un registro de incidente en el sistema (local o remoto). El pipeline de IA procesa en background y el estado evoluciona a "BUSCANDO_TALLER" automáticamente. |
| **Excepción** | No hay ubicación (GPS desactivado), falta conexión y no se pudo almacenar localmente, error en IA (fallback a keywords). |

#### CU-11. Adjuntar Imágenes al Reporte

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Capturar o seleccionar imágenes del daño del vehículo para ayudar a la clasificación y cotización. |
| **Actores** | CLI, SIA |
| **Actor iniciador** | Conductor durante el reporte de emergencia |
| **Precondición** | CU-10 en proceso (emergencia no finalizada). |
| **Flujo principal** | 1. Conductor pulsa "Tomar foto" o "Seleccionar de galería". 2. El sistema permite capturar múltiples imágenes (máx. 5). 3. Las imágenes se comprimen (calidad 80%) y se codifican en base64. 4. Se envían junto con el reporte al endpoint `POST /api/v1/ia/clasificar-imagen`. 5. La respuesta de YOLOv8 (`codigo`, `confianza`, `descripcion`) se muestra al conductor como sugerencia antes de confirmar. 6. Las imágenes quedan asociadas al incidente como evidencia tipo `IMAGEN`. |
| **Postcondición** | Las imágenes quedan asociadas al incidente y la clasificación YOLOv8 está disponible para el conductor. |
| **Excepción** | Archivo corrupto, tamaño excesivo (>8MB), permisos de cámara denegados, modelos IA no disponibles (muestra sugerencia genérica). |

#### CU-12. Adjuntar Audio al Reporte

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Grabar un mensaje de voz describiendo el problema para facilitar la transcripción y clasificación. |
| **Actores** | CLI, SIA |
| **Actor iniciador** | Conductor durante el reporte de emergencia |
| **Precondición** | CU-10 en proceso. |
| **Flujo principal** | 1. Conductor pulsa "Grabar audio". 2. El sistema solicita permiso de micrófono. 3. Conductor graba el mensaje (máx. 60 segundos). 4. El audio se codifica (AAC/WAV a base64). 5. Se envía al endpoint `POST /api/v1/ia/transcribir-audio`. 6. La respuesta (`transcripcion`, `motor`) se muestra al conductor y se almacena como evidencia tipo `AUDIO`. 7. El backend dispara CU-19 automáticamente. |
| **Postcondición** | El audio queda asociado al incidente con su transcripción generada por IA. |
| **Excepción** | Permiso de micrófono denegado, grabación vacía, error en transcripción (OpenAI o Google). |

#### CU-13. Enviar Ubicación GPS al Reportar

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Obtener y enviar las coordenadas geográficas exactas del conductor al momento de reportar la emergencia. |
| **Actores** | CLI, MAP |
| **Actor iniciador** | Conductor (automático al crear emergencia) |
| **Precondición** | Permiso de ubicación concedido en el dispositivo. |
| **Flujo principal** | 1. El sistema accede al GPS del dispositivo. 2. Obtiene latitud y longitud. 3. Envía la ubicación al backend al crear la emergencia. 4. El servicio de mapas se usa para calcular distancias a talleres (CU-22). |
| **Postcondición** | La ubicación queda registrada en el incidente y se utiliza para asignación. |
| **Excepción** | GPS desactivado, señal débil (se usa última ubicación conocida), error en la API de mapas. |

#### CU-14. Visualizar Estado Actual de la Emergencia

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Mostrar al conductor y al taller el estado más reciente del incidente (pendiente, buscando taller, asignado, en camino, etc.). |
| **Actores** | CLI, TAL |
| **Actor iniciador** | Conductor o taller autenticado |
| **Precondición** | CU-10 completado (emergencia creada). |
| **Flujo principal** | 1. Usuario accede a la pantalla de "Seguimiento" de una emergencia específica. 2. El sistema consulta el estado actual desde el backend (o desde caché local si está offline). 3. Muestra el estado con ícono, fecha/hora y descripción. 4. En modo online, se actualiza automáticamente cada 5 segundos (o vía WebSocket). |
| **Postcondición** | El usuario visualiza información actualizada. |
| **Excepción** | No hay conexión y el estado local está desactualizado, ID de emergencia no existe. |

#### CU-15. Cancelar Emergencia

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir al conductor cancelar una solicitud de auxilio que aún no ha sido aceptada por un taller o que está en estado pendiente. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor autenticado |
| **Precondición** | Emergencia en estado "pendiente" o "buscando taller". |
| **Flujo principal** | 1. Conductor accede al detalle de la emergencia. 2. Selecciona "Cancelar Solicitud". 3. Confirma la acción. 4. El sistema cambia el estado a "cancelado" y registra el motivo (opcional). 5. Se notifica a los talleres que habían recibido la solicitud (si aplica). 6. El conductor recibe confirmación. |
| **Postcondición** | La emergencia queda cancelada y no se asignan talleres. |
| **Excepción** | La emergencia ya fue aceptada por un taller (no se permite cancelación), error de conexión. |

#### CU-16. Ver Historial de Emergencias del Conductor

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Listar todas las emergencias previas solicitadas por el conductor, con sus estados y fechas. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor autenticado |
| **Precondición** | CU-01. |
| **Flujo principal** | 1. Conductor accede a "Historial de Emergencias". 2. El sistema consulta la base de datos y devuelve una lista paginada (filtrada por tenant). 3. Cada elemento muestra fecha, tipo de incidente, taller asignado (si lo hubo), estado final. 4. Puede hacer clic para ver detalle. |
| **Postcondición** | Se muestra el historial. |
| **Excepción** | Sin emergencias previas, error de conexión. |

#### CU-17. Transcribir Audio a Texto (IA)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Convertir un archivo de audio (grabación del conductor) a texto para extraer información relevante del incidente. |
| **Actores** | SIA |
| **Actor iniciador** | Sistema (automático al recibir audio) |
| **Precondición** | CU-12 completado (audio adjuntado). |
| **Flujo principal** | 1. El backend recibe el audio codificado en base64. 2. Detecta el tipo MIME (AAC/WAV). 3. Si `OPENAI_API_KEY` está configurada, usa Whisper (OpenAI): envía a `https://api.openai.com/v1/audio/transcriptions` con `model=whisper-1`. 4. Si no hay ключ OpenAI, intenta Google Speech-to-Text (requiere `speech_recognition` + `pydub` para convertir a WAV). 5. Almacena la transcripción en la tabla `evidencia`. 6. Dispara CU-19 (clasificación por texto). |
| **Postcondición** | Se genera una transcripción asociada al incidente. |
| **Excepción** | Audio ininteligible, tiempo excedido (>60s timeout), API no disponible, archivo corrupto. |
| **Motor(es)** | `openai-whisper` (principal) o `google-speech` (fallback). |
| **Endpoint** | `POST /api/v1/ia/transcribir-audio` (ver `backend/app/api/ia.py:28`). |

#### CU-18. Clasificar Incidente por Imágenes (IA)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Utilizar modelos de visión artificial (YOLOv8) para identificar el tipo de daño (batería, llanta, choque, motor, otros) a partir de las fotos enviadas. |
| **Actores** | SIA |
| **Actor iniciador** | Sistema (automático al recibir imágenes) |
| **Precondición** | CU-11 completado. |
| **Flujo principal** | 1. El backend recibe la imagen y la convierte a RGB con PIL. 2. Carga dos modelos YOLOv8 desde `backend/ml/models/`: `dashboard_best.pt` (testigos del tablero) y `cardd_best.pt` (daños CarDD). 3. Ejecuta `model.predict()` con umbral de confianza 0.25. 4. Mapea etiquetas a códigos: `Charging System Issue`→`BATERIA`, `tire flat`→`LLANTA`, `dent/scratch/crack`→`CHOQUE`, `Check Engine`→`MOTOR`. 5. Selecciona la predicción de mayor confianza. Si `conf < 0.35`, clasifica como `OTROS`. 6. Construye una descripción amigable para el conductor. 7. Almacena resultado en `clasificacion_ia` y actualiza el incidente. |
| **Postcondición** | El incidente recibe una categoría con descripción y prioridad sugerida. |
| **Excepción** | Imagen borrosa (conf < 0.35 → "OTROS"), modelo no disponible (fallback con confianza 0), archivo corrupto. |
| **Modelos** | YOLOv8 (`dashboard_best.pt` + `cardd_best.pt`) en `backend/ml/models/`. |
| **Endpoint** | `POST /api/v1/ia/clasificar-imagen` (ver `backend/app/api/ia.py:11`). |

#### CU-19. Clasificar Incidente por Texto (IA)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Analizar la transcripción del audio y el texto adicional del conductor para clasificar el tipo de problema. |
| **Actores** | SIA |
| **Actor iniciador** | Sistema (al recibir texto o después de CU-17) |
| **Precondición** | Se dispone de texto (transcripción o campo adicional). |
| **Flujo principal** | 1. El backend concatena descripción del conductor + transcripción de audio. 2. Aplica `classify_text()` (keywords): busca "bateria/no arranca"→`BATERIA`, "llanta/pinchazo"→`LLANTA`, "choque/colision"→`CHOQUE`, "motor/humo"→`MOTOR`. 3. Calcula confianza: `0.6 + 0.1*hits` (máx 0.95). 4. Fusiona con resultado de CU-18 vía `fuse()`: si ambos coinciden → mayor confianza; si no → toma el de mayor confianza. 5. Si confianza < 0.5, clasifica como `OTROS` y marca incierta. 6. Actualiza el incidente. |
| **Postcondición** | El incidente tiene una clasificación combinada (puede ser "incierto" si no hay suficiente información). |
| **Excepción** | Texto vacío → usa solo resultado de imagen; modelo no responde → fallback a keywords. |
| **Servicio** | `app/services/ai.py:classify_text()` + `fuse()`. |

#### CU-20. Generar Resumen Estructurado del Incidente

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Crear un informe automático en texto legible que resuma los datos del incidente (ubicación, tipo, imágenes, transcripción) para los talleres. |
| **Actores** | SIA |
| **Actor iniciador** | Sistema (después de CU-18 y CU-19) |
| **Precondición** | El incidente tiene al menos clasificación y ubicación. |
| **Flujo principal** | 1. El backend ejecuta `summarize()` en `app/services/ai.py`. 2. Genera plantilla: `"Incidente reportado en [dirección]. [transcripción o descripción o 'Sin descripción adicional.']"`. 3. Almacena el resumen en el campo `resumen_ia` del incidente. 4. Se muestra al taller en la bandeja de solicitudes. |
| **Postcondición** | El incidente cuenta con un resumen listo para ser visualizado. |
| **Excepción** | Datos insuficientes → genera texto genérico con ubicación GPS. |
| **Servicio** | `app/services/ai.py:summarize()`. |

#### CU-21. Determinar Prioridad del Incidente

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Asignar un nivel de prioridad (ALTA, MEDIA, BAJA) basado en el tipo de incidente, el texto del conductor y palabras de emergencia. |
| **Actores** | SIA |
| **Actor iniciador** | Sistema (automático al clasificar) |
| **Precondición** | CU-18 o CU-19 completados (codigo disponible). |
| **Flujo principal** | 1. El sistema evalúa reglas base en `priority_for()`: `CHOQUE/MOTOR`→`ALTA`, `BATERIA/LLANTA`→`MEDIA`, otros→`BAJA`. 2. Si el texto contiene palabras críticas ("emergencia", "peligro", "humo", "fuego", "herido") → fuerza `ALTA`. 3. Asigna prioridad y la almacena en el campo `prioridad` del incidente. |
| **Postcondición** | El incidente tiene un campo prioridad (ALTA/MEDIA/BAJA). |
| **Excepción** | Clasificación incierta → prioridad `BAJA` por defecto. |
| **Servicio** | `app/services/ai.py:priority_for()`. |

---

### Ciclo #3 – Asignación, cotizaciones y pagos (Primer Parcial)

#### CU-22. Buscar Talleres Candidatos

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Obtener una lista de talleres cercanos que puedan atender el tipo de incidente y estén disponibles. |
| **Actores** | SIA, MAP |
| **Actor iniciador** | Sistema (al finalizar CU-10) |
| **Precondición** | Incidente clasificado y con ubicación GPS válida. |
| **Flujo principal** | 1. El backend obtiene la ubicación del incidente. 2. Consulta la base de datos de talleres activos y disponibles (disponibilidad = true) del mismo tenant. 3. Filtra por aquellos que ofrezcan el tipo de servicio requerido (batería, llanta, etc.). 4. Para cada taller, la API de mapas calcula la distancia en km y tiempo de llegada estimado. 5. Ordena por distancia + disponibilidad. 6. Devuelve lista de candidatos (máx. 5). |
| **Postcondición** | Se genera una lista de talleres candidatos. |
| **Excepción** | No hay talleres disponibles en un radio de 20 km, error en API de mapas. |

#### CU-23. Asignar Taller Óptimo

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Seleccionar automáticamente el taller más adecuado según el motor de asignación inteligente (distancia, carga de trabajo, calificación). |
| **Actores** | SIA |
| **Actor iniciador** | Sistema (después de CU-22, si el cliente no elige manualmente) |
| **Precondición** | Existe al menos un taller candidato. |
| **Flujo principal** | 1. El motor de asignación asigna puntajes a cada candidato: menor distancia (+), menor número de servicios activos (+), mayor calificación (+). 2. Selecciona el de mayor puntaje. 3. Envía la notificación al taller (CU-24). 4. Actualiza el estado del incidente a "taller asignado". |
| **Postcondición** | Un taller queda asignado al incidente. |
| **Excepción** | El taller seleccionado rechaza la solicitud (ver CU-26) → se ejecuta de nuevo con el siguiente candidato. |

#### CU-24. Notificar a Taller sobre Nueva Solicitud

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Enviar una notificación push o por WebSocket al taller para informarle de una nueva emergencia asignada. |
| **Actores** | TAL |
| **Actor iniciador** | Sistema (después de CU-23) |
| **Precondición** | Incidente asignado a un taller. |
| **Flujo principal** | 1. El backend genera un mensaje con ID de emergencia, resumen, ubicación. 2. Envía mediante FCM (Firebase Cloud Messaging) para app móvil del taller o mediante WebSocket si está activo. 3. El taller recibe la notificación y puede ver el detalle. 4. Se registra el envío en la tabla de notificaciones. |
| **Postcondición** | El taller es notificado. |
| **Excepción** | Taller no conectado (se guarda para reintentar), error en servicio de push. |

#### CU-25. Aceptar Solicitud con Oferta Editable (Taller)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | El taller responde a la solicitud generando una oferta editable para competir por precio, tiempo y calidad antes de que el cliente elija. |
| **Actores** | TAL |
| **Actor iniciador** | Taller autenticado |
| **Precondición** | CU-24 completado (notificación recibida) y el incidente está en estado "taller asignado". |
| **Flujo principal** | 1. Taller visualiza la solicitud pendiente en su bandeja. 2. El sistema muestra precio sugerido, distancia, dificultad y tiempo estimado. 3. El taller puede subir o bajar el precio sugerido, ajustar el tiempo, asignar técnico y escribir comentario. 4. El backend valida precio/tiempo positivos y crea una cotización pendiente. 5. Se notifica al cliente que hay una nueva oferta disponible. 6. El incidente permanece asignado hasta que el cliente elija una oferta (CU-29). |
| **Postcondición** | Queda registrada una oferta/cotización pendiente asociada a la asignación. |
| **Excepción** | El taller ya no tiene disponibilidad (cambio de último minuto) → se notifica al sistema para reasignar. |

#### CU-26. Rechazar Solicitud (con motivo opcional)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | El taller rechaza la solicitud, liberándola para que el sistema la asigne a otro taller. |
| **Actores** | TAL |
| **Actor iniciador** | Taller autenticado |
| **Precondición** | Incidente en estado "taller asignado" a este taller. |
| **Flujo principal** | 1. Taller selecciona "Rechazar". 2. Opcionalmente selecciona un motivo (demasiado lejos, falta de repuestos, etc.). 3. El sistema cambia el estado a "buscando taller" de nuevo. 4. Registra el rechazo. 5. El motor de asignación selecciona el siguiente candidato (CU-23). |
| **Postcondición** | La solicitud queda libre para reasignación. |
| **Excepción** | No hay más talleres candidatos → el incidente se marca como "no atendido" y se notifica al cliente. |

#### CU-27. Generar Oferta/Cotización Competitiva

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Calcular un precio sugerido automático y permitir que cada taller envíe su precio final ofertado, menor o mayor al sugerido. |
| **Actores** | CLI, TAL, SIA |
| **Actor iniciador** | Conductor o taller (según flujo) |
| **Precondición** | Incidente clasificado y taller asignado. |
| **Flujo principal** | 1. El motor calcula precio sugerido con: costo base por tipo, factor de dificultad, distancia, prioridad y calificación del taller. 2. El taller ve el precio sugerido y puede modificarlo libremente para competir. 3. El taller envía precio final, tiempo estimado y comentario. 4. El sistema guarda la cotización con estado `PENDIENTE`. 5. La app del cliente lista todas las ofertas recibidas con precio, tiempo, distancia y calificación. |
| **Postcondición** | Existen una o más ofertas comparables para que el cliente elija. |
| **Excepción** | El taller no responde dentro de un tiempo límite (se asigna cotización automática por IA). |

#### CU-28. Calcular Tiempo Estimado de Llegada y Reparación

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Estimar cuánto tardará el taller en llegar y completar la reparación, usando distancia, dificultad, tipo de incidente y carga del taller. |
| **Actores** | SIA, TAL |
| **Actor iniciador** | Sistema (al asignar taller o al aceptar solicitud) |
| **Precondición** | Incidente clasificado y taller asignado. |
| **Flujo principal** | 1. El sistema calcula tiempo de llegada: distancia / velocidad promedio + buffer operativo. 2. Calcula reparación base por tipo: batería, llanta, motor, choque u otros. 3. Ajusta por dificultad (baja/media/alta) y carga del taller. 4. El taller puede modificar el tiempo antes de enviar su oferta. 5. El cliente ve tiempo total estimado para comparar ofertas. |
| **Postcondición** | La oferta contiene tiempo de llegada, reparación y tiempo total estimado. |
| **Excepción** | No hay datos históricos → se usa valor por defecto (60 min). |

#### CU-29. Seleccionar Oferta de Taller (Cliente tipo Uber/InDrive)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir que el conductor elija la mejor oferta disponible comparando precio, tiempo, distancia y calidad, similar a Uber/InDrive. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor autenticado |
| **Precondición** | CU-22 completado (lista de candidatos mostrada). |
| **Flujo principal** | 1. El conductor recibe ofertas de talleres que aceptaron competir. 2. Cada oferta muestra precio final, precio sugerido, tiempo estimado, distancia, calificación y comentario. 3. El conductor selecciona una oferta. 4. El sistema marca esa cotización como `ACEPTADA`, rechaza las demás y cambia la asignación elegida a `ACEPTADO`. 5. El incidente pasa a `EN_CAMINO` y se notifica al taller elegido. |
| **Postcondición** | Solo una oferta queda aceptada y el técnico/taller elegido inicia la atención. |
| **Excepción** | El taller seleccionado no está disponible en ese momento → se informa al conductor y vuelve a la lista. |

#### CU-30. Efectuar Pago del Servicio (Pasarela)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Procesar el pago del servicio por parte del conductor mediante una pasarela de pagos integrada (Stripe, Mercado Pago, etc.). |
| **Actores** | CLI, PAG |
| **Actor iniciador** | Conductor autenticado (al finalizar el servicio o antes) |
| **Precondición** | El incidente tiene una cotización aceptada o el servicio ha sido completado. |
| **Flujo principal** | 1. Conductor selecciona "Pagar" en la app. 2. El sistema envía el monto y la descripción a la pasarela. 3. Se abre un webview o se usa SDK para ingresar datos de tarjeta. 4. La pasarela procesa el pago y devuelve un token o confirmación. 5. El backend registra la transacción (tabla pagos) y actualiza el estado del incidente a "pagado". 6. Se genera un comprobante (CU-32). |
| **Postcondición** | El pago queda registrado; se descuenta la comisión del 10% para la plataforma. |
| **Excepción** | Fondos insuficientes, tarjeta rechazada, timeout de la pasarela. |

#### CU-31. Consultar Comisión del Taller (10% para plataforma)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Mostrar al taller la comisión que la plataforma retiene por cada servicio (10% del valor cobrado al cliente). |
| **Actores** | TAL, ADT |
| **Actor iniciador** | Taller o administrador de tenant |
| **Precondición** | Existen pagos registrados asociados al taller. |
| **Flujo principal** | 1. El taller accede a "Reporte de comisiones". 2. El sistema suma el 10% de cada pago completado. 3. Muestra el total acumulado por periodo. 4. Puede exportar el detalle. |
| **Postcondición** | El taller visualiza la información. |
| **Excepción** | No hay pagos registrados. |

#### CU-32. Generar Factura / Comprobante

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Crear un documento (PDF) que sirva como comprobante de pago para el conductor y el taller. |
| **Actores** | CLI, TAL |
| **Actor iniciador** | Conductor o taller (después de un pago exitoso) |
| **Precondición** | CU-30 completado. |
| **Flujo principal** | 1. El sistema genera un PDF con los datos del servicio, montos, comisiones, fechas. 2. El usuario puede descargar o recibir por correo electrónico. 3. Se almacena una referencia en la base de datos. |
| **Postcondición** | El comprobante está disponible. |
| **Excepción** | Error al generar PDF. |

#### CU-49. Calificar Servicio Post-Atención

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir al conductor calificar la calidad del servicio recibido (1 a 5 estrellas) y dejar un comentario opcional para retroalimentación del taller. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor autenticado (al finalizar el servicio) |
| **Precondición** | Incidente en estado "finalizado" y pago completado (CU-30). |
| **Flujo principal** | 1. El sistema envía notificación al conductor invitándolo a calificar. 2. Conductor accede al detalle del incidente finalizado. 3. Selecciona una calificación de 1 a 5 estrellas. 4. Opcionalmente escribe un comentario (máx. 500 caracteres). 5. El sistema almacena la calificación asociada al incidente y al taller. 6. Se actualiza el promedio de calificación del taller. |
| **Postcondición** | La calificación queda registrada y el promedio del taller se actualiza. |
| **Excepción** | El conductor ya calificó previamente (no se permite doble calificación), incidente no está finalizado. |

---

### Ciclo #4 – Tiempo real (WebSockets + tracking) – Segundo Parcial

#### CU-33. Conectar a WebSocket para Seguimiento en Vivo

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Establecer un canal de comunicación bidireccional entre el cliente (o taller) y el backend para recibir actualizaciones instantáneas del incidente. |
| **Actores** | CLI, TAL |
| **Actor iniciador** | Usuario autenticado (conductor o taller) |
| **Precondición** | El incidente está activo (no finalizado) y el usuario tiene permiso (conductor propietario o taller asignado). |
| **Flujo principal** | 1. La aplicación (móvil o web) solicita conexión a `ws://api/ws/{tenant_id}/{incident_id}` con token JWT. 2. El backend valida el token y el tenant. 3. Se crea una conexión persistente. 4. El backend envía el estado actual como primer mensaje. 5. A partir de ahí, cualquier cambio de estado o ubicación se envía inmediatamente por este canal. |
| **Postcondición** | El cliente recibe eventos en tiempo real sin necesidad de polling. |
| **Excepción** | Token inválido, incidente no existe, límite de conexiones excedido. |

#### CU-34. Visualizar Ubicación del Taller en Mapa (Tracking)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Mostrar al conductor la posición actual del vehículo del técnico en un mapa, actualizándose en tiempo real. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor (automático al conectar WebSocket) |
| **Precondición** | CU-33 activo y el incidente está en estado "en camino" o "en atención". |
| **Flujo principal** | 1. El técnico (o taller) envía periódicamente su ubicación GPS al backend (mediante la app del taller). 2. El backend reenvía la coordenada a través del WebSocket a todos los clientes conectados del incidente. 3. La app del conductor actualiza el mapa con un marcador móvil. 4. Se muestra también la ruta estimada (opcional). |
| **Postcondición** | El conductor ve al técnico aproximarse. |
| **Excepción** | El técnico no envía ubicación (GPS apagado), señal perdida. |

#### CU-35. Recibir Notificación Inmediata de Cambio de Estado

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Enviar una alerta push o mensaje WebSocket al conductor cuando el taller cambia el estado del servicio (aceptado, en camino, finalizado, etc.). |
| **Actores** | CLI, TAL |
| **Actor iniciador** | Sistema (al actualizar el estado del incidente) |
| **Precondición** | El incidente tiene un estado que cambia. |
| **Flujo principal** | 1. El taller actualiza el estado (CU-36). 2. El backend persiste el cambio. 3. Se envía una notificación push (FCM) al dispositivo del conductor y también un mensaje por WebSocket si está conectado. 4. La app del conductor muestra un mensaje emergente y actualiza la interfaz. |
| **Postcondición** | El conductor es informado al instante. |
| **Excepción** | Dispositivo desconectado (la notificación se guarda para reintentar). |

#### CU-36. Actualizar Estado del Incidente (Taller)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir al taller modificar el estado del servicio (en camino, en atención, finalizado, cancelado). |
| **Actores** | TAL |
| **Actor iniciador** | Taller autenticado |
| **Precondición** | El incidente está asignado a ese taller y el taller tiene sesión activa. |
| **Flujo principal** | 1. Taller selecciona el incidente. 2. Elige un nuevo estado (por ejemplo, "en camino"). 3. Opcionalmente ingresa comentarios. 4. El sistema valida la transición (no se puede pasar de "finalizado" a "en camino"). 5. Guarda el cambio con timestamp. 6. Dispara notificaciones (CU-35) y actualiza WebSocket. |
| **Postcondición** | El estado del incidente se actualiza. |
| **Excepción** | Transición de estado inválida, error de conexión. |

#### CU-37. Transmitir Llegada del Técnico (Push al cliente)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Notificar al conductor que el técnico ha llegado al lugar del incidente. |
| **Actores** | TAL |
| **Actor iniciador** | Taller (al marcar "llegué") o sistema mediante geocerca (detección automática). |
| **Precondición** | Estado actual "en camino" y la ubicación del técnico coincide con la del incidente (radio < 50m). |
| **Flujo principal** | 1. El taller presiona "Llegué" en su app (o el sistema detecta cercanía). 2. El backend cambia el estado a "en atención". 3. Se envía notificación push al conductor: "El técnico ha llegado". 4. Opcionalmente se inicia un contador de tiempo de atención. |
| **Postcondición** | El conductor sabe que el técnico está en el lugar. |
| **Excepción** | Geocerca no se activa (GPS impreciso). |

---

### Ciclo #5 – Offline, KPIs y multi‑tenant (Segundo Parcial)

#### CU-38. Guardar Emergencia Localmente y Marcar como Pendiente de Sincronización (modo offline)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Almacenar en el dispositivo móvil (SQLite) los datos de una emergencia cuando no hay conexión a internet, etiquetándola visualmente como pendiente de sincronización. |
| **Actores** | CLI |
| **Actor iniciador** | Conductor (al intentar reportar emergencia sin conexión) |
| **Precondición** | No hay conexión a internet (detectada por el sistema). |
| **Flujo principal** | 1. Conductor completa el formulario de emergencia (CU-10). 2. Al enviar, el sistema detecta ausencia de red. 3. Guarda la emergencia en la base de datos local con estado `sync_pendiente = true` y `id_local` único. 4. Asigna un flag `pendiente = true` y muestra la emergencia con un ícono de reloj/sincronización en la interfaz. 5. Muestra un mensaje: "Emergencia guardada localmente. Se sincronizará automáticamente cuando haya conexión". 6. El conductor puede ver el detalle, pero no puede modificar hasta sincronizar. |
| **Postcondición** | La emergencia se persiste localmente y queda visualmente identificada como pendiente de sincronización. |
| **Campo** | **Descripción** |
| **Criterio de aceptación** | 1. Modo avión activado. 2. Conductor completa formulario de emergencia y envía. 3. La emergencia aparece en el historial con ícono de reloj y etiqueta "pendiente sync". 4. En `incidente_local` (SQLite) existe una fila con `estado_sync = 'PENDIENTE'` y un `id_local` UUID único. 5. Al desconectarse y reconectarse, el mensaje "Guardada localmente" persiste visible. |
| **Excepción** | Error al escribir en SQLite (falta de espacio). |

> **Nota:** CU-39 fue fusionado con CU-38 por ser parte de la misma acción (el marcado de pendencia ocurre automáticamente al guardar localmente).

#### CU-40. Sincronizar Automáticamente al Recuperar Conexión

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Enviar al backend todas las emergencias pendientes tan pronto como se restablezca la conexión a internet. |
| **Actores** | CLI, SIA |
| **Actor iniciador** | Sistema (evento de conectividad) |
| **Precondición** | Existen emergencias con `sync_pendiente = true` y se detecta conexión disponible. |
| **Flujo principal** | 1. El detector de conectividad del dispositivo (broadcast receiver en Android, `connectivity_plus`) notifica conexión. 2. El servicio de sincronización toma la lista de emergencias locales. 3. Envía cada una al endpoint `/sync` del backend. 4. El backend procesa y devuelve un ID de servidor. 5. La app actualiza el registro local marcando `sync_pendiente = false` y guarda `id_servidor`. 6. Se notifica al conductor que la emergencia fue enviada. |
| **Postcondición** | Las emergencias pendientes ahora existen en el backend y están sincronizadas. |
| **Excepción** | Error de conexión durante el envío (se reintenta con backoff exponencial, marcando `estado_sync = 'ERROR'`), conflicto de datos. |
| **Criterio de aceptación** | 1. Dos emergencias guardadas offline. 2. Activar red. 3. Ambas aparecen en el servidor con `estado_sincronizacion = 'SINCRONIZADO'`. 4. El historial del móvil ya no muestra ícono de reloj. 5. `incidente_local` tiene ambas filas con `estado_sync = 'SINCRONIZADO'` y `id_servidor` poblado. |

#### CU-41. Resolver Conflictos de Sincronización (evitar duplicados)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Evitar que una misma emergencia se duplique en el servidor debido a reintentos o a múltiples dispositivos. |
| **Actores** | Sistema |
| **Actor iniciador** | Backend al recibir una solicitud de sincronización |
| **Precondición** | Se recibe un objeto con `id_local` y datos. |
| **Flujo principal** | 1. El backend verifica si ya existe un incidente con el mismo `id_local` (en una tabla de mapeo). 2. Si existe, retorna el ID existente sin crear duplicado. 3. Si no existe, crea un nuevo incidente y almacena la relación `id_local` ↔ `id_servidor`. 4. En caso de conflictos de datos (ej. mismo incidente modificado offline dos veces), se aplica la regla "última escritura gana" (timestamp más reciente). |
| **Postcondición** | No hay duplicados; el incidente está correctamente referenciado. |
| **Excepción** | Datos corruptos, violación de integridad. |
| **Criterio de aceptación** | 1. Enviar mismo batch de sincronización dos veces. 2. Primera respuesta: `status = "CREATED"`. 3. Segunda respuesta: `status = "DUPLICATE"` o `"UPDATED"`. 4. `SELECT COUNT(*) FROM emergencias.incidente` no incrementa con el segundo envío. 5. Si `client_updated_at` del segundo envío es más reciente, los datos se actualizan (last-write-wins). |

#### CU-42. Visualizar Dashboard de KPIs (Administrador)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Mostrar al administrador de plataforma o de tenant un panel con indicadores clave de desempeño extraídos de la base de datos en tiempo real. |
| **Actores** | ADM, ADT |
| **Actor iniciador** | Administrador autenticado |
| **Precondición** | Existen incidentes y asignaciones registradas en el sistema. |
| **Flujo principal** | 1. El administrador accede a la sección "KPIs" en la web. 2. El backend ejecuta consultas agregadas (vistas materializadas o queries optimizadas) para calcular: tiempo promedio de asignación, tiempo promedio de llegada, incidentes por tipo, talleres más eficientes, etc. 3. Los resultados se envían al frontend en formato JSON. 4. Se renderizan gráficos (barras, líneas, mapas de calor). 5. El administrador puede filtrar por rango de fechas. |
| **Postcondición** | Los KPIs se muestran correctamente. |
| **Excepción** | No hay datos suficientes (se muestran ceros), error de conexión a BD. |
| **Criterio de aceptación** | 1. Login como `ana@auxilionorte.com` (ADT). 2. Navegar a `/kpis`. 3. Ver cards con valores reales (no ceros). 4. Gráfico de barras "Incidentes por tipo" renderiza. 5. Gráfico "Cumplimiento SLA" renderiza. 6. Tabla "Talleres más eficientes" muestra filas. 7. Botón "Refrescar" ejecuta `POST /kpis/refresh` y actualiza datos. |

#### CU-43. Filtrar KPIs por Tenant

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Permitir que el administrador de plataforma vea indicadores de un tenant específico, y que el administrador de tenant solo vea los suyos (sin mezclar). |
| **Actores** | ADM, ADT |
| **Actor iniciador** | Administrador (superusuario) o ADT |
| **Precondición** | CU-42 activo y el usuario tiene roles adecuados. |
| **Flujo principal** | 1. El administrador de plataforma selecciona un tenant de un dropdown. 2. El backend añade `WHERE tenant_id = :id` a todas las consultas de KPIs. 3. Para un ADT, el filtro es forzado automáticamente (no puede cambiarlo). 4. Se actualizan los gráficos con los datos del tenant seleccionado. |
| **Postcondición** | Los KPIs reflejan únicamente el tenant elegido. |
| **Excepción** | Tenant no existe o no tiene datos. |
| **Criterio de aceptación** | 1. Login como `ana@auxilionorte.com` (ADT Auxilio Norte). 2. No ve dropdown de tenant en pantalla KPIs. 3. Datos mostrados = solo Auxilio Norte. 4. Login como `admin@plataforma.com` (ADM). 5. Ve dropdown con "Auxilio Norte" y "RutaSegura". 6. Selecciona "RutaSegura" → gráficos cambian a datos de RutaSegura. 7. `SELECT * FROM emergencias.mv_kpi_resumen_tenant` muestra filas separadas por tenant que coinciden con lo que ve cada admin. |

#### CU-44. Exportar Reporte de KPIs (PDF/CSV)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Generar un archivo descargable con los KPIs actuales para su análisis externo o presentación. |
| **Actores** | ADM, ADT |
| **Actor iniciador** | Administrador (desde el dashboard) |
| **Precondición** | CU-42 completado. |
| **Flujo principal** | 1. El administrador hace clic en "Exportar". 2. Elige formato (PDF o CSV). 3. El sistema genera el archivo con los datos filtrados actualmente. 4. Se inicia la descarga. |
| **Postcondición** | El usuario obtiene el archivo. |
| **Excepción** | Error al generar archivo, demasiados datos (timeout). |
| **Criterio de aceptación** | 1. En pantalla KPIs, hacer clic en "Exportar CSV". 2. Se descarga archivo `kpis-talleres-YYYY-MM-DD.csv`. 3. El archivo contiene columnas: Taller, Atendidos, Prom. respuesta (min). 4. Los datos coinciden con la tabla visible en pantalla. |

#### CU-45. Configurar Umbrales de SLA (Acuerdo de Nivel de Servicio)

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Definir los tiempos máximos aceptables para cada tipo de incidente (ej. batería: 30 minutos) para calcular el cumplimiento de SLA. |
| **Actores** | ADM |
| **Actor iniciador** | Administrador de plataforma |
| **Precondición** | El sistema tiene tipos de incidentes definidos. |
| **Flujo principal** | 1. Administrador accede a "Configuración SLA". 2. Por cada tipo de incidente, ingresa un tiempo límite (en minutos). 3. Guarda la configuración. 4. El sistema almacena en tabla `sla_config` (por tenant). 5. El cálculo de cumplimiento de SLA (KPI) usa estos umbrales. |
| **Postcondición** | Los nuevos umbrales se aplican en los siguientes cálculos. |
| **Excepción** | Valores no numéricos o negativos. |
| **Criterio de aceptación** | 1. Login como `admin@plataforma.com`. 2. Navegar a `/sla`. 3. Ver tabla con SLA existentes (del seed). 4. Crear nuevo SLA con tipo y tiempo máximo. 5. Editar tiempo máximo de un SLA existente → guardar. 6. Refrescar KPIs → gráfico "Cumplimiento SLA" refleja nuevo umbral. 7. `SELECT * FROM emergencias.sla_config` confirma cambios. |

#### CU-46. Crear Nuevo Tenant

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Registrar una nueva organización (red de talleres) en la plataforma, habilitando el aislamiento multi-tenant. |
| **Actores** | ADM |
| **Actor iniciador** | Administrador de plataforma |
| **Precondición** | El usuario es superusuario. |
| **Flujo principal** | 1. Administrador accede a "Tenants" → "Crear". 2. Ingresa nombre de la organización, dominio, plan (básico, premium). 3. Asigna un administrador de tenant (correo electrónico). 4. El sistema crea una entrada en la tabla `tenant`. 5. Se genera un schema lógico (no físico) mediante `tenant_id`. 6. Se envía invitación al administrador de tenant. |
| **Postcondición** | Nuevo tenant disponible; los datos futuros se aislarán con ese ID. |
| **Excepción** | Nombre duplicado, error de base de datos. |
| **Criterio de aceptación** | 1. Login como `admin@plataforma.com`. 2. Navegar a `/admin/tenants`. 3. Pestaña "Crear tenant": llenar nombre, dominio, seleccionar plan → crear. 4. El tenant aparece en listado. 5. `SELECT * FROM emergencias.tenant` muestra nueva fila. 6. El nuevo tenant aparece en dropdown de KPIs de ADM. |

#### CU-47. Asignar Administrador a un Tenant

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Designar a un usuario existente (o nuevo) como administrador de un tenant específico. |
| **Actores** | ADM |
| **Actor iniciador** | Administrador de plataforma |
| **Precondición** | El tenant existe (CU-46) y el usuario existe o se crea. |
| **Flujo principal** | 1. Administrador selecciona el tenant. 2. Elige "Asignar administrador". 3. Ingresa correo del usuario. 4. El sistema le otorga el rol `tenant_admin` y asocia su `tenant_id`. 5. El usuario recibe una notificación. |
| **Postcondición** | El usuario puede gestionar talleres y ver KPIs de ese tenant. |
| **Excepción** | Usuario no existe (se crea automáticamente con contraseña temporal). |
| **Criterio de aceptación** | 1. ADM selecciona tenant y asigna admin con email + nombre. 2. `SELECT * FROM emergencias.usuario WHERE email = '...'` muestra rol `ADMIN_TENANT` con `tenant_id` correcto. 3. Nuevo admin puede hacer login y acceder a `/kpis` viendo solo datos de su tenant. |

#### CU-48. Configurar Plan de Servicio por Tenant

| Campo | Descripción |
|-------|-------------|
| **Propósito** | Definir las capacidades (máximo de talleres, número de técnicos, acceso a IA avanzada, etc.) según el plan contratado por el tenant. |
| **Actores** | ADM |
| **Actor iniciador** | Administrador de plataforma |
| **Precondición** | Tenant creado. |
| **Flujo principal** | 1. Administrador selecciona un tenant. 2. Elige un plan (básico, profesional, enterprise). 3. El sistema actualiza los límites en la tabla de tenant. 4. El backend aplica restricciones al procesar solicitudes de ese tenant (ej. no puede tener más de 10 talleres). |
| **Postcondición** | El tenant queda limitado según su plan. |
| **Excepción** | Plan no definido. |
| **Criterio de aceptación** | 1. ADM selecciona tenant y cambia plan (ej. de "basico" a "profesional"). 2. `SELECT plan_id FROM emergencias.tenant WHERE id = ...` muestra nuevo plan. 3. Los límites del nuevo plan (max_talleres, max_tecnicos, ia_avanzada) se aplican en endpoints de creación. |

---

Con esto se han especificado todos los casos de uso (48 en total) siguiendo el formato solicitado. Ahora podemos continuar con el **Flujo de Trabajo de Análisis** (diagramas UML) o con el **Diseño**. ¿Por cuál prefiere seguir?
