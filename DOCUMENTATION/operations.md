# Operations (day-2)

Practical runbook for operating the Athena stack after initial deployment.

## Common commands

```bash
./athena status                 # what's running
./athena doctor                 # docker / .env / secret sanity check
./athena restart                # restart all minimal services
./athena down                   # stop all (data preserved in DATA/)
docker network inspect athena   # shared network state
```

For a single service:

```bash
cd INFRASTRUCTURE/compose/ai/opennotebook
docker compose ps
docker compose logs -f open-notebook
docker compose restart
```

## Backups

The single most important thing to protect is `DATA/` — it holds the graph,
the notebook, and the vectors.

```bash
# stop writes, then archive
./athena down
tar -czf DATA/backups/athena-backup-$(date +%F).tar.gz DATA/
./athena up
```

- **SurrealDB** — also consider `surreal export` for a logical dump.
- **Qdrant** (scaffold) — copy `DATA/databases/qdrant` (or use its snapshot API).
- **Tailscale** — `DATA/edge/tailscale` holds the node identity; losing it
  re-keys the tailnet node.

## Recovery

```bash
./athena down
rm -rf DATA/databases/surrealdb
tar -xzf DATA/backups/athena-backup-<date>.tar.gz -C . DATA/databases/surrealdb
./athena up
```

## Secrets

```bash
# rotate a single secret
openssl rand -hex 32
# → edit the per-service .env, then:
cd INFRASTRUCTURE/compose/databases/surrealdb
docker compose up -d surrealdb
```

If `SURREAL_PASSWORD` changes, update it in **both** places it's referenced
(`databases/surrealdb/.env` and `ai/opennotebook/.env` if Open Notebook
shares the graph).

## Networking / access

- **LAN** — services are reachable on the host's mapped ports
  (`NOTEBOOK_PORT`, `CADDY_HTTP_PORT`, …).
- **Tailnet** — with the Tailscale sidecar, the node appears on your tailnet;
  reach the gateway via `http://<tailscale-hostname>/`.
- **Caddy** — the only public-ish entry point. Add/remove apps by editing
  `INFRASTRUCTURE/compose/edge/caddy/Caddyfile` and
  `docker compose -f .../caddy/compose.yaml restart caddy`.

## Troubleshooting

| Symptom | First checks |
| ------- | ------------ |
| `open-notebook` won't start | Is `surrealdb` up? `docker compose -f .../surrealdb/compose.yaml logs` |
| 502 at the gateway | `docker compose -f .../caddy/compose.yaml ps caddy`; port conflict on `CADDY_HTTP_PORT` |
| SurrealDB auth errors | `SURREAL_USER`/`SURREAL_PASSWORD` match in both services' `.env` |
| Tailscale not on tailnet | `docker compose -f .../tailscale/compose.yaml logs tailscale`; `TAILSCALE_AUTHKEY` set? |
| Caddy 404 on a path | `Caddyfile` has the `handle_path` block? |

## Housekeeping

```bash
docker image prune -a           # remove unused images (after tag churn)
du -sh DATA/*                   # watch growth of the data tree
```
