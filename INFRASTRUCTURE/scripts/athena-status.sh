#!/usr/bin/env bash
# athena-status.sh — show the state of the minimal stack across all services.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/../compose" && pwd)"
export ATHENA_DATA_DIR="${ATHENA_DATA_DIR:-$(cd "$COMPOSE_DIR/../.." && pwd)/DATA}"

echo "── Athena status ─────────────────────────────────"
printf '%-22s %s\n' "SERVICE" "STATUS"
printf '%-22s %s\n' "----------------------" "----------------------"
for svc in databases/surrealdb ai/opennotebook edge/tailscale edge/caddy; do
  (cd "$COMPOSE_DIR/$svc" && \
   docker compose ps --format 'json' 2>/dev/null | \
   python -c '
import sys, json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except: continue
    name=d.get("Service","?"); st=d.get("State","?")+"/"+d.get("Status","?")
    print(f"  {name:20s} {st}")
' 2>/dev/null) \
  || echo "  $svc                  (no containers)"
done
echo
echo "Shared network:"
docker network inspect athena --format '  athena: {{.Driver}} ({{len .Containers}} containers)' 2>/dev/null \
  || echo "  athena: NOT CREATED (run: ./athena up)"
echo
echo "DATA dir: $ATHENA_DATA_DIR"
du -sh "$ATHENA_DATA_DIR" 2>/dev/null | awk '{print "  total:  " $1}'
