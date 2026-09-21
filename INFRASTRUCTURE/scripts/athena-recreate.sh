#!/usr/bin/env bash
# athena-recreate.sh — force-recreate the Athena containers.
#
#   recreate = fresh containers from the CURRENT compose.yaml + .env, keeping
#   the DATA/ volumes. Use it after changing a compose file or an .env value,
#   or after `athena create` / a fresh clone.
#
#   Before recreating, it asks whether to pull the latest images:
#       N  = pull new images first, then recreate
#       E  = recreate using the images already on this machine (default)
#
#   Non-interactive (no TTY) defaults to E. DATA/ is never touched.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/athena-lib.sh"

mapfile -t SERVICES < <(athena_services)
if (( ${#SERVICES[@]} == 0 )); then
  echo "  ${C_RED}[FAIL] No services found under: $ATHENA_COMPOSE${C_OFF}" >&2
  echo "  Expected compose/<section>/<name>/compose.yaml (see athena-lib.sh)." >&2
  exit 1
fi

read_recreate_choice() {
  local line=""
  if [ -t 0 ]; then
    echo "  ${C_YELLOW}Recreate with:${C_OFF}"
    echo "    N  pull NEW images first, then recreate"
    echo "    E  use EXISTING images (default)"
    read -r -p "    Choice [E] " line || line=""
  else
    # Non-interactive: honor a piped-in choice if one is provided, else default to E.
    IFS= read -r line 2>/dev/null || line=""
  fi
  local up; up="${line# }"; up="${up%% }"
  up="${up^^}"
  case "$up" in
    ""|E|EX|EXISTING) printf 'existing\n' ;;
    N|NEW)            printf 'new\n' ;;
    *)                printf 'existing\n' ;;
  esac
}

echo ""
echo "  ${C_CYAN}Athena - recreate the stack${C_OFF}"
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

mode="$(read_recreate_choice)"
echo ""
if [ "$mode" = "new" ]; then
  echo "  ${C_YELLOW}[6] Pulling images${C_OFF}"
  for svc in "${SERVICES[@]-}"; do
    if athena_compose_run "$ATHENA_COMPOSE/$svc" compose pull; then
      echo "    ${C_GREEN}[OK] $svc  images pulled${C_OFF}"
    else
      code=$?
      echo "    ${C_YELLOW}[WARN] $svc  pull failed (exit $code); recreating with existing images${C_OFF}"
    fi
  done
else
  echo "  ${C_YELLOW}[6] Pull${C_OFF}"
  echo "    ${C_DIM}[SKIP] Using existing images (chose E)${C_OFF}"
fi

echo ""
echo "  ${C_YELLOW}[7] Recreating services${C_OFF}"
rc=0
for svc in "${SERVICES[@]-}"; do
  if athena_compose_run "$ATHENA_COMPOSE/$svc" compose up -d --force-recreate; then
    echo "    ${C_GREEN}[OK] $svc  recreated${C_OFF}"
  else
    code=$?
    echo "    ${C_RED}[FAIL] $svc  failed to recreate (exit $code)${C_OFF}" >&2
    echo "    Check: docker compose logs (in $ATHENA_COMPOSE/$svc)" >&2
    rc=1
    break
  fi
done

if [ "$rc" -eq 0 ]; then
  echo ""
  echo "  ${C_GREEN}Stack recreated. DATA/ preserved.${C_OFF}"
  echo "    Status          ./athena status"
  echo ""
fi
exit "$rc"
