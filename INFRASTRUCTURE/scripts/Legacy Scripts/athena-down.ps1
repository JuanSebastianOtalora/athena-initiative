#!/usr/bin/env pwsh
# athena-down.ps1 - tear down the minimal stack. DATA is preserved.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InfrastructureDir = Split-Path -Parent (Resolve-Path "$PSScriptRoot\..")
$ComposeDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "INFRASTRUCTURE\compose"

$Services = @("edge\tailscale", "edge\caddy", "ai\opennotebook", "databases\surrealdb")
Write-Host ""
Write-Host "  Athena - tearing down (DATA preserved)" -ForegroundColor Cyan
foreach ($svc in $Services) {
    Write-Host "  stopping $svc ..." -NoNewline
    Push-Location (Join-Path $ComposeDir $svc)
    $null = docker compose down | Out-Null
    Pop-Location
    Write-Host " OK"
}
Write-Host ""
Write-Host "  Stack stopped. DATA/ is unchanged." -ForegroundColor Green
Write-Host ""
