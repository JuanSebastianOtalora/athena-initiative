#!/usr/bin/env pwsh
# athena-create.ps1 - provision a fresh Athena workspace.
#
#   create = PROVISION ONLY: DATA/ layout, per-service .env files, shared
#   SurrealDB password, and the 'athena' docker network.
#   It does NOT pull images and does NOT start any container.
#
#   Idempotent: safe to re-run. Existing .env files are preserved (a real
#   password is reused, never clobbered).
#
#   After this, bring the stack up with:   .\athena-up.ps1

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
Write-Host "  Athena - create the workspace" -ForegroundColor Cyan
Write-Host ""

# --- [1] Docker & Compose (must be usable to create the network) ---
Write-Host "  [1] Docker & Compose" -ForegroundColor Yellow
if (Test-AthenaDocker) {
    Write-Host "    [OK] Docker engine running" -ForegroundColor Green
    Write-Host "    [OK] Docker Compose available" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Docker / Compose not available" -ForegroundColor Red
    Write-Host "    Start Docker Desktop and re-run .\athena-create.ps1" -ForegroundColor Red
    exit 1
}

# --- [2]..[5] Shared provisioning (DATA, .env, password, network) ---
$env:ATHENA_DATA_DIR   = $AthenaData
$env:ATHENA_ASSETS_DIR = $AthenaAssets
Write-Host ""
Ensure-AthenaProvision -Services $Services

Write-Host ""
Write-Host "  Workspace is ready (no containers started yet)." -ForegroundColor Green
Write-Host "    Next:  .\athena-up.ps1        (pull-free start of the stack)" -ForegroundColor DarkGray
Write-Host "    Or:    .\athena-recreate.ps1  (recreate containers now)" -ForegroundColor DarkGray
Write-Host ""
