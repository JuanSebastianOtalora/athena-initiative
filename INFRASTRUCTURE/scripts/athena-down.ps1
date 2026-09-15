#!/usr/bin/env pwsh
# athena-down.ps1 - tear down the minimal stack. DATA is preserved.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InfrastructureDir = Split-Path -Parent (Resolve-Path "$PSScriptRoot\..")
$ComposeDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "INFRASTRUCTURE\compose"

# ── Preflight ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Athena Preflight" -ForegroundColor Cyan
Write-Host "  ----------------" -ForegroundColor Cyan

# 1. Docker installed?
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "  Docker         [FAIL] not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please install Docker Desktop and try again." -ForegroundColor Red
    exit 1
}
Write-Host "  Docker         [OK]   installed"

# 2. Docker Engine running?
docker version --format '{{.Server.Version}}' | Out-Null
$engineOk = ($LASTEXITCODE -eq 0)
if ($engineOk) {
    Write-Host "  Docker Engine  [OK]   running"
} else {
    Write-Host "  Docker Engine  [FAIL] not running" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please start Docker Desktop and run Athena again." -ForegroundColor Red
    exit 1
}

# 3. Docker Compose available?
docker compose version | Out-Null
$composeOk = ($LASTEXITCODE -eq 0)
if ($composeOk) {
    Write-Host "  Docker Compose [OK]   available"
} else {
    Write-Host "  Docker Compose [FAIL] not available" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please install the Docker Compose plugin and run Athena again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Proceeding..." -ForegroundColor Green
Write-Host ""

# ── Tear down ─────────────────────────────────────────────────────────────
$Services = @("edge\tailscale", "edge\caddy", "ai\opennotebook", "databases\surrealdb")
Write-Host "  Athena - tearing down (DATA preserved)" -ForegroundColor Cyan
$allOk = $true
foreach ($svc in $Services) {
    Write-Host "  stopping $svc ..." -NoNewline
    Push-Location (Join-Path $ComposeDir $svc)
    docker compose down | Out-Null
    $svcOk = ($LASTEXITCODE -eq 0)
    Pop-Location
    if ($svcOk) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAILED" -ForegroundColor Red
        $allOk = $false
    }
}
Write-Host ""
if ($allOk) {
    Write-Host "  Stack stopped. DATA/ is unchanged." -ForegroundColor Green
} else {
    Write-Host "  Some services failed to stop. Check output above." -ForegroundColor Yellow
}
Write-Host ""
