#!/usr/bin/env pwsh
# athena-status.ps1 - show the state of the minimal stack.
# Per-service container status (docker compose ps) plus a port check.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$InfrastructureDir = Split-Path -Parent (Resolve-Path $PSScriptRoot)
$ComposeDir = Join-Path $InfrastructureDir "compose"

# Full compose/<category>/<service> paths (services are nested).
$Services = @("databases\surrealdb", "ai\opennotebook", "edge\caddy", "edge\tailscale")

Write-Host ""
Write-Host "  Athena - status" -ForegroundColor Cyan

# --- Preflight (soft) ---
# status is a query: a down Docker is a valid "not running" answer, so exit 0.
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
$engineUp = $false
if ($dockerCmd) {
    $null = docker version --format '{{.Server.Version}}' 2>$null
    $engineUp = ($LASTEXITCODE -eq 0)
}

if (-not $dockerCmd) {
    Write-Host "    Docker not installed - cannot show stack status." -ForegroundColor DarkGray
    Write-Host "    Athena: not running."
    exit 0
}
if (-not $engineUp) {
    Write-Host "    Docker Engine not running." -ForegroundColor DarkGray
    Write-Host "    Athena: not running."
    exit 0
}

# --- Per-service status ---
foreach ($svc in $Services) {
    $svcDir = Join-Path $ComposeDir $svc
    if (-not (Test-Path (Join-Path $svcDir "compose.yaml"))) {
        Write-Host ""
        Write-Host "  [$svc]" -ForegroundColor Cyan
        Write-Host "    [SKIP] compose.yaml not found" -ForegroundColor DarkGray
        continue
    }
    Push-Location $svcDir
    docker compose ps
    Pop-Location
    Write-Host ""
}

# --- Port check ---
Write-Host "  Port check" -ForegroundColor Yellow
$ports = @(80, 443, 8000, 8502)
foreach ($p in $ports) {
    $t = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
    if ($t.TcpTestSucceeded) {
        Write-Host "    :$p  open" -ForegroundColor Green
    } else {
        Write-Host "    :$p  closed" -ForegroundColor DarkGray
    }
}
Write-Host ""
