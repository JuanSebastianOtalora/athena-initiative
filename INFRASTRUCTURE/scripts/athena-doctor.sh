#!/usr/bin/env bash
# athena-doctor.sh — sanity-check the deployment environment.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/../compose" && pwd)"
ROOT="$(cd "$COMPOSE_DIR/../.." && pwd)"
DATA="${ATHENA_DATA_DIR:-$ROOT/DATA}"

ok()   { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ⚠ %s\n' "$1"; }
err()  { printf '  ✗ %s\n' "$1"; }

echo "── Athena doctor ─────────────────────────────"

# ── docker ──
if command -v docker >/dev/null 2>&1; then
  ok "docker: $(docker --version | awk '{print $3}' | tr -d ',')"
else
  err "docker: not found"
fi
if docker compose version >/dev/null 2>&1; then
  ok "compose: $(docker compose version --short)"
else
  err "compose: not found (install docker-compose-plugin)"
fi

# ── per-service .env files ──
echo "── Per-service .env files ──"
for svc in databases/surrealdb ai/opennotebook edge/tailscale edge/caddy; do
  if [ -f "$COMPOSE_DIR/$svc/.env" ]; then
    ok "$svc/.env present"
  else
    warn "$svc/.env missing (run: ./athena up)"
  fi
done

# ── required secrets ──
echo "── Required secrets ──"
if grep -Eq "^[[:space:]]*SURREAL_PASSWORD=[^[:space:]]" \
     "$COMPOSE_DIR/databases/surrealdb/.env" 2>/dev/null; then
  ok "SURREAL_PASSWORD set"
else
  warn "SURREAL_PASSWORD empty (auto-generated on first ./athena up)"
fi
if grep -Eq "^[[:space:]]*OPEN_NOTEBOOK_ENCRYPTION_KEY=[^[:space:]]" \
     "$COMPOSE_DIR/ai/opennotebook/.env" 2>/dev/null; then
  ok "OPEN_NOTEBOOK_ENCRYPTION_KEY set"
else
  warn "OPEN_NOTEBOOK_ENCRYPTION_KEY empty (auto-generated on first ./athena up)"
fi
if grep -Eq "^[[:space:]]*TAILSCALE_AUTHKEY=[^[:space:]]" \
     "$COMPOSE_DIR/edge/tailscale/.env" 2>/dev/null; then
  ok "TAILSCALE_AUTHKEY set (headless tailnet join)"
else
  warn "TAILSCALE_AUTHKEY empty (interactive 'ts login' required)"
fi

# ── DATA skeleton ──
echo "── DATA skeleton ──"
for d in ai/opennotebook databases/surrealdb edge/caddy edge/tailscale media backups; do
  if [ -d "$DATA/$d" ]; then ok "DATA/$d"; else warn "DATA/$d missing"; fi
done

# ── shared network ──
if docker network inspect athena >/dev/null 2>&1; then
  ok "shared docker network 'athena' exists"
else
  warn "shared network 'athena' not created (will be created on ./athena up)"
fi

echo "── doctor complete ──"
