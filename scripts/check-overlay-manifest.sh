#!/usr/bin/env bash
# Verify overlays/updates.json is internally consistent with the overlay tree.
# Run standalone (`scripts/check-overlay-manifest.sh`) or from `nix flake check`
# (the `overlays-manifest` check passes the flake source as $1).
#
# Enforces the §5.2 invariant from docs/config-survey-2026-07.md: the manifest
# and the overlay tree can never silently diverge. Fails (non-zero) on any of:
#   * updates.json is not valid JSON
#   * an overlays/*.nix file is in neither packages[] nor skip[]
#   * a manifest-referenced overlay/skip file does not exist on disk
#   * a package's current_version string does not appear in its overlay file
#   * a pinned_inputs[] entry is missing a required agent field
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel)}"
MANIFEST="$ROOT/overlays/updates.json"
OVERLAYS="$ROOT/overlays"

fail=0
err() {
  printf 'FAIL: %s\n' "$1" >&2
  fail=1
}

# 1. Valid JSON.
if ! jq empty "$MANIFEST" 2>/dev/null; then
  echo "FAIL: overlays/updates.json is not valid JSON" >&2
  exit 1
fi

# 2 + 3. Coverage: every *.nix overlay is listed exactly once; every listed
# file exists.
mapfile -t on_disk < <(find "$OVERLAYS" -maxdepth 1 -name '*.nix' -exec basename {} \; | sort)
mapfile -t listed < <(
  jq -r '(.packages[].overlay | sub("overlays/"; "")), .skip[].file' "$MANIFEST" | sort -u
)

for f in "${on_disk[@]}"; do
  found=0
  for l in "${listed[@]}"; do [[ "$f" == "$l" ]] && found=1 && break; done
  [[ $found -eq 1 ]] || err "overlay $f is in neither packages[] nor skip[] of updates.json"
done

for l in "${listed[@]}"; do
  [[ -f "$OVERLAYS/$l" ]] || err "updates.json references overlays/$l which does not exist"
done

# 4. Each package's current_version must appear verbatim in its overlay file.
while IFS=$'\t' read -r name overlay ver; do
  file="$ROOT/$overlay"
  [[ -f "$file" ]] || { err "package '$name' overlay $overlay missing"; continue; }
  grep -qF "$ver" "$file" \
    || err "package '$name' current_version '$ver' not found in $overlay (manifest/tree drift)"
done < <(jq -r '.packages[] | [.name, .overlay, .current_version] | @tsv' "$MANIFEST")

# 5. Frozen-input tracking: each pinned_inputs[] entry needs the agent fields
# so a freeze is a decision with an exit, not silent drift (F3 / §5.2).
while IFS=$'\t' read -r name missing; do
  [[ -z "$missing" ]] || err "pinned_inputs '$name' missing required field(s): $missing"
done < <(
  jq -r '
    (.pinned_inputs // [])[]
    | . as $e
    | [ "unpin_when", "risk", "last_verified", "rollback_hint" ]
      | map(select($e[.] == null))
      | [ $e.name, join(",") ] | @tsv
  ' "$MANIFEST" | awk -F'\t' '$2 != ""'
)

if [[ $fail -ne 0 ]]; then
  echo "overlay manifest consistency: FAILED" >&2
  exit 1
fi
echo "overlay manifest consistency: OK"
