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

echo "PASS: test_unpin_retry (unpin_retry_due)"

# ─── attempt_unpin: pure-probe worktree verification ───────────────────────
# Hermetic: no real `nix flake update`, no real `nix build`, no network, no
# commit against this checkout. A scratch git repo stands in for the live
# checkout; `nix` is stubbed on PATH — `flake update <name>` simulates the
# lock update by directly rewriting the worktree's flake.lock via jq
# (controlled by $UNPIN_TEST_MOVE_REV), and `build` succeeds/fails per
# $UNPIN_TEST_BUILD_OK. Everything else falls through to the real `nix`
# (needed by `git`'s own machinery indirectly, and harmless since attempt_unpin
# never calls anything else on `nix`).
#
# shellcheck source=/dev/null
source "$REPO/apps/aarch64-darwin/_common.sh"

REAL_NIX="$(command -v nix)"
PINNED_REF="deadbeef0000000000000000000000000000dead"
UNPIN_REF="github:NixOS/nixpkgs/nixpkgs-unstable"
NEW_REV="cafebabe1111111111111111111111111111cafe"
# Decoy plain `nixpkgs` node's rev — must NEVER change across any case below;
# a fix that reads it instead of the real `nixpkgs_2` node would incorrectly
# see this as "did not move".
DECOY_REV="0000decoy0000decoy0000decoy0000decoy000"

# <scratch-dir> -> writes a fresh scratch git repo with a fake pinned input.
setup_scratch() {
  local d; d="$TMP/scratch-$RANDOM-$RANDOM"
  mkdir -p "$d/overlays"
  cat > "$d/flake.nix" <<EOF
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/$PINNED_REF";
  };
}
EOF
  # Mirrors the real repo's flake.lock shape: agenix's own transitive
  # nixpkgs/home-manager/darwin already claim the plain node names, so nix
  # suffixes ours (`nixpkgs` -> `nixpkgs_2`). root.inputs.nixpkgs therefore
  # points at node `nixpkgs_2`, and a decoy plain `nixpkgs` node (unrelated,
  # never touched by `nix flake update nixpkgs`) sits alongside it holding a
  # DIFFERENT rev that never changes. A test reading `.nodes.nixpkgs` instead
  # of resolving through root.inputs would silently pass against the decoy.
  cat > "$d/flake.lock" <<EOF
{
  "nodes": {
    "root": {
      "inputs": { "nixpkgs": "nixpkgs_2" }
    },
    "nixpkgs": {
      "locked": {
        "type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "$DECOY_REV"
      }
    },
    "nixpkgs_2": {
      "locked": {
        "type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "$PINNED_REF"
      }
    }
  },
  "root": "root",
  "version": 7
}
EOF
  cat > "$d/overlays/updates.json" <<EOF
{
  "packages": [], "skip": [], "inputs": {},
  "pinned_inputs": [
    {
      "name": "nixpkgs",
      "flake_input": "nixpkgs",
      "pinned_ref": "$PINNED_REF",
      "unpin_ref": "$UNPIN_REF",
      "reason": "test fixture",
      "risk": "high",
      "last_verified": "2026-07-21",
      "unpin_when": "never",
      "rollback_hint": "n/a",
      "retry_cadence_hours": 168
    }
  ]
}
EOF
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  git -C "$d" add -A && git -C "$d" commit -qm init
  printf '%s' "$d"
}

write_unpin_nix_stub() { # <stub-dir> <move_rev:0|1> <build_ok:0|1>
  local stub="$1" move="$2" ok="$3"
  cat > "$stub/nix" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "registry list") exit 1 ;; esac
if [[ "\$1" == "flake" && "\$2" == "update" ]]; then
  if [[ "$move" == "1" ]]; then
    jq --arg r "$NEW_REV" '.nodes.nixpkgs_2.locked.rev = \$r' flake.lock > flake.lock.tmp && mv flake.lock.tmp flake.lock
  fi
  exit 0
fi
if [[ "\$1" == "build" ]]; then
  if [[ "$ok" == "1" ]]; then exit 0; else echo "error: build failed" >&2; exit 1; fi
fi
exec "$REAL_NIX" "\$@"
EOF
  chmod +x "$stub/nix"
}

run_attempt_unpin() { # <scratch-dir> <move_rev> <build_ok> -> sets $out $rc
  local d="$1" move="$2" ok="$3" stub
  stub="$TMP/stub-$RANDOM-$RANDOM"; mkdir -p "$stub"
  write_unpin_nix_stub "$stub" "$move" "$ok"
  export FLAKE_DIR="$d"
  export MANIFEST="$d/overlays/updates.json"
  export QUARANTINE_FILE="$d/overlays/quarantine.json"
  export FLAKE_SYSTEM_ATTR="fakeSystem"
  printf '{"comment":"t","entries":[]}\n' > "$QUARANTINE_FILE"
  set +e
  out="$(PATH="$stub:$PATH" attempt_unpin nixpkgs 2>&1)"
  rc=$?
  set -e
  rm -rf "$stub"
}

assert_no_worktree_leak() { # <scratch-dir>
  local d="$1" wt
  wt="$(git -C "$d" worktree list | wc -l | tr -d ' ')"
  [[ "$wt" == "1" ]] || fail "worktree leaked for $d: $(git -C "$d" worktree list)"
}

# --- Case: rev did not move -> failure (the original false-success bug) ----
D1="$(setup_scratch)"
run_attempt_unpin "$D1" 0 1
[[ $rc -eq 1 ]] || fail "rev-unchanged case: expected return 1, got $rc"
echo "$out" | grep -qi "success\|can be removed\|ACTION REQUIRED" \
  && fail "rev-unchanged case: must NOT report success: $out"
n_entries="$(jq '.entries | length' "$QUARANTINE_FILE")"
[[ "$n_entries" == "1" ]] || fail "rev-unchanged case: expected a ledger entry, got $n_entries"
assert_no_worktree_leak "$D1"
echo "PASS: test_unpin_retry (rev-did-not-move -> failure, no false success)"

# --- Case: rev moved + build passes -> success ------------------------------
D2="$(setup_scratch)"
FLAKE_NIX_SNAPSHOT="$(cat "$D2/flake.nix")"
FLAKE_LOCK_SNAPSHOT="$(cat "$D2/flake.lock")"
run_attempt_unpin "$D2" 1 1
[[ $rc -eq 0 ]] || fail "rev-moved+build-ok case: expected return 0, got $rc: $out"
last_attempt="$(jq -r '.entries[] | select(.name=="nixpkgs") | .last_attempt' "$QUARANTINE_FILE")"
[[ -n "$last_attempt" && "$last_attempt" != "null" ]] || fail "success case: last_attempt not recorded"
# Data-loss regression guard: the live scratch checkout's flake.nix/flake.lock
# must be BYTE-IDENTICAL after a successful verification — the whole point of
# the worktree redesign is that success never touches the live tree.
[[ "$(cat "$D2/flake.nix")" == "$FLAKE_NIX_SNAPSHOT" ]] || fail "success case: live flake.nix was modified"
[[ "$(cat "$D2/flake.lock")" == "$FLAKE_LOCK_SNAPSHOT" ]] || fail "success case: live flake.lock was modified"
assert_no_worktree_leak "$D2"
echo "PASS: test_unpin_retry (rev-moved + build passes -> success, live tree untouched)"

# --- Case: rev moved + build fails -> failure -------------------------------
D3="$(setup_scratch)"
FLAKE_NIX_SNAPSHOT3="$(cat "$D3/flake.nix")"
FLAKE_LOCK_SNAPSHOT3="$(cat "$D3/flake.lock")"
run_attempt_unpin "$D3" 1 0
[[ $rc -eq 1 ]] || fail "rev-moved+build-fail case: expected return 1, got $rc"
n_entries3="$(jq '.entries | length' "$QUARANTINE_FILE")"
[[ "$n_entries3" == "1" ]] || fail "rev-moved+build-fail case: expected a ledger entry, got $n_entries3"
[[ "$(cat "$D3/flake.nix")" == "$FLAKE_NIX_SNAPSHOT3" ]] || fail "build-fail case: live flake.nix was modified"
[[ "$(cat "$D3/flake.lock")" == "$FLAKE_LOCK_SNAPSHOT3" ]] || fail "build-fail case: live flake.lock was modified"
assert_no_worktree_leak "$D3"
echo "PASS: test_unpin_retry (rev-moved + build fails -> failure, live tree untouched)"

# --- Case: missing unpin_ref -> returns 1 without attempting anything ------
D4="$(setup_scratch)"
jq 'del(.pinned_inputs[0].unpin_ref)' "$D4/overlays/updates.json" > "$D4/overlays/updates.json.tmp" \
  && mv "$D4/overlays/updates.json.tmp" "$D4/overlays/updates.json"
run_attempt_unpin "$D4" 1 1
[[ $rc -eq 1 ]] || fail "missing unpin_ref case: expected return 1, got $rc"
if [[ -f "$QUARANTINE_FILE" ]]; then
  n_entries4="$(jq '.entries | length' "$QUARANTINE_FILE" 2>/dev/null || echo 0)"
  [[ "$n_entries4" == "0" ]] || fail "missing unpin_ref case: must not attempt/record anything, got $n_entries4 entries"
fi
assert_no_worktree_leak "$D4"
echo "PASS: test_unpin_retry (missing unpin_ref -> no attempt)"

# --- Case: root.inputs lacks the input entirely -> locked_rev_for_input ----
# ---   returns empty -> treated as failure, never success ------------------
D5="$(setup_scratch)"
# attempt_unpin's worktree is created from committed HEAD, not the working
# tree, so the edit must be committed for the worktree to see it.
jq 'del(.nodes.root.inputs.nixpkgs)' "$D5/flake.lock" > "$D5/flake.lock.tmp" \
  && mv "$D5/flake.lock.tmp" "$D5/flake.lock"
git -C "$D5" commit -qam "test: drop nixpkgs from root.inputs"
FLAKE_NIX_SNAPSHOT5="$(cat "$D5/flake.nix")"
FLAKE_LOCK_SNAPSHOT5="$(cat "$D5/flake.lock")"
run_attempt_unpin "$D5" 1 1
[[ $rc -eq 1 ]] || fail "unresolvable root.inputs node case: expected return 1, got $rc: $out"
echo "$out" | grep -qi "success\|can be removed\|ACTION REQUIRED" \
  && fail "unresolvable root.inputs node case: must NOT report success: $out"
n_entries5="$(jq '.entries | length' "$QUARANTINE_FILE")"
[[ "$n_entries5" == "1" ]] || fail "unresolvable root.inputs node case: expected a ledger entry, got $n_entries5"
[[ "$(cat "$D5/flake.nix")" == "$FLAKE_NIX_SNAPSHOT5" ]] || fail "unresolvable node case: live flake.nix was modified"
assert_no_worktree_leak "$D5"
echo "PASS: test_unpin_retry (root.inputs missing the input entirely -> failure, not success)"

echo "PASS: test_unpin_retry"
