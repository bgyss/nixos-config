#!/usr/bin/env bash
# Exercises bump-overlays' quarantine + cadence gating without any real
# network, nix build, or commit against this checkout.
#
# Isolation strategy (same shape as tests/update/test_bump_mechanical_only.sh):
#   - a scratch git repo stands in for the flake dir, holding a copy of the
#     real scripts/ and apps/ plus a two-package manifest;
#   - `nix` is stubbed: `registry list` fails closed so locate_flake() falls
#     back to `git rev-parse --show-toplevel` (the scratch repo), and
#     `nix build` is stubbed per-case to succeed or fail;
#   - `curl` is stubbed to report a specific "latest" version per package;
#   - fix-hashes is stubbed to a no-op success.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

setup_repo() { # -> prints scratch repo path
  local d; d="$(mktemp -d)"
  mkdir -p "$d/overlays" "$d/scripts" "$d/apps/aarch64-darwin" "$d/logs"
  cp "$REPO/scripts/quarantine.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/classify-failure.sh" "$REPO/scripts/update-probe.sh" \
     "$REPO/scripts/update-notify.sh" "$REPO/scripts/check-overlay-versions.sh" \
     "$d/scripts/"
  cp "$REPO/apps/aarch64-darwin/_common.sh" "$REPO/apps/aarch64-darwin/bump-overlays" \
     "$d/apps/aarch64-darwin/"
  # A stub fix-hashes that always succeeds without touching anything.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/apps/aarch64-darwin/fix-hashes"
  chmod +x "$d/apps/aarch64-darwin/fix-hashes"
  # Minimal single-package manifest + overlay.
  cat > "$d/overlays/updates.json" <<'EOF'
{
  "packages": [
    {
      "name": "demo",
      "overlay": "overlays/99-demo.nix",
      "current_version": "1.0.0",
      "check": { "method": "github-release", "repo": "demo/demo" },
      "update_type": "prebuilt-binary",
      "platforms": { "aarch64-darwin": { "url_template": "https://example.com/demo-{version}.tar.gz" } }
    }
  ],
  "skip": [],
  "inputs": {},
  "pinned_inputs": []
}
EOF
  cat > "$d/overlays/99-demo.nix" <<'EOF'
_final: _prev: {
  demo = { version = "1.0.0"; };
}
EOF
  printf '{"comment":"test","entries":[]}\n' > "$d/overlays/quarantine.json"
  # locate_flake() falls back to `git rev-parse --show-toplevel`, but only
  # accepts it as the flake dir if flake.nix exists there.
  : > "$d/flake.nix"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A
  git -C "$d" commit -qm init
  printf '%s' "$d"
}

# Stubs: curl reports `latest`, nix build succeeds or fails per $3.
setup_stubs() { # <stub-dir> <latest-version> <build-outcome ok|broken>
  local stub="$1" latest="$2" outcome="$3"
  cat > "$stub/curl" <<EOF
#!/usr/bin/env bash
printf '{"tag_name":"v%s"}' "$latest"
EOF
  if [[ "$outcome" == "ok" ]]; then
    cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "registry list") exit 1 ;;
  "build "*|"build") exit 0 ;;
esac
case "\$1" in
  build) exit 0 ;;
  hash) exec "$REAL_NIX" "\$@" ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  else
    cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "registry list") exit 1 ;;
esac
case "\$1" in
  build) echo "error: builder for '/nix/store/x-demo.drv' failed with exit code 1" >&2; exit 1 ;;
  hash) exec "$REAL_NIX" "\$@" ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  fi
  cat > "$stub/nix-prefetch-url" <<'EOF'
#!/usr/bin/env bash
echo "0000000000000000000000000000000000000000000000000000"
EOF
  chmod +x "$stub/curl" "$stub/nix" "$stub/nix-prefetch-url"
}

# === Case 1: a failing bump writes a classified quarantine entry ============
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "broken"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case1: expected exit 1 on failed bump, got $rc"
got_ver="$(jq -r '.entries[] | select(.name=="demo") | .blocked_version' "$d/overlays/quarantine.json")"
[[ "$got_ver" == "1.1.0" ]] || fail "case1: blocked_version is '$got_ver', expected 1.1.0"
got_fp="$(jq -r '.entries[] | select(.name=="demo") | .fingerprint' "$d/overlays/quarantine.json")"
[[ "$got_fp" == "compile-failure" ]] || fail "case1: fingerprint is '$got_fp', expected compile-failure"
got_good="$(jq -r '.entries[] | select(.name=="demo") | .known_good_version' "$d/overlays/quarantine.json")"
[[ "$got_good" == "1.0.0" ]] || fail "case1: known_good_version is '$got_good', expected 1.0.0"
# A mutating run (even one with a failed bump) must leave overlays/ clean —
# the precondition rejects a dirty overlays/, so anything left dirty here
# wedges every future run at exit 3.
[[ -z "$(git -C "$d" status --porcelain -- overlays/)" ]] \
  || fail "case1: mutating run left overlays/ dirty — next run will exit 3"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out2.log" 2>&1 ) && rc2=0 || rc2=$?
[[ $rc2 -ne 3 ]] || { cat "$d/out2.log"; fail "case1: second run wedged at exit 3"; }
rm -rf "$d" "$stub"

# === Case 6: --dry-run with an ABSENT ledger must not wedge the next run ===
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "ok"
git -C "$d" rm -q overlays/quarantine.json
git -C "$d" commit -qam "remove quarantine ledger (simulate pre-ledger state)"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --dry-run --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/out.log"; fail "case6: expected exit 0 on --dry-run, got $rc"; }
[[ -z "$(git -C "$d" status --porcelain -- overlays/)" ]] \
  || fail "case6: --dry-run with absent ledger left overlays/ dirty — next run will exit 3"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out2.log" 2>&1 ) && rc2=0 || rc2=$?
[[ $rc2 -ne 3 ]] || { cat "$d/out2.log"; fail "case6: following run wedged at exit 3"; }
rm -rf "$d" "$stub"

# === Case 2: a quarantined version is skipped, not retried =================
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "broken"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"1.1.0",
  known_good_version:"1.0.0",first_failed:"2026-01-01T00:00:00Z",
  last_attempt:"2026-01-01T00:00:00Z",attempts:1,phase:"package-build",
  fingerprint:"compile-failure",error_excerpt:"x",retry_policy:"next-version-only"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
# The seeded ledger entry represents state a prior (committed) run left
# behind, so commit it — bump-overlays' precondition refuses to run against
# an already-dirty overlays/.
git -C "$d" commit -qam "seed quarantine"
# nix build must never be reached; make it fatal if it is.
cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in
  build) echo "FATAL: build attempted on a quarantined version" >&2; exit 99 ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
chmod +x "$stub/nix"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
grep -qi "quarantined" "$d/out.log" || { cat "$d/out.log"; fail "case2: no 'quarantined' skip reason reported"; }
grep -q "FATAL" "$d/out.log" && fail "case2: build was attempted on a quarantined version"
[[ $rc -eq 0 ]] || fail "case2: a skipped-because-quarantined run must exit 0, got $rc"
rm -rf "$d" "$stub"

# === Case 3: a NEWER version than the quarantined one is attempted =========
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.2.0" "ok"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"1.1.0",
  known_good_version:"1.0.0",first_failed:"2026-01-01T00:00:00Z",
  last_attempt:"2026-01-01T00:00:00Z",attempts:1,phase:"package-build",
  fingerprint:"compile-failure",error_excerpt:"x",retry_policy:"next-version-only"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
git -C "$d" commit -qam "seed quarantine"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/out.log"; fail "case3: expected exit 0, got $rc"; }
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "1.2.0" ]] \
  || fail "case3: manifest not bumped to 1.2.0"
# A successful bump must clear the stale entry.
[[ "$(jq '.entries | length' "$d/overlays/quarantine.json")" == "0" ]] \
  || fail "case3: successful bump did not clear the quarantine entry"
rm -rf "$d" "$stub"

# === Case 4: a frozen entry blocks every version ==========================
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "9.9.9" "ok"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"1.1.0",
  known_good_version:"1.0.0",first_failed:"2026-01-01T00:00:00Z",
  last_attempt:"2026-01-01T00:00:00Z",attempts:3,phase:"package-build",
  fingerprint:"compile-failure",error_excerpt:"x",retry_policy:"frozen"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
git -C "$d" commit -qam "seed quarantine"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) || true
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "1.0.0" ]] \
  || fail "case4: frozen entry did not block the bump"
rm -rf "$d" "$stub"

# === Case 5: cadence gating defers an out-of-window package ==============
d="$(setup_repo)"; stub="$(mktemp -d)"
setup_stubs "$stub" "1.1.0" "ok"
jq '(.packages[0].cadence_hours) = 168' "$d/overlays/updates.json" > "$d/m" \
  && mv "$d/m" "$d/overlays/updates.json"
git -C "$d" commit -qam "seed cadence_hours"
printf '{"overlays":{"demo":{"bumped_at":"%s"}},"inputs":{},"last_gate":null}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$d/.state.json"
( cd "$d" && PATH="$stub:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
    bash apps/aarch64-darwin/bump-overlays --no-public-sync >"$d/out.log" 2>&1 ) || true
grep -qi "cadence" "$d/out.log" || { cat "$d/out.log"; fail "case5: no cadence skip reason"; }
[[ "$(jq -r '.packages[0].current_version' "$d/overlays/updates.json")" == "1.0.0" ]] \
  || fail "case5: cadence did not defer the bump"
rm -rf "$d" "$stub"

echo "PASS: test_bump_quarantine"
