# athena-lib.sh — shared config + discovery for the athena-*.sh scripts (Linux).
#
#   This is the ONE file you edit when Athena grows.
#   Every command script dot-sources it:
#       SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#       . "$SCRIPT_DIR/athena-lib.sh"
#
#   DISCOVERY is automatic: every compose/<section>/<name> directory that
#   contains compose.yaml / compose.yml / docker-compose.yaml / docker-compose.yml
#   counts as a service. Placeholders without a compose file are ignored.
#
#   ORDER: services in ATHENA_ORDER start in that exact order; anything not
#   listed is still discovered and starts LAST (alphabetical).

# --- Paths (resolved from this file's location) ---
ATHENA_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATHENA_INFRA="$(dirname "$ATHENA_SCRIPTS")"
ATHENA_REPO="$(dirname "$ATHENA_INFRA")"
ATHENA_COMPOSE="$ATHENA_INFRA/compose"
ATHENA_DATA="${ATHENA_DATA_DIR:-$ATHENA_REPO/DATA}"
ATHENA_ASSETS="${ATHENA_ASSETS_DIR:-$ATHENA_DATA/media}"

# --- STARTUP ORDER (edit me) ---
ATHENA_ORDER=(
  "edge/tailscale"      # edge / network first
  "edge/caddy"
  "databases/surrealdb" # databases before the apps that use them
  "ai/opennotebook"     # apps last
)

# --- Colors (auto-off when not a tty or NO_COLOR set) ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_CYAN=$'\033[36m'; C_YELLOW=$'\033[33m'; C_GREEN=$'\033[32m'
  C_RED=$'\033[31m';  C_DIM=$'\033[2m';     C_OFF=$'\033[0m'
else
  C_CYAN=""; C_YELLOW=""; C_GREEN=""; C_RED=""; C_DIM=""; C_OFF=""
fi

# --- Discovery helpers ---

athena_service_dirs() {
  # Every dir under compose/ holding one of the four compose filenames,
  # printed as section/name (sorted, unique). Empty output when none.
  [ -d "$ATHENA_COMPOSE" ] || return 0
  find "$ATHENA_COMPOSE" -type f \
       \( -name compose.yaml -o -name compose.yml \
          -o -name docker-compose.yaml -o -name docker-compose.yml \) -print 2>/dev/null \
    | sed "s|^$ATHENA_COMPOSE/||" \
    | awk -F/ 'NF >= 2 {print $1"/"$2}' \
    | sort -u
}

athena_services() {
  # Discovered services in startup order: ATHENA_ORDER first, the rest after (alpha).
  local found=() ordered=() svc
  mapfile -t found < <(athena_service_dirs)
  for svc in "${ATHENA_ORDER[@]}"; do
    [[ " ${found[*]-} " == *" $svc "* ]] && ordered+=("$svc")
  done
  for svc in "${found[@]-}"; do
    [[ " ${ordered[*]-} " == *" $svc "* ]] || ordered+=("$svc")
  done
  (( ${#ordered[@]} )) && printf '%s\n' "${ordered[@]}"
  return 0
}

athena_services_reversed() {
  # Stop order = startup order reversed (apps first, network last).
  local all=() i
  mapfile -t all < <(athena_services)
  for ((i=${#all[@]}-1; i>=0; i--)); do printf '%s\n' "${all[$i]}"; done
}

# --- .env helpers ---

athena_env_set() { # <envfile> <key> <value> — set (replace first match) or append
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${val}|" "$file" > "$tmp"
  else
    [ -f "$file" ] && cp "$file" "$tmp" || : > "$tmp"
    printf '%s\n' "${key}=${val}" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

athena_env_get() { # <envfile> <key> — value of first KEY=... line, '' if absent
  local file="$1" key="$2" line
  [ -f "$file" ] || return 0
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | head -n1)"
  [ -n "$line" ] || return 0
  printf '%s\n' "${line#*=}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# --- Secrets ---

athena_gen_password() {
  # 32 random bytes as 64 hex chars. openssl preferred; /dev/urandom + od fallback.
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | od -An -v -tx1 | tr -d ' \n'
  fi
}

# --- Docker ---

athena_docker_ok() { # 0 when engine AND compose plugin are usable
  command -v docker >/dev/null 2>&1 || return 1
  docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1
}

athena_compose_run() { # <servicedir> <compose-args...> — suppressed output, returns docker's rc
  local dir="$1"; shift
  ( cd "$dir" && docker "$@" >/dev/null 2>&1 )
}

# --- Dependency hints (distro-aware; the ONLY place package names are spelled out) ---
# Shared here (lib) so BOTH athena-deps.sh and the command scripts can build
# install hints. `detect_pkg_manager`/`pkg_name` are the single source of truth
# for per-distro package names — edit ONE function to support a new distro.

detect_pkg_manager() { # first available manager wins; 'none' if no known one
  local mgr
  if   command -v apt-get >/dev/null 2>&1; then mgr=apt
  elif command -v dnf     >/dev/null 2>&1; then mgr=dnf
  elif command -v yum     >/dev/null 2>&1; then mgr=yum
  elif command -v zypper  >/dev/null 2>&1; then mgr=zypper
  elif command -v pacman  >/dev/null 2>&1; then mgr=pacman
  elif command -v apk     >/dev/null 2>&1; then mgr=apk
  else mgr=none; fi
  # apt-get (Debian/Ubuntu) and apt (Arch) both map to the 'apt' recipe.
  echo "$mgr"
}

pkg_name() { # <manager> <dep> → package name(s) for that manager
  case "$1/$2" in
    apt/docker)                 echo "docker.io docker-compose-plugin" ;;
    apk/docker)                 echo "docker docker-compose" ;;
    dnf/docker|yum/docker)      echo "docker-ce docker-compose-plugin" ;;
    zypper/docker)              echo "docker docker-compose" ;;
    pacman/docker)              echo "docker docker-compose" ;;
    */jq)                       echo "jq" ;;
    */bash)                     echo "bash" ;;
    *)                          echo "$2" ;;
  esac
}

athena_pkg_hint() { # <dep> → exact install command string, '' when no known package manager
  local mgr name
  mgr="$(detect_pkg_manager)"
  [ "$mgr" = "none" ] && return 0
  name="$(pkg_name "$mgr" "$1")"
  case "$mgr" in
    apt)     echo "sudo apt-get update && sudo apt-get install -y $name" ;;
    dnf|yum) echo "sudo $mgr install -y $name" ;;
    zypper)  echo "sudo zypper install -y $name" ;;
    pacman)  echo "sudo pacman -Sy --noconfirm $name" ;;
    apk)     echo "sudo apk add --no-cache $name" ;;
  esac
}

athena_install_hint() { # <dep> — the exact install command, or a manual note
  local dep="$1" hint
  hint="$(athena_pkg_hint "$dep")"
  if [ -n "$hint" ]; then
    echo "    Install:  $hint"
    echo "    or:       ./athena deps install $dep"
  else
    echo "    No known package manager — install '$dep' manually (docker: https://docs.docker.com/engine/install/), then re-run."
  fi
}

# --- Shared provisioning (idempotent): DATA root, .env seeding, shared password, network ---
# No images, no containers. Honors ATHENA_DATA_DIR / ATHENA_ASSETS_DIR.

athena_provision() {
  local services=("$@") svc svc_dir env_file example created=0
  local -A ENV_FILES=()

  echo "  ${C_YELLOW}[2] DATA layout${C_OFF}"
  [ -d "$ATHENA_DATA" ]   || { mkdir -p "$ATHENA_DATA";   created=1; }
  [ -d "$ATHENA_ASSETS" ] || { mkdir -p "$ATHENA_ASSETS"; created=1; }
  if [ "$created" -gt 0 ]; then
    echo "    ${C_GREEN}[OK] Created DATA/ root + media/ under: $ATHENA_DATA${C_OFF}"
  else
    echo "    ${C_GREEN}[OK] DATA/ layout present: $ATHENA_DATA${C_OFF}"
  fi

  echo ""
  echo "  ${C_YELLOW}[3] Per-service .env files${C_OFF}"
  for svc in "${services[@]-}"; do
    svc_dir="$ATHENA_COMPOSE/$svc"
    env_file="$svc_dir/.env"
    example="$svc_dir/.env.example"
    if [ ! -f "$env_file" ]; then
      if [ -f "$example" ]; then cp "$example" "$env_file"; else : > "$env_file"; fi
      echo "    ${C_GREEN}[OK] $svc  created${C_OFF}"
    else
      echo "    ${C_GREEN}[OK] $svc  exists${C_OFF}"
    fi
    ENV_FILES[$svc]="$env_file"
  done

  echo ""
  echo "  ${C_YELLOW}[4] Shared SurrealDB password${C_OFF}"
  local has_surreal=0 has_notebook=0
  case " ${services[*]-} " in *" databases/surrealdb "*) has_surreal=1  ;; esac
  case " ${services[*]-} " in *" ai/opennotebook "*)     has_notebook=1 ;; esac
  if [ "$has_surreal" -eq 0 ] && [ "$has_notebook" -eq 0 ]; then
    echo "    ${C_DIM}[SKIP] surrealdb not in stack${C_OFF}"
  else
    local surreal_env="" notebook_env="" existing="" is_placeholder=1 shared_pass synced=0
    [ "$has_surreal" -eq 1 ]  && surreal_env="${ENV_FILES[databases/surrealdb]-}"
    [ "$has_notebook" -eq 1 ] && notebook_env="${ENV_FILES[ai/opennotebook]-}"
    [ -n "$surreal_env" ] && existing="$(athena_env_get "$surreal_env" SURREAL_PASSWORD)"
    if [ -n "$existing" ]; then
      case "$existing" in '#'*) : ;; *) is_placeholder=0 ;; esac
      if [ "$is_placeholder" -eq 0 ]; then
        case "$existing" in *REQUIRED*|*CHANGE*|*YOUR*PASSWORD*) is_placeholder=1 ;; esac
      fi
      [ "${#existing}" -ge 16 ] || is_placeholder=1
    fi
    if [ "$is_placeholder" -eq 0 ]; then
      shared_pass="$existing"
      echo "    ${C_GREEN}[OK] Reusing existing password (surrealdb/.env)${C_OFF}"
    else
      shared_pass="$(athena_gen_password)"
      echo "    ${C_GREEN}[OK] Generated new shared password${C_OFF}"
    fi
    if [ -n "$surreal_env" ];  then athena_env_set "$surreal_env"  SURREAL_PASSWORD "$shared_pass"; synced=$((synced+1)); fi
    if [ -n "$notebook_env" ]; then athena_env_set "$notebook_env" SURREAL_PASSWORD "$shared_pass"; synced=$((synced+1)); fi
    echo "    ${C_GREEN}[OK] Synchronized to $synced .env files${C_OFF}"
  fi

  echo ""
  echo "  ${C_YELLOW}[5] Docker network${C_OFF}"
  local network="athena"
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx "$network"; then
    echo "    ${C_GREEN}[OK] Network '$network' already exists${C_OFF}"
  else
    docker network create --driver bridge "$network" >/dev/null 2>&1
    echo "    ${C_GREEN}[OK] Created network: $network${C_OFF}"
  fi
  return 0
}
