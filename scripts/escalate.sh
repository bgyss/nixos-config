#!/usr/bin/env bash
# Escalate a classified overlay failure to a budgeted headless Claude session
# (spec §4).
#
# THE CONTRACT, in one line: Claude may edit; only this wrapper may verify and
# commit. A `fixed` verdict is a hypothesis — the wrapper's own build is the
# evidence. A verdict whose build does not reproduce is recorded as gave-up,
# because a model asserting success is exactly the failure mode to design
# against.
#
# Work happens in a throwaway git worktree, never the daily-driver checkout:
# bump-overlays exits 3 when overlays/ is dirty, so leftover edits from a
# failed repair would silently disable the next day's entire run.
#
# Exit: 0 verified fix committed | 1 gave up | 2 skipped (dedup/budget)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO/scripts/update-state.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/quarantine.sh"
# shellcheck source=/dev/null
source "$REPO/scripts/classify-failure.sh"

CLAUDE_BIN="${ESCALATE_CLAUDE_BIN:-claude}"
MAX_TURNS=40
TIMEOUT=900
PACKAGE=""; VERSION=""; PHASE=""; LOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package)   PACKAGE="$2"; shift 2 ;;
    --version)   VERSION="$2"; shift 2 ;;
    --phase)     PHASE="$2"; shift 2 ;;
    --log)       LOG="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PACKAGE" && -n "$VERSION" && -n "$LOG" ]] || {
  echo "usage: escalate.sh --package <n> --version <v> --phase <p> --log <f>" >&2; exit 2; }

MANIFEST="$REPO/overlays/updates.json"
fingerprint="$(classify_failure "$LOG" | cut -f1)"

# ── Budget gates (spec §5) ────────────────────────────────────────────────
if ! quarantine_should_escalate "$PACKAGE" "$fingerprint"; then
  echo "escalate: skipping $PACKAGE — '$fingerprint' already gave up, or attempt ceiling reached"
  exit 2
fi

# ── Assemble the brief ────────────────────────────────────────────────────
# Deliberately small (target <3k tokens) and pre-digested. Handing over the
# repo to explore is where tokens go to die.
ts="$(date -u +%Y%m%dT%H%M%SZ)"
brief="$REPO/logs/escalation-${PACKAGE}-${ts}.md"
mkdir -p "$REPO/logs"

pkg_json="$(jq --arg n "$PACKAGE" '.packages[] | select(.name==$n)' "$MANIFEST")"
overlay_rel="$(jq -r '.overlay' <<<"$pkg_json")"
update_type="$(jq -r '.update_type' <<<"$pkg_json")"
prior="$(quarantine_field "$PACKAGE" escalation_verdict)"

# Record this attempt in the ledger now, so quarantine_set_escalation below has
# an entry to attach status/verdict to — quarantine_set_escalation only updates
# an EXISTING entry, it never creates one. In the normal pipeline the caller
# that detected the failure has usually already called quarantine_record, but
# this upsert is idempotent (same blocked_version just increments attempts)
# so it is always safe to call here too.
quarantine_record "$PACKAGE" overlay "$VERSION" "$(jq -r '.current_version' <<<"$pkg_json")" \
  "$PHASE" "$fingerprint" next-version-only "$(tail -c 500 "$LOG" 2>/dev/null | quarantine_sanitize)"

cat > "$brief" <<EOF
Use the overlay-repair skill.

A mechanical overlay bump failed and was rolled back. Repair it, or conclude it
needs a human.

## Package
- name: $PACKAGE
- attempted version: $VERSION
- last known-good version: $(jq -r '.current_version' <<<"$pkg_json")
- overlay file: $overlay_rel
- update_type: $update_type
- failure phase: $PHASE
- classified fingerprint: $fingerprint

## Manifest entry
\`\`\`json
$pkg_json
\`\`\`

## Prior escalation verdict for this package
${prior:-none}

## Build log (tail, store paths collapsed)
\`\`\`
$(tail -80 "$LOG" 2>/dev/null | quarantine_sanitize)
\`\`\`

## What to do
1. Read $overlay_rel and the '$update_type' section of docs/overlay-update-routine.md.
2. Make the minimal edit that could plausibly fix this, bumping the overlay's
   pinned version/hash AND overlays/updates.json's current_version together.
3. Verify with a scoped build:
   nix build --no-link --impure --expr 'let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./$overlay_rel) ]; }; in pkgs.$PACKAGE'
4. Write verdict.json in the repo root (schema in the skill). Do NOT commit.

If two attempts do not work, write status "gave-up" with a precise diagnosis.
A wrong-but-building overlay is worse than a frozen one.
EOF

# ── Throwaway worktree ────────────────────────────────────────────────────
wt="$(mktemp -d)/repair"
branch="escalate/${PACKAGE}-${ts}"
if ! git -C "$REPO" worktree add -q -b "$branch" "$wt" HEAD; then
  echo "escalate: could not create worktree" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "wrapper could not create a git worktree"
  exit 1
fi
cleanup() {
  git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO" branch -D "$branch" >/dev/null 2>&1 || true
  rm -rf "$(dirname "$wt")"
}
trap cleanup EXIT

# ── Run the model ─────────────────────────────────────────────────────────
# Allowed tools ARE the contract: no sudo, no git commit, no git push, no
# network fetch beyond the two prefetch commands.
session_log="$REPO/logs/escalation-${PACKAGE}-${ts}.session.log"
start_epoch="$(date +%s)"
( cd "$wt" && timeout "$TIMEOUT" "$CLAUDE_BIN" -p --model sonnet \
    --max-turns "$MAX_TURNS" \
    --permission-mode acceptEdits \
    --allowedTools 'Read,Edit,Write,Bash(nix build:*),Bash(nix-prefetch-url:*),Bash(nix hash:*),Bash(nix fmt),Bash(git diff:*)' \
    "$(cat "$brief")" ) >"$session_log" 2>&1
claude_rc=$?
duration=$(( $(date +%s) - start_epoch ))

# ── Read the verdict ──────────────────────────────────────────────────────
# A missing or malformed verdict is gave-up, never an implicit success.
status="gave-up"; verdict="no verdict.json produced (claude exited $claude_rc)"
if [[ -f "$wt/verdict.json" ]] && jq empty "$wt/verdict.json" 2>/dev/null; then
  status="$(jq -r '.status // "gave-up"' "$wt/verdict.json")"
  verdict="$(jq -r '.verdict // "no verdict text"' "$wt/verdict.json")"
fi
rm -f "$wt/verdict.json"

printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$PACKAGE" "$status" "$duration" \
  "$(grep -oE '[0-9]+ tokens' "$session_log" 2>/dev/null | tail -1 | tr -d ' tokens')" \
  >> "$REPO/logs/escalation-costs.tsv"

if [[ "$status" != "fixed" ]]; then
  echo "escalate: $PACKAGE gave up — $verdict"
  quarantine_set_escalation "$PACKAGE" "gave-up" "$verdict"
  exit 1
fi

# ── Independent verification — the wrapper's build, not Claude's claim ────
if [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
  echo "escalate: verdict claimed 'fixed' but nothing changed — treating as gave-up" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "claimed fixed but produced no diff: $verdict"
  exit 1
fi

overlay_rel_wt="$overlay_rel"
if ! ( cd "$wt" && nix build --no-link --impure --expr \
        "let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./$overlay_rel_wt) ]; }; in pkgs.${PACKAGE}" ) \
      >>"$session_log" 2>&1; then
  echo "escalate: 'fixed' verdict did not reproduce — scoped build failed. Treating as gave-up." >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "verdict claimed fixed but the wrapper's scoped build failed to reproduce it: $verdict"
  exit 1
fi

# Full-system verification, hardcoded to this repo's one darwin host. Not
# read from apps/aarch64-darwin/_common.sh's FLAKE_SYSTEM_ATTR: that file is
# meant to be sourced from apps/, not scripts/, and pulling it in here would
# couple this script to that directory's assumptions for one constant.
if ! ( cd "$wt" && nix build ".#darwinConfigurations.garmonbozia.system" --no-link ) \
      >>"$session_log" 2>&1; then
  echo "escalate: scoped build passed but the full system build failed. Treating as gave-up." >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "verification: scoped build passed, full system build failed: $verdict"
  exit 1
fi

# ── Commit in the worktree, cherry-pick into the real checkout ────────────
git -C "$wt" add -A
git -C "$wt" -c core.hooksPath=/dev/null commit -q \
  -m "overlays: repair $PACKAGE bump to $VERSION

Escalated repair, verified by scoped + full system build.
Verdict: $verdict"
fix_sha="$(git -C "$wt" rev-parse HEAD)"

if ! git -C "$REPO" cherry-pick "$fix_sha" >>"$session_log" 2>&1; then
  git -C "$REPO" cherry-pick --abort >/dev/null 2>&1 || true
  echo "escalate: cherry-pick of the verified fix failed" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "verified fix could not be cherry-picked cleanly"
  exit 1
fi

quarantine_set_escalation "$PACKAGE" "fixed" "$verdict"
# Deliberately NOT quarantine_clear here: quarantine_clear removes the whole
# entry (there is no "unblock but keep escalation" op), which would erase the
# escalation_status="fixed" record we just wrote. blocked_version staying on
# the ledger is harmless — it only blocks that exact (now-superseded) version,
# per quarantine_is_blocked's next-version-only semantics.
echo "escalate: $PACKAGE repaired and committed as $(git -C "$REPO" rev-parse --short HEAD)"
echo "escalate: verdict — $verdict"
exit 0
