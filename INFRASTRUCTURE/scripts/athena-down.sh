#!/usr/bin/env bash
# athena-down.sh — tear down the minimal stack. DATA is preserved.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/../compose" && pwd)"
export ATHENA_DATA_DIR="${ATHENA_DATA_DIR:-$(cd "$COMPOSE_DIR/../.." && pwd)/DATA}"

echo "→ Athena down (data preserved under $ATHENA_DATA_DIR)"
for svc in edge/caddy edge/tailscale ai/opennotebook databases/surrealdb; do
  (cd "$COMPOSE_DIR/$svc" && docker compose down) || true
done
echo "✓ Stopped. DATA is untouched."
echo "  To also remove the shared network:  docker network rm athena"
