#!/usr/bin/env pwsh
# athena-status.ps1 - show the state of the stack.
# Per-service container status (docker compose ps) plus a localhost port check.
# Ports are discovered from each container's PUBLISHED ports (docker compose ps
# --format json) - nothing is hardcoded. status is a query: a down Docker is a
# valid "not running" answer, so exit 0.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "athena-startup-order.ps1")
$Services = Get-AthenaServices

function Get-ServicePublishedPorts {
    param([string]$ServiceDir)
    # Published ports for a service, read from its running container.
    # 0.0.0.0 / empty publishers are reachable via localhost.
    if (-not (Test-Path $ServiceDir)) { return @() }
    Push-Location $ServiceDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = docker compose ps --format json 2>$null | Out-String
    $ErrorActionPreference = $prevEAP
    Pop-Location
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $obj = $null
    try { $obj = $raw | ConvertFrom-Json } catch { return @() }
    $ports = @()
    foreach ($c in @($obj)) {
        foreach ($p in @($c.Publishers)) {
            if ($null -eq $p) { continue }
            $url = [string]$p.URL
            if ($url -eq "0.0.0.0" -or $url -eq "" -or $url -eq "[::]") {
                $port = [int]$p.PublishedPort
                if ($port -gt 0 -and $ports -notcontains $port) { $ports += $port }
            }
        }
    }
    return @($ports)
}

Write-Host ""
Write-Host "  Athena - stack status" -ForegroundColor Cyan
Write-Host ""

# --- Preflight (soft) ---
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
$engineUp = $false
if ($dockerCmd) {
    $null = docker version --format '{{.Server.Version}}' 2>$null
    $engineUp = ($LASTEXITCODE -eq 0)
}

if (-not $dockerCmd) {
    Write-Host "  Docker not installed - cannot show stack status." -ForegroundColor DarkGray
    Write-Host "  Athena: not running." -ForegroundColor DarkGray
    exit 0
}
if (-not $engineUp) {
    Write-Host "  Docker Engine not running." -ForegroundColor DarkGray
    Write-Host "  Athena: not running." -ForegroundColor DarkGray
    exit 0
}

# --- Per-service status + its published ports ---
if ($Services.Count -eq 0) {
    Write-Host "  No services found under: $AthenaCompose" -ForegroundColor DarkGray
    Write-Host ""
}
foreach ($svc in $Services) {
    $svcDir = Join-Path $AthenaCompose $svc
    Write-Host "  $svc" -ForegroundColor Cyan
    Push-Location $svcDir
    docker compose ps
    Pop-Location
    $pub = @(Get-ServicePublishedPorts -ServiceDir $svcDir)
    if ($pub.Count -gt 0) {
        Write-Host "    ports: $(($pub | Sort-Object) -join ', ')" -ForegroundColor DarkGray
    } else {
        Write-Host "    ports: (none published to localhost)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# --- Port check (only ports a running container actually publishes) ---
Write-Host "  Port check" -ForegroundColor Yellow
$allPorts = @()
$owner    = @{}
foreach ($svc in $Services) {
    foreach ($p in @(Get-ServicePublishedPorts -ServiceDir (Join-Path $AthenaCompose $svc))) {
        if ($allPorts -notcontains $p) { $allPorts += $p; $owner[$p] = $svc }
    }
}
if ($allPorts.Count -eq 0) {
    Write-Host "    (no running container publishes a localhost port)" -ForegroundColor DarkGray
} else {
    foreach ($p in ($allPorts | Sort-Object)) {
        $t = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue
        $who = $owner[$p]
        if ($t.TcpTestSucceeded) {
            Write-Host "    :$p  open    ($who)" -ForegroundColor Green
        } else {
            Write-Host "    :$p  closed  ($who)" -ForegroundColor DarkGray
        }
    }
}
Write-Host ""
