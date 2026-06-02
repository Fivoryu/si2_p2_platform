"""Ejecuta pruebas Ciclo 1 contra http://localhost:8000 (equivalente a la colección Postman)."""
import json
import sys
import uuid
import urllib.error
import urllib.request
from datetime import datetime

BASE = "http://localhost:8000"
TENANT = "22222222-0000-0000-0000-000000000001"
PUBLIC = "22222222-0000-0000-0000-000000000000"
TALLER_ID = "66666666-0000-0000-0000-000000000001"
PWD = "password123"
results: list[dict] = []


def req(method, path, body=None, token=None, expect=(200, 201, 204, 202)):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=15) as resp:
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


def main() -> int:
    # 00 Health
    req("GET", "/health", expect=(200,))
    results[-1]["cu"] = "00 Health"

    conductor_token = taller_token = adt_token = None

    # CU-01
    for label, email in [
        ("CU-01 conductor", "carlos@mail.com"),
        ("CU-01 taller", "centro@auxilionorte.com"),
        ("CU-01 admin tenant", "ana@auxilionorte.com"),
    ]:
        _, data = req(
            "POST",
            "/auth/login",
            {"email": email, "password": PWD, "tenant_id": TENANT},
        )
        results[-1]["cu"] = label
        if "conductor" in label:
            conductor_token = data.get("access_token")
        elif "taller" in label:
            taller_token = data.get("access_token")
        else:
            adt_token = data.get("access_token")

    req("POST", "/auth/login", {"email": "admin@plataforma.com", "password": PWD})
    results[-1]["cu"] = "CU-01 admin plataforma"

    # CU-04
    email_new = f"ciclo1_{uuid.uuid4().hex[:8]}@mail.com"
    req(
        "POST",
        "/auth/register",
        {
            "nombre": "Test Ciclo1",
            "email": email_new,
            "telefono": "70001111",
            "password": PWD,
        },
        expect=(201,),
    )
    results[-1]["cu"] = "CU-04 register"
    req(
        "POST",
        "/auth/login",
        {"email": email_new, "password": PWD, "tenant_id": PUBLIC},
    )
    results[-1]["cu"] = "CU-04 login"

    # CU-05
    placa = "C1" + uuid.uuid4().hex[:5].upper()
    req(
        "POST",
        "/vehiculos",
        {"placa": placa, "marca": "Toyota", "modelo": "Yaris", "anio": 2020},
        token=conductor_token,
        expect=(201,),
    )
    results[-1]["cu"] = "CU-05 POST vehiculo"
    _, lst = req("GET", "/vehiculos", token=conductor_token)
    results[-1]["cu"] = "CU-05 GET vehiculos"
    veh_ok = any(v.get("placa") == placa for v in lst.get("items", []))
    results[-1]["ok"] = results[-1]["ok"] and veh_ok

    # CU-06
    req("PATCH", "/usuarios/me", {"telefono": "78887777"}, token=conductor_token)
    results[-1]["cu"] = "CU-06 PATCH me"
    _, prof = req("GET", "/usuarios/me", token=conductor_token)
    results[-1]["cu"] = "CU-06 GET me"
    results[-1]["ok"] = results[-1]["ok"] and prof.get("telefono") == "78887777"

    # CU-03
    req("POST", "/auth/forgot-password", {"email": email_new}, expect=(202,))
    results[-1]["cu"] = "CU-03 forgot-password"

    # CU-07
    _, taller = req(
        "POST",
        "/talleres",
        {
            "nombre": "Taller Ciclo1",
            "email": f"t{uuid.uuid4().hex[:6]}@auxilionorte.com",
            "direccion": "Test",
            "latitud": -17.78,
            "longitud": -63.18,
            "capacidad_max": 4,
        },
        token=adt_token,
        expect=(201,),
    )
    results[-1]["cu"] = "CU-07 POST taller"
    taller_new = taller.get("id")

    # CU-08
    tel_tec = "7" + uuid.uuid4().hex[:7]
    req(
        "POST",
        "/tecnicos",
        {
            "taller_id": taller_new,
            "nombre": "Tec Ciclo1",
            "telefono": tel_tec,
            "especialidad": "General",
        },
        token=adt_token,
        expect=(201,),
    )
    results[-1]["cu"] = "CU-08 POST tecnico"

    # CU-09
    req(
        "PATCH",
        f"/talleres/{TALLER_ID}/disponibilidad",
        {"disponible": False, "capacidad_max": 4},
        token=taller_token,
    )
    results[-1]["cu"] = "CU-09 OFF"
    req(
        "PATCH",
        f"/talleres/{TALLER_ID}/disponibilidad",
        {"disponible": True, "capacidad_max": 5},
        token=taller_token,
    )
    results[-1]["cu"] = "CU-09 ON"

    # CU-02
    req("POST", "/auth/logout", {}, token=conductor_token, expect=(204,))
    results[-1]["cu"] = "CU-02 logout"

    passed = sum(1 for r in results if r["ok"])
    failed = [r for r in results if not r["ok"]]
    print("=== SI2 Ciclo 1 -", datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "===")
    print(f"PASSED: {passed}/{len(results)}")
    if failed:
        print("FAILED:")
        for f in failed:
            print(" ", json.dumps(f, default=str))
    print()
    for r in results:
        icon = "PASS" if r["ok"] else "FAIL"
        print(f"  [{icon}] {r['cu']:32} HTTP {r['status']:3}  {r['step']}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
