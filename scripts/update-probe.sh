#!/usr/bin/env bash
# Sourced probe library. Requires update-state.sh already sourced.
# Not `set -e`/`set -u` here: this file is sourced into a caller's shell (or the
# test harness), and imposing strict mode here would change the calling shell's
# behavior — same rationale as scripts/update-state.sh.
: "${UPDATE_MANIFEST:=}"
_manifest() {
  if [[ -n "${UPDATE_MANIFEST:-}" ]]; then printf '%s' "$UPDATE_MANIFEST"; return; fi
  local d; d="$(git rev-parse --show-toplevel 2>/dev/null)" || d="$PWD"
  printf '%s/overlays/updates.json' "$d"
}

# iso8601 -> epoch seconds (GNU date -d or BSD date -j)
_iso_to_epoch() {
  local s="$1"
  date -u -d "$s" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$s" +%s 2>/dev/null
}

input_is_frozen() {
  local n="$1" m; m="$(_manifest)"
  # Fail CLOSED: if the manifest can't be read/parsed, treat the input as frozen
  # rather than "not found in pinned_inputs" (which would look identical to a
  # genuinely-unfrozen input and risk auto-updating something like nixpkgs that
  # is frozen for a real reason).
  [[ -r "$m" ]] || return 0
  jq empty "$m" >/dev/null 2>&1 || return 0
  jq -e --arg n "$n" '(.pinned_inputs // []) | any(.name==$n)' "$m" >/dev/null
}

input_is_due() { # <name> <now_epoch>
  local n="$1" now="$2"
  # Frozen check MUST come first: a frozen input (pinned_inputs[]) is never due,
  # regardless of cadence/on_demand config — nixpkgs is frozen here due to a real
  # CVE-related OOM bug, and auto-updating it would be a real regression.
  input_is_frozen "$n" && return 1
  local ondemand cadence
  ondemand="$(jq -r --arg n "$n" '.inputs[$n].on_demand // false' "$(_manifest)")"
  [[ "$ondemand" == "true" ]] && return 1
  cadence="$(jq -r --arg n "$n" '.inputs[$n].cadence_hours // 24' "$(_manifest)")"
  [[ "$cadence" == "0" ]] && return 1
  local last; last="$(state_get_input_updated_at "$n")"
  [[ -z "$last" ]] && return 0            # never updated -> due
  local last_e; last_e="$(_iso_to_epoch "$last")"
  [[ -z "$last_e" ]] && return 0
  (( now >= last_e + cadence * 3600 ))
}

probe_overlays() {
  local repo; repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  local json; json="$("$repo/scripts/check-overlay-versions.sh" --json 2>/dev/null || true)"
  [[ -z "$json" ]] && { printf ''; return 0; }
  # record known_latest for successfully-probed overlays
  while IFS=$'\t' read -r name latest; do
    [[ -n "$name" ]] && state_set_overlay "$name" "$latest" "$(now_iso)"
  done < <(echo "$json" | jq -r '.[] | select(.status=="OK" or .status=="OUTDATED") | "\(.name)\t\(.latest)"')
  echo "$json" | jq -r '[.[] | select(.outdated) | .name] | join(",")'
}

# Upstream ref of a github input (locked in flake.lock). Best-effort.
# Safety principle: a probe FAILURE must never cause a spurious update. Every
# failure path below returns 1 ("not moved"), not 0 — a due-but-unmoved input
# is simply retried on the next run once the probe succeeds; that's the safe
# failure mode, not "assume moved and let apply-mode fetch/lock proceed".
_input_upstream_moved() { # <name>  -> exit 0 only if confirmed moved
  local n="$1" repo; repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  local meta; meta="$(nix flake metadata "$repo" --json 2>/dev/null)" || return 1
  local node owner name rev branch
  node="$(echo "$meta" | jq -r --arg n "$n" '.locks.nodes[$n].locked // empty')"
  [[ -z "$node" ]] && return 1
  [[ "$(echo "$node" | jq -r '.type // ""')" == "github" ]] || return 1
  owner="$(echo "$node" | jq -r '.owner')"; name="$(echo "$node" | jq -r '.repo')"
  rev="$(echo "$node" | jq -r '.rev')"; branch="$(echo "$node" | jq -r '.ref // "HEAD"')"
  local head
  head="$(curl -sf --max-time 15 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$owner/$name/commits/$branch" 2>/dev/null \
    | jq -r '.sha // empty')" || return 1
  [[ -z "$head" ]] && return 1            # probe failed -> not confirmed moved -> no update
  [[ "$head" != "$rev" ]]
}

probe_flake_inputs() { # mode: report|apply
  local mode="${1:-report}" repo now updated=()
  repo="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  now="$(date -u +%s)"
  local inputs
  inputs="$(jq -r '(.inputs // {}) | keys[]' "$(_manifest)")"
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    input_is_due "$n" "$now" || continue
    _input_upstream_moved "$n" || continue
    if [[ "$mode" == "apply" ]]; then
      # Only reset the cadence clock when the lock command actually succeeds;
      # a failure (network, auth, etc.) must leave state untouched so the
      # input is retried next run instead of silently going quiet for a full
      # cadence period.
      if nix flake lock "$repo" --update-input "$n" >/dev/null 2>&1; then
        state_set_input_updated_at "$n" "$(now_iso)"
      else
        continue
      fi
    fi
    updated+=("$n")
  done <<< "$inputs"
  (IFS=,; echo "${updated[*]:-}")
}

# Decision gate for `prepare`: build only if something real changed.
# exit 0 (build) if either list is non-empty.
gate_should_build() { [[ -n "${1:-}" || -n "${2:-}" ]]; }
