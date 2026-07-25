#!/usr/bin/env bash
# Exercises bump-overlays' detect/classify stage — specifically the
# --mechanical-only flag used by the unattended scheduled-check run — without
# fetching anything or touching this checkout. A scratch git repo stands in
# for the flake dir with:
#   - a fake scripts/check-overlay-versions.sh emitting a fixed JSON report
#     (uv outdated + mechanical, c4 outdated + go-source, tmux outdated but
#     not an automated update_type),
#   - a minimal overlays/updates.json matching it,
#   - a `nix` stub whose `registry list` fails closed so locate_flake() falls
#     back to `git rev-parse --show-toplevel` and resolves to the scratch repo.
# Every case runs --dry-run, so no overlay file is ever rewritten, no hash is
# fetched and nothing is committed — this asserts classification only.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

REAL_NIX="$(command -v nix)"
STUB="$(mktemp -d)"
cat > "$STUB/nix" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "registry" && "\$2" == "list" ]]; then exit 1; fi
exec "$REAL_NIX" "\$@"
EOF
chmod +x "$STUB/nix"

scratch="$(mktemp -d)"
git -C "$scratch" init -q
git -C "$scratch" config user.email "test@example.com"
git -C "$scratch" config user.name "Test"
mkdir -p "$scratch/scripts" "$scratch/apps/aarch64-darwin" "$scratch/overlays"
: > "$scratch/flake.nix"
cp "$REPO/apps/aarch64-darwin/_common.sh" "$scratch/apps/aarch64-darwin/_common.sh"
cp "$REPO/scripts/update-state.sh" "$scratch/scripts/update-state.sh"
cp "$REPO/apps/aarch64-darwin/bump-overlays" "$scratch/apps/aarch64-darwin/bump-overlays"
chmod +x "$scratch/apps/aarch64-darwin/bump-overlays"

cat > "$scratch/scripts/check-overlay-versions.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"name":"uv","status":"OUTDATED","outdated":true,"current":"0.1.0","latest":"0.2.0"},
  {"name":"c4","status":"OUTDATED","outdated":true,"current":"0-unstable-2026-01-01","latest":"0-unstable-2026-07-13"},
  {"name":"tmux","status":"OUTDATED","outdated":true,"current":"3.6","latest":"3.7b"}
]
JSON
EOF
chmod +x "$scratch/scripts/check-overlay-versions.sh"

cat > "$scratch/overlays/updates.json" <<'EOF'
{
  "packages": [
    {"name":"uv","overlay":"overlays/25-uv.nix","update_type":"prebuilt-binary-multiplatform","current_version":"0.1.0"},
    {"name":"c4","overlay":"overlays/56-c4.nix","update_type":"go-source","current_version":"0-unstable-2026-01-01","current_rev":"deadbeef","check":{"method":"github-commit","repo":"x/c4","branch":"main"}},
    {"name":"tmux","overlay":"overlays/96-tmux.nix","update_type":"source-build","current_version":"3.6"}
  ],
  "skip": [],
  "inputs": {},
  "pinned_inputs": []
}
EOF

git -C "$scratch" add -A
git -C "$scratch" commit -q -m "init"

run_bump() { (cd "$scratch" && PATH="$STUB:$PATH" bash "$scratch/apps/aarch64-darwin/bump-overlays" "$@" 2>&1) || true; }

fail=0

# --mechanical-only: uv planned, c4 explicitly excluded as go-source, tmux
# excluded as a non-automated update_type. Neither excluded package may show
# up in the planned lists.
out="$(run_bump --mechanical-only --dry-run)"
grep -q "Planned mechanical bumps: uv"      <<<"$out" || { echo "FAIL: uv should be planned: $out"; fail=1; }
grep -q "Planned go-source bumps: none"     <<<"$out" || { echo "FAIL: go-source list should be empty: $out"; fail=1; }
grep -q "c4: go-source bump excluded by --mechanical-only" <<<"$out" || { echo "FAIL: c4 should be skipped with the --mechanical-only reason: $out"; fail=1; }
grep -q "tmux: update_type 'source-build' not automated" <<<"$out" || { echo "FAIL: tmux should be skipped as non-automated: $out"; fail=1; }

# Without the flag, c4 is back in scope — proves the exclusion comes from the
# flag and not from the fixture accidentally misclassifying c4.
out_all="$(run_bump --dry-run)"
grep -q "Planned go-source bumps: c4" <<<"$out_all" || { echo "FAIL: c4 should be planned without --mechanical-only: $out_all"; fail=1; }

# Lock contention must be a distinct exit 2, not a generic failure — that is
# what lets scheduled-check stay silent instead of firing a false alarm.
mkdir "$scratch/.update-state.json.lock.d"
set +e
(cd "$scratch" && PATH="$STUB:$PATH" bash "$scratch/apps/aarch64-darwin/bump-overlays" --mechanical-only --dry-run >/dev/null 2>&1)
rc=$?
set -e
[[ $rc -eq 2 ]] || { echo "FAIL: lock contention should exit 2, got $rc"; fail=1; }
rmdir "$scratch/.update-state.json.lock.d"

# Dirty overlays/ must be its own exit 3, distinct from lock contention.
echo "dirty" >> "$scratch/overlays/updates.json"
set +e
(cd "$scratch" && PATH="$STUB:$PATH" bash "$scratch/apps/aarch64-darwin/bump-overlays" --mechanical-only --dry-run >/dev/null 2>&1)
rc=$?
set -e
[[ $rc -eq 3 ]] || { echo "FAIL: dirty overlays/ should exit 3, got $rc"; fail=1; }
git -C "$scratch" checkout -- overlays/

rm -rf "$scratch" "$STUB"
[[ $fail -eq 0 ]] && echo "PASS: test_bump_mechanical_only" || exit 1
