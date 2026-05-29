# Configura repos separados + submódulos en la raíz.
# Requisitos: Git, remotos vacíos ya creados, URLs en repos.config.ps1
#
# Uso:
#   .\scripts\setup-multi-repo.ps1 -WhatIf          # solo muestra pasos
#   .\scripts\setup-multi-repo.ps1 -PushChildren    # init+push backend/web/mobile
#   .\scripts\setup-multi-repo.ps1 -AddSubmodules   # raíz + submodule add (tras PushChildren)

param(
    [switch]$WhatIf,
    [switch]$PushChildren,
    [switch]$AddSubmodules
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$configPath = Join-Path $PSScriptRoot "repos.config.ps1"

if (-not (Test-Path $configPath)) {
    Write-Error "Crea y edita scripts/repos.config.ps1 con tus URLs."
}
. $configPath

function Run-Git {
    param([string]$Dir, [string[]]$Args)
    $cmd = "git $($Args -join ' ')"
    Write-Host "  $cmd" -ForegroundColor DarkGray
    if (-not $WhatIf) {
        Push-Location $Dir
        try { & git @Args } finally { Pop-Location }
    }
}

function Init-ChildRepo {
    param([string]$Name, [string]$RemoteUrl)
    $dir = Join-Path $Root $Name
    if (-not (Test-Path $dir)) { Write-Error "No existe carpeta $Name" }

    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    if (Test-Path (Join-Path $dir ".git")) {
        Write-Host "  Ya es repo git, omitiendo init." -ForegroundColor Yellow
    } else {
        Run-Git $dir @("init")
        Run-Git $dir @("add", ".")
        Run-Git $dir @("commit", "-m", "Initial commit: $Name")
        Run-Git $dir @("branch", "-M", $Branch)
    }
    $remotes = if (-not $WhatIf) { git -C $dir remote 2>$null } else { @() }
    if ($remotes -notcontains "origin") {
        Run-Git $dir @("remote", "add", "origin", $RemoteUrl)
    }
    if ($PushChildren) {
        Run-Git $dir @("push", "-u", "origin", $Branch)
    }
}

function Add-PlatformSubmodules {
    Write-Host "`n=== Plataforma (raíz) ===" -ForegroundColor Cyan

    foreach ($name in @("backend", "web", "mobile")) {
        $bak = "${name}.bak"
        $path = Join-Path $Root $name
        $bakPath = Join-Path $Root $bak
        if ((Test-Path $path) -and -not (Test-Path (Join-Path $path ".git"))) {
            if (-not $WhatIf) {
                if (Test-Path $bakPath) { Remove-Item $bakPath -Recurse -Force }
                Rename-Item $path $bak
                Write-Host "  Renombrado $name -> $bak" -ForegroundColor Yellow
            } else {
                Write-Host "  [WhatIf] Renombraría $name -> $bak"
            }
        }
    }

    if (-not (Test-Path (Join-Path $Root ".git"))) {
        Run-Git $Root @("init")
        Run-Git $Root @("add", "docker-compose.yml", "database", "docs", "infra", "scripts", "README.md", ".gitignore", ".gitattributes", ".gitmodules.example", "docs/MULTI_REPO.md")
        Run-Git $Root @("commit", "-m", "Initial commit: platform")
        Run-Git $Root @("branch", "-M", $Branch)
        $remotes = if (-not $WhatIf) { git -C $Root remote 2>$null } else { @() }
        if ($remotes -notcontains "origin") {
            Run-Git $Root @("remote", "add", "origin", $Platform)
        }
    }

    $map = @{
        backend = $Backend
        web     = $Web
        mobile  = $Mobile
    }
    foreach ($pair in $map.GetEnumerator()) {
        $subPath = Join-Path $Root $pair.Key
        if (-not (Test-Path $subPath)) {
            Run-Git $Root @("submodule", "add", $pair.Value, $pair.Key)
        } else {
            Write-Host "  $($pair.Key) ya existe, omitiendo submodule add." -ForegroundColor Yellow
        }
    }

    Run-Git $Root @("add", ".gitmodules")
    Run-Git $Root @("commit", "-m", "Add submodules" )
    if ($PushChildren) {
        Run-Git $Root @("push", "-u", "origin", $Branch)
    }
}

Write-Host "Raíz: $Root" -ForegroundColor Green
Write-Host "Platform: $Platform"
Write-Host "Backend:  $Backend"
Write-Host "Web:      $Web"
Write-Host "Mobile:   $Mobile"

if (-not $PushChildren -and -not $AddSubmodules) {
    Write-Host @"

Modos:
  -PushChildren   Inicializa y hace push de backend, web, mobile
  -AddSubmodules  Prepara raíz y enlaza submódulos (ejecutar después de PushChildren)
  -WhatIf         Solo imprime comandos

Ejemplo completo:
  .\scripts\setup-multi-repo.ps1 -PushChildren
  .\scripts\setup-multi-repo.ps1 -AddSubmodules -PushChildren

"@ -ForegroundColor Yellow
    exit 0
}

if ($PushChildren) {
    Init-ChildRepo "backend" $Backend
    Init-ChildRepo "web" $Web
    Init-ChildRepo "mobile" $Mobile
}

if ($AddSubmodules) {
    Add-PlatformSubmodules
}

Write-Host "`nListo. Ver docs/MULTI_REPO.md" -ForegroundColor Green
