# Athena Initiative

> **Athena is an open knowledge architecture** 


Knowledge is one of humanity's most valuable resources. Most of it is found scattered across manuals, forums, videos, pictures and in the heads of experienced people. It usually disappears when we don't document it or share it. Athena exists to preserve the knowledge and particularly **the process of thinking** behind that knowledge: the reasoning, the decisions, the alternatives that were considered, and the conclusions reached.

Athena organizes reasoning and knowledge into reusable structures that both people and machines can understand, use and adapt. It separates **knowledge** from the **technology and interfaces** used to access it.

> **Athena is an idea, not a product.** This repository is **one reference implementation** of that idea that will be evolving with each domain is worked on and included in its database.
> This implementation is but one demonstration of how it can be used/deployed and what can be archived with it.

>This repository It is not the definition of Athena, and it is not required to use Athena's knowledge core. 

>The architecture's deployment and possible configuration is can be found in [DOCUMENTATION/](DOCUMENTATION/) **the code here is one way to instantiate it.**

  
---


## Deployed architecture


```
PROJECT ATHENA

   │

   ├─ DATA            What the apps of the software stack produce as persistent data.

   │                  (local, gitignored, backable up)

   │

   ├─ INFRASTRUCTURE  What Athena Software Stack runs

   │                  (committed, reproducible from Git)

   │

   ├─ DOCUMENTATION   How Athena works and the multiple ways it can be configured.

   │

   └─ DEVELOPMENT     Third-party sources, future work files. 
```



### What's in each layer


| Layer | Holds | Committed? |
| ----- | ----- | ---------- |
| `DATA/` | Application state (Open Notebook, SurrealDB), | **No** — `.gitkeep` placeholders only |
| `INFRASTRUCTURE/compose/<category>/<service>/` | Per-service `compose.yaml` + `.env.example` (committed) + `.env` (local) | compose + .env.example |
| `INFRASTRUCTURE/scripts/` | `athena-up/down/restart/status/doctor.sh` | Yes |
| `DOCUMENTATION/` | AKEF spec, architecture, quickstart, operations | Yes |
| `DEVELOPMENT/third-party/` | Reserved for future third-party source repos | Yes (empty) |

  
## Minimal stack

  
The **minimal** stack is the core implementation. It is deliberately provided this way to allow people to discover what they can do with basic tools and how Athena adapts to the different workflows its users might have.

#Disclaimer
Some tools or designed stacks might make use of Large Language Models, Machine Learning Models, Computer Vision Models/Algorithms and Speech Models **however** that doesn't make Athena an **AI project**. Athena is a knowledge-preservation architecture, where the actual value of it falls on the content that is created, curated and structurally standardized by its community.


| Service | Tier | Role |
| ------- | ---- | ---- |
| **Open Notebook** | minimal | Knowledge workspace: sources, transformations, embeddings, retrieval — **requires** SurrealDB |
| **SurrealDB** | minimal | Home for AKEF structures and digitalized machine readable knowledge|
| **Caddy** | minimal | Single HTTP gateway |
| **Tailscale** | minimal | Private tailnet identity (node, not a blanket publisher) |

Qdrant, Postgres, Redis, Portainer, ready to be filled in as future stacks are defined.

  

## Quick start

  
```bash

git clone <repo> athena

cd athena

  

./athena up        # creates DATA skeleton + .env files + starts the minimal stack

./athena status    # verify

./athena doctor    # sanity-check the deployment

./athena down      # stop (data preserved under DATA/)

```

  

That's it. The `athena` wrapper runs `INFRASTRUCTURE/scripts/athena-up.sh`,

which:


1. Creates the `DATA/` skeleton (idempotent).

2. Copies each minimal service's `.env.example` → `.env` (if missing).

3. Generates the shared `SURREAL_PASSWORD` (into **both** surrealdb and open-notebook) and `OPEN_NOTEBOOK_ENCRYPTION_KEY`.

4. Creates the shared `athena` docker network.

5. Starts services in dependency order:

   `surrealdb → open-notebook → tailscale → caddy`.

  
**URLs once running:**

| URL                     | Service                                 |
| ----------------------- | --------------------------------------- |
| `http://localhost:8502` | Open Notebook (web UI)                  |
| `http://localhost:5055` | Open Notebook (API)                     |
| `http://localhost`      | Caddy gateway (routes to Open Notebook) |
| tailnet hostname        | via Tailscale (see note below)          |

> **Tailscale note:** the Tailscale container is a *node* on the shared `athena` docker network. Joining a tailnet gives **that container** a tailnet IP; it does **not** by itself publish the other containers onto the tailnet.

> To expose the stack off-LAN, Caddy must listen on the `tailscale0` interface (or you reach it via `tailscale serve`). See [operations](DOCUMENTATION/operations.md).

  

## Data paths & portability

  

By default, every compose file mounts from `${ATHENA_DATA_DIR:-./DATA}/...` **repo-root-relative**, no host-specific paths. The scripts resolve `ATHENA_DATA_DIR` to the absolute repo-root `DATA/` before starting. To point at externally stored knowledge (Synology share, encrypted volume, separate disk), export `ATHENA_DATA_DIR=/path/to/data` before running `./athena up`.

  

## Documentation

  

- [Quickstart & deployment](DOCUMENTATION/quickstart.md)

- [Architecture (four layers, knowledge vs infrastructure)](DOCUMENTATION/architecture.md)

- [Operations (day-2 runbook)](DOCUMENTATION/operations.md)

- [AKEF specification](DOCUMENTATION/akef.md)

  

## Roadmap Overview

  

| Phase                                     | Focus                                                                                                     |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1-Vision & Foundation                     | Philosophy, architecture, direction, public presence                                                      |
| 2-Knowledge Infrastructure                | Ingestion, organization, indexing, retrieval, reasoning structures                                        |
| 3-Cross-Platform Access                   | Mobile, wearables, hands-free endpoints                                                                   |
| 4-First Live deployment + Interactive MVP | Contextual, environment-aware knowledge assistance for computer troubleshooting as first knowledge domain |
| 5-Second Knowledge domain Expansion       | New domain automotive repair/maintenance                                                                  |
| 6-Third Knowledge domain Expansion        | New domain heavy-machinery troubleshoot repair/maintenance                                                |

---
