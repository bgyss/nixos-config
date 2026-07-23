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

run_case() {
  local scratch="$1" prepare_body="$2" notify_log
  notify_log="$(mktemp)"
  cat > "$scratch/apps/aarch64-darwin/prepare" <<EOF2
#!/usr/bin/env bash
$prepare_body
EOF2
  chmod +x "$scratch/apps/aarch64-darwin/prepare"
  (
    cd "$scratch"
    NOTIFY_LOG="$notify_log" PATH="$STUB:$PATH" bash "$scratch/apps/aarch64-darwin/scheduled-check"
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

rm -rf "$STUB"
[[ $fail -eq 0 ]] && echo "PASS: test_scheduled_check" || exit 1
