#!/usr/bin/env pwsh
# Athena - single entry point (Windows / PowerShell).
#   .\athena.ps1 up | down | restart | status | doctor
param([Parameter(Position=0)][string]$Cmd)
if ($Cmd -in @("", "help", "-h", "--help")) {
    Write-Host "  Athena - entry point (Windows)"
    Write-Host "  Usage: .\athena.ps1 {up|down|restart|status|doctor}"
    exit 0
}
$Script = Join-Path $PSScriptRoot "INFRASTRUCTURE\scripts\athena-$Cmd.ps1"
if (-not (Test-Path $Script)) {
    Write-Host "  Unknown command: $Cmd  (valid: up, down, restart, status, doctor)" -ForegroundColor Red
    exit 1
}
& $Script
