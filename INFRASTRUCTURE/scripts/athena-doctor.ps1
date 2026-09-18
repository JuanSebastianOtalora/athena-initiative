#!/usr/bin/env pwsh
# athena-doctor.ps1 - sanity-check the deployment environment (Windows).
# Checks the environment AND every discovered service (compose file, .env,
# .env.example) plus the DATA layout. Query only - never changes anything.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "athena-startup-order.ps1")
$Services = Get-AthenaServices
$issues   = 0

Write-Host ""
Write-Host "  Athena - environment check" -ForegroundColor Cyan
Write-Host ""

# --- Docker ---
Write-Host "  [1] Docker" -ForegroundColor Yellow
try {
    $ver = docker version --format '{{.Server.Version}}' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] Engine running (v$ver)" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] Daemon not running: $ver" -ForegroundColor Red
        $issues++
    }
} catch {
    Write-Host "    [FAIL] Docker CLI not found" -ForegroundColor Red
    $issues++
}

docker compose version | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] Compose plugin" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Compose plugin missing" -ForegroundColor Red
    $issues++
}

# --- Per-service files ---
Write-Host ""
Write-Host "  [2] Per-service files" -ForegroundColor Yellow
if ($Services.Count -eq 0) {
    Write-Host "    [MISS] No services found under: $AthenaCompose" -ForegroundColor Yellow
    $issues++
}
foreach ($svc in $Services) {
    $d = Join-Path $AthenaCompose $svc
    $hasExample = Test-Path (Join-Path $d ".env.example")
    $hasEnv     = Test-Path (Join-Path $d ".env")
    Write-Host "    [OK] $svc  (.env.example=$hasExample, .env=$hasEnv)" -ForegroundColor Green
}

# --- DATA layout ---
# Per-service data paths live in the compose.yaml volumes (Docker creates them
# on `up`), so doctor only asserts the single DATA/ root exists.
Write-Host ""
Write-Host "  [3] DATA layout" -ForegroundColor Yellow
if (Test-Path $AthenaData) {
    Write-Host "    [OK] DATA/ root present: $AthenaData" -ForegroundColor Green
} else {
    Write-Host "    [MISS] DATA/ root  (run athena-up to create)" -ForegroundColor Yellow
    $issues++
}

# --- Orphan containers ---
# A running container whose compose project has no matching service dir in the
# tree means the dir was deleted out from under it (or was never added to it).
# Scoped via the com.docker.compose.project label, so unrelated containers
# on the machine are never flagged.
Write-Host ""
Write-Host "  [4] Orphan containers" -ForegroundColor Yellow
$knownProjects = @($Services | ForEach-Object { ($_ -split '/')[-1].ToLowerInvariant() })
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$composeContainers = docker ps --format '{{.ID}}  {{.Names}}  {{.Label "com.docker.compose.project"}}' 2>$null
$ErrorActionPreference = $prevEAP
$orphans = @()
foreach ($line in @($composeContainers)) {
    if ($null -eq $line -or $line -notmatch '^\S+\s+\S+\s+(.+)$') { continue }
    $name    = ($line -split '\s+')[1]
    $project = $Matches[1].ToLowerInvariant()
    $match = $knownProjects | Where-Object { $project -eq $_ } | Select-Object -First 1
    if (-not $match) { $orphans += $name }
}
if ($orphans.Count -eq 0) {
    Write-Host "    [OK] No orphaned containers" -ForegroundColor Green
} else {
    foreach ($o in $orphans) {
        Write-Host "    [ORPHAN] $o  (no matching service dir - delete with: docker rm -f $o)" -ForegroundColor Red
        $issues++
    }
}

Write-Host ""
if ($issues -eq 0) {
    Write-Host "  All checks passed." -ForegroundColor Green
} else {
    Write-Host "  $issues issue(s) found. See above." -ForegroundColor Yellow
}
Write-Host ""
