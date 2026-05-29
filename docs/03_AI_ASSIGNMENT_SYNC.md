# 03 — AI Pipeline · Assignment Engine · Offline Sync

## A. AI pipeline — CU-17..CU-21

Runs as a background task after `POST /incidentes`. Uses external APIs first (fast). All results stored in `clasificacion_ia` and the incident is updated.

### A.1 Service interface — `app/services/ai.py`
```python
import httpx, json
from sqlalchemy import text
from ..core.config import settings
from ..core.db import SessionLocal

TIPOS = {  # codigo -> uuid (load once from tipo_incidente; cache)
    "BATERIA": "33333333-0000-0000-0000-000000000001",
    "LLANTA":  "33333333-0000-0000-0000-000000000002",
    "MOTOR":   "33333333-0000-0000-0000-000000000003",
    "CHOQUE":  "33333333-0000-0000-0000-000000000004",
    "OTROS":   "33333333-0000-0000-0000-000000000005",
}

async def transcribe(audio_url: str) -> str:
    """OpenAI Whisper. Return transcription text."""
    # download file, POST to https://api.openai.com/v1/audio/transcriptions (model=whisper-1)
    ...

async def classify_text(texto: str) -> tuple[str, float]:
    """Return (codigo, confidence). Use keyword rules + LLM fallback.
       Keywords: bateria/no arranca->BATERIA; pinchazo/llanta->LLANTA;
       choque/colision->CHOQUE; humo/motor->MOTOR; else OTROS."""
    ...

async def classify_image(image_url: str) -> tuple[str, float]:
    """Vision model (OpenAI gpt-4o vision or local CNN). Return (codigo, confidence)."""
    ...

def fuse(text_res, img_res) -> tuple[str, float]:
    """Combine: if both agree -> high confidence; else pick higher confidence;
       if max confidence < 0.5 -> ('OTROS' , conf) and mark INCIERTA."""
    ...

def priority_for(codigo: str, texto: str) -> str:
    base = {"CHOQUE":"ALTA","MOTOR":"ALTA","BATERIA":"MEDIA","LLANTA":"MEDIA"}.get(codigo,"BAJA")
    if any(w in (texto or "").lower() for w in ["emergencia","peligro","humo","fuego","herido"]):
        base = "ALTA"
    return base

def summarize(inc: dict, transcripcion: str) -> str:
    return (f"Incidente tipo {inc['tipo']} reportado en {inc.get('direccion') or 'ubicación GPS'}. "
            f"Descripción: {transcripcion or inc.get('descripcion') or 'sin texto'}.")
```

### A.2 Orchestrator (called by BackgroundTasks)
```python
async def run_ai_pipeline(incidente_id: str, tenant_id: str):
    db = SessionLocal()
    db.execute(text("SELECT set_config('app.current_tenant', :t, true)"), {"t": tenant_id})
    inc = db.execute(text("SELECT * FROM emergencias.incidente WHERE id=:id"),
                     {"id": incidente_id}).mappings().first()
    evs = db.execute(text("SELECT * FROM emergencias.evidencia WHERE incidente_id=:id"),
                     {"id": incidente_id}).mappings().all()

    transcripcion = ""
    for e in evs:
        if e["tipo"] == "AUDIO" and e["url"]:
            transcripcion = await transcribe(e["url"])
            db.execute(text("UPDATE emergencias.evidencia SET transcripcion=:t WHERE id=:i"),
                       {"t": transcripcion, "i": e["id"]})

    text_res = await classify_text((inc["descripcion"] or "") + " " + transcripcion)
    img_res = None
    for e in evs:
        if e["tipo"] == "IMAGEN" and e["url"]:
            img_res = await classify_image(e["url"]); break

    codigo, conf = fuse(text_res, img_res)
    prio = priority_for(codigo, (inc["descripcion"] or "") + " " + transcripcion)
    tipo_id = TIPOS[codigo]

    db.execute(text("""INSERT INTO emergencias.clasificacion_ia
        (tenant_id,incidente_id,fuente,tipo_incidente_id,etiqueta,confianza,prioridad_sugerida,modelo)
        VALUES (:t,:i,'COMBINADA',:tp,:lbl,:c,:p,'openai')"""),
        {"t":tenant_id,"i":incidente_id,"tp":tipo_id,"lbl":codigo,"c":conf,"p":prio})

    resumen = summarize({"tipo":codigo,"direccion":inc["direccion"],"descripcion":inc["descripcion"]}, transcripcion)
    db.execute(text("""UPDATE emergencias.incidente
        SET tipo_incidente_id=:tp, prioridad=:p, resumen_ia=:r, estado='BUSCANDO_TALLER'
        WHERE id=:i"""), {"tp":tipo_id,"p":prio,"r":resumen,"i":incidente_id})
    db.commit(); db.close()

    # then trigger assignment (section B)
    await assign_best_workshop(incidente_id, tenant_id)
```

> If no API keys are available for the demo, ship `classify_text` with the keyword rules only (deterministic, free) and a stub `classify_image`. That still satisfies CU-18/19 visibly.

---

## B. Assignment engine — CU-22..CU-26, CU-29

### B.1 Candidate search (CU-22) — `app/services/assignment.py`
```python
from sqlalchemy import text

CANDIDATE_SQL = text("""
WITH inc AS (
  SELECT latitud, longitud, tipo_incidente_id FROM emergencias.incidente WHERE id = :inc
)
SELECT t.id AS taller_id, t.nombre, t.calificacion,
       -- straight-line km via earthdistance; swap for Google Distance Matrix if MAPS_API_KEY set
       (earth_distance(ll_to_earth(t.latitud,t.longitud),
                       ll_to_earth(inc.latitud,inc.longitud)) / 1000.0) AS distancia_km,
       (SELECT count(*) FROM emergencias.asignacion a
         WHERE a.taller_id = t.id AND a.estado IN ('ASIGNADO','ACEPTADO')) AS carga
FROM emergencias.taller t
JOIN inc ON true
JOIN emergencias.taller_servicio ts
  ON ts.taller_id = t.id AND ts.tipo_incidente_id = inc.tipo_incidente_id
WHERE t.disponible = true AND t.activo = true
  AND (earth_distance(ll_to_earth(t.latitud,t.longitud),
                      ll_to_earth(inc.latitud,inc.longitud)) / 1000.0) <= 20  -- 20 km radius
ORDER BY distancia_km ASC
LIMIT 5;
""")

def score(distancia_km, carga, calificacion, capacidad_max=3):
    # higher is better; weights tuned for demo
    w_dist, w_load, w_rating = 0.5, 0.3, 0.2
    dist_score = 1.0 / (1.0 + distancia_km)
    load_score = max(0.0, 1.0 - carga / max(capacidad_max, 1))
    rating_score = calificacion / 5.0
    return round(w_dist*dist_score + w_load*load_score + w_rating*rating_score, 4)
```

### B.2 Auto-assign (CU-23) + reassign on reject (CU-26)
```python
async def assign_best_workshop(incidente_id: str, tenant_id: str):
    db = _scoped_session(tenant_id)
    cands = db.execute(CANDIDATE_SQL, {"inc": incidente_id}).mappings().all()
    if not cands:
        db.execute(text("UPDATE emergencias.incidente SET estado='NO_ATENDIDO' WHERE id=:i"),
                   {"i": incidente_id}); db.commit()
        await manager.publish(tenant_id, incidente_id, {"type":"STATUS_CHANGED",
            "incident_id":incidente_id,"data":{"estado_nuevo":"NO_ATENDIDO"}})
        return

    # persist candidates with score
    ranked = sorted(cands, key=lambda c: score(c["distancia_km"], c["carga"], c["calificacion"]), reverse=True)
    for c in ranked:
        db.execute(text("""INSERT INTO emergencias.taller_candidato
            (tenant_id,incidente_id,taller_id,distancia_km,tiempo_llegada_min,puntaje)
            VALUES (:t,:i,:tl,:d,:eta,:s)
            ON CONFLICT (incidente_id,taller_id) DO NOTHING"""),
            {"t":tenant_id,"i":incidente_id,"tl":c["taller_id"],"d":round(c["distancia_km"],2),
             "eta":int(c["distancia_km"]*2)+3, "s":score(c["distancia_km"],c["carga"],c["calificacion"])})

    best = ranked[0]
    db.execute(text("""INSERT INTO emergencias.asignacion
        (tenant_id,incidente_id,taller_id,estado,asignacion_automatica)
        VALUES (:t,:i,:tl,'ASIGNADO',true)"""),
        {"t":tenant_id,"i":incidente_id,"tl":best["taller_id"]})
    db.execute(text("UPDATE emergencias.incidente SET estado='TALLER_ASIGNADO' WHERE id=:i"),
               {"i":incidente_id})
    db.commit()
    # notify workshop (WS + FCM) and broadcast
    await manager.publish(tenant_id, incidente_id, {"type":"ASSIGNMENT",
        "incident_id":incidente_id,"data":{"taller_id":str(best["taller_id"]),
        "taller_nombre":best["nombre"],"estado":"ASIGNADO"}})
```

Reject flow (`POST /asignaciones/{id}/rechazar`): set that asignacion `RECHAZADO` + `motivo_rechazo`, set incident back to `BUSCANDO_TALLER`, then call `assign_best_workshop` again **excluding** workshops already RECHAZADO for this incident. If none left → `NO_ATENDIDO`.

Manual selection (CU-29): `POST /incidentes/{id}/asignar-manual {taller_id}` skips scoring and assigns directly.

### B.3 Repair time estimate (CU-28)
```python
def estimate_repair_min(db, taller_id, tipo_incidente_id):
    row = db.execute(text("""SELECT tiempo_base_min FROM emergencias.tarifa
        WHERE taller_id=:t AND tipo_incidente_id=:tp"""),
        {"t":taller_id,"tp":tipo_incidente_id}).first()
    base = row[0] if row else 60
    carga = db.execute(text("""SELECT count(*) FROM emergencias.asignacion
        WHERE taller_id=:t AND estado IN ('ASIGNADO','ACEPTADO')"""), {"t":taller_id}).scalar()
    return int(base * (1 + 0.15 * carga))   # T_base * factor_carga
```

---

## C. Offline sync — CU-38..CU-41

### C.1 Endpoint — `app/api/sync.py`
```
POST /sync   🔒 (CONDUCTOR)
```
Request (batch of incidents created offline):
```json
{ "incidentes": [
  { "external_id":"<uuid generated on device>",
    "vehiculo_id":"<uuid>",
    "descripcion":"No arranca",
    "latitud":-17.78, "longitud":-63.18, "direccion":"Av X",
    "client_created_at":"2026-06-01T13:00:00Z",
    "client_updated_at":"2026-06-01T13:05:00Z",
    "evidencias":[{"tipo":"IMAGEN","contenido_b64":"...","mime_type":"image/jpeg"}]
  }
]}
```
Response:
```json
{ "results": [ { "external_id":"...", "incidente_id":"<server uuid>", "status":"CREATED|DUPLICATE|UPDATED" } ] }
```

### C.2 Algorithm (idempotent, last-write-wins)
```python
@router.post("/sync")
def sync(body: SyncBatch, bg: BackgroundTasks,
         user=Depends(require_roles("CONDUCTOR")), db=Depends(get_db)):
    out = []
    for item in body.incidentes:
        existing = db.execute(text("""SELECT incidente_id FROM emergencias.sync_mapping
            WHERE tenant_id=:t AND external_id=:e"""),
            {"t":user.tenant,"e":str(item.external_id)}).first()

        if existing:
            inc_id = existing[0]
            # last-write-wins on conflict
            db.execute(text("""UPDATE emergencias.incidente
                SET descripcion=:d, latitud=:la, longitud=:lo, direccion=:dir
                WHERE id=:i AND updated_at < :cu"""),
                {"d":item.descripcion,"la":item.latitud,"lo":item.longitud,
                 "dir":item.direccion,"i":inc_id,"cu":item.client_updated_at})
            out.append({"external_id":str(item.external_id),"incidente_id":str(inc_id),"status":"UPDATED"})
            continue

        # create fresh
        inc_id = db.execute(text("""INSERT INTO emergencias.incidente
            (tenant_id,conductor_id,vehiculo_id,estado,external_id,
             estado_sincronizacion,dispositivo_origen,descripcion,latitud,longitud,direccion,reportado_at)
            VALUES (:t,:c,:v,'PENDIENTE',:e,'SINCRONIZADO',:dev,:d,:la,:lo,:dir,:rep)
            RETURNING id"""),
            {"t":user.tenant,"c":user.id,"v":str(item.vehiculo_id),"e":str(item.external_id),
             "dev":body.dispositivo,"d":item.descripcion,"la":item.latitud,"lo":item.longitud,
             "dir":item.direccion,"rep":item.client_created_at}).scalar()
        db.execute(text("""INSERT INTO emergencias.sync_mapping
            (tenant_id,external_id,incidente_id,dispositivo,last_write_at)
            VALUES (:t,:e,:i,:dev,:cu)"""),
            {"t":user.tenant,"e":str(item.external_id),"i":inc_id,
             "dev":body.dispositivo,"cu":item.client_updated_at})
        # store evidences, then queue AI
        bg.add_task(run_ai_pipeline, str(inc_id), user.tenant)
        out.append({"external_id":str(item.external_id),"incidente_id":str(inc_id),"status":"CREATED"})
    return {"results": out}
```

Key guarantees:
- **No duplicates**: `sync_mapping (tenant_id, external_id)` UNIQUE + the lookup. Re-sending the same batch returns `DUPLICATE/UPDATED`, never a second row.
- **Conflict resolution**: `UPDATE ... WHERE updated_at < client_updated_at` = last-write-wins.
- Idempotent: safe to retry with exponential backoff from the client.

### C.3 Acceptance
- POST the same batch twice → second response has `status=DUPLICATE`/`UPDATED`, `SELECT count(*)` unchanged.
- An offline incident appears server-side with `estado='PENDIENTE'` and a `sync_mapping` row.
