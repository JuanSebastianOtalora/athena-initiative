#!/usr/bin/env bash
# athena-up.sh — bring up the Athena stack.
#
#   up = START only: it never recreates running containers.
#   (athena-recreate.sh does the force-recreate pass.)
#
#   Services are discovered from compose/<section>/<name> dirs that contain
#   a compose file; their start order comes from athena-lib.sh (ATHENA_ORDER).
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
echo "  ${C_CYAN}Athena - bring up the stack${C_OFF}"
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
echo "  ${C_YELLOW}[6] Starting services${C_OFF}"
rc=0
for svc in "${SERVICES[@]-}"; do
  if athena_compose_run "$ATHENA_COMPOSE/$svc" compose up -d; then
    echo "    ${C_GREEN}[OK] $svc  started${C_OFF}"
  else
    code=$?
    echo "    ${C_RED}[FAIL] $svc  failed to start (exit $code)${C_OFF}" >&2
    echo "    Check: docker compose logs (in $ATHENA_COMPOSE/$svc)" >&2
    rc=1
    break
  fi
done

if [ "$rc" -eq 0 ]; then
  echo ""
  echo "  ${C_GREEN}Stack is up.${C_OFF}"
  echo "    Open Notebook   http://localhost:8502"
  echo "    SurrealDB       http://localhost:8000"
  echo "    Gateway         http://localhost"
  echo "    Status          ./athena status"
  echo ""
fi
exit "$rc"
