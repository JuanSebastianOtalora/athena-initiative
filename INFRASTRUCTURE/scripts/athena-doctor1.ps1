#!/usr/bin/env pwsh
# athena-doctor.ps1 - sanity-check the deployment environment (Windows).
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ComposeDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "INFRASTRUCTURE\compose"
$RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Services   = @("databases\surrealdb", "ai\opennotebook", "edge\caddy", "edge\tailscale")

Write-Host ""
Write-Host "  Athena - doctor (Windows)" -ForegroundColor Cyan
Write-Host "  Repo: $RepoRoot"
Write-Host ""

# Docker
Write-Host "  Docker" -ForegroundColor Yellow
try {
    $ver = docker version --format '{{.Server.Version}}' 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Host "    [OK] engine $ver" }
    else { Write-Host "    [FAIL] daemon not running: $ver" -ForegroundColor Red }
} catch { Write-Host "    [FAIL] docker CLI not found" -ForegroundColor Red }

docker compose version | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "    [OK] compose plugin" } else { Write-Host "    [FAIL] compose plugin missing" -ForegroundColor Red }

# Per-service files
Write-Host "  Per-service files" -ForegroundColor Yellow
foreach ($svc in $Services) {
    $d = Join-Path $ComposeDir $svc
    $hasCompose = Test-Path (Join-Path $d "compose.yaml")
    $hasExample = Test-Path (Join-Path $d ".env.example")
    $hasEnv     = Test-Path (Join-Path $d ".env")
    $mark = if ($hasCompose) { "OK" } else { "MISSING compose.yaml" }
    Write-Host "    $svc  [$mark]  .env.example=$hasExample  .env=$hasEnv"
}

# DATA layout
Write-Host "  DATA/ layout" -ForegroundColor Yellow
$dataDirs = @("ai\opennotebook", "databases\surrealdb", "edge\caddy\data", "edge\caddy\config", "edge\tailscale", "media")
foreach ($d in $dataDirs) {
    $p = Join-Path $RepoRoot "DATA\$d"
    if (Test-Path $p) { Write-Host "    [OK] DATA\$d" } else { Write-Host "    [MISS] DATA\$d (run athena-up to create)" }
}
Write-Host ""
