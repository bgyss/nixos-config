#!/usr/bin/env bash
# Asserts (a) the real manifest declares weekly cadence for the branch-HEAD go
# packages, and (b) check-overlay-manifest.sh rejects a non-integer or
# non-positive cadence_hours. The check is run against a scratch COPY of the
# repo so the real tree is never mutated.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MANIFEST="$REPO/overlays/updates.json"

fail() { echo "FAIL: $1"; exit 1; }

# --- real manifest: c4 and hey-cli are weekly ------------------------------
for p in c4 hey-cli; do
  got="$(jq -r --arg n "$p" '.packages[] | select(.name==$n) | .cadence_hours // "unset"' "$MANIFEST")"
  [[ "$got" == "168" ]] || fail "$p cadence_hours is '$got', expected 168"
done

# --- real manifest still passes the check ---------------------------------
bash "$REPO/scripts/check-overlay-manifest.sh" "$REPO" >/dev/null \
  || fail "real manifest no longer passes check-overlay-manifest.sh"

# --- a bad cadence is rejected -------------------------------------------
# Copy the repo's tracked files so the check sees a complete, valid tree.
git -C "$REPO" archive HEAD | tar -x -C "$TMP"
reject() { # <jq-filter> <label>
  jq "$1" "$MANIFEST" > "$TMP/overlays/updates.json"
  if bash "$REPO/scripts/check-overlay-manifest.sh" "$TMP" >/dev/null 2>&1; then
    fail "check accepted $2"
  fi
}
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = "weekly"' "a string cadence_hours"
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = 0' "a zero cadence_hours"
reject '(.packages[] | select(.name=="c4") | .cadence_hours) = -5' "a negative cadence_hours"

echo "PASS: test_manifest_cadence"
