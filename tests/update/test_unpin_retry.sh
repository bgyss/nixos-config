#!/usr/bin/env bash
# Tests prepare's unpin-retry gating in isolation by sourcing the helper
# functions out of the real `prepare` script — no nix, no network, no commits.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# Every pinned input declares a retry cadence.
n_pins="$(jq '.pinned_inputs | length' "$REPO/overlays/updates.json")"
n_cad="$(jq '[.pinned_inputs[] | select(has("retry_cadence_hours"))] | length' "$REPO/overlays/updates.json")"
[[ "$n_pins" == "$n_cad" ]] || fail "only $n_cad of $n_pins pinned_inputs declare retry_cadence_hours"

# Extract the helpers from `prepare` without executing its main body. The
# marker comments below must exist in prepare (added in Step 4).
sed -n '/^# ---8<--- unpin-retry helpers ---8<---$/,/^# ---8<--- end unpin-retry helpers ---8<---$/p' \
  "$REPO/apps/aarch64-darwin/prepare" > "$TMP/helpers.sh"
[[ -s "$TMP/helpers.sh" ]] || fail "unpin-retry helper markers not found in prepare"

export QUARANTINE_FILE="$TMP/quarantine.json"
MANIFEST="$REPO/overlays/updates.json"
# shellcheck source=/dev/null
source "$REPO/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/quarantine.sh"
# shellcheck source=/dev/null
source "$TMP/helpers.sh"
quarantine_init

# A pin never attempted before is due immediately.
unpin_retry_due nixpkgs || fail "a never-attempted pin was not due"

# A pin attempted just now is not due.
quarantine_record nixpkgs input "unpin-attempt" "af45a5c" "system-build" \
  "unpin-failed" "retry-after:168" "patch OOM"
if unpin_retry_due nixpkgs; then fail "a just-attempted pin was reported due"; fi

# Backdated past the window, it is due again.
jq '(.entries[] | select(.name=="nixpkgs") | .last_attempt) = "2000-01-01T00:00:00Z"' \
  "$QUARANTINE_FILE" > "$TMP/x" && mv "$TMP/x" "$QUARANTINE_FILE"
unpin_retry_due nixpkgs || fail "a stale pin attempt was not due again"

# An unknown input is never due (nothing to unpin).
if unpin_retry_due not-a-real-input; then fail "unknown input reported due"; fi

echo "PASS: test_unpin_retry"
