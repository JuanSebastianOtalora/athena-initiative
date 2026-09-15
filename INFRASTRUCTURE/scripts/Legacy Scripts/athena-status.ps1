#!/usr/bin/env pwsh
# athena-status.ps1 - show the state of the minimal stack.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ComposeDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "INFRASTRUCTURE\compose"
$Services   = @("databases\surrealdb", "ai\opennotebook", "edge\caddy", "edge\tailscale")

Write-Host ""
Write-Host "  Athena - status" -ForegroundColor Cyan
foreach ($svc in $Services) {
    Push-Location (Join-Path $ComposeDir $svc)
    docker compose ps
    Pop-Location
}

Write-Host ""
Write-Host "  Port check" -ForegroundColor Yellow
$ports = @(80, 443, 8000, 8502)
foreach ($p in $ports) {
    $t = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
    $state = if ($t.TcpTestSucceeded) { "open" } else { "closed" }
    Write-Host "    :$p  $state"
}
Write-Host ""
