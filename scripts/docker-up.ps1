# Levanta todo el stack (Floci + DB + Redis + API + Web)
Set-Location $PSScriptRoot\..

Write-Host "Building and starting services..." -ForegroundColor Cyan
docker compose up -d --build

Write-Host ""
Write-Host "Waiting for backend health..." -ForegroundColor Yellow
$max = 60
for ($i = 0; $i -lt $max; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:8000/health" -UseBasicParsing -TimeoutSec 2
        if ($r.StatusCode -eq 200) { break }
    } catch { Start-Sleep -Seconds 2 }
}

Write-Host ""
Write-Host "Stack listo:" -ForegroundColor Green
Write-Host "  Web:     http://localhost:4200"
Write-Host "  API:     http://localhost:8000/docs"
Write-Host "  Floci:   http://localhost:4566"
Write-Host "  Postgres: localhost:5432"
Write-Host ""
Write-Host "Login taller: centro@auxilionorte.com / password123"
docker compose ps
