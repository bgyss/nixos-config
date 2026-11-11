#!/usr/bin/env bash
# Sourced helpers for the non-authoritative update state cache.
# State file: $UPDATE_STATE_FILE (default <repo>/.update-state.json).

: "${UPDATE_STATE_FILE:=}"
# NOTE: unlike executable scripts in this repo (e.g. check-overlay-versions.sh) that
# locate the repo root via dirname "${BASH_SOURCE[0]}", this file is *sourced* from
# varying locations by different callers, so it has no fixed on-disk path of its own
# to anchor from. `git rev-parse --show-toplevel` (falling back to $PWD outside a repo)
# is the intentional choice here.
_state_file() {
  if [[ -n "${UPDATE_STATE_FILE:-}" ]]; then printf '%s' "$UPDATE_STATE_FILE"; return; fi
  local dir; dir="$(git rev-parse --show-toplevel 2>/dev/null)" || dir="$PWD"
  printf '%s/.update-state.json' "$dir"
}

# True if the state file exists and is valid JSON; getters use this to degrade to
# "no known value" instead of letting jq abort a caller running under set -e.
_state_readable() {
  local f; f="$(_state_file)"
  [[ -f "$f" ]] && jq empty "$f" >/dev/null 2>&1
}

state_init() {
  local f; f="$(_state_file)"
  if [[ ! -f "$f" ]] || ! jq empty "$f" 2>/dev/null; then
    printf '{"overlays":{},"inputs":{},"last_gate":null}\n' > "$f"
  fi
}

_state_write() { # jq-filter args...
  local f tmp; f="$(_state_file)"; tmp="$(mktemp)"
  if jq "$@" "$f" > "$tmp"; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"
    return 1
  fi
}

state_get_overlay_known_latest() {
  _state_readable || { printf ''; return 0; }
  jq -r --arg n "$1" '.overlays[$n].known_latest // empty' "$(_state_file)"
}
state_set_overlay() {
  # MERGE into the existing entry, never replace it. Replacing dropped
  # `bumped_at`, and `prepare` runs this probe right after `bump-overlays` on
  # every scheduled run — so the cadence stamp was erased minutes after it was
  # written and per-package cadence_hours never gated anything (c4/hey-cli,
  # declared weekly, were bumped every day upstream moved).
  _state_write --arg n "$1" --arg v "$2" --arg t "$3" \
    '.overlays[$n] = ((.overlays[$n] // {}) + {known_latest:$v, checked_at:$t})'
}
# Last time a bump was ATTEMPTED for this package (success or failure). Drives
# per-package cadence gating in bump-overlays. Distinct from
# state_set_overlay's known_latest, which records what upstream is offering.
state_get_overlay_bumped_at() {
  _state_readable || { printf ''; return 0; }
  jq -r --arg n "$1" '.overlays[$n].bumped_at // empty' "$(_state_file)"
}
state_set_overlay_bumped_at() {
  _state_write --arg n "$1" --arg t "$2" '.overlays[$n].bumped_at = $t'
}
state_get_input_updated_at() {
  _state_readable || { printf ''; return 0; }
  jq -r --arg n "$1" '.inputs[$n].updated_at // empty' "$(_state_file)"
}
state_set_input_updated_at() {
  _state_write --arg n "$1" --arg t "$2" '.inputs[$n] = {updated_at:$t}'
}
state_set_last_gate() { _state_write --arg t "$1" '.last_gate = $t'; }

_state_lockfile() { printf '%s.lock' "$(_state_file)"; }
# The lock is a directory (mkdir is atomic) holding the owner's pid. Without
# the pid a run that died uncleanly (SIGKILL, power loss, a reboot mid-build)
# left the directory behind forever, and since callers treat contention as a
# benign, SILENT exit 2, every later scheduled run quietly did nothing.
# A lock is stale — and reclaimed — when its owner pid is no longer running,
# or when it carries no pid and is older than STATE_LOCK_STALE_MINUTES (a lock
# from before pids were recorded, or a crash between mkdir and the pid write).
: "${STATE_LOCK_STALE_MINUTES:=360}"
_state_lock_is_stale() { # <lockdir>
  local d="$1" pid
  pid="$(cat "$d/pid" 2>/dev/null)"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill -0 "$pid" 2>/dev/null && return 1   # owner alive -> genuinely held
    return 0
  fi
  [[ -n "$(find "$d" -maxdepth 0 -mmin "+${STATE_LOCK_STALE_MINUTES}" 2>/dev/null)" ]]
}
state_lock() {
  local d; d="$(_state_lockfile).d"
  if ! mkdir "$d" 2>/dev/null; then
    _state_lock_is_stale "$d" || return 1
    echo "state_lock: reclaiming stale lock $d (owner pid '$(cat "$d/pid" 2>/dev/null)' is gone)" >&2
    rm -f "$d/pid"
    rmdir "$d" 2>/dev/null
    mkdir "$d" 2>/dev/null || return 1   # lost a reclaim race to another run
  fi
  # $$ is the top-level script's pid even inside a subshell, i.e. the process
  # whose EXIT trap will call state_unlock.
  printf '%s\n' "$$" > "$d/pid"
}
state_unlock() {
  local d; d="$(_state_lockfile).d"
  rm -f "$d/pid" 2>/dev/null
  rmdir "$d" 2>/dev/null || true
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
