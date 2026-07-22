#!/usr/bin/env bash
# Shared helpers for the darwin apps. Sourced, not executed.
# Removes the repo-location logic that used to be copy-pasted into
# fix-hashes / update (F6 in docs/config-survey-2026-07.md).

# Colors (only when stdout is a tty).
if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_NC='\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_NC=''
fi

msg()  { echo -e "${C_GREEN}$*${C_NC}"; }
warn() { echo -e "${C_YELLOW}$*${C_NC}"; }
err()  { echo -e "${C_RED}$*${C_NC}" >&2; }

# The apps run from a read-only Nix store path, so find the actual mutable repo.
# Try the nix registry first (set up by this config), then git.
locate_flake() {
  local dir=""
  if dir=$(nix registry list 2>/dev/null | awk '/flake:nixos-config/ {gsub(/^path:/, "", $3); print $3; exit}') && [[ -n "$dir" ]]; then
    printf '%s' "$dir"; return 0
  fi
  if dir=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -f "$dir/flake.nix" ]]; then
    printf '%s' "$dir"; return 0
  fi
  err "cannot locate nixos-config repo. Register it with:"
  err "  nix registry add nixos-config path:/path/to/nixos-config"
  return 1
}

# The flake attribute for the live host's built system (used by sourcing scripts).
# shellcheck disable=SC2034
FLAKE_SYSTEM_ATTR="darwinConfigurations.garmonbozia.system"
