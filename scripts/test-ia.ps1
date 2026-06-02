# Prueba E2E del pipeline IA (login + incidente + foto YOLO).
# Uso:
#   .\scripts\test-ia.ps1
#   .\scripts\test-ia.ps1 -Source cardd
#   .\scripts\test-ia.ps1 -RebuildBackend

param(
    [ValidateSet("dashboard", "cardd")]
    [string]$Source = "dashboard",
    [string]$BaseUrl = "http://localhost:8000",
    [switch]$RebuildBackend
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Push-Location $Root
try {
    if ($RebuildBackend) {
        Write-Host "Reconstruyendo backend (ultralytics + modelos)..." -ForegroundColor Cyan
        docker compose up -d --build backend
        Write-Host "Esperando health del backend..." -ForegroundColor Cyan
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 3
            try {
                $h = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 5
                if ($h.status -eq "ok") { break }
            } catch { }
        } while ((Get-Date) -lt $deadline)
    }

    $modelsDir = Join-Path $Root "backend\ml\models"
    if (-not (Test-Path (Join-Path $modelsDir "dashboard_best.pt"))) {
        Write-Warning "Falta backend\ml\models\dashboard_best.pt"
    }
    if (-not (Test-Path (Join-Path $modelsDir "cardd_best.pt"))) {
        Write-Warning "Falta backend\ml\models\cardd_best.pt"
    }

    $pyArgs = @(
        (Join-Path $Root "scripts\test-ia.py"),
        "--base-url", $BaseUrl,
        "--source", $Source
    )

    $python = $null
    if (Test-Path (Join-Path $Root "backend\.venv\Scripts\python.exe")) {
        $python = Join-Path $Root "backend\.venv\Scripts\python.exe"
    } else {
        $python = "python"
    }

    & $python @pyArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host ""
    Write-Host "Tip: prueba daños con  .\scripts\test-ia.ps1 -Source cardd" -ForegroundColor DarkGray
    Write-Host "Tip: si falla en Docker, reconstruye:  .\scripts\test-ia.ps1 -RebuildBackend" -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
