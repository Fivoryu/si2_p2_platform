# Plan Detallado 100% - Emergencias Vehiculares

## Resumen

Objetivo: completar el proyecto para defenderlo como 100% del Segundo Parcial, reforzando CU1-CU48 con enfasis en tracking completo, asignacion inteligente, penalizacion por rechazos, ranking por calidad/eficiencia, pagos completos, KPIs avanzados, offline robusto, seguridad y multi-tenant.

## 1. Seguridad Base Y Multi-Tenant

- Usar autenticacion verificada en endpoints protegidos, validando tokens revocados.
- Validar ownership por incidente: conductor propietario, taller asignado, tecnico del taller asignado, admin tenant solo su tenant y admin plataforma global.
- Endurecer WebSocket para validar token, tenant, permiso sobre incidente y rol autorizado.
- Evitar contrasenas fijas como `password123`; usar contrasenas temporales aleatorias o flujo de invitacion/reset.
- Aplicar limites reales del plan del tenant en talleres y tecnicos.
- Revisar RLS para evitar acceso amplio cuando `app.current_tenant` este vacio.

## 2. Tracking Completo CU33-CU37

### Backend

- WebSocket `/ws/{tenant_id}/{incident_id}` valida token, tenant, usuario autorizado y token no revocado.
- Snapshot inicial incluye incidente, asignacion, taller, tecnico, ultima ubicacion, ETA e historial reciente.
- Persistir ubicaciones en `ubicacion_tracking` con latitud, longitud, tecnico, fake/real, velocidad, precision y timestamp.
- Bloquear que el conductor envie `TECH_LOCATION`.
- Emitir eventos: `STATE_SNAPSHOT`, `STATUS_CHANGED`, `TECH_LOCATION`, `ETA_UPDATED`, `TECH_ARRIVED`, `SERVICE_STARTED`, `SERVICE_FINISHED`.

### App Movil Conductor

- Mostrar mapa con ubicacion del conductor, ubicacion del tecnico, ruta o linea de aproximacion, ETA, estado y ultima actualizacion.
- Si no llega una nueva ubicacion, mostrar la ultima ubicacion conocida y hace cuanto fue recibida.
- Cuando el tecnico este cerca, notificar llegada y cambiar a `EN_ATENCION`.

### Web Taller/Tecnico

- Permitir enviar ubicacion.
- Permitir marcar en camino, llegada, inicio de atencion y finalizacion.
- Actualizar bandeja y detalle en tiempo real por WebSocket.

## 3. Motor De Asignacion Inteligente CU22-CU29

Cada taller candidato debe calcularse con:

- Distancia al incidente.
- Tiempo promedio de llegada historico.
- Calificacion del taller.
- Calificacion/eficiencia del tecnico cuando exista.
- Servicios finalizados, cancelados y cumplimiento SLA.
- Especialidad por tipo de incidente.
- Carga actual y disponibilidad.
- Historial de rechazos.
- Historial con el mismo cliente.
- Demanda actual por zona/hora.
- Incidentes por tipo atendidos exitosamente.

Formula base:

```text
score =
  distancia_score * 0.25 +
  disponibilidad_score * 0.15 +
  rating_score * 0.15 +
  eficiencia_score * 0.15 +
  especialidad_score * 0.10 +
  sla_score * 0.10 +
  carga_score * 0.05 -
  rechazo_penalty * 0.15
```

Reglas de rechazo:

- Rechazos recientes reducen prioridad.
- Rechazos al mismo cliente o mismo tipo penalizan mas.
- La penalizacion decae con el tiempo.
- El rechazo por saturacion o fuera de especialidad debe penalizar menos.

## 4. Ranking De Tecnicos

- Elegir tecnico segun disponibilidad, especialidad, servicios activos, historial del tipo de incidente, tiempo promedio de llegada y cercania si existe ubicacion.
- Registrar `asignacion.tecnico_id`.
- Si el taller acepta sin tecnico, el backend sugiere automaticamente uno disponible.
- KPIs deben separar rendimiento de taller y tecnico.

## 5. Precio Dinamico Y Pagos Completos CU27-CU32

El precio sugerido debe considerar:

- Precio base por tipo de emergencia.
- Prioridad.
- Distancia.
- ETA.
- Demanda actual.
- Hora pico.
- Rating/calidad del taller.
- Cumplimiento SLA.
- Eficiencia historica.
- Dificultad del servicio.
- Penalizacion/descuento por rechazos.

Formula base:

```text
precio_final =
  precio_base_tipo
  + costo_distancia
  + costo_prioridad
  + ajuste_demanda
  + ajuste_calidad
  + ajuste_dificultad
```

Luego:

```text
comision_plataforma = precio_final * 0.10
monto_taller = precio_final - comision_plataforma
```

Pagos:

- Mantener `/pagos/intent`.
- Confirmar pago real por `/pagos/webhook` con firma Stripe.
- Bloquear `/pagos/mock-complete` en produccion.
- Evitar pagos duplicados.
- Generar factura solo cuando el pago queda completado.
- Cambiar incidente a `PAGADO` solo despues de pago exitoso.

## 6. KPIs Avanzados

KPIs obligatorios:

- Total de incidentes.
- Tiempo promedio de asignacion.
- Tiempo promedio de llegada.
- Tiempo promedio de atencion.
- Incidentes por tipo.
- Incidentes por zona.
- Talleres mas eficientes.
- Cumplimiento SLA.
- Comisiones por taller.
- Ingresos de plataforma.

KPIs avanzados:

- Tasa de rechazo por taller.
- Tasa de aceptacion.
- Tiempo promedio de respuesta.
- Rating por taller.
- Ranking de tecnicos.
- Servicios finalizados por tecnico.
- Demanda por hora.
- Demanda por zona.
- Precio promedio por tipo.
- Relacion precio/calidad.

## 7. Offline Y Sync CU38-CU41

- Guardar emergencia localmente antes de enviar.
- Mostrar estados: pendiente, sincronizando, sincronizado y error.
- Sincronizar automaticamente al recuperar conexion.
- Evitar duplicados por `external_id`.
- Validar vehiculo del conductor.
- Limitar lote y evidencias.
- Evitar que `client_updated_at` manipulado pise datos criticos.
- Permitir reintento manual si falla.

## 8. Cierre CU1-CU48

- CU1-CU9: auth, perfiles, vehiculos, talleres, tecnicos y disponibilidad.
- CU10-CU16: incidente completo con texto, imagen, audio, GPS, estado e historial.
- CU17-CU21: IA por texto, imagen, audio, resumen y prioridad.
- CU22-CU29: busqueda, asignacion, rechazo, oferta y seleccion.
- CU30-CU32: pago real, comision y factura.
- CU33-CU37: WebSocket seguro, tracking, ETA y notificaciones.
- CU38-CU41: offline, sync, conflictos y no duplicados.
- CU42-CU45: dashboard KPI, filtros, exportacion y SLA.
- CU46-CU48: tenant, admin, plan y limites reales.

## 9. Pruebas De Aceptacion

### Seguridad

- Conductor A no ve incidente de conductor B.
- Taller no asignado no cambia estado.
- Usuario del mismo tenant no entra a WebSocket ajeno.
- Token revocado no funciona.
- Admin tenant no ve otro tenant.

### Tracking

- Snapshot inicial completo.
- Tecnico envia ubicacion.
- Conductor ve movimiento.
- ETA se actualiza.
- Llegada cambia estado.
- Reconexion mantiene estado y ultima ubicacion.

### Asignacion

- Taller cercano gana si tiene buen score.
- Taller con rechazos baja en ranking.
- Taller con mejor SLA/rating puede superar a uno mas cercano.
- Rechazo reasigna al siguiente candidato.
- Tipo de emergencia filtra especialidad.

### Pricing Y Pagos

- Precio cambia por distancia, prioridad, demanda y calidad.
- Comision 10% correcta.
- Stripe webhook confirma pago.
- Factura se genera.
- Pago duplicado se bloquea.

### KPIs

- Dashboard carga datos reales.
- Filtro tenant funciona.
- Export CSV/PDF funciona.
- SLA cambia resultados.
- KPIs avanzados aparecen.

### Offline

- Modo avion guarda emergencia.
- Historial muestra pendiente.
- Reconexion sincroniza.
- Reintento no duplica.
- Error queda reintentable.

## Checklist Final

- Endpoints criticos validan permisos.
- Logout revoca token realmente.
- WebSocket valida propietario/asignacion.
- Tracking completo funciona en mapa.
- Talleres que rechazan pierden prioridad.
- Ranking usa resenas, eficiencia, SLA, distancia y tipo.
- Precio se calcula por demanda, calidad, distancia y emergencia.
- Stripe test funciona con webhook.
- Factura y comision se generan.
- Offline sincroniza sin duplicar.
- KPIs muestran datos reales.
- Planes se aplican realmente.
- Web produccion no apunta a localhost.
- Hay pruebas y capturas para demostrar todo.

## Supuestos

- CU39 sigue fusionado con CU38.
- CU49 queda como caso adicional de calificacion post-atencion.
- Stripe en modo test es la pasarela recomendada.
- La prioridad es defensa academica completa con seguridad suficiente para no dejar huecos evidentes.
