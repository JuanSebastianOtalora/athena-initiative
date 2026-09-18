#!/usr/bin/env pwsh
# athena-down.ps1 - tear down the Athena stack. DATA is preserved.
# Stop order = startup order reversed (apps first, network last),
# so dependencies stay alive until dependents are gone.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "athena-startup-order.ps1")
$Services = Get-AthenaServicesReversed

Write-Host ""
Write-Host "  Athena - stop the stack" -ForegroundColor Cyan
Write-Host ""

Write-Host "  [1] Preflight" -ForegroundColor Yellow
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "    [FAIL] Docker not installed" -ForegroundColor Red
    Write-Host "    Please install Docker Desktop and try again." -ForegroundColor Red
    exit 1
}
Write-Host "    [OK] Docker installed" -ForegroundColor Green

docker version --format '{{.Server.Version}}' | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] Docker Engine running" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Docker Engine not running" -ForegroundColor Red
    Write-Host "    Please start Docker Desktop and try again." -ForegroundColor Red
    exit 1
}

docker compose version | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] Docker Compose available" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Docker Compose not available" -ForegroundColor Red
    Write-Host "    Please install the Docker Compose plugin and try again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  [2] Stopping services" -ForegroundColor Yellow
if ($Services.Count -eq 0) {
    Write-Host "    [SKIP] No services found under: $AthenaCompose" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Stack stopped. DATA/ is preserved." -ForegroundColor Green
    exit 0
}
$allOk = $true
foreach ($svc in $Services) {
    Push-Location (Join-Path $AthenaCompose $svc)
    # Compose progress goes to stderr; drop both streams, keep the exit code.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $null = docker compose down 2>$null | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    Pop-Location
    if ($code -eq 0) {
        Write-Host "    [OK] $svc  stopped" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] $svc  could not be stopped (exit $code)" -ForegroundColor Red
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "  Stack stopped. DATA/ is preserved." -ForegroundColor Green
} else {
    Write-Host "  Some services failed to stop. Check output above." -ForegroundColor Yellow
    exit 1
}
Write-Host ""
