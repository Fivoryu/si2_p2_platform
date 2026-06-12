#!/usr/bin/env bash
# Preparar mapa OSRM para Bolivia (equivalente Linux de prepare-osrm.ps1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$ROOT/osrm-data"
mkdir -p "$DATA_DIR"

PBF="$DATA_DIR/bolivia-latest.osm.pbf"
URL="https://download.geofabrik.de/south-america/bolivia-latest.osm.pbf"

if [ ! -f "$PBF" ]; then
  echo "Descargando mapa de Bolivia (~120 MB)..."
  curl -fL "$URL" -o "$PBF"
else
  echo "Usando PBF existente: $PBF"
fi

echo "Extrayendo grafo OSRM..."
if docker info >/dev/null 2>&1; then D=docker; else D="sudo docker"; fi
$D run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-extract -p /opt/car.lua /data/bolivia-latest.osm.pbf

echo "Particionando..."
$D run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-partition /data/bolivia-latest.osrm

echo "Customizando..."
$D run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-customize /data/bolivia-latest.osrm

for f in "$DATA_DIR"/bolivia-latest.osrm*; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  cp -f "$f" "$DATA_DIR/${base/bolivia-latest/map}"
done

echo ""
echo "Listo. Archivos map.osrm* en osrm-data/"
echo "Sin mapa local, el backend usa router.project-osrm.org como respaldo."
