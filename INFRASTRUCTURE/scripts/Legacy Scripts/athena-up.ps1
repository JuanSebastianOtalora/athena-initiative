#!/usr/bin/env pwsh
# athena-up.ps1 - bring up the minimal Athena stack (Windows / PowerShell).
# Mirrors athena-up.sh.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeDir   = Resolve-Path "$ScriptDir\..\compose"
$RepoRoot     = Split-Path -Parent (Resolve-Path "$ComposeDir\..")
$Data         = if ($env:ATHENA_DATA_DIR) { $env:ATHENA_DATA_DIR } else { Join-Path $RepoRoot "DATA" }
$Assets       = if ($env:ATHENA_ASSETS_DIR) { $env:ATHENA_ASSETS_DIR } else { Join-Path $Data "media" }
$Services     = @("databases\surrealdb", "ai\opennotebook", "edge\caddy", "edge\tailscale")

function Test-Docker {
    try {
        $null = docker version --format '{{.Server.Version}}' 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Docker daemon not running" }
    } catch {
        Write-Host "  [FAIL] Docker not available: $_" -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] Docker engine running" -ForegroundColor Green
}

function Test-Compose {
    $null = docker compose version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Docker Compose plugin not found" -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] Docker Compose available" -ForegroundColor Green
}

function Ensure-DataDirs {
    $dirs = @(
        (Join-Path $Data "ai\opennotebook"),
        (Join-Path $Data "databases\surrealdb"),
        (Join-Path $Data "edge\caddy\data"),
        (Join-Path $Data "edge\caddy\config"),
        (Join-Path $Data "edge\tailscale"),
        $Assets
    )
    $created = 0
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null; $created++ }
    }
    if ($created -gt 0) {
        Write-Host "  [OK] Created $created data directory(ies)" -ForegroundColor Green
    } else {
        Write-Host "  [OK] DATA/ layout present" -ForegroundColor Green
    }
}

function Set-EnvFile {
    param([string]$Path, [string]$Key, [string]$Value)
    $line = "${Key}=${Value}"
    $content = if (Test-Path $Path) { Get-Content $Path } else { @() }
    $keyRe  = "^{0}\s*=" -f [regex]::Escape($Key)
    $found  = $content | Where-Object { $_ -match $keyRe } | Select-Object -First 1
    if ($found) {
        $content = $content | ForEach-Object { if ($_ -match $keyRe) { $line } else { $_ } }
    } else {
        $content += $line
    }
    $content | Set-Content $Path -Encoding UTF8
}

function Get-EnvValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path $Path)) { return $null }
    $line = Get-Content $Path | Where-Object { $_ -match ("^{0}\s*=" -f [regex]::Escape($Key)) } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1].Trim()
}

function Generate-SecurePassword {
    try {
        $bytes = [byte[]]::new(32)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        return ([System.BitConverter]::ToString($bytes) -replace '-','').ToLower()
    } catch {
        return ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
    }
}

#  Run 
Write-Host ""
Write-Host "  Athena - minimal stack (Windows)" -ForegroundColor Cyan
Write-Host "  Repo: $RepoRoot"
Write-Host ""
Write-Host "  1/5  Docker & Compose" -ForegroundColor Yellow
Test-Docker
Test-Compose
Write-Host "  2/5  DATA/ layout" -ForegroundColor Yellow
Ensure-DataDirs
Write-Host "  3/5  Per-service .env files" -ForegroundColor Yellow

$envFiles = @{}
foreach ($svc in $Services) {
    $svcDir  = Join-Path $ComposeDir $svc
    $envFile = Join-Path $svcDir ".env"
    $example = Join-Path $svcDir ".env.example"
    if (-not (Test-Path $envFile)) {
        if (Test-Path $example) { Copy-Item $example $envFile }
        else { New-Item -ItemType File -Path $envFile | Out-Null }
        Write-Host "    created: $envFile"
    } else {
        Write-Host "    exists:  $envFile"
    }
    $envFiles[$svc] = $envFile
}

Write-Host "  4/5  Generating shared SurrealDB password" -ForegroundColor Yellow
$surrealEnv   = $envFiles["databases\surrealdb"]
$notebookEnv  = $envFiles["ai\opennotebook"]
$existingPass = Get-EnvValue -Path $surrealEnv -Key "SURREAL_PASSWORD"

$isPlaceholder = (
    [string]::IsNullOrWhiteSpace($existingPass) -or
    $existingPass.TrimStart().StartsWith("#") -or
    $existingPass -match "REQUIRED|CHANGE[-_ ]?ME|YOUR[-_ ]?PASSWORD"
)

if (-not $isPlaceholder -and $existingPass.Length -ge 16) {
    $sharedPass = $existingPass
    Write-Host "    reusing existing password from surrealdb/.env"
} else {
    $sharedPass = Generate-SecurePassword
    Write-Host "    generated new shared password"
}

Set-EnvFile -Path $surrealEnv  -Key "SURREAL_PASSWORD" -Value $sharedPass
Set-EnvFile -Path $notebookEnv -Key "SURREAL_PASSWORD" -Value $sharedPass
Write-Host "    synchronized password to both .env files"


# Ensure shared Docker network exists
Write-Host "  Running Athena internal container network " -ForegroundColor Yellow
$Network = "athena"
$NetworkExists = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $Network }

if (-not $NetworkExists) {
    Write-Host "    creating Docker network: $Network"
    docker network create --driver bridge $Network | Out-Null
}

Write-Host "  5/5  Starting services (dependency order)" -ForegroundColor Yellow
$env:ATHENA_DATA_DIR   = $Data
$env:ATHENA_ASSETS_DIR = $Assets
foreach ($svc in $Services) {
    Write-Host "    starting $svc ..." -NoNewline
    Push-Location (Join-Path $ComposeDir $svc)
    $null = docker compose up -d | Out-Null
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host "  [FAIL] $svc failed to start (exit $code)." -ForegroundColor Red
        Write-Host "  Check: docker compose -f $ComposeDir\$svc\compose.yaml logs"
        exit 1
    }
    Write-Host " OK" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Minimal stack is up." -ForegroundColor Green
Write-Host "  Open Notebook  http://localhost:8502"
Write-Host "  SurrealDB      http://localhost:8000"
Write-Host "  Gateway        http://localhost"
Write-Host "  Status         ./athena status    (or .\athena.ps1 status)"
Write-Host ""
