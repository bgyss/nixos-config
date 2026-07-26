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
     "$REPO/scripts/classify-failure.sh" "$REPO/scripts/escalate.sh" \
     "$REPO/scripts/check-overlay-manifest.sh" "$d/scripts/"
  cat > "$d/overlays/updates.json" <<'EOF'
{ "packages": [ { "name": "demo", "overlay": "overlays/99-demo.nix",
    "current_version": "1.0.0", "update_type": "prebuilt-binary",
    "check": { "method": "github-release", "repo": "demo/demo" } } ],
  "skip": [] }
EOF
  printf '_final: _prev: { demo = { version = "1.0.0"; }; }\n' > "$d/overlays/99-demo.nix"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  cat > "$d/overlays/health-checks.json" <<'EOF'
{ "assertions": [ { "package": "demo", "skip": "no binary to smoke-test in the test fixture" } ] }
EOF
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
# The prompt arrives as the last positional arg; cwd is the worktree. A
# genuine fix bumps the overlay's pinned version AND updates.json's
# current_version together, matching what the brief instructs (and what the
# post-Finding-1 landing gates require).
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
sed -i.bak 's/"current_version": "1\.0\.0"/"current_version": "1.1.0"/' overlays/updates.json && rm -f overlays/updates.json.bak
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"widened the version bound","files_changed":["overlays/99-demo.nix","overlays/updates.json"]}
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
# The fix commit, plus the ledger commit that records the quarantine clear
# (Finding 1/2: the ledger write must always be committed, or the next
# bump-overlays run wedges at exit 3).
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "3" ]] \
  || fail "case1: expected exactly two new commits (fix + ledger)"
[[ -z "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo blocked_version')" ]] \
  || fail "case1: ledger entry not cleared on verified success — would freeze after 3 successes"
grep -q "	demo	fixed	" "$d/logs/escalation-costs.tsv" \
  || { cat "$d/logs/escalation-costs.tsv" 2>/dev/null; fail "case1: cost log missing a 'fixed' row for demo"; }
# The ledger write (or clear) must be committed, or the next bump-overlays run
# wedges at exit 3 (overlays/ dirty).
[[ -z "$(git -C "$d" status --porcelain -- overlays/quarantine.json)" ]] \
  || fail "case1: quarantine.json left uncommitted"
# No worktrees may be left behind.
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] \
  || fail "case1: worktree leaked"
rm -rf "$d" "$stub"

# === Case 2: gave-up commits nothing and records the verdict =============
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_gaveup "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case2: expected exit 1, got $rc"
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case2: gave-up produced an overlay change"
# One new commit is expected here: the ledger commit recording the gave-up
# verdict (Finding 1) — but never an overlay fix commit.
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case2: expected exactly one new commit (ledger only)"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "gave-up" ]] \
  || fail "case2: gave-up not recorded"
[[ -z "$(git -C "$d" status --porcelain -- overlays/quarantine.json)" ]] \
  || fail "case2: quarantine.json left uncommitted — wedges the next bump-overlays run"
grep -q "	demo	gave-up	" "$d/logs/escalation-costs.tsv" \
  || { cat "$d/logs/escalation-costs.tsv" 2>/dev/null; fail "case2: cost log missing a 'gave-up' row for demo"; }
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] || fail "case2: worktree leaked"
rm -rf "$d" "$stub"

# === Case 3: a LYING verdict is caught by the wrapper's own build ========
# This is the load-bearing test: Claude's claim is never the evidence.
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_lies "$stub"; stub_nix "$stub" broken
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case3: an unverifiable 'fixed' verdict was accepted (exit $rc)"
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case3: committed a fix whose build failed"
# One new commit expected: the ledger commit recording the gave-up verdict.
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case3: expected exactly one new commit (ledger only)"
grep -qi "did not reproduce\|verification\|does not pin" "$d/esc.log" \
  || { cat "$d/esc.log"; fail "case3: discrepancy not reported"; }
[[ -z "$(git -C "$d" status --porcelain -- overlays/quarantine.json)" ]] \
  || fail "case3: quarantine.json left uncommitted — wedges the next bump-overlays run"
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

# A `nix` stub whose scoped `--expr` build passes but whose flake-attribute
# (full system) build fails — distinguished by whether --expr is among the args.
stub_nix_scoped_pass_full_fail() { # <stub-dir>
  cat > "$1/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
if [[ "\$1" == "build" ]]; then
  for a in "\$@"; do
    if [[ "\$a" == "--expr" ]]; then exit 0; fi
  done
  echo "error: full system build still broken" >&2
  exit 1
fi
exec "$REAL_NIX" "\$@"
EOF
  chmod +x "$1/nix"
}

# === Case 6: scoped build passes, full system build fails =================
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed "$stub"; stub_nix_scoped_pass_full_fail "$stub"
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case6: expected exit 1 (full system build failure), got $rc"
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case6: committed despite full system build failure"
# One new commit expected: the ledger commit recording the gave-up verdict.
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case6: expected exactly one new commit (ledger only)"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "gave-up" ]] \
  || fail "case6: gave-up not recorded"
grep -q "scoped build passed but the full system build failed" "$d/esc.log" \
  || fail "case6: failed for the wrong reason"
[[ -z "$(git -C "$d" status --porcelain -- overlays/quarantine.json)" ]] \
  || fail "case6: quarantine.json left uncommitted — wedges the next bump-overlays run"
[[ "$(git -C "$d" worktree list | wc -l | tr -d ' ')" == "1" ]] || fail "case6: worktree leaked"
rm -rf "$d" "$stub"

# A stub claude that LIES a different way: writes an unrelated scratch note
# under overlays/ and claims fixed, without ever touching the pinned overlay
# itself. Both wrapper builds pass trivially because the worktree starts from
# the rolled-back, known-good tree (Finding 1, exploit A).
stub_claude_scratch_note() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
echo "# investigated, looks fine now" > overlays/REPAIR-NOTES.md
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"left notes for a human","files_changed":["overlays/REPAIR-NOTES.md"]}
JSON
EOF
  chmod +x "$1/claude"
}

# A stub claude that does the "half-fix": bumps only updates.json's
# current_version, never the overlay file itself, and claims fixed
# (Finding 1, exploit B — the half-fix SKILL.md warns about).
stub_claude_half_fix() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/updates.json && rm -f overlays/updates.json.bak
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"bumped the manifest version","files_changed":["overlays/updates.json"]}
JSON
EOF
  chmod +x "$1/claude"
}

# === Case 7: 'fixed' but the overlay itself was never touched =============
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_scratch_note "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || { cat "$d/esc.log"; fail "case7: a scratch-note 'fixed' verdict was accepted (exit $rc)"; }
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case7: overlay still claims a bump landed"
[[ ! -f "$d/overlays/REPAIR-NOTES.md" ]] \
  || fail "case7: scratch note leaked into the real repo — got published to the public mirror"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case7: expected exactly one new commit (ledger only), scratch note got committed"
[[ "$(cd "$d" && QUARANTINE_FILE="$d/overlays/quarantine.json" bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_field demo escalation_status')" == "gave-up" ]] \
  || fail "case7: gave-up not recorded"
rm -rf "$d" "$stub"

# === Case 8: 'fixed' but only updates.json's current_version was bumped ===
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_half_fix "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || { cat "$d/esc.log"; fail "case8: a manifest-only half-fix was accepted (exit $rc)"; }
grep -q '"current_version": "1.0.0"' "$d/overlays/updates.json" \
  || fail "case8: half-fix landed in the real repo — manifest/tree now permanently drifted"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case8: expected exactly one new commit (ledger only), half-fix got committed"
rm -rf "$d" "$stub"

# A stub claude that does a COMPLETE, correct bump (mirrors stub_claude_fixed)
# — used to reach the scoped-build-failure branch, which the "lies" stub in
# case 3 no longer reaches now that it exits earlier at the "does not pin"
# gate (Finding 3: that branch had gone uncovered).
# === Case 9: all landing gates pass, but the scoped build genuinely fails ==
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed "$stub"; stub_nix "$stub" broken
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || { cat "$d/esc.log"; fail "case9: expected exit 1 (scoped build failure), got $rc"; }
grep -q "1.0.0" "$d/overlays/99-demo.nix" || fail "case9: committed despite scoped build failure"
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case9: expected exactly one new commit (ledger only)"
grep -q "did not reproduce" "$d/esc.log" \
  || { cat "$d/esc.log"; fail "case9: failed for the wrong reason — expected the scoped-build message"; }
[[ -z "$(git -C "$d" status --porcelain -- overlays/quarantine.json)" ]] \
  || fail "case9: quarantine.json left uncommitted"
rm -rf "$d" "$stub"

# A stub claude that bumps the primary version field AND updates.json
# correctly, but leaves a second, real (non-comment) pin of the OLD version
# in the overlay — simulating a multi-platform overlay (ngrok/mise/uv) where
# only some per-platform entries were bumped (Finding 1).
stub_claude_partial_multi_pin() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
sed -i.bak 's/"current_version": "1\.0\.0"/"current_version": "1.1.0"/' overlays/updates.json && rm -f overlays/updates.json.bak
# A second, un-bumped pin of the OLD version — e.g. a missed platform entry.
printf '_final: _prev: { demoLinux = { version = "1.0.0"; }; }\n' >> overlays/99-demo.nix
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"bumped darwin entry","files_changed":["overlays/99-demo.nix","overlays/updates.json"]}
JSON
EOF
  chmod +x "$1/claude"
}

# === Case 10: old version still pinned elsewhere in real code (not a comment)
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_partial_multi_pin "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || { cat "$d/esc.log"; fail "case10: a partial multi-pin bump was accepted (exit $rc)"; }
grep -q '"current_version": "1.0.0"' "$d/overlays/updates.json" \
  || fail "case10: partial bump landed in the real repo"
grep -q "still references the old version" "$d/esc.log" \
  || { cat "$d/esc.log"; fail "case10: failed for the wrong reason"; }
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case10: expected exactly one new commit (ledger only)"
rm -rf "$d" "$stub"

# A stub claude that does a complete, correct bump, but also leaves the OLD
# version mentioned only in a comment — the realistic case go/ngrok/tmux/
# yt-dlp-ejs hit in the real repo, where narrative header comments are not
# part of the bump routine. This must still succeed: the gate only cares
# about code, not prose.
stub_claude_fixed_with_stale_comment() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
sed -i.bak 's/"current_version": "1\.0\.0"/"current_version": "1.1.0"/' overlays/updates.json && rm -f overlays/updates.json.bak
sed -i.bak '1s/^/# previously pinned 1.0.0, bumped for CVE-nnnn\n/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"bumped version, left a historical comment","files_changed":["overlays/99-demo.nix","overlays/updates.json"]}
JSON
EOF
  chmod +x "$1/claude"
}

# === Case 11: old version survives only in a comment — must still succeed ==
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_fixed_with_stale_comment "$stub"; stub_nix "$stub" ok
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/esc.log"; fail "case11: a correct bump with a stale comment was rejected (exit $rc)"; }
grep -q "1.1.0" "$d/overlays/99-demo.nix" || fail "case11: fix not cherry-picked into the repo"
rm -rf "$d" "$stub"

# A stub claude that does a complete, correct bump but ALSO writes a file
# outside overlays/ — the scoped `--impure` build would validate a tree
# including it, but the wrapper only ever stages/commits overlays/ (Finding 2).
stub_claude_stray_file() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
sed -i.bak 's/1\.0\.0/1.1.0/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
sed -i.bak 's/"current_version": "1\.0\.0"/"current_version": "1.1.0"/' overlays/updates.json && rm -f overlays/updates.json.bak
mkdir -p patches
echo "some patch content" > patches/demo-fix.patch
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"bumped version and added a supporting patch","files_changed":["overlays/99-demo.nix","overlays/updates.json","patches/demo-fix.patch"]}
JSON
EOF
  chmod +x "$1/claude"
}

# === Case 12: a repair needing files outside overlays/ is refused =========
d="$(setup)"; stub="$(mktemp -d)"; stub_claude_stray_file "$stub"; stub_nix "$stub" broken
run_escalate "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || { cat "$d/esc.log"; fail "case12: a repair touching files outside overlays/ was accepted (exit $rc)"; }
[[ ! -f "$d/patches/demo-fix.patch" ]] \
  || fail "case12: stray file leaked into the real repo — got published to the public mirror"
grep -q "outside overlays/" "$d/esc.log" \
  || { cat "$d/esc.log"; fail "case12: failed for the wrong reason"; }
[[ "$(git -C "$d" log --oneline | wc -l | tr -d ' ')" == "2" ]] \
  || fail "case12: expected exactly one new commit (ledger only)"
rm -rf "$d" "$stub"

# === Case 13: old version is a proper PREFIX of the new one (Finding: the
# gate must strip the new version's own text before looking for the old one,
# or a correct repair like tmux 3.7 -> 3.7a/mise 2026.7.1 -> 2026.7.14 is
# falsely rejected because the new pin's text contains the old version). ===
setup_prefix() { # -> scratch repo path
  local d; d="$(mktemp -d)"
  mkdir -p "$d/overlays" "$d/scripts" "$d/logs"
  cp "$REPO/scripts/quarantine.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/classify-failure.sh" "$REPO/scripts/escalate.sh" \
     "$REPO/scripts/check-overlay-manifest.sh" "$d/scripts/"
  cat > "$d/overlays/updates.json" <<'EOF'
{ "packages": [ { "name": "demo", "overlay": "overlays/99-demo.nix",
    "current_version": "3.7", "update_type": "prebuilt-binary",
    "check": { "method": "github-release", "repo": "demo/demo" } } ],
  "skip": [] }
EOF
  printf '_final: _prev: { demo = { version = "3.7"; }; }\n' > "$d/overlays/99-demo.nix"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  cat > "$d/overlays/health-checks.json" <<'EOF'
{ "assertions": [ { "package": "demo", "skip": "no binary to smoke-test in the test fixture" } ] }
EOF
  printf "error: builder for '/nix/store/x-demo.drv' failed with exit code 1\n" > "$d/logs/build.log"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A && git -C "$d" commit -qm init
  printf '%s' "$d"
}

# A complete, correct bump from 3.7 -> 3.7b: overlay's pin becomes "3.7b",
# which CONTAINS "3.7" as a substring — exactly what previously tripped the
# old-version-absence gate on a fully correct repair.
stub_claude_prefix_bump() { # <stub-dir>
  cat > "$1/claude" <<'EOF'
#!/usr/bin/env bash
sed -i.bak 's/3\.7/3.7b/' overlays/99-demo.nix && rm -f overlays/99-demo.nix.bak
sed -i.bak 's/"current_version": "3\.7"/"current_version": "3.7b"/' overlays/updates.json && rm -f overlays/updates.json.bak
cat > verdict.json <<'JSON'
{"status":"fixed","package":"demo","fingerprint":"compile-failure",
 "verdict":"bumped to 3.7b per upstream's point-release convention","files_changed":["overlays/99-demo.nix","overlays/updates.json"]}
JSON
EOF
  chmod +x "$1/claude"
}

run_escalate_prefix() { # <repo> <stub>
  ( cd "$1" && PATH="$2:$PATH" ESCALATE_CLAUDE_BIN="$2/claude" \
      bash scripts/escalate.sh --package demo --version 3.7b \
        --phase package-build --log logs/build.log >"$1/esc.log" 2>&1 )
}

d="$(setup_prefix)"; stub="$(mktemp -d)"; stub_claude_prefix_bump "$stub"; stub_nix "$stub" ok
run_escalate_prefix "$d" "$stub" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/esc.log"; fail "case13: a correct prefix bump (3.7 -> 3.7b) was rejected (exit $rc)"; }
grep -q "3.7b" "$d/overlays/99-demo.nix" || fail "case13: fix not cherry-picked into the repo"
rm -rf "$d" "$stub"

echo "PASS: test_escalate"
