# Deployment (Windows & Linux)

  
Deploy the Athena stack on **Windows** or on **any Linux distribution** (Debian, Ubuntu, Alpine, Fedora, Arch including minimal installs).

## Before you start: which scripts are which?

This repository ships the **same stack manager in two languages**, so it works natively wherever you are:
  
| Script                                               | What it is                                                                                                                                 | Runs on                                                                        |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `athena.ps1` + `INFRASTRUCTURE/scripts/athena-*.ps1` | **PowerShell** the scripting language built into Windows. PowerShell is a full shell (like `bash`) that ships with Windows out of the box. | Windows                                                                        |
| `athena` + `INFRASTRUCTURE/scripts/athena-*.sh`      | **Bash** the standard shell on Linux and macOS. Bash is pre-installed on essentially every Linux distro.                                   | Linux / macOS (also runs in [git-bash](https://gitforwindows.org/) on Windows) |

Both families do **exactly the same things** same commands, same output layout, same exit codes. Pick the one that matches your OS; you never need both at once.

**What the stack gives you:** Tailscale (private network), Caddy (web gateway), SurrealDB (database) and Open Notebook (the AI notebook), all connected on a shared `athena` docker network with their data persisted under `DATA/`.

  
## Prerequisites (both platforms)

- **Docker Engine 24+ with the Compose plugin** the only hard requirement.

- Windows: [Docker Desktop](https://www.docker.com/products/docker-desktop/) *if you are running 21H2 or a similar non supported win version for docker try changing windows version through regedit* , or Docker Engine on WSL2.

- Linux: your distro's `docker` + `docker compose` packages (e.g. `apt install docker.io docker-compose-v2` on Debian/Ubuntu).

- ~4 GB free RAM, ~2 GB free disk (minimal tier).

- **`jq`**a tiny JSON tool, used by `athena status` to list published ports.

**Optional**: every command works without it; `status` just skips the port check.

  
### Installing `jq`

| Platform             | Command                                          |
| -------------------- | ------------------------------------------------ |
| Windows (winget)     | `winget install jqlang.jq`                       |
| Windows (Chocolatey) | `choco install jq`                               |
| Debian / Ubuntu      | `sudo apt-get update && sudo apt-get install jq` |
| Fedora               | `sudo dnf install jq`                            |
| Arch                 | `sudo pacman -S jq`                              |
| Alpine               | `sudo apk add jq`                                |

Or let the scripts do it for you (only if you're on Linux, and it always asks before installing): `./athena deps install jq`.

## Deployment command by command

The table below is the full deployment lifecycle. **Left column = Windows (PowerShell), right column = Linux (bash).** Use the rows in order for a fresh machine.

| Step                       | Windows (PowerShell)                       | Linux (bash)                                             | What it does                                                                                                                                                                                |
| -------------------------- | ------------------------------------------ | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Get the repo            | `git clone <repo> athena` <br> `cd athena` | same                                                     | Clone the repository and enter it.                                                                                                                                                          |
| 2. Docker check            | `.\athena.ps1 doctor`                      | `./athena doctor`                                        | Verify Docker engine, Compose plugin, service files and `DATA/` layout.                                                                                                                     |
| 3. Install `jq` (optional) | `winget install jqlang.jq`                 | see *Installing jq* above, or `./athena deps install jq` | Enables the port check in `status`.                                                                                                                                                         |
| 4. Create workspace        | `.\athena.ps1 create`                      | `./athena create`                                        | Provision `DATA/`, per-service `.env` files (from `.env.example`), generate the shared SurrealDB password, create the `athena` network. **No containers start.** Idempotent safe to re-run. |
| 5. Start the stack         | `.\athena.ps1 up`                          | `./athena up`                                            | Start all services in dependency order: `tailscale → caddy → surrealdb → opennotebook`. Pulls no images (uses what's on the machine). Idempotent.                                           |
| 6. See what's running      | `.\athena.ps1 status`                      | `./athena status`                                        | Per-service container state + published ports (needs `jq` for the port check).                                                                                                              |
| 7. Sanity check            | `.\athena.ps1 doctor`                      | `./athena doctor`                                        | Docker, `.env` files, `DATA/` layout, orphaned containers.                                                                                                                                  |
| 8. Apply config changes    | `.\athena.ps1 recreate`                    | `./athena recreate`                                      | Force-recreate containers from the current `compose.yaml` + `.env` (keeps `DATA/`). Asks whether to `pull` new images first (default: no).                                                  |
| 9. Restart                 | `.\athena.ps1 restart`                     | `./athena restart`                                       | Restart every service in dependency order, then show the resulting state.                                                                                                                   |
| 10. Stop the stack         | `.\athena.ps1 down`                        | `./athena down`                                          | Stop services in reverse order (apps first, network last). **`DATA/` is preserved.**                                                                                                        |

### Quick start (copy-paste)

**Windows:** 

```powershell

git clone <repo> athena

cd athena

.\athena.ps1 create

.\athena.ps1 up

.\athena.ps1 status

```

  
**Linux:**

```bash

git clone <repo> athena

cd athena

./athena create

./athena up

./athena status

```
  

## Where do I find my services?

After `up`, the published ports (as reported by `./athena status`) are typically:

  
| Service         | Default port            |
| --------------- | ----------------------- |
| Open Notebook   | 8502 (per compose file) |
| SurrealDB       | 8000 (per compose file) |
| Caddy (gateway) | 80 / 443                |

`./athena status` reads the *actual* published ports from the running containers nothing is hardcoded so it always reflects your real configuration.

## Adding a custom service

Drop a new `INFRASTRUCTURE/compose/<section>/<name>/compose.yaml` and it's discovered automatically — no script edits. For its data to be pre-created and owned by you (so non-root containers can write), mount it under the data root: `${ATHENA_DATA_DIR:-./DATA}/<name>`. A host path outside that root is *not* auto-created — create and chown it yourself before the first `up`. If a container later fails with `PermissionDenied`, `./athena doctor` flags the root-owned dir and tells you the `chown` fix.

## Troubleshooting

| Symptom                                     | Try                                                                                                                                                           |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Docker / Compose not available`            | Start Docker Desktop (Windows) or the `docker` service (Linux: `sudo systemctl start docker`), then re-run.                                                   |
| `status` says `jq not found`                | Install `jq` (above). Everything else still works.                                                                                                            |
| `./athena` fails with garbled text on Linux | Your checkout has CRLF line endings. Fix: `dos2unix athena INFRASTRUCTURE/scripts/*.sh` (or re-clone; `.gitattributes` now enforces LF).                      |
| `surrealdb` restarts with `PermissionDenied`  | `DATA/databases/surrealdb` is root-owned (Docker's root daemon created it). Fix: `sudo chown <you> DATA/databases/surrealdb`, then `docker restart athena-surrealdb`. `./athena doctor` flags this as `[OWN]`. `                    |
| A port is already in use                    | Another process owns it. `./athena status` shows which service publishes it; stop the conflicting process or change the port in the service's `compose.yaml`. |
| Something feels wrong                       | `./athena doctor` it lists every issue it finds and how to fix it.                                                                                            |

## Day-2 operations

For backups, single-service management and other day-2 tasks see [operations.md](operations.md). For an explanation of what each script does section by section (useful if you want to adapt it as a base), see [scripts-reference.md](scripts-reference.md).