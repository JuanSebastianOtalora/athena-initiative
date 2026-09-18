#!/usr/bin/env pwsh
# athena-recreate.ps1 - force-recreate the Athena containers (Windows / PowerShell).
#
#   recreate = fresh containers from the CURRENT compose.yaml + .env, keeping
#   the DATA/ volumes. Use it after changing a compose file or an .env value,
#   or after `athena-create.ps1` / a fresh clone.
#
#   Before recreating, it asks whether to pull the latest images:
#       N  = pull new images first, then recreate
#       E  = recreate using the images already on this machine (default)
#
#   DATA/ is never touched.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "athena-startup-order.ps1")

$Services = @(Get-AthenaServices)
if ($Services.Count -eq 0) {
    Write-Host "  [FAIL] No services found under: $AthenaCompose" -ForegroundColor Red
    Write-Host "  Expected compose/<section>/<name>/compose.yaml (see athena-startup-order.ps1)." -ForegroundColor Red
    exit 1
}

function Read-RecreateChoice {
    Write-Host "  Recreate with:" -ForegroundColor Yellow
    Write-Host "    N  pull NEW images first, then recreate"
    Write-Host "    E  use EXISTING images (default)"
    $line = Read-Host "    Choice [E]"
    $choice = $line.Trim().ToUpper()
    if ($choice -in @("", "E", "EX", "EXISTING"))  { return "existing" }
    if ($choice -in @("N", "NEW"))                  { return "new" }
    return "existing"
}

Write-Host ""
Write-Host "  Athena - recreate the stack" -ForegroundColor Cyan
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

# --- [6] Pull (optional) ---
$mode = Read-RecreateChoice
Write-Host ""
if ($mode -eq "new") {
    Write-Host "  [6] Pulling images" -ForegroundColor Yellow
    foreach ($svc in $Services) {
        $svcDir = Join-Path $AthenaCompose $svc
        $code   = Invoke-AthenaCompose -ServiceDir $svcDir -ComposeArgs @("compose", "pull")
        if ($code -eq 0) {
            Write-Host "    [OK] $svc  images pulled" -ForegroundColor Green
        } else {
            Write-Host "    [WARN] $svc  pull failed (exit $code); recreating with existing images" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  [6] Pull" -ForegroundColor Yellow
    Write-Host "    [SKIP] Using existing images (chose E)" -ForegroundColor DarkGray
}

# --- [7] Recreate services ---
Write-Host ""
Write-Host "  [7] Recreating services" -ForegroundColor Yellow
foreach ($svc in $Services) {
    $svcDir = Join-Path $AthenaCompose $svc
    $code   = Invoke-AthenaCompose -ServiceDir $svcDir -ComposeArgs @("compose", "up", "-d", "--force-recreate")
    if ($code -ne 0) {
        Write-Host "    [FAIL] $svc  failed to recreate (exit $code)" -ForegroundColor Red
        Write-Host "    Check: docker compose logs (in $AthenaCompose\$svc)" -ForegroundColor Red
        exit 1
    }
    Write-Host "    [OK] $svc  recreated" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Stack recreated. DATA/ preserved." -ForegroundColor Green
Write-Host "    Status          .\athena-status.ps1"
Write-Host ""
