# Scripts reference what each script does, section by section


A plain-language tour of the stack-manager scripts, for people who want to **understand** them or use them as a **base for their own automation**.
  

The PowerShell (`.ps1`) and bash (`.sh`) families are **behavioral twins**: same commands, same numbered sections, same exit codes. The tables below show both side by side the sections are identical, so reading one column tells you what the other does.

## The file map

| File                                         | Role                                                                                                                                                                                                 |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `athena.ps1` / `athena`                      | **Dispatcher** one entry point that routes `create up down restart recreate status doctor` (and `deps` on Linux) to the right script. You can call it or call the scripts directly.                  |
| `athena-startup-order.ps1` / `athena-lib.sh` | **Shared library** paths, service discovery, startup order, `.env` helpers, secret generation, provisioning. Every other script dot-sources it. **This is the one file you edit when Athena grows.** |
| `athena-create.*`                            | Provision a fresh workspace (no containers start).                                                                                                                                                   |
| `athena-up.*`                                | Start the stack.                                                                                                                                                                                     |
| `athena-down.*`                              | Stop the stack (data preserved).                                                                                                                                                                     |
| `athena-restart.*`                           | Restart every service.                                                                                                                                                                               |
| `athena-recreate.*`                          | Force-recreate containers (keeps `DATA/`).                                                                                                                                                           |
| `athena-status.*`                            | Show what's running + published ports.                                                                                                                                                               |
| `athena-doctor.*`                            | Sanity-check the environment.                                                                                                                                                                        |
| `athena-deps.sh`                             | **Linux only** dependency detection and consent-gated installs (the only distro-aware code).                                                                                                         |

## Conventions (both families)

- **YAML Discovery, no container list is hardcoded.** A "service" is any `INFRASTRUCTURE/compose/<section>/<name>/` directory that contains one of `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`. Placeholder directories without a compose file are ignored.
  Add a new service = add a directory + compose file; **no script changes needed** (unless you want to change start order see below).

- **Startup order.** Listed in the shared library (`ATHENA_ORDER` / `$AthenaOrder`): `edge/tailscale → edge/caddy → databases/surrealdb → ai/opennotebook`.
  Anything discovered but not listed starts last (alphabetical). Stop order is the **reverse** apps go first, network last.

- **`[#]` sections.** Every script prints numbered sections `[1]…[7]` with `[OK]` / `[FAIL]` / `[SKIP]` per step, so you can follow what it's doing.

- **Exit codes.** Mutating commands (`create up down restart recreate`) exit **non-zero on failure** (scripting-friendly). Query commands (`status doctor`) exit **0 even when the stack is down** "not running" is a valid answer.

- **Idempotent.** `create`, `up`, `recreate` are safe to re-run. Existing `.env` files are preserved; a real password is reused, never clobbered.

- **DATA ownership is the scripts' job.** `create`/`up`/`recreate` pre-create every per-service `DATA/<…>` subdirectory (discovered from the compose files) *before* any container starts. This matters because when a bind-mount's host directory is missing, the Docker daemon (always root) auto-creates it **root-owned** — and containers that run as a non-root user (e.g. surrealdb) then fail with `PermissionDenied`. If you ever see that, `doctor` flags it (`[OWN] ... owned by root`) and the fix is `sudo chown <you> DATA/<dir>`. For services that run **non-root** (surrealdb ships as uid 65532), the dir must be owned by that uid — `create`/`up` detect each service's effective uid (compose `user:` line or the image default) and set it, asking for one `sudo` when you're a normal user. `doctor` flags any dir whose owner doesn't match with the exact `chown` to run. (Alternative: run such a service as `user: root` in its compose file — then ownership never matters.)
  **Custom services:** any new service you add is auto-discovered — for its data to be pre-created and owned by you, mount it under the data root as `${ATHENA_DATA_DIR:-./DATA}/<name>`; a host path outside that root is *not* auto-created, so create/chown it yourself before the first `up`.

- **No silent installs.** Nothing is ever installed without an explicit `y` from you (Linux `./athena deps install <dep>`).

  
## `create`: Provides a fresh workspace

> Provisions files and the network. **Pulls nothing, starts nothing.**

  
| Section                         | What it does                                                                                                                                                                                                                              |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[1] Docker & Compose`          | Hard check: engine running + Compose plugin available (the `athena` network needs Docker). Fails fast with a hint otherwise.                                                                                                              |
| `[2] DATA layout`               | Creates the `DATA/` root, `DATA/media/`, and every per-service `DATA/<…>/` subdirectory the compose files bind-mount (discovered, not hardcoded) — owned by the invoking user, so non-root containers (surrealdb) can write.                |
| `[3] Per-service .env files`    | For each discovered service: copies `.env.example` → `.env` (or creates an empty one). Existing `.env` is left alone.                                                                                                                     |
| `[4] Shared SurrealDB password` | If a real `SURREAL_PASSWORD` already exists (≥16 chars, not a placeholder) it is **reused**; otherwise a fresh 64-hex password is generated. It's written into **both** the surrealdb and opennotebook `.env` files so they always agree. |
| `[5] Docker network`            | Ensures the shared external network `athena` exists (creates it if not).                                                                                                                                                                  |

Both flavors end with "Workspace is ready (no containers started yet)" and point you at `up` / `recreate`.

## `up`: Starts the stack

| Section                 | What it does                                                                                                                                               |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[1] Docker & Compose`  | Same hard check as `create`.                                                                                                                               |
| `[2]…[5]`               | Shared provisioning (identical to `create` and `up` is self-sufficient on a fresh clone).                                                                  |
| `[6] Starting services` | For each service in startup order: `docker compose up -d` in that service's directory. Stops at the first failure and points you at `docker compose logs`. |

Ends with the service URLs (Open Notebook, SurrealDB, Gateway) and a pointer to `status`.

## `down`: Stops the stack

| Section                 | What it does                                                                                                                                                                                                                                                     |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[1] Preflight`         | Docker installed + engine running + Compose available.                                                                                                                                                                                                           |
| `[2] Stopping services` | For each service in **reverse** startup order: `docker compose down`. Compose writes progress to stderr, so the scripts deliberately drop both streams and keep only the exit code (this is why `up`/`down` use `ErrorActionPreference=Continue` / no `set -e`). |

`DATA/` is always preserved, `down` only removes containers/networks of the services.


## `restart`: Restart everything

| Section                   | What it does                                                                                                                           |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `[1] Preflight`           | Docker installed + engine running + Compose available + services discovered.                                                           |
| `[2] Restarting services` | For each service in startup order: `docker compose restart` **output intentionally shown** so you can follow per-container stop/start. |
| `[3] Resulting state`     | `docker compose ps` per service, so you see what ended up running.                                                                     |

## `recreate`: Force-recreate containers

> Use after changing a `compose.yaml` or a `.env` value, or after a fresh clone.
> Fresh containers from the **current** config; `DATA/` volumes are kept.

| Section                   | What it does                                                                                                                                                                                                                                                   |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[1] Docker & Compose`    | Hard check.                                                                                                                                                                                                                                                    |
| `[2]…[5]`                 | Shared provisioning (idempotent).                                                                                                                                                                                                                              |
| `[6] Pull`                | **Asks:** `N` = pull new images first, `E` = use images already on this machine (default). A pull failure is a warning, not a stop it recreates with existing images. Non-interactive runs default to `E` (they still read a piped answer if one is provided). |
| `[7] Recreating services` | `docker compose up -d --force-recreate` per service in startup order.                                                                                                                                                                                          |

## `status`: Lists what's running related to the services/containers

| Section           | What it does                                                                                                                                                                                                                                                                    |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (preflight, soft) | If Docker is missing or the engine is down it prints "Athena: not running" and exits **0** a query, not a failure.                                                                                                                                                              |
| (per service)     | `docker compose ps` for each service, plus its **published ports**, read from the running containers (`0.0.0.0` / `[::]` publishers count as localhost-reachable). Nothing is hardcoded.                                                                                        |
| `Port check`      | TCP-probes each published port on `localhost` (PowerShell: `Test-NetConnection`; bash: `/dev/tcp`) and reports `open` / `closed` with the owning service. **Requires `jq`** to read the JSON port list without it, this section is skipped gracefully and the rest still works. |

## `doctor`:  Sanity check

| Section                 | What it does                                                                                                                                                                                                                                      |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `[1] Docker`            | Engine running (with version) + Compose plugin.                                                                                                                                                                                                   |
| `[2] Per-service files` | For each discovered service: is `.env.example` present? Is `.env` present?                                                                                                                                                                        |
| `[3] DATA layout`       | `DATA/` root exists, and every per-service `DATA/<…>/` subdirectory (from the compose files) exists. A subdirectory owned by **root** is flagged `[OWN]` — non-root containers can't write there; fix with `sudo chown <you> DATA/<dir>`.           |
| `[4] Orphan containers` | Running containers whose compose **project** (via the `com.docker.compose.project` label) has no matching service directory i.e. the dir was deleted out from under them. Unrelated containers are never flagged. Suggests `docker rm -f <name>`. 

Ends with `All checks passed.` or `# issue(s) found. See above.`


## `deps`: Linux only

| Subcommand                    | What it does                                                                                                                                                                                         |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `./athena deps`               | Report: `docker` (CLI + engine + Compose), `jq` each `[OK]` or `[MISS]` with the exact install command for **your** distro (`apt`/`dnf`/`zypper`/`pacman`/`apk`), plus the detected package manager. |
| `./athena deps install <dep>` | Actually installs, but **only after you type `y`**. Runs as-is if root, via `sudo` if available, and tells you to re-run as root if neither exists. Never silent, never guessed.                     |

This is the **only distro-aware code** in the whole tree everything else is distro-neutral and simply asks this file for the right command.

  
## The shared library, section by section

### `athena-startup-order.ps1` (Windows) / `athena-lib.sh` (Linux)

| Block                       | What it does                                                                                                                                                                                         |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Paths**                   | Resolved from the file's own location, so the scripts work from any working directory: `ATHENA_REPO`, `ATHENA_COMPOSE`, `ATHENA_DATA` (`DATA/`, overridable via `ATHENA_DATA_DIR`), `ATHENA_ASSETS`. |
| **STARTUP ORDER (edit me)** | The one list that defines start order. Add a line = add a service to the ordered set.                                                                                                                |
| **Colors**                  | ANSI colors auto-disabled when stdout isn't a terminal or `NO_COLOR` is set (Linux). PowerShell uses `Write-Host -ForegroundColor` directly.                                                         |
| **Discovery**               | `Get-AthenaServiceDirs` / `athena_service_dirs` scans `compose/` for the four compose filenames, prints `section/name`.                                                                              |
| **Ordering**                | `Get-AthenaServices` / `athena_services` startup order (listed first, the rest alphabetical); `…Reversed` for stop order.                                                                            |
| **`.env` helpers**          | `Set-AthenaEnvFile` / `athena_env_set`, `Get-AthenaEnvValue` / `athena_env_get` read/write a single key in a `.env` file without clobbering the rest.                                                |
| **Secrets**                 | `Generate-AthenaSecurePassword` / `athena_gen_password` 64-hex, from `openssl rand -hex 32` with an `/dev/urandom` fallback (no openssl needed).                                                     |
| **Provisioning**            | `Ensure-AthenaProvision` / `athena_provision` the shared `[2]…[5]` block that `create`/`up`/`recreate` all reuse (DATA layout → `.env` → password → network).                                        |
| **Compose runner**          | `Invoke-AthenaCompose` / `athena_compose_run` `cd` into the service dir and run a compose command, returning its exit code.                                                                          |
| **Docker check**            | `Test-AthenaDocker` / `athena_docker_ok` CLI present + engine up + Compose plugin.                                                                                                                   |

## Adapting this as a base

  
1. **Add a service:** create `INFRASTRUCTURE/compose/<section>/<name>/` with a `compose.yaml` + `.env.example`. It's automatically discovered by every script.

2. **Change start order:** edit the order list in the shared library.

3. **Add a dependency:** add it to the `deps` report (Linux) nothing else needs to know.

4. **Change ports:** edit the service's `compose.yaml`; `status` picks up the real published ports automatically.

5. **Keep the conventions:** numbered `[#]` sections, `[OK]/[FAIL]/[SKIP]` lines, idempotency and "queries exit 0". Those are what make the scripts scriptable and the output greppable.