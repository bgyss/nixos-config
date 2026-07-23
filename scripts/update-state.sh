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
  _state_write --arg n "$1" --arg v "$2" --arg t "$3" \
    '.overlays[$n] = {known_latest:$v, checked_at:$t}'
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
state_lock() {
  local d; d="$(_state_lockfile).d"
  mkdir "$d" 2>/dev/null   # atomic; fails if held
}
state_unlock() {
  local d; d="$(_state_lockfile).d"
  rmdir "$d" 2>/dev/null || true
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
