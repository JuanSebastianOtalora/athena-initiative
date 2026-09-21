#!/usr/bin/env bash
# athena-create.sh — provision a fresh Athena workspace.
#
#   create = PROVISION ONLY: DATA/ layout, per-service .env files, shared
#   SurrealDB password, and the 'athena' docker network.
#   It does NOT pull images and does NOT start any container.
#
#   Idempotent: safe to re-run. Existing .env files are preserved (a real
#   password is reused, never clobbered).
#
#   After this, bring the stack up with:  ./athena up
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/athena-lib.sh"

mapfile -t SERVICES < <(athena_services)
if (( ${#SERVICES[@]} == 0 )); then
  echo "  ${C_RED}[FAIL] No services found under: $ATHENA_COMPOSE${C_OFF}" >&2
  echo "  Expected compose/<section>/<name>/compose.yaml (see athena-lib.sh)." >&2
  exit 1
fi

echo ""
echo "  ${C_CYAN}Athena - create the workspace${C_OFF}"
echo ""

echo "  ${C_YELLOW}[1] Docker & Compose${C_OFF}"
if athena_docker_ok; then
  echo "    ${C_GREEN}[OK] Docker engine running${C_OFF}"
  echo "    ${C_GREEN}[OK] Docker Compose available${C_OFF}"
else
  echo "    ${C_RED}[FAIL] Docker / Compose not available${C_OFF}" >&2
  echo "$(athena_install_hint docker)" >&2
  exit 1
fi

export ATHENA_DATA_DIR="$ATHENA_DATA"
export ATHENA_ASSETS_DIR="$ATHENA_ASSETS"
echo ""
athena_provision "${SERVICES[@]}"

echo ""
echo "  ${C_GREEN}Workspace is ready (no containers started yet).${C_OFF}"
echo "    ${C_DIM}Next:  ./athena up         (pull-free start of the stack)${C_OFF}"
echo "    ${C_DIM}Or:    ./athena recreate   (recreate containers now)${C_OFF}"
echo ""
exit 0
