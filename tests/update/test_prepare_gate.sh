#!/usr/bin/env bash
# Exercises the real `prepare` script's gate short-circuit end-to-end, without
# ever reaching a real `nix build`/`git commit`. Everything that could touch
# the network, the nix store, or this checkout's git history is stubbed:
#   - curl: hermetic stand-in reflecting each overlay's own current_version
#     back as "latest" (same technique as test_probe_inputs.sh /
#     test_check_app.sh), so probe_overlays reports nothing outdated. A
#     second variant (FORCE_OUTDATED_PKG) makes exactly one named package
#     report a bumped "latest" so probe_overlays sees it as outdated, without
#     ever touching the real tracked overlays/updates.json.
#   - nix: `flake metadata` returns no github input nodes (so the input probe
#     has nothing to chase upstream and `probe_flake_inputs apply` reports
#     nothing updated); `nix build`/`nix store` are stubbed to abort loudly if
#     ever invoked — that's the assertion that the gate actually short-circuits
#     before reaching the build/commit tail. Anything else falls through to
#     the real `nix` binary (needed by `locate_flake`'s registry lookup).
# `prepare` no longer calls `fix-hashes` automatically at all (overlay bumps
# are a manual routine — see docs/overlay-update-routine.md); case 2 below
# asserts this indirectly by diffing the overlay .nix and updates.json before
# and after the run.
# State/manifest are isolated to a scratch copy so this test can never mutate
# the real .update-state.json or overlays/updates.json in the checkout.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

write_stubs() { # <stub-dir> <force-outdated-pkg-name-or-empty>
  local stub="$1" force="$2"
  cat > "$stub/curl" <<EOF
#!/usr/bin/env bash
MANIFEST="$REPO/overlays/updates.json"
FORCE="$force"
url=""
for a in "\$@"; do
  case "\$a" in http*) url="\$a" ;; esac
done
case "\$url" in
  */repos/*/releases/latest)
    repo="\${url#*api.github.com/repos/}"; repo="\${repo%/releases/latest}"
    pkg=\$(jq -c --arg r "\$repo" '.packages[] | select(.check.repo==\$r and .check.method=="github-release")' "\$MANIFEST")
    name=\$(jq -r '.name' <<<"\$pkg")
    if [[ -n "\$FORCE" && "\$name" == "\$FORCE" ]]; then
      printf '{"tag_name":"v99999.0.0"}'; exit 0
    fi
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    prefix=\$(jq -r '.check.tag_prefix // ""' <<<"\$pkg")
    if [[ -n "\$prefix" ]]; then tag="\${prefix}\${cur}"; else tag="v\${cur}"; fi
    printf '{"tag_name":"%s"}' "\$tag"; exit 0 ;;
  */repos/*/commits/*)
    repo="\${url#*api.github.com/repos/}"; repo="\${repo%/commits/*}"
    pkg=\$(jq -c --arg r "\$repo" '.packages[] | select(.check.repo==\$r and .check.method=="github-commits")' "\$MANIFEST")
    rev=\$(jq -r '.current_rev // empty' <<<"\$pkg")
    [[ -z "\$rev" ]] && exit 1
    printf '{"sha":"%s"}' "\$rev"; exit 0 ;;
  */pypi.org/pypi/*/json)
    package="\${url#*pypi.org/pypi/}"; package="\${package%/json}"
    pkg=\$(jq -c --arg p "\$package" '.packages[] | select(.check.package==\$p and .check.method=="pypi")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    printf '{"info":{"version":"%s"}}' "\$cur"; exit 0 ;;
  */registry.npmjs.org/*/latest)
    package="\${url#*registry.npmjs.org/}"; package="\${package%/latest}"
    pkg=\$(jq -c --arg p "\$package" '.packages[] | select(.check.package==\$p and .check.method=="npm")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    printf '{"version":"%s"}' "\$cur"; exit 0 ;;
  */go.dev/dl/*)
    pkg=\$(jq -c '.packages[] | select(.check.method=="go-dev")' "\$MANIFEST")
    cur=\$(jq -r '.current_version' <<<"\$pkg")
    printf '[{"stable":true,"version":"go%s"}]' "\$cur"; exit 0 ;;
  *)
    exit 1 ;;
esac
EOF
  chmod +x "$stub/curl"

  local real_nix; real_nix="$(command -v nix)"
  cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "flake" && "\$2" == "metadata" ]]; then echo '{"locks":{"nodes":{}}}'; exit 0; fi
if [[ "\$1" == "flake" && "\$2" == "lock" ]]; then exit 0; fi
if [[ "\$1" == "registry" && "\$2" == "list" ]]; then exit 1; fi
if [[ "\$1" == "build" ]]; then echo "TEST FAILURE: nix build should not run when gate says nothing to do" >&2; exit 99; fi
if [[ "\$1" == "store" ]]; then echo "TEST FAILURE: nix store diff-closures should not run" >&2; exit 99; fi
exec "$real_nix" "\$@"
EOF
  chmod +x "$stub/nix"

  # git: prepare's tail also shells out to `git`. Guard against any accidental
  # commit by making git a fail-loud stub too — belt and suspenders alongside
  # the nix-build stub, since the gate should exit long before either runs.
  local real_git; real_git="$(command -v git)"
  cat > "$stub/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "commit" ]]; then echo "TEST FAILURE: git commit should not run when gate says nothing to do" >&2; exit 99; fi
exec "$real_git" "\$@"
EOF
  chmod +x "$stub/git"
}

overall_fail=0

# --- Case 1: nothing outdated, no input due -> short-circuit ---------------
STUB1="$(mktemp -d)"
write_stubs "$STUB1" ""
export UPDATE_STATE_FILE="$(mktemp)"; rm -f "$UPDATE_STATE_FILE"
export UPDATE_MANIFEST="$(mktemp)"
cp "$REPO/overlays/updates.json" "$UPDATE_MANIFEST"

out="$(PATH="$STUB1:$PATH" bash "$REPO/apps/aarch64-darwin/prepare" 2>&1)"
status=$?
rm -rf "$STUB1"
rm -f "$UPDATE_STATE_FILE" "$UPDATE_MANIFEST"

if [[ $status -ne 0 ]]; then
  echo "FAIL: prepare exited $status"; echo "$out"; overall_fail=1
elif ! echo "$out" | grep -qi "nothing to do"; then
  echo "FAIL: expected nothing-to-do"; echo "$out"; overall_fail=1
elif echo "$out" | grep -qi "TEST FAILURE"; then
  echo "FAIL: build/commit path was reached"; echo "$out"; overall_fail=1
else
  echo "PASS: test_prepare_gate (nothing to do)"
fi

# --- Case 2: overlay outdated, NO flake input moved -------------------------
# This is the exact regression the final review caught: `prepare` must gate
# on flake-input movement only. An outdated overlay is informational — it
# must be printed, but must never trigger fix-hashes, never rewrite the
# overlay .nix or overlays/updates.json, and never reach nix build/git commit.
STUB2="$(mktemp -d)"
write_stubs "$STUB2" "claude-code"
export UPDATE_STATE_FILE="$(mktemp)"; rm -f "$UPDATE_STATE_FILE"
export UPDATE_MANIFEST="$(mktemp)"
cp "$REPO/overlays/updates.json" "$UPDATE_MANIFEST"
MANIFEST_SNAPSHOT="$(mktemp)"; cp "$UPDATE_MANIFEST" "$MANIFEST_SNAPSHOT"
OVERLAY_FILE="$REPO/overlays/41-claude-code.nix"
OVERLAY_SNAPSHOT="$(mktemp)"; cp "$OVERLAY_FILE" "$OVERLAY_SNAPSHOT"

out2="$(PATH="$STUB2:$PATH" bash "$REPO/apps/aarch64-darwin/prepare" 2>&1)"
status2=$?

rm -rf "$STUB2"
rm -f "$UPDATE_STATE_FILE"

if [[ $status2 -ne 0 ]]; then
  echo "FAIL: prepare (outdated overlay, no input) exited $status2"; echo "$out2"; overall_fail=1
fi
if ! echo "$out2" | grep -qi "outdated"; then
  echo "FAIL: expected outdated overlay to be reported: $out2"; overall_fail=1
fi
if ! echo "$out2" | grep -qi "nothing to do"; then
  echo "FAIL: gate should still say nothing to do (inputs didn't move): $out2"; overall_fail=1
fi
if echo "$out2" | grep -qi "TEST FAILURE"; then
  echo "FAIL: build/commit/fix-hashes path was reached for an overlay-only change: $out2"; overall_fail=1
fi
if ! diff -q "$OVERLAY_SNAPSHOT" "$OVERLAY_FILE" >/dev/null; then
  echo "FAIL: prepare must never rewrite an overlay .nix file"; overall_fail=1
fi
if ! diff -q "$MANIFEST_SNAPSHOT" "$UPDATE_MANIFEST" >/dev/null; then
  echo "FAIL: prepare must never rewrite overlays/updates.json"; overall_fail=1
fi

rm -f "$UPDATE_MANIFEST" "$MANIFEST_SNAPSHOT" "$OVERLAY_SNAPSHOT"

if [[ $overall_fail -eq 0 ]]; then
  echo "PASS: test_prepare_gate (outdated overlay is informational only)"
else
  exit 1
fi
