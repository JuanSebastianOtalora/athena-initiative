#!/usr/bin/env pwsh
# athena-startup-order.ps1 - shared config + discovery for the athena-*.ps1 scripts.
#
#   This is the ONE file you edit when Athena grows.
#   The other scripts dot-source it at the top:
#       . (Join-Path $PSScriptRoot "athena-startup-order.ps1")
#
#   DISCOVERY is automatic: every compose\<section>\<name> directory that
#   contains a compose.yaml / compose.yml / docker-compose.yaml /
#   docker-compose.yml counts as a service. Placeholders without a compose
#   file (mcp, monitoring, edge/portainer, ...) are ignored until you add one.
#
#   ORDER: services listed below start in that exact order; anything you do
#   NOT list is still discovered and started LAST (alphabetical).
#   Default order mirrors a printer config: network/gateway first, then the
#   databases the apps depend on, then the apps - so nothing is left stale
#   or disconnected, and an app never starts before the service it needs.

# --- Paths (resolved from this file's location) ---
$AthenaScripts = $PSScriptRoot                       # .../INFRASTRUCTURE/scripts
$AthenaInfra   = Split-Path -Parent $AthenaScripts  # .../INFRASTRUCTURE
$AthenaRepo    = Split-Path -Parent $AthenaInfra    # .../Athena-Initiative GitHub
$AthenaCompose = Join-Path $AthenaInfra "compose"   # .../INFRASTRUCTURE/compose
$AthenaData    = if ($env:ATHENA_DATA_DIR) { $env:ATHENA_DATA_DIR } else { Join-Path $AthenaRepo "DATA" }
$AthenaAssets  = if ($env:ATHENA_ASSETS_DIR) { $env:ATHENA_ASSETS_DIR } else { Join-Path $AthenaData "media" }

# --- STARTUP ORDER (edit me) ---
# Like a Klipper config, grouped by section: edge / databases / ai.
$AthenaOrder = @(
    # edge / network - first, so nothing is left stale or disconnected
    "edge/tailscale"
    "edge/caddy"
    # databases - before the apps that use them
    "databases/surrealdb"
    # ai / apps - last
    "ai/opennotebook"
)

# --- DATA ---
# Per-service data paths (edge/caddy/data, edge/tailscale, databases/surrealdb,
# ai/opennotebook/...) are NOT defined here - they live in each service's
# compose.yaml, and Docker creates the host dirs on `up` from that config.
# The scripts only anchor the single DATA/ root (ATHENA_DATA_DIR) that the
# yamls resolve against. A future athena-create.ps1 owns fresh layout setup.

# --- PORTS ---
# Not defined here: athena-status reads each running container's PUBLISHED ports
# from `docker compose ps --format json`, so a new service is covered with no edits.

# --- Discovery helpers (no need to edit below this line) ---

function Get-AthenaServiceDirs {
    # Every directory under compose/ that holds one of the four compose filenames.
    if (-not (Test-Path $AthenaCompose)) { return @() }
    Get-ChildItem -Path $AthenaCompose -Recurse -File |
        Where-Object { $_.Name -in @("compose.yaml","compose.yml","docker-compose.yaml","docker-compose.yml") } |
        ForEach-Object {
            $rel = $_.FullName.Substring($AthenaCompose.Length).TrimStart('\')
            if ($rel -match '^([^/\\]+[/\\][^/\\]+)') { $Matches[1] -replace '\\','/' }
        } |
        Sort-Object -Unique
}

function Get-AthenaServices {
    # Discovered services in startup order: $AthenaOrder first, the rest after (alpha).
    $found   = Get-AthenaServiceDirs
    $ordered = @()
    foreach ($svc in $AthenaOrder) { if ($found -contains $svc) { $ordered += $svc } }
    foreach ($svc in $found)      { if ($ordered -notcontains $svc) { $ordered += $svc } }
    return $ordered
}

function Get-AthenaServicesReversed {
    # Stop order = startup order reversed (apps first, network last).
    $all = @(Get-AthenaServices)
    $rev = @()
    for ($i = $all.Count - 1; $i -ge 0; $i--) { $rev += $all[$i] }
    return $rev
}

# ============================================================
#  SHARED HELPERS - used by up / create / recreate
# ============================================================

# Run a docker compose sub-command inside a service dir. Compose writes its
# progress UI to stderr; under EAP=Stop that becomes a terminating
# NativeCommandError and reflows on resize. Drop both streams; the caller
# checks $LASTEXITCODE. Returns $LASTEXITCODE.
function Invoke-AthenaCompose {
    param([Parameter(Mandatory)][string]$ServiceDir, [Parameter(Mandatory)][string[]]$ComposeArgs)
    Push-Location $ServiceDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & docker @ComposeArgs 2>$null | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    Pop-Location
    return $code
}

function Test-AthenaDocker {
    # True when the Docker engine and the compose plugin are both usable.
    try {
        docker version --format '{{.Server.Version}}' | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
    } catch { return $false }
    docker compose version | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Set-AthenaEnvFile {
    param([string]$Path, [string]$Key, [string]$Value)
    $line    = "${Key}=${Value}"
    $content = if (Test-Path $Path) { Get-Content $Path } else { @() }
    $keyRe   = "^{0}\s*=" -f [regex]::Escape($Key)
    $found   = $content | Where-Object { $_ -match $keyRe } | Select-Object -First 1
    if ($found) { $content = $content | ForEach-Object { if ($_ -match $keyRe) { $line } else { $_ } } }
    else        { $content += $line }
    $content | Set-Content $Path -Encoding UTF8
}

function Get-AthenaEnvValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path $Path)) { return $null }
    $line = Get-Content $Path | Where-Object { $_ -match ("^{0}\s*=" -f [regex]::Escape($Key)) } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1].Trim()
}

function Generate-AthenaSecurePassword {
    try {
        $bytes = [byte[]]::new(32)
        $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        return ([System.BitConverter]::ToString($bytes) -replace '-','').ToLower()
    } catch {
        return ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
    }
}

# Shared provisioning (idempotent): DATA root, per-service .env seeding, shared
# SurrealDB password sync, and the 'athena' network. No images, no containers.
# Expects $env:ATHENA_DATA_DIR / ATHENA_ASSETS_DIR to be set by the caller.
function Ensure-AthenaProvision {
    param([Parameter(Mandatory)][string[]]$Services)

    Write-Host "  [2] DATA layout" -ForegroundColor Yellow
    $created = 0
    if (-not (Test-Path $AthenaData))   { New-Item -ItemType Directory -Path $AthenaData   -Force | Out-Null; $created++ }
    if (-not (Test-Path $AthenaAssets)) { New-Item -ItemType Directory -Path $AthenaAssets -Force | Out-Null; $created++ }
    if ($created -gt 0) { Write-Host "    [OK] Created DATA/ root + media/ under: $AthenaData" -ForegroundColor Green }
    else                { Write-Host "    [OK] DATA/ layout present: $AthenaData" -ForegroundColor Green }

    Write-Host ""
    Write-Host "  [3] Per-service .env files" -ForegroundColor Yellow
    $envFiles = @{}
    foreach ($svc in $Services) {
        $svcDir  = Join-Path $AthenaCompose $svc
        $envFile = Join-Path $svcDir ".env"
        $example = Join-Path $svcDir ".env.example"
        if (-not (Test-Path $envFile)) {
            if (Test-Path $example) { Copy-Item $example $envFile }
            else { New-Item -ItemType File -Path $envFile | Out-Null }
            Write-Host "    [OK] $svc  created" -ForegroundColor Green
        } else {
            Write-Host "    [OK] $svc  exists" -ForegroundColor Green
        }
        $envFiles[$svc] = $envFile
    }

    Write-Host ""
    Write-Host "  [4] Shared SurrealDB password" -ForegroundColor Yellow
    $hasSurreal  = $Services -contains "databases/surrealdb"
    $hasNotebook = $Services -contains "ai/opennotebook"
    if (-not $hasSurreal -and -not $hasNotebook) {
        Write-Host "    [SKIP] surrealdb not in stack" -ForegroundColor DarkGray
    } else {
        $surrealEnv   = if ($hasSurreal)  { $envFiles["databases/surrealdb"] } else { $null }
        $notebookEnv  = if ($hasNotebook) { $envFiles["ai/opennotebook"] } else { $null }
        $existingPass = if ($surrealEnv)  { Get-AthenaEnvValue -Path $surrealEnv -Key "SURREAL_PASSWORD" } else { $null }
        $isPlaceholder = (
            [string]::IsNullOrWhiteSpace($existingPass) -or
            $existingPass.TrimStart().StartsWith("#") -or
            $existingPass -match "REQUIRED|CHANGE[-_ ]?ME|YOUR[-_ ]?PASSWORD"
        )
        if (-not $isPlaceholder -and $existingPass.Length -ge 16) {
            $sharedPass = $existingPass
            Write-Host "    [OK] Reusing existing password (surrealdb/.env)" -ForegroundColor Green
        } else {
            $sharedPass = Generate-AthenaSecurePassword
            Write-Host "    [OK] Generated new shared password" -ForegroundColor Green
        }
        $synced = 0
        if ($surrealEnv)  { Set-AthenaEnvFile -Path $surrealEnv  -Key "SURREAL_PASSWORD" -Value $sharedPass; $synced++ }
        if ($notebookEnv) { Set-AthenaEnvFile -Path $notebookEnv -Key "SURREAL_PASSWORD" -Value $sharedPass; $synced++ }
        Write-Host "    [OK] Synchronized to $synced .env files" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  [5] Docker network" -ForegroundColor Yellow
    $Network = "athena"
    $exists  = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq $Network }
    if (-not $exists) {
        docker network create --driver bridge $Network | Out-Null
        Write-Host "    [OK] Created network: $Network" -ForegroundColor Green
    } else {
        Write-Host "    [OK] Network '$Network' already exists" -ForegroundColor Green
    }
}
