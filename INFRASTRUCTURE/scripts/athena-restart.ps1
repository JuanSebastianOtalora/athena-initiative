#!/usr/bin/env pwsh
# athena-restart.ps1 - restart all minimal-stack services (dependency order).
# The restart output (per-container start/stop) is printed so you can follow
# the procedure; a final `docker compose ps` shows the resulting state.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InfrastructureDir = Split-Path -Parent (Resolve-Path "$PSScriptRoot")
$ComposeDir = Join-Path $InfrastructureDir "compose"
$DataDir = Join-Path (Split-Path -Parent $InfrastructureDir) "DATA"
$Services = @("databases\surrealdb", "ai\opennotebook", "edge\caddy", "edge\tailscale")

# --- Preflight -------------------------------------------------------------
Write-Host "  Athena Preflight"
Write-Host "  ----------------"

$dockerInstalled = $false
try {
    $null = Get-Command docker -ErrorAction SilentlyContinue
    $dockerInstalled = $true
} catch { $dockerInstalled = $false }
if (-not $dockerInstalled) {
    Write-Host "  Docker         [FAIL]  not installed"
    Write-Host ""
    Write-Host "  Please install Docker Desktop (https://www.docker.com/products/docker-desktop) and run Athena again."
    exit 1
}
Write-Host "  Docker         [OK]    installed"

$daemonOk = $false
try {
    docker info 2>&1 | Out-Null
    $daemonOk = ($LASTEXITCODE -eq 0)
} catch { $daemonOk = $false }
if (-not $daemonOk) {
    Write-Host "  Docker Engine  [FAIL]  not running"
    Write-Host ""
    Write-Host "  Please start Docker Desktop and run Athena again."
    exit 1
}
Write-Host "  Docker Engine  [OK]    running"

$composeOk = $false
try {
    docker compose version 2>&1 | Out-Null
    $composeOk = ($LASTEXITCODE -eq 0)
} catch { $composeOk = $false }
if (-not $composeOk) {
    Write-Host "  Docker Compose [FAIL]  not available"
    Write-Host ""
    Write-Host "  Please install the Docker Compose plugin and run Athena again."
    exit 1
}
Write-Host "  Docker Compose [OK]    available"

Write-Host ""
Write-Host "  Proceeding..."
Write-Host ""

# --- Restart (output shown) ------------------------------------------------
Write-Host "  Athena - restarting stack (dependency order)"
Write-Host "  --------------------------------------------"

foreach ($svc in $Services) {
    $dir = Join-Path $ComposeDir $svc
    if (Test-Path $dir) {
        Push-Location $dir
        Write-Host ""
        Write-Host "  Restarting: $svc"
        docker compose restart          # <-- output intentionally shown
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            Write-Host ""
            Write-Host "  [FAIL]  Restart failed for '$svc'. See output above."
            exit 1
        }
        Pop-Location
    }
}

# --- Final state -----------------------------------------------------------
Write-Host ""
Write-Host "  Resulting state"
Write-Host "  ---------------"
foreach ($svc in $Services) {
    $dir = Join-Path $ComposeDir $svc
    if (Test-Path $dir) {
        Push-Location $dir
        docker compose ps
        Pop-Location
    }
}

Write-Host ""
Write-Host "  [OK]  Stack restarted."
