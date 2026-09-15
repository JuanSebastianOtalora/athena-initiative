#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  athena-up.sh — bring up the minimal Athena stack.
#
#  Steps:
#    1. Resolve repo root (this script's grandparent) and DATA dir.
#    2. Create any missing DATA/<service>/ dirs (idempotent).
#    3. Copy .env.example → .env for each minimal service if not present.
#    4. Generate the shared SURREAL_PASSWORD + any other empty secrets
#       (idempotent, warns).
#    5. Create the shared external `athena` docker network.
#    6. docker compose up -d for each minimal service, in dependency order.
#
#  Minimal stack: caddy · tailscale · open-notebook · surrealdb
#  Order:         surrealdb → open-notebook → tailscale → caddy
#
#  Open Notebook REQUIRES SurrealDB — the same SURREAL_PASSWORD is generated
#  into both services' .env files so the credentials always match.
#
#  Override the data root with ATHENA_DATA_DIR to point at externally stored
#  knowledge (e.g. a Synology share, a separate disk, an encrypted volume).
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="${ATHENA_DATA_DIR:-$ROOT/DATA}"
COMPOSE_DIR="$ROOT/INFRASTRUCTURE/compose"

# Minimal-stack services in dependency order.
SERVICES=(
  "databases/surrealdb"
  "ai/opennotebook"
  "edge/tailscale"
  "edge/caddy"
)

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

echo "→ Athena up — minimal stack"
echo "  repo:   $ROOT"
echo "  data:   $DATA"

# ── 1. DATA skeleton ────────────────────────────────────────────────────────
echo "→ Ensuring DATA directories exist"
for d in "ai/opennotebook" "databases/surrealdb" \
         "databases/postgres" "databases/qdrant" "databases/redis" \
         "edge/caddy/data" "edge/caddy/config" "edge/tailscale" \
         "media" "backups"; do
  mkdir -p "$DATA/$d"
  [ -f "$DATA/$d/.gitkeep" ] || \
    echo "# placeholder — generated locally, never committed." > "$DATA/$d/.gitkeep"
done

# ── 2. Per-service .env files ───────────────────────────────────────────────
echo "→ Ensuring per-service .env files exist"
for svc in "${SERVICES[@]}"; do
  dir="$COMPOSE_DIR/$svc"
  if [ ! -f "$dir/.env" ]; then
    cp "$dir/.env.example" "$dir/.env"
    echo "   created $svc/.env"
  else
    echo "   present $svc/.env"
  fi
done

# ── 3. Generate secrets ─────────────────────────────────────────────────────
echo "→ Ensuring secrets are set"

# set_var <envfile> <varname> <value>
set_var() {
  local envfile="$1" varname="$2" val="$3"
  if grep -Eq "^[[:space:]]*${varname}=" "$envfile"; then
    sed -i.bak "s|^\([[:space:]]*${varname}=.*\)$|\1 ${val}|" "$envfile" && rm -f "$envfile.bak"
  else
    echo "${varname}=${val}" >> "$envfile"
  fi
}

# SURREAL_PASSWORD is SHARED between surrealdb and open-notebook.
# Generate once, write into both, so the credentials always match.
if ! grep -Eq "^[[:space:]]*SURREAL_PASSWORD=[^[:space:]]" \
     "$COMPOSE_DIR/databases/surrealdb/.env" 2>/dev/null; then
  SP="$(gen_secret)"
  set_var "$COMPOSE_DIR/databases/surrealdb/.env"  SURREAL_PASSWORD "$SP"
  set_var "$COMPOSE_DIR/ai/opennotebook/.env"      SURREAL_PASSWORD "$SP"
  echo "   generated SURREAL_PASSWORD (shared by surrealdb + open-notebook)"
fi

# OPEN_NOTEBOOK_ENCRYPTION_KEY (open-notebook only)
if ! grep -Eq "^[[:space:]]*OPEN_NOTEBOOK_ENCRYPTION_KEY=[^[:space:]]" \
     "$COMPOSE_DIR/ai/opennotebook/.env" 2>/dev/null; then
  ONK="$(gen_secret)"
  set_var "$COMPOSE_DIR/ai/opennotebook/.env" OPEN_NOTEBOOK_ENCRYPTION_KEY "$ONK"
  echo "   generated OPEN_NOTEBOOK_ENCRYPTION_KEY"
fi

# Tailscale: optional — if empty, the node will require interactive login.
# (Do not auto-generate; the user must provide a real tskey-... value.)

# ── 4. Shared external network ─────────────────────────────────────────────
echo "→ Ensuring shared docker network 'athena'"
docker network inspect athena >/dev/null 2>&1 \
  || docker network create athena >/dev/null

# ── 5. Start services in dependency order ──────────────────────────────────
echo "→ Starting minimal stack"
# ATHENA_DATA_DIR  → app state / DB files (default: repo-root DATA/)
# ATHENA_ASSETS_DIR → externally stored knowledge/assets (default: DATA/media)
# Both are exported as ABSOLUTE paths so every nested compose file resolves
# them relative to the repo root, regardless of the compose file's own dir.
export ATHENA_DATA_DIR="$DATA"
export ATHENA_ASSETS_DIR="${ATHENA_ASSETS_DIR:-$DATA/media}"
for svc in "${SERVICES[@]}"; do
  echo "   up: $svc"
  (cd "$COMPOSE_DIR/$svc" && docker compose up -d)
done

echo
echo "✓ Athena is up. Services:"
( cd "$COMPOSE_DIR/databases/surrealdb" && docker compose ps --format 'table {{.Name}}\t{{.Status}}' | tail -n +1 )
( cd "$COMPOSE_DIR/ai/opennotebook"     && docker compose ps --format 'table {{.Name}}\t{{.Status}}' | tail -n +2 )
( cd "$COMPOSE_DIR/edge/tailscale"      && docker compose ps --format 'table {{.Name}}\t{{.Status}}' | tail -n +2 )
( cd "$COMPOSE_DIR/edge/caddy"          && docker compose ps --format 'table {{.Name}}\t{{.Status}}' | tail -n +2 )

echo
echo "  Gateway:  http://localhost:80"
echo "  Notebook: http://localhost:8502"
echo "  API:      http://localhost:5055"
echo "  Tailscale: (join with: docker compose exec tailscale ts login)"
