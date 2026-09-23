#!/usr/bin/env bash
# athena-down.sh — tear down the Athena stack. DATA is preserved.
# Stop order = startup order reversed (apps first, network last),
# so dependencies stay alive until dependents are gone.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/athena-lib.sh"

mapfile -t SERVICES < <(athena_services_reversed)

echo ""
echo "  ${C_CYAN}Athena - stop the stack${C_OFF}"
echo ""

echo "  ${C_YELLOW}[1] Preflight${C_OFF}"
if ! command -v docker >/dev/null 2>&1; then
  echo "    ${C_RED}[FAIL] Docker not installed${C_OFF}" >&2
  echo "$(athena_install_hint docker)" >&2
  exit 1
fi
echo "    ${C_GREEN}[OK] Docker installed${C_OFF}"
if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  echo "    ${C_RED}[FAIL] Docker Engine not running${C_OFF}" >&2
  echo "    Start the Docker daemon and try again." >&2
  exit 1
fi
echo "    ${C_GREEN}[OK] Docker Engine running${C_OFF}"
if ! docker compose version >/dev/null 2>&1; then
  echo "    ${C_RED}[FAIL] Docker Compose not available${C_OFF}" >&2
  echo "    Install the Docker Compose plugin and try again." >&2
  exit 1
fi
echo "    ${C_GREEN}[OK] Docker Compose available${C_OFF}"

echo ""
echo "  ${C_YELLOW}[2] Stopping services${C_OFF}"
if (( ${#SERVICES[@]} == 0 )); then
  echo "    ${C_DIM}[SKIP] No services found under: $ATHENA_COMPOSE${C_OFF}"
  echo ""
  echo "  ${C_GREEN}Stack stopped. DATA/ is preserved.${C_OFF}"
  exit 0
fi

all_ok=1
for svc in "${SERVICES[@]-}"; do
  if athena_compose_run "$ATHENA_COMPOSE/$svc" compose down; then
    echo "    ${C_GREEN}[OK] $svc  stopped${C_OFF}"
  else
    code=$?
    echo "    ${C_RED}[FAIL] $svc  could not be stopped (exit $code)${C_OFF}" >&2
    all_ok=0
  fi
done

echo ""
if [ "$all_ok" -eq 1 ]; then
  echo "  ${C_GREEN}Stack stopped. DATA/ is preserved.${C_OFF}"
  exit 0
fi
echo "  ${C_YELLOW}Some services failed to stop. Check output above.${C_OFF}" >&2
exit 1
