# Architecture

Athena is an **idea** — an architecture for preserving and nurturing human
reasoning. This repository is **one reference implementation** of that idea, a
local-first Docker stack that demonstrates the architecture in a runnable form.
The architecture (this document and [AKEF](akef.md)) is the thing that matters;
the code here is one way to instantiate it, and it is not required to use Athena.

The implementation is built around a simple, deliberate distinction: **what
Athena preserves** vs. **how Athena runs it**. The two are kept in separate
directories so that one can change without the other.

```
PROJECT ATHENA
   │
   ├─ DATA            What Athena stores and preserves
   ├─ INFRASTRUCTURE  How Athena runs and is configured
   ├─ DOCUMENTATION   How Athena works and is operated
   └─ DEVELOPMENT     Third-party sources, future work
```

## Why separate them?

Take Open Notebook as the example.

Its **infrastructure** is:

```
INFRASTRUCTURE/compose/ai/opennotebook/
├── compose.yaml
└── .env
```

This describes *how* to run Open Notebook: Docker image, container name,
ports, environment variables, networks, volume mappings, restart policy.

Its **data** is elsewhere:

```
DATA/ai/opennotebook/
```

That contains uploaded files and application state.

If you decide tomorrow *"I don't want to use this Open Notebook Docker image
anymore"*, you can remove and recreate the infrastructure **without touching
the data**.

The same applies to SurrealDB:

```
INFRASTRUCTURE/compose/databases/surrealdb/   ← how to run
DATA/databases/surrealdb/mydatabase.db        ← what's preserved
```

The database engine is **replaceable infrastructure**. The database contents
are **Athena's data**.

This is the foundation of Athena's technology-agnostic design. The same
knowledge that lives in SurrealDB today could live in PostgreSQL tomorrow, or
in another storage implementation the day after, **without conceptually
changing what Athena's knowledge is**:

```
SurrealDB  →  Athena data
PostgreSQL →  Athena data
<other>    →  Athena data
```

## The two planes

On top of the DATA/INFRASTRUCTURE split, Athena also separates **knowledge**
from **presentation**:

```
┌──────────────────────────────────────────────────────────────────┐
│  KNOWLEDGE PLANE  (renderer-independent, long-lived)              │
│                                                                  │
│   DATA/media/   →  raw sources (manuals, media, articles)        │
│        │  ingest + L1 transforms                                 │
│        ▼                                                         │
│   DATA/ai/opennotebook/  →  sources, embeddings, state           │
│        │  embed + index                                          │
│        ▼                                                         │
│   DATA/databases/surrealdb/  →  graph + document store           │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │  retrieve / query
┌──────────────────────────────────────────────────────────────────┐
│  ACCESS PLANE  (swappable endpoints)                              │
│                                                                  │
│   Caddy (gateway) →  Open Notebook · (future endpoints: mobile,   │
│                      wearable, XR, voice)                         │
│   Tailscale → private tailnet identity (a node, not a publisher)  │
└──────────────────────────────────────────────────────────────────┘
```

- **Knowledge plane** is where knowledge *is*. It must survive any change in
  the access plane — replace a UI, swap a backend, move to a new device, and
  the knowledge stays intact.
- **Access plane** is where knowledge *is seen*. Every endpoint is a
  disposable view over the same graph (AKEF `View` object).

## Services

| Service | Tier | Role |
| ------- | ---- | ---- |
| **SurrealDB** | minimal | Graph + document store; the durable home for AKEF structures. |
| **Open Notebook** | minimal | Knowledge workspace: sources, transformations, embeddings, retrieval. **Requires SurrealDB.** |
| **Caddy** | minimal | Single HTTP gateway; routes path prefixes to each app. |
| **Tailscale** | minimal | Private tailnet identity (a node on the shared network, not a blanket publisher). |
| **Qdrant** | scaffold | Vector store for embeddings / semantic retrieval. |
| **PostgreSQL** | scaffold | Relational fallback / alternative to SurrealDB. |
| **Redis** | scaffold | Caching / queueing (future). |
| **Portainer** | scaffold | Container dashboard / operations. |

Athena is **not AI-first**. Any LLM / embedding backend is **optional and
user-supplied** — run it here, or point the workspace at an inference service
running elsewhere. The minimal stack works without any AI component.

All services join one shared user-defined Compose network (`athena`, created
by `athena-up.sh`) and reach each other **by container name** (e.g.
`ws://surrealdb:8000/rpc`) — no host exposure needed for internal traffic.

### Tailscale — what it does and doesn't do

The Tailscale container is **a node on the shared `athena` docker network**.
Joining a tailnet gives **that container** a stable tailnet IP and identity.
It does **not** by itself publish the other containers onto the tailnet as if
they shared Tailscale's network namespace. To expose the stack off-LAN, the
gateway (Caddy) must listen on the `tailscale0` interface, or you reach it
via `tailscale serve`. This is why the minimal stack's "off-LAN" story is
"the Caddy gateway, on the tailnet" rather than "the whole stack, magically
reachable."

## Data & persistence

Runtime state is mounted from the `DATA/` tree, which lives **next to** the
repo (at the repo root by default). Each service's `compose.yaml` uses
`${ATHENA_DATA_DIR:-./DATA}/...` so the same file works:

- from the repo root (`./athena up` resolves `ATHENA_DATA_DIR` to an absolute path),
- from a different checkout location (just re-run `./athena up`),
- at an externally stored location (export `ATHENA_DATA_DIR=/path/to/share`).

```
DATA/
├── ai/opennotebook/        Open Notebook state (sources, embeddings, sqlite)
├── databases/surrealdb/    SurrealDB RocksDB files
├── databases/postgres/     (scaffold)
├── databases/qdrant/       (scaffold)
├── databases/redis/        (scaffold)
├── edge/caddy/data         Caddy runtime data (TLS, cache)
├── edge/caddy/config       Caddy config (certs, admin)
├── edge/tailscale/         Tailscale state (keys, identity)
├── media/                  External source material (manuals, media, articles)
└── backups/                Athena backups (critical)
```

`DATA/` is **gitignored** — only the `.gitkeep` skeleton is committed. The
*structure* (graph, artifacts, indexes) is what Athena preserves; raw blobs
are re-acquirable.

## Secrets & configuration

- **Committed**: per-service `compose.yaml`, per-service `.env.example`,
  `Caddyfile`, scripts, documentation.
- **Local (gitignored)**: per-service `.env`, everything under `DATA/`.
- **Secrets** (encryption key, DB password, Tailscale auth key) are generated
  at first `./athena up` and live **only** in the per-service `.env`.
  `SURREAL_PASSWORD` is generated **once** and written into **both** the
  surrealdb and open-notebook `.env` files, so the shared credential always
  matches.

## Design constraints

- **Local-first** — the entire minimal tier runs on one machine with no cloud.
- **Modular** — every service is independently replaceable.
- **Renderer-independent** — knowledge is stored once (AKEF), presented many ways.
- **Not AI-first** — AI / inference is optional and user-supplied; the core is
  a knowledge-preservation stack.
- **Preservation** — durable graph + artifacts outlive any single interface or
  vendor; the goal is knowledge that is still understandable in 20 years.
- **Technology-agnostic** — the data model (AKEF) is decoupled from the
  storage engine; SurrealDB today, PostgreSQL tomorrow, without changing the
  knowledge.
