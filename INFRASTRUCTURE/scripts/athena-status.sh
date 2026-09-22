#!/usr/bin/env bash
# athena-status.sh — show the state of the stack.
# Per-service container status (docker compose ps) plus a localhost port check.
# Ports are discovered from each container's PUBLISHED ports
# (docker compose ps --format json) — nothing is hardcoded.
#
# jq is the one soft dependency (documented). Without it the port-check
# section is skipped with a clear note; everything else still works.
# status is a query: a down Docker is a valid "not running" answer → exit 0.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/athena-lib.sh"

mapfile -t SERVICES < <(athena_services)

# Published ports for one service dir: 'PUBLISHED<TAB>URL' per line (empty ok).
athena_published_ports() { # <servicedir>
  local dir="$1" raw
  [ -d "$dir" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  raw="$(cd "$dir" && docker compose ps --format json 2>/dev/null)" || return 0
  [ -n "$raw" ] || return 0
  printf '%s\n' "$raw" | jq -r '
    (if type == "array" then .[] else . end)
    | (.Publishers // [])[]
    | select((.URL // "0.0.0.0") | IN("0.0.0.0", "0", "", "::"))
    | select((.PublishedPort | tostring | tonumber) > 0)
    | [.PublishedPort, (.URL // "0.0.0.0")] | @tsv
  ' 2>/dev/null
}

athena_port_open() { # <port> → 0 when localhost:<port> accepts a TCP connect
  local port="$1"
  ( exec 3<>"/dev/tcp/127.0.0.1/$port" ) >/dev/null 2>&1
}

echo ""
echo "  ${C_CYAN}Athena - stack status${C_OFF}"
echo ""

# --- Preflight (soft) ---
if ! command -v docker >/dev/null 2>&1; then
  echo "  ${C_DIM}Docker not installed — cannot show stack status.${C_OFF}"
  echo "  ${C_DIM}Athena: not running.${C_OFF}"
  exit 0
fi
if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  echo "  ${C_DIM}Docker Engine not running.${C_OFF}"
  echo "  ${C_DIM}Athena: not running.${C_OFF}"
  exit 0
fi

# --- Per-service status + its published ports ---
if (( ${#SERVICES[@]} == 0 )); then
  echo "  ${C_DIM}No services found under: $ATHENA_COMPOSE${C_OFF}"
  echo ""
fi
for svc in "${SERVICES[@]-}"; do
  svc_dir="$ATHENA_COMPOSE/$svc"
  echo "  ${C_CYAN}$svc${C_OFF}"
  ( cd "$svc_dir" && docker compose ps )
  ports=""
  if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r p _; do
      [ -n "$p" ] && ports="${ports}${ports:+, }$p"
    done < <(athena_published_ports "$svc_dir" | sort -n -u)
  fi
  if [ -n "$ports" ]; then
    echo "    ${C_DIM}ports: $ports${C_OFF}"
  else
    echo "    ${C_DIM}ports: (none published to localhost)${C_OFF}"
  fi
  echo ""
done

# --- Port check (only ports a running container actually publishes) ---
echo "  ${C_YELLOW}Port check${C_OFF}"
if ! command -v jq >/dev/null 2>&1; then
  echo "    ${C_DIM}(skipped: jq not found — install for port checks:$(athena_pkg_hint jq))${C_OFF}"
else
  all_ports=""
  declare -A OWNER=()
  for svc in "${SERVICES[@]-}"; do
    while IFS=$'\t' read -r p _; do
      [ -n "$p" ] || continue
      case " $all_ports " in *" $p "*) : ;; *) all_ports="$all_ports $p"; OWNER[$p]="$svc" ;; esac
    done < <(athena_published_ports "$ATHENA_COMPOSE/$svc")
  done
  all_ports="${all_ports# }"
  if [ -z "$all_ports" ]; then
    echo "    ${C_DIM}(no running container publishes a localhost port)${C_OFF}"
  else
    for p in $(printf '%s\n' "$all_ports" | sort -n); do
      who="${OWNER[$p]}"
      if athena_port_open "$p"; then
        echo "    ${C_GREEN}:$p  open    ($who)${C_OFF}"
      else
        echo "    ${C_DIM}:$p  closed  ($who)${C_OFF}"
      fi
    done
  fi
fi
echo ""
exit 0
