#!/usr/bin/env pwsh
# athena-restart.ps1 - restart all stack services (dependency order).
# Restart output (per-container start/stop) is printed so you can follow the
# procedure; a final `docker compose ps` shows the resulting state.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "athena-startup-order.ps1")
$Services = Get-AthenaServices

Write-Host ""
Write-Host "  Athena - restart the stack" -ForegroundColor Cyan
Write-Host ""

# --- Preflight ---
Write-Host "  [1] Preflight" -ForegroundColor Yellow

$dockerInstalled = $false
try {
    $null = Get-Command docker -ErrorAction SilentlyContinue
    $dockerInstalled = $true
} catch { $dockerInstalled = $false }
if (-not $dockerInstalled) {
    Write-Host "    [FAIL] Docker not installed" -ForegroundColor Red
    Write-Host "    Please install Docker Desktop (https://www.docker.com/products/docker-desktop) and try again." -ForegroundColor Red
    exit 1
}
Write-Host "    [OK] Docker installed" -ForegroundColor Green

$daemonOk = $false
try {
    docker info 2>&1 | Out-Null
    $daemonOk = ($LASTEXITCODE -eq 0)
} catch { $daemonOk = $false }
if (-not $daemonOk) {
    Write-Host "    [FAIL] Docker Engine not running" -ForegroundColor Red
    Write-Host "    Please start Docker Desktop and try again." -ForegroundColor Red
    exit 1
}
Write-Host "    [OK] Docker Engine running" -ForegroundColor Green

$composeOk = $false
try {
    docker compose version 2>&1 | Out-Null
    $composeOk = ($LASTEXITCODE -eq 0)
} catch { $composeOk = $false }
if (-not $composeOk) {
    Write-Host "    [FAIL] Docker Compose not available" -ForegroundColor Red
    Write-Host "    Please install the Docker Compose plugin and try again." -ForegroundColor Red
    exit 1
}
Write-Host "    [OK] Docker Compose available" -ForegroundColor Green

if ($Services.Count -eq 0) {
    Write-Host ""
    Write-Host "  [FAIL] No services found under: $AthenaCompose" -ForegroundColor Red
    exit 1
}

# --- Restart (output shown) ---
Write-Host ""
Write-Host "  [2] Restarting services" -ForegroundColor Yellow
foreach ($svc in $Services) {
    $dir = Join-Path $AthenaCompose $svc
    Push-Location $dir
    Write-Host "    $svc" -ForegroundColor Cyan
    docker compose restart          # <-- output intentionally shown
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Host "    [FAIL] Restart failed for '$svc'. See output above." -ForegroundColor Red
        exit 1
    }
    Pop-Location
    Write-Host "    [OK] Restarted" -ForegroundColor Green
}

# --- Final state ---
Write-Host ""
Write-Host "  [3] Resulting state" -ForegroundColor Yellow
foreach ($svc in $Services) {
    $dir = Join-Path $AthenaCompose $svc
    Push-Location $dir
    docker compose ps
    Pop-Location
}

Write-Host ""
Write-Host "  Stack restarted." -ForegroundColor Green
Write-Host ""
