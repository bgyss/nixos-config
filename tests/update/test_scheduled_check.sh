#!/usr/bin/env bash
# Exercises apps/aarch64-darwin/scheduled-check end-to-end without ever
# invoking a real `prepare` (no real nix build/git-commit against this
# checkout) and without sending a real macOS notification. Everything that
# could touch the network, the nix store, or this checkout's git history is
# stubbed:
#   - a scratch git repo stands in for the flake dir (its own copy of
#     scripts/update-notify.sh + a fake apps/aarch64-darwin/{_common.sh,
#     prepare,scheduled-check}), so `git rev-parse HEAD` / `git commit` only
#     ever touch throwaway state.
#   - nix: `registry list` fails closed so _common.sh's locate_flake() falls
#     back to `git rev-parse --show-toplevel`, resolving to the scratch repo
#     (whatever's cwd at invocation) rather than whatever this host's real
#     "nixos-config" registry entry points at.
#   - osascript: captures the notify() call instead of posting a real
#     notification.
#   - the stub `prepare` is swapped per case to simulate: (a) success with a
#     new commit, (b) success with nothing to commit, (c) a hard failure, (d)
#     a broken environment where `git rev-parse HEAD` itself fails (repo with
#     zero commits, so HEAD doesn't resolve), (e) exit code 2 (lock
#     contention — another prepare run already in progress) — covering the
#     "never activates, fail-safe on error, stay silent on benign lock
#     contention" requirements, including staying silent ONLY when nothing
#     actually changed or the failure was benign.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

REAL_NIX="$(command -v nix)"
STUB="$(mktemp -d)"
cat > "$STUB/nix" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "registry" && "\$2" == "list" ]]; then exit 1; fi
# Never let the scheduled-check verification build (or its closure diff) hit
# the real store: it would try to build this host's actual system closure.
# \$FAKE_NIX_BUILD_RC lets a case choose whether that build "succeeds".
if [[ "\$1" == "build" ]]; then
  touch ./result
  exit "\${FAKE_NIX_BUILD_RC:-0}"
fi
if [[ "\$1" == "store" && "\$2" == "diff-closures" ]]; then exit 0; fi
exec "$REAL_NIX" "\$@"
EOF
chmod +x "$STUB/nix"
cat > "$STUB/osascript" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$NOTIFY_LOG"
EOF
chmod +x "$STUB/osascript"

setup_scratch() {
  local scratch; scratch="$(mktemp -d)"
  git -C "$scratch" init -q
  git -C "$scratch" config user.email "test@example.com"
  git -C "$scratch" config user.name "Test"
  mkdir -p "$scratch/scripts" "$scratch/apps/aarch64-darwin"
  : > "$scratch/flake.nix" # locate_flake()'s git-toplevel fallback requires this to exist.
  cp "$REPO/scripts/update-notify.sh" "$scratch/scripts/update-notify.sh"
  cp "$REPO/apps/aarch64-darwin/_common.sh" "$scratch/apps/aarch64-darwin/_common.sh"
  cp "$REPO/apps/aarch64-darwin/scheduled-check" "$scratch/apps/aarch64-darwin/scheduled-check"
  chmod +x "$scratch/apps/aarch64-darwin/scheduled-check"
  # Stub the public mirror sync: never touch the real public checkout, just
  # record that scheduled-check called it (and when).
  cat > "$scratch/scripts/sync-to-public.sh" <<EOF2
#!/usr/bin/env bash
echo called >> "$scratch/sync-calls.log"
EOF2
  chmod +x "$scratch/scripts/sync-to-public.sh"
  git -C "$scratch" add -A
  git -C "$scratch" commit -q -m "init" --allow-empty
  printf '%s' "$scratch"
}

# Like setup_scratch, but with zero commits, so `git rev-parse HEAD` fails —
# simulating a broken environment (unborn branch / not really a usable repo)
# rather than stubbing git itself.
setup_scratch_no_head() {
  local scratch; scratch="$(mktemp -d)"
  git -C "$scratch" init -q
  git -C "$scratch" config user.email "test@example.com"
  git -C "$scratch" config user.name "Test"
  mkdir -p "$scratch/scripts" "$scratch/apps/aarch64-darwin"
  : > "$scratch/flake.nix"
  cp "$REPO/scripts/update-notify.sh" "$scratch/scripts/update-notify.sh"
  cp "$REPO/apps/aarch64-darwin/_common.sh" "$scratch/apps/aarch64-darwin/_common.sh"
  cp "$REPO/apps/aarch64-darwin/scheduled-check" "$scratch/apps/aarch64-darwin/scheduled-check"
  chmod +x "$scratch/apps/aarch64-darwin/scheduled-check"
  # Deliberately no `git add`/`git commit` here — HEAD stays unborn.
  printf '%s' "$scratch"
}

# run_case <scratch> <prepare_body> [bump_body]
# bump_body defaults to a no-op "nothing to bump" so the pre-existing cases
# below keep exercising exactly what they used to.
run_case() {
  local scratch="$1" prepare_body="$2" bump_body="${3:-exit 0}" notify_log
  notify_log="$(mktemp)"
  cat > "$scratch/apps/aarch64-darwin/prepare" <<EOF2
#!/usr/bin/env bash
$prepare_body
EOF2
  chmod +x "$scratch/apps/aarch64-darwin/prepare"
  # Record the flags scheduled-check passes, so a case can assert on them.
  cat > "$scratch/apps/aarch64-darwin/bump-overlays" <<EOF2
#!/usr/bin/env bash
echo "\$@" >> "$scratch/bump-args.log"
$bump_body
EOF2
  chmod +x "$scratch/apps/aarch64-darwin/bump-overlays"
  (
    cd "$scratch"
    NOTIFY_LOG="$notify_log" FAKE_NIX_BUILD_RC="${FAKE_NIX_BUILD_RC:-0}" \
      PATH="$STUB:$PATH" bash "$scratch/apps/aarch64-darwin/scheduled-check"
  ) || true
  cat "$notify_log"
  rm -f "$notify_log"
}

fail=0

# Case A: prepare succeeds and commits -> expect a "ready" notification.
scratch_a="$(setup_scratch)"
out_a="$(run_case "$scratch_a" 'git commit -q --allow-empty -m "flake.lock: Update"')"
if ! grep -q "ready" <<<"$out_a"; then
  echo "FAIL: case A (new commit) did not notify 'ready': $out_a"; fail=1
fi
rm -rf "$scratch_a"

# Case B: prepare succeeds with nothing to commit -> expect no notification.
scratch_b="$(setup_scratch)"
out_b="$(run_case "$scratch_b" 'exit 0')"
if [[ -n "$out_b" ]]; then
  echo "FAIL: case B (no new commit) should not notify, got: $out_b"; fail=1
fi
rm -rf "$scratch_b"

# Case C: prepare fails -> expect a FAILED notification, no commit.
scratch_c="$(setup_scratch)"
before_c="$(git -C "$scratch_c" rev-parse HEAD)"
out_c="$(run_case "$scratch_c" 'exit 1')"
after_c="$(git -C "$scratch_c" rev-parse HEAD)"
if ! grep -qi "FAILED" <<<"$out_c"; then
  echo "FAIL: case C (prepare failure) did not notify FAILED: $out_c"; fail=1
fi
if [[ "$before_c" != "$after_c" ]]; then
  echo "FAIL: case C (prepare failure) must not commit"; fail=1
fi
rm -rf "$scratch_c"

# Case D: git rev-parse HEAD fails (no commits yet) -> must still notify a
# failure rather than silently doing nothing, even though prepare "succeeds".
scratch_d="$(setup_scratch_no_head)"
out_d="$(run_case "$scratch_d" 'exit 0')"
if ! grep -qi "FAILED" <<<"$out_d"; then
  echo "FAIL: case D (git rev-parse HEAD failure) did not notify FAILED: $out_d"; fail=1
fi
if ! grep -qi "HEAD" <<<"$out_d"; then
  echo "FAIL: case D notification should mention HEAD/environment: $out_d"; fail=1
fi
rm -rf "$scratch_d"

# Case E: prepare exits 2 (lock contention — another prepare run already in
# progress) -> must stay silent, no notification at all. This is distinct
# from a genuine failure: exit 2 means "benign, someone else has the lock",
# not "something broke".
scratch_e="$(setup_scratch)"
before_e="$(git -C "$scratch_e" rev-parse HEAD)"
out_e="$(run_case "$scratch_e" 'exit 2')"
after_e="$(git -C "$scratch_e" rev-parse HEAD)"
if [[ -n "$out_e" ]]; then
  echo "FAIL: case E (lock contention, exit 2) should not notify, got: $out_e"; fail=1
fi
if [[ "$before_e" != "$after_e" ]]; then
  echo "FAIL: case E (lock contention) must not commit"; fail=1
fi
rm -rf "$scratch_e"

# ── Overlay auto-bump cases ─────────────────────────────────────────────────

# Case F: bump-overlays commits, prepare has nothing to do -> the revision is
# only reachable through the bump, so scheduled-check must run the full system
# build itself and then notify "ready".
scratch_f="$(setup_scratch)"
out_f="$(run_case "$scratch_f" 'exit 0' \
  'git commit -q --allow-empty -m "overlays: update claude-code to v9.9.9"')"
if ! grep -q "ready" <<<"$out_f"; then
  echo "FAIL: case F (bump-only commit) did not notify 'ready': $out_f"; fail=1
fi
if ! grep -q "full system build" "$scratch_f/logs/nixos-scheduled-check.log"; then
  echo "FAIL: case F must run the full system build as evidence"; fail=1
fi
# The bump must be handed --no-public-sync (scheduled-check owns the mirror,
# so nothing is published before the full build vouches for it) and the mirror
# must then actually run — otherwise a bump-only run never reaches GitHub.
if ! grep -q -- "--no-public-sync" "$scratch_f/bump-args.log"; then
  echo "FAIL: case F must invoke bump-overlays with --no-public-sync"; fail=1
fi
if [[ ! -s "$scratch_f/sync-calls.log" ]]; then
  echo "FAIL: case F must mirror to the public repo after a successful build"; fail=1
fi
rm -rf "$scratch_f"

# Case G: bump-overlays commits but the verification build fails -> must NOT
# claim the revision is ready; must say the build failed and how to discard.
scratch_g="$(setup_scratch)"
out_g="$(FAKE_NIX_BUILD_RC=1 run_case "$scratch_g" 'exit 0' \
  'git commit -q --allow-empty -m "overlays: update claude-code to v9.9.9"')"
if grep -q "ready" <<<"$out_g"; then
  echo "FAIL: case G (verification build failed) must not notify 'ready': $out_g"; fail=1
fi
if ! grep -qi "FAILED" <<<"$out_g"; then
  echo "FAIL: case G did not notify FAILED: $out_g"; fail=1
fi
if ! grep -q "reset --hard" <<<"$out_g"; then
  echo "FAIL: case G should tell the user how to discard the bump commits: $out_g"; fail=1
fi
if [[ -s "$scratch_g/sync-calls.log" ]]; then
  echo "FAIL: case G must NOT publish bumps the verification build rejected"; fail=1
fi
rm -rf "$scratch_g"

# Case H: partial bump failure — one package committed, another failed
# (exit 1 plus the "Failed: N (names)" summary line). Expect BOTH a "ready"
# notification for what landed and a bump-FAILED notification naming the
# package that didn't.
scratch_h="$(setup_scratch)"
out_h="$(run_case "$scratch_h" 'exit 0' \
  'git commit -q --allow-empty -m "overlays: update uv to v9.9.9"
echo "Failed: 1 (trailbase) — see docs/overlay-update-routine.md"
exit 1')"
if ! grep -q "ready" <<<"$out_h"; then
  echo "FAIL: case H should still propose the successful bump: $out_h"; fail=1
fi
if ! grep -q "trailbase" <<<"$out_h"; then
  echo "FAIL: case H should name the failed package: $out_h"; fail=1
fi
rm -rf "$scratch_h"

# Case I: nothing bumped, nothing prepared -> still completely silent (the
# steady state; a daily notification with no news would train you to ignore
# them). Also asserts the added bump stage introduced no spurious build.
scratch_i="$(setup_scratch)"
out_i="$(run_case "$scratch_i" 'exit 0' 'echo "Nothing to bump."; exit 0')"
if [[ -n "$out_i" ]]; then
  echo "FAIL: case I (no bump, no prepare) should not notify, got: $out_i"; fail=1
fi
if grep -q "full system build" "$scratch_i/logs/nixos-scheduled-check.log"; then
  echo "FAIL: case I must not run a system build when nothing changed"; fail=1
fi
rm -rf "$scratch_i"

# Case J: bump-overlays hits lock contention (exit 2) and prepare does too ->
# benign, stay silent. Guards against exit 2 being treated as a bump failure.
scratch_j="$(setup_scratch)"
out_j="$(run_case "$scratch_j" 'exit 2' 'exit 2')"
if [[ -n "$out_j" ]]; then
  echo "FAIL: case J (lock contention in both stages) should not notify, got: $out_j"; fail=1
fi
rm -rf "$scratch_j"

# Case K: prepare itself commits (an input moved) on top of a bump -> prepare
# already built that exact tree, so scheduled-check must NOT build a second
# time; one "ready" notification for the combined revision.
scratch_k="$(setup_scratch)"
out_k="$(run_case "$scratch_k" 'git commit -q --allow-empty -m "flake.lock: Update"' \
  'git commit -q --allow-empty -m "overlays: update uv to v9.9.9"')"
if ! grep -q "ready" <<<"$out_k"; then
  echo "FAIL: case K did not notify 'ready': $out_k"; fail=1
fi
if grep -q "full system build" "$scratch_k/logs/nixos-scheduled-check.log"; then
  echo "FAIL: case K must not rebuild — prepare already built that tree"; fail=1
fi
rm -rf "$scratch_k"

rm -rf "$STUB"
[[ $fail -eq 0 ]] && echo "PASS: test_scheduled_check" || exit 1
