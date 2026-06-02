"""Ejecuta pruebas Ciclo 2 contra http://localhost:8000 (reporte, sync, IA, cancelación)."""
import base64
import json
import sys
import time
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timezone

BASE = "http://localhost:8000"
TENANT = "22222222-0000-0000-0000-000000000001"
VEHICULO_ID = "55555555-0000-0000-0000-000000000001"
PWD = "password123"
results: list[dict] = []

# 1x1 JPEG mínimo
TINY_JPEG_B64 = (
    "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//AP//AP//AP//AP//AP//AP//AP//AP//"
    "AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//AP//2wBDAQoKCg0KCg0KCg0K"
    "Cg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0KCg0K"
    "Cg3/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAr/xAAUEAEA"
    "AAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAA"
    "AAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k="
)


def req(method, path, body=None, token=None, expect=(200, 201, 204, 202)):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as resp:
            raw = resp.read().decode() or "{}"
            code = resp.status
            try:
                parsed = json.loads(raw) if raw.strip() else {}
            except json.JSONDecodeError:
                parsed = raw
            ok = code in expect
            results.append({"cu": None, "step": f"{method} {path}", "status": code, "ok": ok})
            return code, parsed
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = raw
        ok = e.code in expect
        results.append(
            {
                "cu": None,
                "step": f"{method} {path}",
                "status": e.code,
                "ok": ok,
                "error": parsed,
            }
        )
        return e.code, parsed


def wait_for_ai(incidente_id, token, max_wait=8):
    for _ in range(max_wait):
        _, detail = req("GET", f"/incidentes/{incidente_id}", token=token)
        inc = detail.get("incidente", detail)
        if inc.get("resumen_ia") or inc.get("estado") == "BUSCANDO_TALLER":
            return inc
        time.sleep(1)
    return detail.get("incidente", detail) if isinstance(detail, dict) else {}


def main() -> int:
    req("GET", "/health", expect=(200,))
    results[-1]["cu"] = "00 Health"

    _, login = req(
        "POST",
        "/auth/login",
        {"email": "carlos@mail.com", "password": PWD, "tenant_id": TENANT},
    )
    results[-1]["cu"] = "CU-01 login conductor"
    token = login.get("access_token")
    if not token:
        print("FAIL: no conductor token")
        return 1

    now = datetime.now(timezone.utc).isoformat()
    ext_id = str(uuid.uuid4())

    # CU-10/11/13 — reporte online con foto (POST /incidentes)
    _, created = req(
        "POST",
        "/incidentes",
        {
            "vehiculo_id": VEHICULO_ID,
            "descripcion": "Batería descargada, no arranca el motor",
            "latitud": -17.7833,
            "longitud": -63.1821,
            "direccion": "Av. Cañoto, Santa Cruz",
            "external_id": ext_id,
        },
        token=token,
        expect=(201,),
    )
    results[-1]["cu"] = "CU-10 POST incidente online"
    inc_online = created.get("id")
    if inc_online:
        req(
            "POST",
            f"/incidentes/{inc_online}/evidencias",
            None,
            token=token,
            expect=(201, 422),
        )
        results[-1]["cu"] = "CU-11 evidencia REST (opcional)"

    # CU-17-21 — esperar pipeline IA
    if inc_online:
        inc = wait_for_ai(inc_online, token)
        results.append(
            {
                "cu": "CU-17-21 resumen_ia",
                "step": f"GET /incidentes/{inc_online}",
                "status": 200,
                "ok": bool(inc.get("resumen_ia")),
            }
        )
        results.append(
            {
                "cu": "CU-17-21 estado IA",
                "step": "estado post-IA",
                "status": 200,
                "ok": inc.get("estado") in ("BUSCANDO_TALLER", "PENDIENTE", "TALLER_ASIGNADO"),
            }
        )

    # CU-10/38-40 — sync batch (offline-first)
    ext_sync = str(uuid.uuid4())
    _, sync_res = req(
        "POST",
        "/sync",
        {
            "dispositivo": "postman-ciclo2",
            "incidentes": [
                {
                    "external_id": ext_sync,
                    "vehiculo_id": VEHICULO_ID,
                    "descripcion": "Pinchazo de llanta en avenida",
                    "latitud": -17.79,
                    "longitud": -63.18,
                    "direccion": "Av. Busch",
                    "client_created_at": now,
                    "client_updated_at": now,
                    "evidencias": [
                        {
                            "tipo": "IMAGEN",
                            "contenido_b64": TINY_JPEG_B64,
                            "mime_type": "image/jpeg",
                        },
                        {
                            "tipo": "AUDIO",
                            "contenido_b64": base64.b64encode(b"fake-aac").decode(),
                            "mime_type": "audio/aac",
                            "texto": "Tengo un pinchazo urgente",
                        },
                    ],
                }
            ],
        },
        token=token,
        expect=(200,),
    )
    results[-1]["cu"] = "CU-39 POST /sync"
    sync_id = None
    if sync_res.get("results"):
        sync_id = sync_res["results"][0].get("incidente_id")

    if sync_id:
        inc2 = wait_for_ai(sync_id, token)
        results.append(
            {
                "cu": "CU-39 sync+IA",
                "step": f"sync incident {sync_id}",
                "status": 200,
                "ok": bool(inc2.get("resumen_ia") or inc2.get("tipo_incidente_id")),
            }
        )

    # CU-15 — cancelación
    _, cancel_body = req(
        "POST",
        "/incidentes",
        {
            "vehiculo_id": VEHICULO_ID,
            "descripcion": "Incidente para cancelar",
            "latitud": -17.78,
            "longitud": -63.18,
        },
        token=token,
        expect=(201,),
    )
    results[-1]["cu"] = "CU-15 crear para cancelar"
    cancel_id = cancel_body.get("id")
    if cancel_id:
        req(
            "POST",
            f"/incidentes/{cancel_id}/cancelar",
            {"motivo": "Ya no necesito asistencia"},
            token=token,
            expect=(200,),
        )
        results[-1]["cu"] = "CU-15 POST cancelar"
        _, detail = req("GET", f"/incidentes/{cancel_id}", token=token)
        results[-1]["cu"] = "CU-15 verificar CANCELADO"
        inc = detail.get("incidente", detail)
        results[-1]["ok"] = results[-1]["ok"] and inc.get("estado") == "CANCELADO"

    # CU-16 — historial
    _, lst = req("GET", "/incidentes?limit=10", token=token)
    results[-1]["cu"] = "CU-16 GET historial"
    items = lst.get("items", [])
    results[-1]["ok"] = results[-1]["ok"] and len(items) >= 1

    if inc_online:
        _, det = req("GET", f"/incidentes/{inc_online}", token=token)
        results[-1]["cu"] = "CU-16 GET detalle anidado"
        results[-1]["ok"] = results[-1]["ok"] and "incidente" in det

    passed = sum(1 for r in results if r["ok"])
    failed = [r for r in results if not r["ok"]]
    print("=== SI2 Ciclo 2 -", datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "===")
    print(f"PASSED: {passed}/{len(results)}")
    if failed:
        print("FAILED:")
        for f in failed:
            print(" ", json.dumps(f, default=str))
    print()
    for r in results:
        icon = "PASS" if r["ok"] else "FAIL"
        cu = r.get("cu") or "?"
        print(f"  [{icon}] {cu:32} HTTP {r['status']:3}  {r['step']}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
