#!/usr/bin/env bash
# athena-restart.sh — restart all minimal-stack services (in dependency order).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/../compose" && pwd)"
export ATHENA_DATA_DIR="${ATHENA_DATA_DIR:-$(cd "$COMPOSE_DIR/../.." && pwd)/DATA}"

echo "→ Athena restart"
for svc in databases/surrealdb ai/opennotebook edge/tailscale edge/caddy; do
  echo "   restarting: $svc"
  (cd "$COMPOSE_DIR/$svc" && docker compose restart)
done
echo "✓ Done."
