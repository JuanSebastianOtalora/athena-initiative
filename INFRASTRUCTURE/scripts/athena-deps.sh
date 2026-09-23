#!/usr/bin/env bash
# athena-deps.sh — dependency detection & bootstrap (THE distro-aware layer).
#
#   ./athena deps                  report: docker, compose plugin, jq + hints
#   ./athena deps install <dep>    interactive install (explicit "y" consent)
#
#   Distro-neutral scripts never hardcode apt/apk/dnf — they ask this file
#   for the right command and show it. Nothing is ever installed silently.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/athena-lib.sh"
# (detect_pkg_manager / pkg_name / athena_pkg_hint come from athena-lib.sh —
#  the single source of truth for per-distro package names.)

# as-is if root, else via sudo (never silent; never guessed)
run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else echo "    (not root and no sudo — re-run as root)"; return 126; fi
}

install_dep() { # <dep> — actually install (caller already got consent)
  local dep="$1" mgr names=() name
  mgr="$(detect_pkg_manager)"
  [ "$mgr" = "none" ] && { echo "    [FAIL] no package manager found"; return 1; }
  read -ra names <<< "$(pkg_name "$mgr" "$dep")"
  case "$mgr" in
    apt)     run_privileged apt-get update && run_privileged apt-get install -y "${names[@]}" ;;
    dnf|yum) run_privileged "$mgr" install -y "${names[@]}" ;;
    zypper)  run_privileged zypper install -y "${names[@]}" ;;
    pacman)  run_privileged pacman -Sy --noconfirm "${names[@]}" ;;
    apk)     run_privileged apk add --no-cache "${names[@]}" ;;
  esac
}

dep_status() { # <dep> → 0 present / 1 missing (docker = CLI + engine + compose plugin)
  case "$1" in
    docker) command -v docker >/dev/null 2>&1 \
            && docker version --format '{{.Server.Version}}' >/dev/null 2>&1 \
            && docker compose version >/dev/null 2>&1 ;;
    *)      command -v "$1" >/dev/null 2>&1 ;;
  esac
}

ensure_dep() { # <dep> — report+hint if missing; interactive install only with consent. 0 = available.
  local dep="$1" hint ans
  dep_status "$dep" && return 0
  echo "    ${C_RED}[MISS] $dep is not available.${C_OFF}"
  hint="$(athena_pkg_hint "$dep")"
  if [ -z "$hint" ]; then
    echo "    No known package manager. Install '$dep' manually, then re-run."
    return 1
  fi
  echo "    Install with:  $hint"
  if [ -t 0 ]; then
    read -r -p "    Install now? [y/N] " ans || ans=""
    case "$ans" in
      y|Y|yes|YES|Yes)
        if install_dep "$dep"; then echo "    ${C_GREEN}[OK] $dep installed${C_OFF}"; return 0
        else echo "    ${C_RED}[FAIL] install of $dep failed${C_OFF}"; return 1; fi ;;
    esac
  fi
  echo "    ${C_DIM}[SKIP] declined (or non-interactive)${C_OFF}"
  return 1
}

# --- CLI ---
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  MODE="${1:-report}"; [ $# -gt 0 ] && shift
  case "$MODE" in
    report)
      echo ""
      echo "  ${C_CYAN}Athena - dependencies${C_OFF}"
      echo ""
      hint=""
      for dep in docker jq; do
        if dep_status "$dep"; then
          echo "    [OK]   $dep"
        else
          echo "    [MISS] $dep"
          hint="$(athena_pkg_hint "$dep")"
          [ -n "$hint" ] && echo "           install: $hint"
          echo "           or:      ./athena deps install $dep"
        fi
      done
      echo "    package manager: $(detect_pkg_manager)"
      echo ""
      ;;
    install)
      [ $# -gt 0 ] || { echo "usage: ./athena deps install <dep...>   (docker | jq)"; exit 2; }
      echo ""
      echo "  ${C_CYAN}Athena - install dependencies${C_OFF}"
      echo ""
      for dep in "$@"; do
        if dep_status "$dep"; then
          echo "    [OK]   $dep already present"
        else
          ensure_dep "$dep"
        fi
      done
      echo ""
      ;;
    *)
      echo "usage: ./athena deps [install <dep...>]"; exit 2 ;;
  esac
fi
