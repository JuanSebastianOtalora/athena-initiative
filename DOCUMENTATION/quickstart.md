# Quickstart & Deployment

Get Athena running on a single machine in a few minutes.

## Prerequisites

- **Docker Engine** 24+ with the **Compose** plugin (`docker compose version`).
- ~4 GB free RAM, ~2 GB disk (minimal tier).
- (Optional) **Ollama** for local LLM/embeddings, if you want AI-assisted retrieval.

## 1. Clone

```bash
git clone <repo> athena
cd athena
```

## 2. Start the minimal stack

```bash
./athena up
```

That one command will:

1. Create the `DATA/` skeleton (idempotent — safe to re-run).
2. Copy each minimal service's `.env.example` → `.env` if it doesn't exist.
3. Generate any empty secrets (`SURREAL_PASSWORD`, `OPEN_NOTEBOOK_ENCRYPTION_KEY`).
4. Create the shared external `athena` docker network.
5. Start services in dependency order:
   `surrealdb → open-notebook → tailscale → caddy`.

> `./athena up` is a thin wrapper over
> `INFRASTRUCTURE/scripts/athena-up.sh`, which is the canonical implementation.

### Or, step by step (manual)

```bash
# 1. DATA skeleton
mkdir -p DATA/ai/opennotebook DATA/databases/surrealdb \
         DATA/edge/caddy/data DATA/edge/caddy/config DATA/edge/tailscale DATA/media

# 2. Per-service .env files
for svc in databases/surrealdb ai/opennotebook edge/caddy edge/tailscale; do
  cp "INFRASTRUCTURE/compose/$svc/.env.example" "INFRASTRUCTURE/compose/$svc/.env"
done

# 3. Generate required secrets
openssl rand -hex 32   # → SURREAL_PASSWORD          (surrealdb/.env)
openssl rand -hex 32   # → OPEN_NOTEBOOK_ENCRYPTION_KEY (opennotebook/.env)

# 4. Shared network
docker network create athena

# 5. Start services (dependency order)
export ATHENA_DATA_DIR="$(pwd)/DATA"
(cd INFRASTRUCTURE/compose/databases/surrealdb && docker compose up -d)
(cd INFRASTRUCTURE/compose/ai/opennotebook     && docker compose up -d)
(cd INFRASTRUCTURE/compose/edge/tailscale      && docker compose up -d)
(cd INFRASTRUCTURE/compose/edge/caddy          && docker compose up -d)
```

## 3. Verify

```bash
./athena status
./athena doctor
```

Then open:

| URL | Service |
| --- | ------- |
| `http://localhost:8502` | Open Notebook (web UI) |
| `http://localhost:5055` | Open Notebook (API) |
| `http://localhost` | Caddy gateway (routes to Open Notebook) |

## Tailscale (optional tailnet)

The minimal tier includes a Tailscale sidecar. Two options:

- **Headless** (servers): put a headless auth key in
  `INFRASTRUCTURE/compose/edge/tailscale/.env` →
  `TAILSCALE_AUTHKEY=tskey-...`, and the node joins automatically.
- **Interactive** (laptops): leave `TAILSCALE_AUTHKEY` empty and run
  `docker compose -f INFRASTRUCTURE/compose/edge/tailscale/compose.yaml exec tailscale ts login`
  once to authorize.

## Stopping & removing

```bash
./athena stop                 # stops services, preserves DATA/
docker network rm athena      # (only if you also want to drop the network)
```

Runtime state lives in `DATA/` and survives `down`. Removing `DATA/`
**destroys the local databases** — back them up first if they hold knowledge.

## Updating

```bash
git pull
docker compose pull        # from each service dir
./athena restart
```

Image tags are mostly `:latest` / `:v2` — pin exact versions in the per-service
`.env` or `compose.yaml` for reproducible production deployments.
