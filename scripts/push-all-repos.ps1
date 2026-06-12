# Commit y push ordenado: backend -> web -> mobile -> platform (submodules).
# Uso:
#   .\scripts\push-all-repos.ps1 -Message "feat: despliegue AWS"
#   .\scripts\push-all-repos.ps1 -Message "fix" -DryRun

param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$configPath = Join-Path $PSScriptRoot "repos.config.ps1"
. $configPath

function Invoke-RepoGit {
    param(
        [string]$Dir,
        [string[]]$GitArgs
    )
    $cmd = "git $($GitArgs -join ' ')"
    Write-Host "  [$([IO.Path]::GetFileName($Dir))] $cmd" -ForegroundColor Cyan
    if (-not $DryRun) {
        Push-Location $Dir
        try { & git @GitArgs } finally { Pop-Location }
    }
}

function Push-ChildRepo {
    param([string]$Name)
    $dir = Join-Path $Root $Name
    if (-not (Test-Path (Join-Path $dir ".git"))) {
        throw "No es repo git: $dir"
    }
    $remotes = git -C $dir remote
    if ($remotes -notcontains "origin") {
        throw "Sin remote origin en $Name. Configura con: git -C $Name remote add origin <url>"
    }
    $status = git -C $dir status --porcelain
    if ($status) {
        Invoke-RepoGit $dir @("add", "-A")
        Invoke-RepoGit $dir @("commit", "-m", $Message)
    } else {
        Write-Host "  [$Name] sin cambios" -ForegroundColor DarkGray
    }
    Invoke-RepoGit $dir @("push", "origin", $Branch)
}

Write-Host "Push multi-repo - rama $Branch" -ForegroundColor Green

foreach ($child in @("backend", "web", "mobile")) {
    Write-Host "`n=== $child ===" -ForegroundColor Yellow
    Push-ChildRepo $child
}

Write-Host "`n=== platform ===" -ForegroundColor Yellow
foreach ($child in @("backend", "web", "mobile")) {
    Invoke-RepoGit $Root @("add", $child)
}
$platformStatus = git -C $Root status --porcelain
if ($platformStatus) {
    Invoke-RepoGit $Root @("add", "-A")
    Invoke-RepoGit $Root @("commit", "-m", "$Message (platform + submodule pointers)")
} else {
    Write-Host "  [platform] sin cambios" -ForegroundColor DarkGray
}
Invoke-RepoGit $Root @("push", "origin", $Branch)

Write-Host "`nListo. 4 repos actualizados." -ForegroundColor Green
