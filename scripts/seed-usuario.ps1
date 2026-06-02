# Crea o actualiza el conductor demo.movil@mail.com (password123 + vehículo DEMO01).
# Uso: .\scripts\seed-usuario.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Sql = Join-Path $Root "database\seeds\usuario_conductor_movil.sql"

if (-not (Test-Path $Sql)) {
    throw "No se encontró: $Sql"
}

Push-Location $Root
try {
    Get-Content $Sql -Raw | docker compose exec -T db psql -U postgres -d emergencias_db -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "psql falló con código $LASTEXITCODE" }
    Write-Host ""
    Write-Host "Usuario sembrado correctamente:" -ForegroundColor Green
    Write-Host "  Email:    demo.movil@mail.com"
    Write-Host "  Password: password123"
    Write-Host "  Tenant:   22222222-0000-0000-0000-000000000001  (Auxilio Norte)"
    Write-Host "  Vehículo: DEMO01 (Hyundai Tucson 2022)"
}
finally {
    Pop-Location
}
