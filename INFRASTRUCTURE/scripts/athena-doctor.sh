#!/usr/bin/env bash
# athena-doctor.sh — sanity-check the deployment environment.
# Checks the environment AND every discovered service (compose file, .env,
# .env.example) plus the DATA layout. Query only — never changes anything.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/athena-lib.sh"

mapfile -t SERVICES < <(athena_services)
issues=0

echo ""
echo "  ${C_CYAN}Athena - environment check${C_OFF}"
echo ""

echo "  ${C_YELLOW}[1] Docker${C_OFF}"
if ! command -v docker >/dev/null 2>&1; then
  echo "    ${C_RED}[FAIL] Docker CLI not found${C_OFF}"
  issues=$((issues+1))
else
  ver="$(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  if [ -n "$ver" ]; then
    echo "    ${C_GREEN}[OK] Engine running (v$ver)${C_OFF}"
  else
    echo "    ${C_RED}[FAIL] Daemon not running: ${ver:-no version reported}${C_OFF}"
    issues=$((issues+1))
  fi
fi
if docker compose version >/dev/null 2>&1; then
  echo "    ${C_GREEN}[OK] Compose plugin${C_OFF}"
else
  echo "    ${C_RED}[FAIL] Compose plugin missing${C_OFF}"
  issues=$((issues+1))
fi

echo ""
echo "  ${C_YELLOW}[2] Per-service files${C_OFF}"
if (( ${#SERVICES[@]} == 0 )); then
  echo "    ${C_YELLOW}[MISS] No services found under: $ATHENA_COMPOSE${C_OFF}"
  issues=$((issues+1))
fi
for svc in "${SERVICES[@]-}"; do
  d="$ATHENA_COMPOSE/$svc"
  has_example="no"; [ -f "$d/.env.example" ] && has_example="yes"
  has_env="no";     [ -f "$d/.env" ]         && has_env="yes"
  echo "    ${C_GREEN}[OK] $svc  (.env.example=$has_example, .env=$has_env)${C_OFF}"
done

echo ""
echo "  ${C_YELLOW}[3] DATA layout${C_OFF}"
if [ ! -d "$ATHENA_DATA" ]; then
  echo "    ${C_YELLOW}[MISS] DATA/ root  (run ./athena create to create)${C_OFF}"
  issues=$((issues+1))
fi
# Every per-service data dir the compose files bind-mount must exist. If it's
# missing, `up` will make Docker's root daemon create it (root-owned), which
# breaks containers that run non-root (surrealdb).
while IFS= read -r sub; do
  [ -n "$sub" ] || continue
  d="$ATHENA_DATA/$sub"
  if [ ! -d "$d" ]; then
    echo "    ${C_YELLOW}[MISS] DATA/$sub  (run ./athena create to create)${C_OFF}"
    issues=$((issues+1))
  else
    owner_id="$(stat -c '%u' "$d" 2>/dev/null || echo '?')"
    if [ "$owner_id" = "0" ] && [ "$(id -u)" != "0" ]; then
      echo "    ${C_RED}[OWN ] DATA/$sub  owned by root — containers running non-root can't write here (fix: sudo chown $(id -un):$(id -gn) "$d")${C_OFF}"
      issues=$((issues+1))
    else
      echo "    ${C_GREEN}[OK] DATA/$sub${C_OFF}"
    fi
  fi
done < <(athena_data_subdirs)

echo ""
echo "  ${C_YELLOW}[4] Orphan containers${C_OFF}"
# A running container whose compose project has no matching service dir in the
# tree means the dir was deleted out from under it (or was never added to it).
# Scoped via the com.docker.compose.project label, so unrelated containers
# on the machine are never flagged.
declare -A KNOWN=()
for svc in "${SERVICES[@]-}"; do
  KNOWN["${svc##*/}"]=1
done
orphans=""
if command -v docker >/dev/null 2>&1; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r cid name project <<< "$line"
    [ -n "$name" ] || continue
    [ -n "${KNOWN[$project]-}" ] || orphans="${orphans}${orphans:+, }$name"
  done < <(docker ps --format '{{.ID}}\t{{.Names}}\t{{.Label "com.docker.compose.project"}}' 2>/dev/null)
fi
if [ -z "$orphans" ]; then
  echo "    ${C_GREEN}[OK] No orphaned containers${C_OFF}"
else
  for o in $(printf '%s\n' "$orphans" | tr ',' '\n'); do
    echo "    ${C_RED}[ORPHAN] $o  (no matching service dir — delete with: docker rm -f $o)${C_OFF}"
    issues=$((issues+1))
  done
fi

echo ""
if [ "$issues" -eq 0 ]; then
  echo "  ${C_GREEN}All checks passed.${C_OFF}"
else
  echo "  ${C_YELLOW}$issues issue(s) found. See above.${C_OFF}"
fi
echo ""
exit 0
