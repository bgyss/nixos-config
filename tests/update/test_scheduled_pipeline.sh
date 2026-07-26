#!/usr/bin/env bash
# End-to-end test of the two-mode scheduled-check pipeline:
#   --propose-only (and bare invocation): bump -> escalate -> prepare -> build.
#     Never activates.
#   --activate-only <sha>: activate -> health -> rollback-on-failure -> sync.
#
# Every dangerous step is stubbed: no real bump, build, activation, rollback,
# notification, or mirror push, and no real `claude`. Asserts ORDERING and
# branch decisions, which is what actually matters about this script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
REAL_NIX="$(command -v nix)"
fail() { echo "FAIL: $1"; exit 1; }

# setup <bump-outcome> -> repo path
# bump-outcome: "bumped" (commits something) | "nothing" (no-op, exit 0) |
#               "lock" (exit 2, lock contention)
setup() {
  local bump="$1"
  local d; d="$(mktemp -d)"
  mkdir -p "$d/apps/aarch64-darwin" "$d/scripts" "$d/overlays" "$d/logs"
  : > "$d/flake.nix" # locate_flake()'s git-toplevel fallback requires this to exist.
  cp "$REPO/scripts/update-notify.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/quarantine.sh" "$REPO/scripts/classify-failure.sh" "$d/scripts/"
  cp "$REPO/apps/aarch64-darwin/_common.sh" \
     "$REPO/apps/aarch64-darwin/scheduled-check" "$d/apps/aarch64-darwin/"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  printf '{"packages":[],"skip":[],"inputs":{},"pinned_inputs":[]}\n' > "$d/overlays/updates.json"

  # Every step logs to $d/order.log so the test can assert the sequence.
  local trace="$d/order.log"
  make_stub() { # <name> <exit-code> <extra-body>
    cat > "$d/apps/aarch64-darwin/$1" <<EOF
#!/usr/bin/env bash
echo "$1" >> "$trace"
${3:-}
exit $2
EOF
    chmod +x "$d/apps/aarch64-darwin/$1"
  }
  case "$bump" in
    bumped) make_stub bump-overlays 0 'git commit -q --allow-empty -m "overlays: update demo to v2"' ;;
    nothing) make_stub bump-overlays 0 '' ;;
    lock) make_stub bump-overlays 2 '' ;;
  esac
  make_stub prepare 0 ''            # prepare: nothing to do (common case)
  make_stub activate 0 ''
  make_stub rollback 0 ''

  printf '#!/usr/bin/env bash\necho health >> "%s"\nexit 0\n' "$trace" > "$d/scripts/post-activate-health.sh"
  chmod +x "$d/scripts/post-activate-health.sh"

  printf '#!/usr/bin/env bash\necho sync >> "%s"\nexit 0\n' "$trace" > "$d/scripts/sync-to-public.sh"
  printf '#!/usr/bin/env bash\necho escalate >> "%s"\nexit 1\n' "$trace" > "$d/scripts/escalate.sh"
  chmod +x "$d/scripts/sync-to-public.sh" "$d/scripts/escalate.sh"

  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A && git -C "$d" commit -qm init
  printf '%s' "$d"
}

# Like setup, but with zero commits, so `git rev-parse HEAD` fails inside the
# script itself — simulating a broken environment (unborn branch) rather than
# stubbing git.
setup_no_head() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/apps/aarch64-darwin" "$d/scripts" "$d/overlays" "$d/logs"
  : > "$d/flake.nix" # locate_flake()'s git-toplevel fallback requires this to exist.
  cp "$REPO/scripts/update-notify.sh" "$REPO/scripts/update-state.sh" \
     "$REPO/scripts/quarantine.sh" "$REPO/scripts/classify-failure.sh" "$d/scripts/"
  cp "$REPO/apps/aarch64-darwin/_common.sh" \
     "$REPO/apps/aarch64-darwin/scheduled-check" "$d/apps/aarch64-darwin/"
  printf '{"comment":"t","entries":[]}\n' > "$d/overlays/quarantine.json"
  printf '{"packages":[],"skip":[],"inputs":{},"pinned_inputs":[]}\n' > "$d/overlays/updates.json"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  # Deliberately no commit: HEAD stays unborn.
  printf '%s' "$d"
}

stubs() { # <dir> <build-outcome> -> stub PATH dir
  local s; s="$(mktemp -d)"
  if [[ "$2" == "ok" ]]; then
    cat > "$s/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in build) touch ./result; exit 0 ;; store) exit 0 ;; *) exec "$REAL_NIX" "\$@" ;; esac
EOF
  else
    cat > "$s/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
case "\$1" in
  build) echo "error: builder for '/nix/store/x.drv' failed with exit code 1" >&2; exit 1 ;;
  store) exit 0 ;;
  *) exec "$REAL_NIX" "\$@" ;;
esac
EOF
  fi
  cat > "$s/osascript" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$1/notify.log"
EOF
  chmod +x "$s/nix" "$s/osascript"
  printf '%s' "$s"
}

# make_escalate_stub <dir> <exit-code>
# Overwrites scripts/escalate.sh with a stub that appends one line per
# invocation ("pkg=<name> version=<v> phase=<p> log=<log>") to
# <dir>/escalate-calls.log and always exits <exit-code>. Replaces the
# always-exit-1 stub that setup() installs, so tests can control the
# escalation outcome and inspect exactly what was passed.
make_escalate_stub() {
  local d="$1" rc="$2"
  cat > "$d/scripts/escalate.sh" <<EOF
#!/usr/bin/env bash
echo "pkg=\$2 version=\$4 phase=\$6 log=\$8" >> "$d/escalate-calls.log"
exit $rc
EOF
  chmod +x "$d/scripts/escalate.sh"
}

# seed_overlay_entries <dir> <json-entries-array>
seed_overlay_entries() {
  local d="$1" entries="$2"
  jq --argjson e "$entries" '.entries = $e' "$d/overlays/quarantine.json" > "$d/overlays/quarantine.json.tmp"
  mv "$d/overlays/quarantine.json.tmp" "$d/overlays/quarantine.json"
}

run() { # <repo> <stub> [args...]
  local d="$1" s="$2"; shift 2
  ( cd "$d" && PATH="$s:$PATH" UPDATE_STATE_FILE="$d/.state.json" \
      bash apps/aarch64-darwin/scheduled-check "$@" >"$d/run.log" 2>&1 )
}

# === Case 1: propose-only happy path — bump, escalate(none), prepare, build =
d="$(setup bumped)"; s="$(stubs "$d" ok)"
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "case1: expected exit 0, got $rc"; }
order="$(tr '\n' ' ' < "$d/order.log")"
[[ "$order" == "bump-overlays prepare "* ]] || fail "case1: wrong order: $order"
grep -q "activate" "$d/order.log" && fail "case1: --propose-only activated"
[[ -f "$d/logs/proposed-revision" ]] || fail "case1: no proposed-revision written"
sha="$(cat "$d/logs/proposed-revision")"
[[ -n "$sha" ]] || fail "case1: proposed-revision empty"
grep -q "full system build\|==> closure diff" "$d/run.log" 2>/dev/null || \
  grep -q "revision .* built" "$d/logs/nixos-scheduled-check.log" || \
  fail "case1: no evidence a full build ran"
rm -rf "$d" "$s"

# === Case 1b: bare invocation defaults to --propose-only ===================
d="$(setup bumped)"; s="$(stubs "$d" ok)"
run "$d" "$s" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "case1b: expected exit 0, got $rc"
grep -q "activate" "$d/order.log" && fail "case1b: bare invocation activated"
[[ -f "$d/logs/proposed-revision" ]] || fail "case1b: no proposed-revision written"
rm -rf "$d" "$s"

# === Case 2: nothing changed — silent, no build, no proposed-revision ======
d="$(setup nothing)"; s="$(stubs "$d" ok)"
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "case2: expected exit 0, got $rc"
grep -q "activate" "$d/order.log" && fail "case2: activated with nothing to do"
[[ ! -s "$d/notify.log" ]] || { cat "$d/notify.log"; fail "case2: notified on a no-op run"; }
[[ ! -f "$d/logs/proposed-revision" ]] || fail "case2: proposed-revision written with nothing to propose"
rm -rf "$d" "$s"

# === Case 3: build fails -> exit 1, revision quarantined+frozen, notified ==
# Not escalated (spec §3): a system-build failure after per-package builds
# passed is a collision or eval problem, not one package's fault.
d="$(setup bumped)"; s="$(stubs "$d" broken)"
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case3: expected exit 1, got $rc"
grep -q "activate" "$d/order.log" && fail "case3: activated after a failed build"
grep -q "escalate" "$d/order.log" && fail "case3: escalated a revision-level failure"
grep -qi "fail" "$d/notify.log" || fail "case3: no failure notification"
[[ ! -f "$d/logs/proposed-revision" ]] || fail "case3: proposed-revision written despite build failure"
[[ "$(jq -r '[.entries[] | select(.kind=="revision")] | length' "$d/overlays/quarantine.json")" == "1" ]] \
  || fail "case3: no revision-kind quarantine entry written"
[[ "$(jq -r '.entries[] | select(.kind=="revision") | .retry_policy' "$d/overlays/quarantine.json")" == "frozen" ]] \
  || fail "case3: revision entry not frozen"
rm -rf "$d" "$s"

# === Case 3b: a ledger-only commit is NOT a revision ========================
# bump-overlays commits overlays/quarantine.json on any run that records or
# clears an entry, including runs where every bump FAILED. That must never
# trigger a build: the whole content is JSON bookkeeping.
d="$(setup nothing)"; s="$(stubs "$d" ok)"
cat > "$d/apps/aarch64-darwin/bump-overlays" <<EOF
#!/usr/bin/env bash
echo "bump-overlays" >> "$d/order.log"
jq '.entries = [{name:"demo",kind:"overlay",blocked_version:"9.9.9"}]' \
  "$d/overlays/quarantine.json" > "$d/q" && mv "$d/q" "$d/overlays/quarantine.json"
git add overlays/quarantine.json
git -c core.hooksPath=/dev/null commit -q -m "quarantine: update ledger"
exit 1
EOF
chmod +x "$d/apps/aarch64-darwin/bump-overlays"
run "$d" "$s" --propose-only || true
grep -q "activate" "$d/order.log" && fail "case3b: activated on a ledger-only commit"
grep -qi "system-build\|full system build" "$d/logs/nixos-scheduled-check.log" 2>/dev/null \
  && fail "case3b: built on a ledger-only commit"
grep -qi "ready\|activated" "$d/notify.log" 2>/dev/null \
  && fail "case3b: announced a revision for ledger-only churn"
[[ ! -f "$d/logs/proposed-revision" ]] || fail "case3b: proposed-revision written for ledger-only churn"
rm -rf "$d" "$s"

# === Case 4: broken environment — git rev-parse HEAD itself fails ==========
# Migrated from the old test_scheduled_check.sh: HEAD must still notify a
# failure rather than silently doing nothing.
d="$(setup_no_head)"; s="$(stubs "$d" ok)"
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case4: expected exit 1, got $rc"
grep -qi "FAILED" "$d/notify.log" 2>/dev/null || fail "case4: did not notify FAILED"
grep -qi "HEAD" "$d/notify.log" 2>/dev/null || fail "case4: notification should mention HEAD/environment"
rm -rf "$d" "$s"

# === Case 5: exit 2 on lock contention — benign, stay silent ===============
d="$(setup lock)"; s="$(stubs "$d" ok)"
before="$(git -C "$d" rev-parse HEAD)"
run "$d" "$s" --propose-only && rc=0 || rc=$?
after="$(git -C "$d" rev-parse HEAD)"
[[ $rc -eq 2 ]] || fail "case5: expected exit 2, got $rc"
[[ ! -s "$d/notify.log" ]] || { cat "$d/notify.log"; fail "case5: notified on lock contention"; }
[[ "$before" == "$after" ]] || fail "case5: lock contention must not commit"
rm -rf "$d" "$s"

# === Escalation loop (Finding 3): kind:"overlay" quarantine entries drive
# escalate.sh invocations. Covers the 3-slot budget cap, the retry-after:
# transient skip, and the exit 0/1/2 dispatch — none of which any prior case
# exercised, since setup()'s default ledger is empty.

# === Case E1: one escalating overlay entry -> exactly one invocation, with
# the right --package/--version/--phase read from the ledger ===============
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" '[{"name":"demo","kind":"overlay","blocked_version":"2.0.0","phase":"build","retry_policy":"next-version-only","attempts":1}]'
make_escalate_stub "$d" 1
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "caseE1: expected exit 0, got $rc"; }
[[ "$(wc -l < "$d/escalate-calls.log" 2>/dev/null)" -eq 1 ]] 2>/dev/null \
  || { cat "$d/escalate-calls.log" 2>/dev/null; fail "caseE1: expected exactly one escalate.sh invocation"; }
grep -q "^pkg=demo version=2.0.0 phase=build " "$d/escalate-calls.log" \
  || { cat "$d/escalate-calls.log"; fail "caseE1: wrong package/version/phase passed to escalate.sh"; }
rm -rf "$d" "$s"

# === Case E2: retry_policy starting retry-after: is skipped — no invocation
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" '[{"name":"flaky","kind":"overlay","blocked_version":"1.2.3","phase":"build","retry_policy":"retry-after:24","attempts":1}]'
make_escalate_stub "$d" 1
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "caseE2: expected exit 0, got $rc"; }
[[ ! -s "$d/escalate-calls.log" ]] \
  || { cat "$d/escalate-calls.log"; fail "caseE2: escalate.sh invoked for a retry-after (transient) entry"; }
rm -rf "$d" "$s"

FIVE_ENTRIES='[
  {"name":"p1","kind":"overlay","blocked_version":"1","phase":"build","retry_policy":"next-version-only","attempts":1},
  {"name":"p2","kind":"overlay","blocked_version":"1","phase":"build","retry_policy":"next-version-only","attempts":1},
  {"name":"p3","kind":"overlay","blocked_version":"1","phase":"build","retry_policy":"next-version-only","attempts":1},
  {"name":"p4","kind":"overlay","blocked_version":"1","phase":"build","retry_policy":"next-version-only","attempts":1},
  {"name":"p5","kind":"overlay","blocked_version":"1","phase":"build","retry_policy":"next-version-only","attempts":1}
]'

# === Case E3: 3-slot budget cap holds — 5 escalating entries, stub exits 1,
# escalate.sh invoked exactly 3 times ========================================
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" "$FIVE_ENTRIES"
make_escalate_stub "$d" 1
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "caseE3: expected exit 0, got $rc"; }
[[ "$(wc -l < "$d/escalate-calls.log" 2>/dev/null)" -eq 3 ]] 2>/dev/null \
  || { cat "$d/escalate-calls.log" 2>/dev/null; fail "caseE3: budget cap did not hold at 3 invocations"; }
rm -rf "$d" "$s"

# === Case E4: exit 2 does not consume a slot — 5 entries, stub exits 2,
# escalate.sh invoked all 5 times (no budget accounting on a decline) =======
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" "$FIVE_ENTRIES"
make_escalate_stub "$d" 2
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "caseE4: expected exit 0, got $rc"; }
[[ "$(wc -l < "$d/escalate-calls.log" 2>/dev/null)" -eq 5 ]] 2>/dev/null \
  || { cat "$d/escalate-calls.log" 2>/dev/null; fail "caseE4: exit-2 declines must not consume budget slots — expected 5 invocations"; }
rm -rf "$d" "$s"

# === Case E5: exit 0 marks the package fixed-by-Claude and notifies, naming
# it ==========================================================================
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" '[{"name":"demo","kind":"overlay","blocked_version":"2.0.0","phase":"build","retry_policy":"next-version-only","attempts":1}]'
make_escalate_stub "$d" 0
run "$d" "$s" --propose-only && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "caseE5: expected exit 0, got $rc"; }
grep -qi "Claude repaired an overlay" "$d/notify.log" \
  || { cat "$d/notify.log"; fail "caseE5: no repaired-overlay notification"; }
grep -q "demo" "$d/notify.log" || { cat "$d/notify.log"; fail "caseE5: notification did not name the repaired package"; }
rm -rf "$d" "$s"

# === Case E6a: escalate.sh receives logs/bump-<name>.log when present ======
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" '[{"name":"demo","kind":"overlay","blocked_version":"2.0.0","phase":"build","retry_policy":"next-version-only","attempts":1}]'
: > "$d/logs/bump-demo.log"
make_escalate_stub "$d" 1
run "$d" "$s" --propose-only
grep -q "log=.*/logs/bump-demo\.log\$" "$d/escalate-calls.log" \
  || { cat "$d/escalate-calls.log" 2>/dev/null; fail "caseE6a: escalate.sh did not receive the per-package bump log"; }
rm -rf "$d" "$s"

# === Case E6b: escalate.sh falls back to the run log when no per-package
# bump log exists =============================================================
d="$(setup nothing)"; s="$(stubs "$d" ok)"
seed_overlay_entries "$d" '[{"name":"demo","kind":"overlay","blocked_version":"2.0.0","phase":"build","retry_policy":"next-version-only","attempts":1}]'
make_escalate_stub "$d" 1
run "$d" "$s" --propose-only
grep -q "log=.*/logs/nixos-scheduled-check\.log\$" "$d/escalate-calls.log" \
  || { cat "$d/escalate-calls.log" 2>/dev/null; fail "caseE6b: escalate.sh did not fall back to the run log"; }
rm -rf "$d" "$s"

# === Case 6: --activate-only happy path — activate, health, sync, SILENT ===
# Spec §2 "Notification policy": silent on success, including activation.
d="$(setup nothing)"; s="$(stubs "$d" ok)"
sha="$(git -C "$d" rev-parse HEAD)"
run "$d" "$s" --activate-only "$sha" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || { cat "$d/run.log"; fail "case6: expected exit 0, got $rc"; }
order="$(tr '\n' ' ' < "$d/order.log")"
[[ "$order" == *"activate health sync"* ]] || fail "case6: wrong order: $order"
[[ ! -s "$d/notify.log" ]] || { cat "$d/notify.log"; fail "case6: notified on a healthy activation"; }
rm -rf "$d" "$s"

# === Case 7: --activate-only health check fails -> rollback, notify, no sync
d="$(setup nothing)"; s="$(stubs "$d" ok)"
sha="$(git -C "$d" rev-parse HEAD)"
printf '#!/usr/bin/env bash\necho health >> "%s/order.log"\necho "FAIL: demo" >&2\nexit 1\n' "$d" \
  > "$d/scripts/post-activate-health.sh"
chmod +x "$d/scripts/post-activate-health.sh"
run "$d" "$s" --activate-only "$sha" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case7: expected exit 1, got $rc"
order="$(tr '\n' ' ' < "$d/order.log")"
[[ "$order" == *"activate health rollback"* ]] || fail "case7: rollback did not follow failed health: $order"
grep -q "sync" "$d/order.log" && fail "case7: mirrored a revision that failed health"
grep -qi "roll" "$d/notify.log" || { cat "$d/notify.log"; fail "case7: no rollback notification"; }
[[ "$(jq -r '.entries[] | select(.kind=="revision") | .name' "$d/overlays/quarantine.json")" != "" ]] \
  || fail "case7: no revision-kind quarantine entry written"
[[ "$(jq -r '.entries[] | select(.kind=="revision") | .retry_policy' "$d/overlays/quarantine.json")" == "frozen" ]] \
  || fail "case7: revision entry not frozen"
grep -q "escalate" "$d/order.log" && fail "case7: a revision-level health failure must not be escalated"
rm -rf "$d" "$s"

# === Case 8: --activate-only with a missing sha fails cleanly ==============
d="$(setup nothing)"; s="$(stubs "$d" ok)"
run "$d" "$s" --activate-only && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case8a: missing sha should exit 1, got $rc"
grep -q "activate" "$d/order.log" 2>/dev/null && fail "case8a: activated with no sha given"
rm -rf "$d" "$s"

# === Case 8b: --activate-only with a non-committed sha fails cleanly =======
d="$(setup nothing)"; s="$(stubs "$d" ok)"
run "$d" "$s" --activate-only "0000000000000000000000000000000000dead" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case8b: bogus sha should exit 1, got $rc"
grep -q "activate" "$d/order.log" 2>/dev/null && fail "case8b: activated a non-committed sha"
grep -qi "FAILED" "$d/notify.log" 2>/dev/null || fail "case8b: no failure notification for a bogus sha"
rm -rf "$d" "$s"

# === Case 8c: --activate-only <sha> <extra> errors instead of ignoring it ===
d="$(setup nothing)"; s="$(stubs "$d" ok)"
sha="$(git -C "$d" rev-parse HEAD)"
run "$d" "$s" --activate-only "$sha" "unexpected-extra-arg" && rc=0 || rc=$?
[[ $rc -eq 1 ]] || fail "case8c: trailing argument should exit 1, got $rc"
grep -q "activate" "$d/order.log" 2>/dev/null && fail "case8c: activated despite a trailing argument"
rm -rf "$d" "$s"

echo "PASS: test_scheduled_pipeline"
