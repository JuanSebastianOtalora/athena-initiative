#!/usr/bin/env bash
# tests/run.sh — daemon-less RED/GREEN for athena-*.sh (Linux or git-bash).
# Usage: bash tests/run.sh [lib|create|up|down|restart|status|doctor|recreate|all]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- sandbox repo (scripts resolve paths from their own location) ---
mkdir -p "$T/repo/INFRASTRUCTURE"
cp -r "$ROOT/INFRASTRUCTURE/compose"  "$T/repo/INFRASTRUCTURE/compose"
cp -r "$ROOT/INFRASTRUCTURE/scripts" "$T/repo/INFRASTRUCTURE/scripts"
S="$T/repo/INFRASTRUCTURE/scripts"

# --- fake docker on PATH ---
mkdir -p "$T/bin"; cp "$ROOT/tests/fake-docker" "$T/bin/docker"; chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH" FAKE_DOCKER_LOG="$T/dock.log" FAKE_DOCKER_STATE="$T/state"
export FAKE_DOCKER_DAEMON=1
mkdir -p "$T/state"; : > "$T/dock.log"
export NO_COLOR=1
export ATHENA_DATA_DIR="$T/repo/DATA"

pass=0; failed=0
check() { # desc, haystack, needle
  if printf '%s' "$2" | grep -qF -- "$3"; then echo "PASS  $1"; pass=$((pass+1));
  else echo "FAIL  $1"; echo "  expected to contain: $3"
       printf '%s\n' "$2" | sed -n '1,12p' | sed 's/^/  | /'; failed=$((failed+1)); fi
}
check_not() { # desc, haystack, needle-that-must-NOT-appear
  if printf '%s' "$2" | grep -qF -- "$3"; then echo "FAIL  $1"; echo "  must not contain: $3"; failed=$((failed+1));
  else echo "PASS  $1"; pass=$((pass+1)); fi
}
check_rc() { # desc, actual, expected
  if [ "$2" -eq "$3" ]; then echo "PASS  $1"; pass=$((pass+1));
  else echo "FAIL  $1 (got $2, want $3)"; failed=$((failed+1)); fi
}
run() { bash "$S/$1" "$@" 2>&1; }
order_of() { # log-arg-substring -> service order from logged cwds
  grep -F -- "$1" "$T/dock.log" | awk -F'cwd=' '{print $2}' | awk -F/ '{print $(NF-1)"/"$NF}'
}

target="${1:-all}"; [ $# -gt 0 ] && shift

case "$target" in
  lib)
    out="$(bash -c ". '$S/athena-lib.sh'; athena_services" 2>&1)"; rc=$?
    check_rc "lib: sources cleanly" "$rc" 0
    check  "lib: tailscale starts first" "$out" "edge/tailscale"
    check  "lib: opennotebook last" "$(printf '%s\n' "$out" | tail -1)" "ai/opennotebook"
    n="$(printf '%s\n' "$out" | grep -c .)"
    check_rc "lib: exactly 4 services (got $n)" "$((n-4))" 0
    rev="$(bash -c ". '$S/athena-lib.sh'; athena_services_reversed" 2>&1)"
    check  "lib: reversed ends with tailscale" "$(printf '%s\n' "$rev" | tail -1)" "edge/tailscale"
    ok="$(bash -c ". \"$S/athena-lib.sh\"; athena_docker_ok && echo yes || echo no" 2>&1)"
    check  "lib: athena_docker_ok (fake daemon up)" "$ok" "yes"
    ok="$(FAKE_DOCKER_DAEMON=0 bash -c ". \"$S/athena-lib.sh\"; athena_docker_ok && echo yes || echo no" 2>&1)"
    check  "lib: athena_docker_ok (daemon-down path)" "$ok" "no"
    ;;
  create)
    out="$(run athena-create.sh)"; rc=$?
    check_rc "create: exit 0" "$rc" 0
    check_rc "create: DATA/ created" "$([ -d "$T/repo/DATA" ] && echo 0 || echo 1)" 0
    for svc in edge/tailscale edge/caddy databases/surrealdb ai/opennotebook; do
      check_rc "create: .env for $svc" "$([ -f "$T/repo/INFRASTRUCTURE/compose/$svc/.env" ] && echo 0 || echo 1)" 0
    done
    check_rc "create: network 'athena' created" "$([ -f "$T/state/net-athena" ] && echo 0 || echo 1)" 0
    SP1="$(grep -E '^SURREAL_PASSWORD=' "$T/repo/INFRASTRUCTURE/compose/databases/surrealdb/.env" | cut -d= -f2)"
    SP2="$(grep -E '^SURREAL_PASSWORD=' "$T/repo/INFRASTRUCTURE/compose/ai/opennotebook/.env" | cut -d= -f2)"
    check_rc "create: shared password 64-hex" "$(echo "$SP1" | grep -cE '^[0-9a-f]{64}$')" 1
    check_rc "create: password synced to both" "$([ "$SP1" = "$SP2" ] && echo 0 || echo 1)" 0
    out2="$(run athena-create.sh)"
    check_rc "create: idempotent re-run" "$?" 0
    check  "create: re-run REUSES password" "$out2" "Reusing existing password"
    ;;
  up)
    out="$(run athena-up.sh)"; rc=$?
    check_rc "up: exit 0" "$rc" 0
    ord="$(order_of 'up -d')"
    check "up: 4x compose up" "$(printf '%s\n' "$ord" | grep -c .)" "4"
    check "up: starts tailscale first" "$(printf '%s\n' "$ord" | head -1)" "edge/tailscale"
    check "up: starts opennotebook last" "$(printf '%s\n' "$ord" | tail -1)" "ai/opennotebook"
    check "up: reports OK per service" "$out" "ai/opennotebook  started"
    ;;
  down)
    out="$(run athena-down.sh)"; rc=$?
    check_rc "down: exit 0" "$rc" 0
    ord="$(order_of 'args=compose down')"
    check "down: 4x compose down" "$(printf '%s\n' "$ord" | grep -c .)" "4"
    check "down: stops opennotebook FIRST (reversed)" "$(printf '%s\n' "$ord" | head -1)" "ai/opennotebook"
    check "down: stops tailscale LAST" "$(printf '%s\n' "$ord" | tail -1)" "edge/tailscale"
    ;;
  restart)
    out="$(run athena-restart.sh)"; rc=$?
    check_rc "restart: exit 0" "$rc" 0
    check "restart: 4x compose restart" "$(grep -cF 'args=compose restart' "$T/dock.log")" "4"
    check "restart: shows resulting state" "$out" "fake-1"
    ;;
  status)
    out="$(run athena-status.sh)"; rc=$?
    check_rc "status: exit 0 (query)" "$rc" 0
    check "status: lists each service" "$out" "databases/surrealdb"
    if command -v jq >/dev/null 2>&1; then
      check "status: published port 8000 detected" "$out" ":8000"
      check "status: port check runs" "$out" "closed"
    else
      check "status: jq-missing degradation" "$out" "jq not found"
    fi
    ;;
  doctor)
    out="$(run athena-doctor.sh)"; rc=$?
    check_rc "doctor: exit 0 (query)" "$rc" 0
    check  "doctor: flags the orphan"      "$out" "rogue-1"
    check_not "doctor: does NOT flag known surrealdb" "$out" "surreal-1"
    check  "doctor: checks DATA layout"    "$out" "DATA layout"
    ;;
  recreate)
    out="$(printf 'E\n' | run athena-recreate.sh)"; rc=$?
    check_rc "recreate(E): exit 0" "$rc" 0
    check "recreate: 4x force-recreate" "$(grep -cF 'force-recreate' "$T/dock.log")" "4"
    check_not "recreate(E): no pull" "$(cat "$T/dock.log")" "pull"
    out="$(printf 'N\n' | run athena-recreate.sh)"
    check "recreate(N): pulls then recreates" "$(cat "$T/dock.log")" "args=compose pull"
    ;;
  all)
    rc_all=0
    for t in lib create up down restart status doctor recreate; do
      echo "── $t ──"
      out="$(bash "$0" "$t" 2>&1)"; rc_t=$?
      printf '%s\n' "$out" | grep -vE '^PASS=[0-9]+ FAIL=[0-9]+$'
      p="$(printf '%s\n' "$out" | grep -oE 'PASS=[0-9]+' | tail -1 | cut -d= -f2)"
      f="$(printf '%s\n' "$out" | grep -oE 'FAIL=[0-9]+' | tail -1 | cut -d= -f2)"
      pass=$((pass + ${p:-0})); failed=$((failed + ${f:-0}))
      [ "$rc_t" -eq 0 ] || rc_all=1
    done
    ;;
  *) echo "unknown target: $target"; exit 2 ;;
esac

echo
echo "PASS=$pass FAIL=$failed"
[ "$failed" -eq 0 ]
