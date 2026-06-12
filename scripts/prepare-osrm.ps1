# Preparar mapa OSRM para Santa Cruz / Bolivia
#
# Requisitos: Docker en ejecución
# Uso (PowerShell, desde la raíz del repo):
#   .\scripts\prepare-osrm.ps1
#
# Tras completar, reinicia OSRM:
#   docker compose restart osrm backend

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$DataDir = Join-Path $Root "osrm-data"
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

$Pbf = Join-Path $DataDir "bolivia-latest.osm.pbf"
$Url = "https://download.geofabrik.de/south-america/bolivia-latest.osm.pbf"

if (-not (Test-Path $Pbf)) {
    Write-Host "Descargando mapa de Bolivia (~120 MB). Puede tardar varios minutos..."
    Invoke-WebRequest -Uri $Url -OutFile $Pbf
} else {
    Write-Host "Usando PBF existente: $Pbf"
}

Write-Host "Extrayendo grafo OSRM (extract)..."
docker run --rm -v "${DataDir}:/data" osrm/osrm-backend `
    osrm-extract -p /opt/car.lua /data/bolivia-latest.osm.pbf

Write-Host "Particionando..."
docker run --rm -v "${DataDir}:/data" osrm/osrm-backend `
    osrm-partition /data/bolivia-latest.osrm

Write-Host "Customizando..."
docker run --rm -v "${DataDir}:/data" osrm/osrm-backend `
    osrm-customize /data/bolivia-latest.osrm

Get-ChildItem $DataDir -Filter "bolivia-latest.osrm*" | ForEach-Object {
    $newName = $_.Name -replace 'bolivia-latest', 'map'
    Copy-Item $_.FullName (Join-Path $DataDir $newName) -Force
}

Write-Host ""
Write-Host "Listo. Archivos map.osrm* en osrm-data/"
Write-Host "Ejecuta: docker compose restart osrm backend"
Write-Host ""
Write-Host "Nota: sin mapa local, el backend usa OSRM público (router.project-osrm.org) como respaldo."
