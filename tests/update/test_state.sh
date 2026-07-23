#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export UPDATE_STATE_FILE="$(mktemp)"
rm -f "$UPDATE_STATE_FILE"   # start absent
source "$REPO/scripts/update-state.sh"

# init creates a valid skeleton
state_init
jq -e '.overlays and .inputs' "$UPDATE_STATE_FILE" >/dev/null || { echo "FAIL: skeleton"; exit 1; }

# overlay round-trip
state_set_overlay claude-code 2.1.218 2026-07-23T10:00:00Z
got="$(state_get_overlay_known_latest claude-code)"
[[ "$got" == "2.1.218" ]] || { echo "FAIL: overlay got '$got'"; exit 1; }

# input round-trip
state_set_input_updated_at codex 2026-07-23T09:00:00Z
[[ "$(state_get_input_updated_at codex)" == "2026-07-23T09:00:00Z" ]] || { echo "FAIL: input"; exit 1; }

# corrupt-file recovery
echo "not json {" > "$UPDATE_STATE_FILE"
state_init
jq -e '.overlays' "$UPDATE_STATE_FILE" >/dev/null || { echo "FAIL: recovery"; exit 1; }

# last_gate round-trip
state_set_last_gate 2026-07-23T11:00:00Z
got_gate="$(jq -r '.last_gate' "$UPDATE_STATE_FILE")"
[[ "$got_gate" == "2026-07-23T11:00:00Z" ]] || { echo "FAIL: last_gate got '$got_gate'"; exit 1; }

# now_iso produces a plausible ISO8601 UTC timestamp
now="$(now_iso)"
[[ "$now" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "FAIL: now_iso got '$now'"; exit 1; }

# getters degrade gracefully (no crash) when the state file is missing entirely
rm -f "$UPDATE_STATE_FILE"
got_missing_overlay="$(state_get_overlay_known_latest claude-code)"
[[ -z "$got_missing_overlay" ]] || { echo "FAIL: expected empty for missing file, got '$got_missing_overlay'"; exit 1; }
got_missing_input="$(state_get_input_updated_at codex)"
[[ -z "$got_missing_input" ]] || { echo "FAIL: expected empty input for missing file, got '$got_missing_input'"; exit 1; }

# getters degrade gracefully (no crash) when the state file is invalid JSON
echo "not json {" > "$UPDATE_STATE_FILE"
got_invalid_overlay="$(state_get_overlay_known_latest claude-code)"
[[ -z "$got_invalid_overlay" ]] || { echo "FAIL: expected empty for invalid file, got '$got_invalid_overlay'"; exit 1; }

# restore a valid state file for the lock test below
state_init

# lock is exclusive
state_lock || { echo "FAIL: first lock"; exit 1; }
( state_lock ) && { echo "FAIL: second lock should fail"; exit 1; }
state_unlock

echo "PASS: test_state"
