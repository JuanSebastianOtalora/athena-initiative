#!/usr/bin/env bash
# athena-restart.sh — restart all stack services (dependency order).
# Restart output (per-container start/stop) is printed so you can follow the
# procedure; a final `docker compose ps` shows the resulting state.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/athena-lib.sh"

mapfile -t SERVICES < <(athena_services)

echo ""
echo "  ${C_CYAN}Athena - restart the stack${C_OFF}"
echo ""

echo "  ${C_YELLOW}[1] Preflight${C_OFF}"
if ! command -v docker >/dev/null 2>&1; then
  echo "    ${C_RED}[FAIL] Docker not installed${C_OFF}" >&2
  echo "$(athena_install_hint docker)" >&2
  exit 1
fi
echo "    ${C_GREEN}[OK] Docker installed${C_OFF}"
if ! docker info >/dev/null 2>&1; then
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

if (( ${#SERVICES[@]} == 0 )); then
  echo ""
  echo "  ${C_RED}[FAIL] No services found under: $ATHENA_COMPOSE${C_OFF}" >&2
  exit 1
fi

echo ""
echo "  ${C_YELLOW}[2] Restarting services${C_OFF}"
for svc in "${SERVICES[@]-}"; do
  dir="$ATHENA_COMPOSE/$svc"
  echo "    ${C_CYAN}$svc${C_OFF}"
  if ! ( cd "$dir" && docker compose restart ); then
    echo "    ${C_RED}[FAIL] Restart failed for '$svc'. See output above.${C_OFF}" >&2
    exit 1
  fi
  echo "    ${C_GREEN}[OK] Restarted${C_OFF}"
done

echo ""
echo "  ${C_YELLOW}[3] Resulting state${C_OFF}"
for svc in "${SERVICES[@]-}"; do
  ( cd "$ATHENA_COMPOSE/$svc" && docker compose ps )
done

echo ""
echo "  ${C_GREEN}Stack restarted.${C_OFF}"
echo ""
exit 0
