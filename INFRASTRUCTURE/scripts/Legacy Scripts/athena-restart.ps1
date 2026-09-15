#!/usr/bin/env pwsh
# athena-restart.ps1 - restart all minimal-stack services (dependency order).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ComposeDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "INFRASTRUCTURE\compose"
$Services   = @("edge\tailscale", "edge\caddy", "ai\opennotebook", "databases\surrealdb")

Write-Host ""
Write-Host "  Athena - restarting (dependency order)" -ForegroundColor Cyan
foreach ($svc in $Services) {
    Write-Host "  restarting $svc ..." -NoNewline
    Push-Location (Join-Path $ComposeDir $svc)
    docker compose down | Out-Null
    docker compose up -d | Out-Null
    Pop-Location
    Write-Host " OK"
}
Write-Host ""
Write-Host "  Stack restarted." -ForegroundColor Green
Write-Host ""
