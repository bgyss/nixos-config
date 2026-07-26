#!/usr/bin/env bash
# Exercises scripts/escalate.sh with a STUB claude binary, so no tokens are
# ever spent and no model is invoked. The stub writes a verdict.json (and
# optionally edits the overlay) to simulate each outcome. The verification
# build is stubbed via a fake `nix`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

setup() { # -> scratch repo path
  local d; d="$(mktemp -d)"
  mkdir -p "$d/overlays" "$d/scripts" "$d/logs"
  cp "$REPO/scripts/quarantine.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/classify-failure.sh" "$REPO/scripts/escalate.sh" "$d/scripts/"
  cat > "$d/overlays/updates.json" <<'EOF'
{ "packages": [ { "name": "demo", "overlay": "overlays/99-demo.nix",
    "current_version": "1.0.0", "update_type": "prebuilt-binary",
    "check": { "method": "github-release", "repo": "demo/demo" } } ],
  "skip": [] }
EOF
  printf '_final: _prev: { demo = { version = "1.0.0"; }; }\n' > "$d/overlays/99-demo.nix"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  printf "error: builder for '/nix/store/x-demo.drv' failed with exit code 1\n" > "$d/logs/build.log"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A && git -C "$d" commit -qm init
  printf '%s' "$d"
}

# A stub `claude` that edits the overlay and writes a "fixed" verdict.
stub_claude_fixed() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
# The prompt arrives as the last positional arg; cwd is the worktree.
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"widened the version bound","files_changed":["overlays/99-demo.nix"]}
JSON
EOF
  chmod +x "$1/claude"
}

stub_claude_gaveup() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
cat > verdict.json <<'JSON'
{"status":"gave-up","package":"demo","fingerprint":"compile-failure",
 "verdict":"upstream renamed the entrypoint; needs manual review","files_changed":[]}
JSON
EOF
  chmod +x "$1/claude"
}

# A stub claude that LIES: claims fixed but changes nothing that builds.
stub_claude_lies() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
echo "# cosmetic" >> overlays/99-demo.nix
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"definitely fixed, trust me","files_changed":["overlays/99-demo.nix"]}
JSON
EOF
  chmod +x "$1/claude"
}

stub_nix() { # <stub-dir> <ok|broken>
  if [[ "$2" == "ok" ]]; then
    cat > "$1/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build) exit 0 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
  else
    cat > "$1/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build) echo "error: still broken" >&2; exit 1 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
  fi
  chmod +x "$1/nix"
}

run_escalate() { # <repo> <stub>
  ( cd "$1" && PATH="$2:$PATH" ESCALATE_CLAUDE_BIN="$2/claude" \
      bash scripts/escalate.sh --package demo --version 1.1.0 \
        --phase package-build --log logs/build.log >"$1/esc.log" 2>&1 )
}

# === Case 1: a verified fix is committed ==================================
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/esc.log"; fail "case1: expected exit 0, got $rc"; }
grep -q "1.1.0" "$d/overlays/99-demo.nix" || fail "case1: fix not cherry-picked into the repo"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case1: expected exactly one new commit"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "fixed" ]] \
  || fail "case1: escalation_status not recorded as fixed"
# No worktrees may be left behind.
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case1: worktree leaked"
rm -rf "$d" "$stub"

# === Case 2: gave-up commits nothing and records the verdict =============
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_gaveup "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case2: expected exit 1, got $rc"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case2: gave-up produced a commit"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "gave-up" ]] \
  || fail "case2: gave-up not recorded"
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] || fail "case2: worktree leaked"
rm -rf "$d" "$stub"

# === Case 3: a LYING verdict is caught by the wrapper's own build ========
# This is the load-bearing test: Claude's claim is never the evidence.
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_lies "$stub"; stub_nix "$stub" broken
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case3: an unverifiable 'fixed' verdict was accepted (exit $rc)"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case3: committed a fix whose build failed"
grep -qi "did not reproduce\|verification" "$d/esc.log" \
  || { cat "$d/esc.log"; fail "case3: discrepancy not reported"; }
rm -rf "$d" "$stub"

# === Case 4: a missing verdict.json is treated as gave-up ===============
d="$(setup)"; stub="$(mktemp -d)"; stub_nix "$stub" ok
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/claude"; chmod +x "$stub/claude"
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case4: missing verdict not treated as gave-up (exit $rc)"
rm -rf "$d" "$stub"

# === Case 5: dedup refuses a second escalation on the same fingerprint ===
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed "$stub"; stub_nix "$stub" ok
( cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c '
  source scripts/update-state.sh; source scripts/quarantine.sh
  quarantine_record demo overlay 1.1.0 1.0.0 package-build compile-failure next-version-only x
  quarantine_set_escalation demo gave-up "already tried"' )
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 2 ]] || fail "case5: expected exit 2 (skipped by dedup), got $rc"
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case5: overlay was modified despite dedup"
rm -rf "$d" "$stub"

echo "PASS: test_escalate"
