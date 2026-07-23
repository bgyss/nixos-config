#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export UPDATE_STATE_FILE="$(mktemp)"; rm -f "$UPDATE_STATE_FILE"
export UPDATE_MANIFEST="$(mktemp)"
cat > "$UPDATE_MANIFEST" <<'JSON'
{ "packages": [], "skip": [],
  "pinned_inputs": [ { "name": "nixpkgs" } ],
  "inputs": { "nixpkgs": {"cadence_hours":168},
              "codex": {"cadence_hours":24},
              "secrets": {"cadence_hours":0,"on_demand":true},
              "zerocadence": {"cadence_hours":0} } }
JSON
source "$REPO/scripts/update-state.sh"; state_init
source "$REPO/scripts/update-probe.sh"

# iso8601 timestamp for "$1" seconds before now (portable GNU/BSD date)
iso_before() {
  local delta="$1"
  date -u -r $((NOW-delta)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d @$((NOW-delta)) +%Y-%m-%dT%H:%M:%SZ
}
iso_of_epoch() {
  local e="$1"
  date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d @"$e" +%Y-%m-%dT%H:%M:%SZ
}

NOW=$(date -u +%s)

# nixpkgs is frozen -> never due
input_is_frozen nixpkgs || { echo "FAIL: nixpkgs should be frozen"; exit 1; }
input_is_due nixpkgs "$NOW" && { echo "FAIL: frozen input due"; exit 1; }

# secrets on_demand -> never due
input_is_due secrets "$NOW" && { echo "FAIL: on_demand due"; exit 1; }

# codex never updated -> due
input_is_due codex "$NOW" || { echo "FAIL: fresh codex should be due"; exit 1; }

# codex updated 1h ago, cadence 24h -> NOT due
state_set_input_updated_at codex "$(iso_before 3600)"
input_is_due codex "$NOW" && { echo "FAIL: codex within cadence marked due"; exit 1; }

# codex updated 25h ago -> due
state_set_input_updated_at codex "$(iso_before 90000)"
input_is_due codex "$NOW" || { echo "FAIL: codex past cadence not due"; exit 1; }

# --- Minor gap 1: exact cadence boundary (now == last_e + cadence*3600) ---
BOUNDARY_LAST=$((NOW - 24*3600))
state_set_input_updated_at codex "$(iso_of_epoch "$BOUNDARY_LAST")"
input_is_due codex "$NOW" || { echo "FAIL: codex exactly at cadence boundary should be due (>=)"; exit 1; }

# --- Minor gap 2: cadence_hours:0 WITHOUT on_demand must independently short-circuit ---
input_is_due zerocadence "$NOW" && { echo "FAIL: cadence_hours:0 (no on_demand) should never be due"; exit 1; }

# ==========================================================================
# Critical fix regression coverage: a probe FAILURE must never look like
# "moved"/"safe to update" — it must resolve to "not moved" / no update.
# ==========================================================================

# input_is_frozen fails CLOSED (treated as frozen) when the manifest is unreadable.
BAD_MANIFEST="$(mktemp -u)"   # deliberately does not exist
( export UPDATE_MANIFEST="$BAD_MANIFEST"
  source "$REPO/scripts/update-probe.sh"
  input_is_frozen anything || { echo "FAIL: unreadable manifest should fail closed (frozen)"; exit 1; }
) || exit 1

# input_is_frozen fails CLOSED when the manifest is present but invalid JSON.
BAD_JSON="$(mktemp)"
printf 'not json{{{' > "$BAD_JSON"
( export UPDATE_MANIFEST="$BAD_JSON"
  source "$REPO/scripts/update-probe.sh"
  input_is_frozen anything || { echo "FAIL: invalid-JSON manifest should fail closed (frozen)"; exit 1; }
) || exit 1
rm -f "$BAD_JSON"

# _input_upstream_moved: a probe failure (no flake here, so `nix flake metadata`
# / lock-node lookup fails) must resolve to "not moved" (exit 1), never "moved".
FAKEDIR="$(mktemp -d)"
( cd "$FAKEDIR"
  source "$REPO/scripts/update-state.sh"
  source "$REPO/scripts/update-probe.sh"
  if _input_upstream_moved "definitely-not-a-real-input"; then
    echo "FAIL: upstream-probe failure must not report 'moved'"; exit 1
  fi
) || exit 1
rm -rf "$FAKEDIR"

# probe_flake_inputs apply mode: if `nix flake lock` itself fails, the cadence
# clock (updated_at) must be left untouched, and the input must not appear in
# the returned "updated" list.
STUBDIR="$(mktemp -d)"
cat > "$STUBDIR/nix" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$STUBDIR/nix"
(
  export UPDATE_STATE_FILE UPDATE_MANIFEST
  export PATH="$STUBDIR:$PATH"
  source "$REPO/scripts/update-state.sh"
  source "$REPO/scripts/update-probe.sh"
  # Force "moved" so we actually reach the nix-lock call (isolates the
  # apply-mode failure-handling behavior from the upstream-probe check).
  _input_upstream_moved() { return 0; }
  before="$(state_get_input_updated_at codex)"
  out="$(probe_flake_inputs apply)"
  after="$(state_get_input_updated_at codex)"
  if [[ "$out" == *"codex"* ]]; then
    echo "FAIL: codex should not be reported updated when nix flake lock fails"; exit 1
  fi
  if [[ "$after" != "$before" ]]; then
    echo "FAIL: updated_at must be untouched when nix flake lock fails"; exit 1
  fi
)
STUB_STATUS=$?
rm -rf "$STUBDIR"
[[ $STUB_STATUS -eq 0 ]] || exit 1

echo "PASS: test_probe_inputs"
