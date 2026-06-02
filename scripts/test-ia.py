"""Prueba E2E: login → incidente → foto → pipeline IA (YOLO)."""
from __future__ import annotations

import argparse
import json
import mimetypes
import sys
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"

BASE_DEFAULT = "http://localhost:8000"
TENANT = "22222222-0000-0000-0000-000000000001"
VEHICULO = "55555555-0000-0000-0000-000000000001"
EMAIL = "carlos@mail.com"
PASSWORD = "password123"

TIPO_NAMES = {
    "33333333-0000-0000-0000-000000000001": "BATERIA",
    "33333333-0000-0000-0000-000000000002": "LLANTA",
    "33333333-0000-0000-0000-000000000003": "MOTOR",
    "33333333-0000-0000-0000-000000000004": "CHOQUE",
    "33333333-0000-0000-0000-000000000005": "OTROS",
}

SAMPLE_DIRS = {
    "dashboard": BACKEND / "ml" / "datasets" / "dashboard_yolo" / "images" / "val",
    "cardd": BACKEND / "ml" / "datasets" / "cardd_yolo" / "images" / "val",
}


def json_request(method: str, base: str, path: str, body=None, token: str | None = None):
    url = base.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=30) as resp:
            raw = resp.read().decode() or "{}"
            return resp.status, json.loads(raw) if raw.strip() else {}
    except HTTPError as e:
        raw = e.read().decode()
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {"detail": raw}
        raise RuntimeError(f"{method} {path} -> {e.code}: {parsed}") from e


def upload_image(base: str, incidente_id: str, image_path: Path, token: str):
    boundary = uuid.uuid4().hex
    file_bytes = image_path.read_bytes()
    mime = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"
    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="tipo"\r\n\r\nIMAGEN\r\n',
            f"--{boundary}\r\n".encode(),
            (
                f'Content-Disposition: form-data; name="file"; filename="{image_path.name}"\r\n'
                f"Content-Type: {mime}\r\n\r\n"
            ).encode(),
            file_bytes,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    url = base.rstrip("/") + f"/incidentes/{incidente_id}/evidencias"
    req = Request(
        url,
        data=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )
    try:
        with urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except HTTPError as e:
        raw = e.read().decode()
        raise RuntimeError(f"POST evidencia -> {e.code}: {raw}") from e


def pick_sample(source: str) -> Path:
    folder = SAMPLE_DIRS[source]
    if not folder.is_dir():
        raise FileNotFoundError(f"No existe carpeta de muestras: {folder}")
    for ext in ("*.jpg", "*.jpeg", "*.png"):
        files = sorted(folder.glob(ext))
        if files:
            return files[0]
    raise FileNotFoundError(f"Sin imágenes en {folder}")


def wait_for_ai(base: str, incidente_id: str, token: str, timeout: int = 60):
    deadline = time.time() + timeout
    last = {}
    last_evs: list = []
    while time.time() < deadline:
        _, detail = json_request("GET", base, f"/incidentes/{incidente_id}", token=token)
        inc = detail.get("incidente", detail)
        last = inc
        last_evs = detail.get("evidencias", [])
        tipo_id = inc.get("tipo_incidente_id")
        tipo = TIPO_NAMES.get(str(tipo_id), "OTROS")
        if inc.get("resumen_ia") and tipo_id and tipo != "OTROS":
            return inc, last_evs
        time.sleep(1)
    return last, last_evs


def main() -> int:
    parser = argparse.ArgumentParser(description="Prueba pipeline IA con foto real")
    parser.add_argument("--base-url", default=BASE_DEFAULT)
    parser.add_argument(
        "--source",
        choices=("dashboard", "cardd"),
        default="dashboard",
        help="Dataset de la foto de prueba",
    )
    parser.add_argument("--image", type=Path, default=None, help="Imagen concreta (opcional)")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    image = args.image or pick_sample(args.source)
    if not image.is_file():
        print(f"ERROR: imagen no encontrada: {image}", file=sys.stderr)
        return 1

    base = args.base_url
    print(f"API: {base}")
    print(f"Imagen: {image.name} ({args.source})")

    _, health = json_request("GET", base, "/health")
    print(f"Health: {health.get('status', health)}")

    _, login = json_request(
        "POST",
        base,
        "/auth/login",
        {"email": EMAIL, "password": PASSWORD, "tenant_id": TENANT},
    )
    token = login["access_token"]
    print(f"Login OK: {EMAIL}")

    _, created = json_request(
        "POST",
        base,
        "/incidentes",
        {
            "vehiculo_id": VEHICULO,
            "descripcion": "Problema con el vehículo, envío foto para diagnóstico",
            "latitud": -17.7833,
            "longitud": -63.1821,
            "direccion": "Av. Cañoto, Santa Cruz (prueba IA)",
        },
        token=token,
    )
    inc_id = created["id"]
    print(f"Incidente creado: {inc_id}")

    ev = upload_image(base, inc_id, image, token)
    print(f"Evidencia subida: {ev.get('url', ev)}")

    print("Esperando pipeline IA...")
    inc, evs = wait_for_ai(base, inc_id, token, timeout=args.timeout)

    tipo_id = inc.get("tipo_incidente_id")
    tipo = TIPO_NAMES.get(str(tipo_id), tipo_id or "?")
    print()
    print("=== Resultado IA ===")
    print(f"  Estado:     {inc.get('estado')}")
    print(f"  Tipo:       {tipo}")
    print(f"  Prioridad:  {inc.get('prioridad')}")
    print(f"  Resumen:    {inc.get('resumen_ia')}")
    print(f"  Evidencias: {len(evs)}")

    if not inc.get("resumen_ia") or not tipo_id:
        print("\nFAIL: la IA no completó a tiempo. ¿Backend reconstruido con ultralytics y modelos montados?")
        return 1

    if tipo == "OTROS":
        print("\nFAIL: clasificó OTROS. La foto no llegó a YOLO a tiempo o no hubo detección.")
        print("  Reintenta: .\\scripts\\test-ia.ps1")
        return 1

    print("\nOK: pipeline IA completado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
