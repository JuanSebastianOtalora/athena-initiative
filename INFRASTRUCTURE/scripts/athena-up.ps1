#!/usr/bin/env pwsh
# athena-up.ps1 - bring up the Athena stack (Windows / PowerShell).
#
#   up = START only: it never recreates running containers.
#   (athena-recreate.ps1 does the force-recreate pass.)
#
#   Services are discovered from compose/<section>/<name> dirs that contain
#   a compose file; their start order comes from athena-startup-order.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "athena-startup-order.ps1")

$Services = @(Get-AthenaServices)
if ($Services.Count -eq 0) {
    Write-Host "  [FAIL] No services found under: $AthenaCompose" -ForegroundColor Red
    Write-Host "  Expected compose/<section>/<name>/compose.yaml (see athena-startup-order.ps1)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Athena - bring up the stack" -ForegroundColor Cyan
Write-Host ""

# --- [1] Docker & Compose ---
Write-Host "  [1] Docker & Compose" -ForegroundColor Yellow
if (-not (Test-AthenaDocker)) {
    Write-Host "    [FAIL] Docker / Compose not available" -ForegroundColor Red
    Write-Host "    Start Docker Desktop and try again." -ForegroundColor Red
    exit 1
}
Write-Host "    [OK] Docker engine running" -ForegroundColor Green
Write-Host "    [OK] Docker Compose available" -ForegroundColor Green

# --- [2]..[5] Shared provisioning (idempotent) ---
$env:ATHENA_DATA_DIR   = $AthenaData
$env:ATHENA_ASSETS_DIR = $AthenaAssets
Write-Host ""
Ensure-AthenaProvision -Services $Services

# --- [6] Starting services ---
Write-Host ""
Write-Host "  [6] Starting services" -ForegroundColor Yellow
foreach ($svc in $Services) {
    $svcDir = Join-Path $AthenaCompose $svc
    $code   = Invoke-AthenaCompose -ServiceDir $svcDir -ComposeArgs @("compose", "up", "-d")
    if ($code -ne 0) {
        Write-Host "    [FAIL] $svc  failed to start (exit $code)" -ForegroundColor Red
        Write-Host "    Check: docker compose logs (in $AthenaCompose\$svc)" -ForegroundColor Red
        exit 1
    }
    Write-Host "    [OK] $svc  started" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Stack is up." -ForegroundColor Green
Write-Host "    Open Notebook   http://localhost:8502"
Write-Host "    SurrealDB       http://localhost:8000"
Write-Host "    Gateway         http://localhost"
Write-Host "    Status          .\athena-status.ps1"
Write-Host ""
