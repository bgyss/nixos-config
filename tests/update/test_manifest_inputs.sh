#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

# Real manifest must validate.
bash "$REPO/scripts/check-overlay-manifest.sh" "$REPO" >/dev/null || { echo "FAIL: real manifest"; exit 1; }

# A copy with a malformed inputs entry must FAIL.
# Only copy what check-overlay-manifest.sh actually reads (overlays/) — copying
# the whole repo tree (incl. .git) fails on some checkouts where cp can't
# duplicate special files like an active fsmonitor socket.
tmp="$(mktemp -d)"; mkdir -p "$tmp/overlays"; cp -r "$REPO/overlays/." "$tmp/overlays/"
jq '.inputs.badinput = {}' "$REPO/overlays/updates.json" > "$tmp/overlays/updates.json"
if bash "$REPO/scripts/check-overlay-manifest.sh" "$tmp" >/dev/null 2>&1; then
  echo "FAIL: malformed inputs entry accepted"; exit 1
fi
echo "PASS: test_manifest_inputs"
