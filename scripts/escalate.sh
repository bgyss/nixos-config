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

# ── Safety net: install before any ledger write ──────────────────────────
# Installed before quarantine_record below writes anything, not after. If the
# script died between a ledger write and trap installation -- mktemp -d
# failing, a brief-write failure, SIGTERM from the launchd agent -- the
# ledger would be left modified and uncommitted, and bump-overlays refuses to
# start (exit 3) on every future run, forever. $wt/$branch/$wt_parent are not
# assigned until the worktree section further down, so cleanup guards them.
commit_ledger() {
  git -C "$REPO" status --porcelain -- overlays/quarantine.json 2>/dev/null | grep -q . || return 0
  git -C "$REPO" add overlays/quarantine.json 2>/dev/null || true
  git -C "$REPO" -c core.hooksPath=/dev/null commit -q -o overlays/quarantine.json \
    -m "quarantine: record escalation outcome" 2>/dev/null || true
  return 0
}
cleanup() {
  [[ -n "${wt:-}" ]] && git -C "$REPO" worktree remove --force "$wt" >/dev/null 2>&1
  [[ -n "${branch:-}" ]] && git -C "$REPO" branch -D "$branch" >/dev/null 2>&1
  [[ -n "${wt_parent:-}" ]] && rm -rf "$wt_parent"
  commit_ledger
}
trap cleanup EXIT

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
# The pre-repair pinned version, i.e. what the overlay pins right now (the
# worktree starts from this rolled-back, known-good tree). Used below as the
# load-bearing "did the bump actually land" check (Finding 1).
known_good="$(jq -r '.current_version' <<<"$pkg_json")"

# Record this attempt in the ledger now, so quarantine_set_escalation below has
# an entry to attach status/verdict to — quarantine_set_escalation only updates
# an EXISTING entry, it never creates one. bump-overlays already recorded this
# failure in the normal pipeline; recording it again would double-count
# attempts, and attempts>=3 auto-promotes to `frozen`, which blocks EVERY
# version forever — so two real failures would permanently freeze the package
# instead of three. Only create an entry here when nothing recorded the
# failure first (i.e. this script invoked directly). Keyed on the blocked
# VERSION, not mere presence: a stale entry for an older version (e.g.
# blocked_version 0.9.0 while we're now escalating for 1.1.0) must still be
# refreshed here, or the verdict attaches to the wrong version and the ledger
# never reflects the version actually being escalated.
if [[ "$(quarantine_field "$PACKAGE" blocked_version)" != "$VERSION" ]]; then
  quarantine_record "$PACKAGE" overlay "$VERSION" "$(jq -r '.current_version' <<<"$pkg_json")" \
    "$PHASE" "$fingerprint" next-version-only "$(tail -c 500 "$LOG" 2>/dev/null | quarantine_sanitize)"
fi

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
4. Write verdict.json in the worktree root (schema in the skill). Do NOT commit.

If two attempts do not work, write status "gave-up" with a precise diagnosis.
A wrong-but-building overlay is worse than a frozen one.
EOF

# ── Throwaway worktree ────────────────────────────────────────────────────
# overlays/quarantine.json lives under overlays/, and bump-overlays refuses to
# start when overlays/ is dirty (exit 3). bump-overlays runs BEFORE this
# script in the daily pipeline, so its own trap cannot clean up after us: any
# ledger write we leave uncommitted wedges every future run, permanently and
# silently. (commit_ledger/cleanup/trap are installed above, before the
# quarantine_record call, so this section only needs to assign the paths.)
wt_parent="$(mktemp -d)"
wt="$wt_parent/repair"
branch="escalate/${PACKAGE}-${ts}"
session_log="$REPO/logs/escalation-${PACKAGE}-${ts}.session.log"
if ! git -C "$REPO" worktree add -q -b "$branch" "$wt" HEAD; then
  echo "escalate: could not create worktree" >&2
  # infra-error, not gave-up: no model ever ran, so this is not a verdict.
  # quarantine_should_escalate only refuses on exactly "gave-up", so this
  # leaves the fingerprint-dedup brake unarmed and the package retryable on
  # the next run.
  quarantine_set_escalation "$PACKAGE" "infra-error" "wrapper could not create a git worktree"
  exit 1
fi

# Run the manifest-consistency check against the PRISTINE worktree, before the
# model touches anything. check-overlay-manifest.sh validates the ENTIRE
# manifest (every package's overlay/skip coverage, cadence fields, etc.), not
# just $PACKAGE. In the daily pipeline bump-overlays commits earlier in the
# same run with no `nix flake check` gate, so drift it introduces for package
# X must not turn a genuine repair of package Y into a misleading gave-up. If
# the manifest is already broken here, that's pre-existing and not
# attributable to this repair, so the later gate is skipped (never silently
# weakened — just scoped to what this repair could plausibly have caused).
pristine_manifest_ok=1
if ! bash "$REPO/scripts/check-overlay-manifest.sh" "$wt" >>"$session_log" 2>&1; then
  pristine_manifest_ok=0
  echo "escalate: overlay manifest check already failing before repair started (pre-existing drift unrelated to $PACKAGE) — post-repair manifest gate will be skipped" >>"$session_log"
fi

# ── Run the model ─────────────────────────────────────────────────────────
# Allowed tools ARE the contract: no sudo, no git commit, no git push, no
# network fetch beyond the two prefetch commands.
start_epoch="$(date +%s)"
( cd "$wt" && timeout "$TIMEOUT" "$CLAUDE_BIN" -p --model sonnet \
    --max-turns "$MAX_TURNS" \
    --permission-mode acceptEdits \
    --allowedTools 'Read,Edit,Write,Bash(nix build:*),Bash(nix-prefetch-url:*),Bash(nix hash:*),Bash(nix fmt),Bash(git diff:*)' \
    "$(cat "$brief")" ) >>"$session_log" 2>&1
claude_rc=$?
duration=$(( $(date +%s) - start_epoch ))

# ── Read the verdict ──────────────────────────────────────────────────────
# A missing or malformed verdict is gave-up, never an implicit success —
# EXCEPT exit 126/127 (POSIX: command found but not executable / command not
# found), which mean the wrapper's own environment couldn't even launch
# $CLAUDE_BIN (e.g. a launchd job whose PATH doesn't reach the nix profile).
# That is a wrapper/infrastructure failure, not a model verdict, and must be
# recorded as "infra-error" rather than "gave-up" — quarantine_should_escalate
# only refuses future escalations on exactly "gave-up", so misclassifying a
# wedged binary as gave-up would permanently disable escalation for this
# package/fingerprint even after the environment is fixed (the fingerprint
# deliberately survives version changes, so nothing else would ever clear
# it).
if [[ $claude_rc -eq 126 || $claude_rc -eq 127 ]]; then
  status="infra-error"
  verdict="wrapper could not execute \$CLAUDE_BIN ($CLAUDE_BIN exited $claude_rc — not found or not executable)"
else
  status="gave-up"; verdict="no verdict.json produced (claude exited $claude_rc)"
  if [[ -f "$wt/verdict.json" ]] && jq empty "$wt/verdict.json" 2>/dev/null; then
    status="$(jq -r '.status // "gave-up"' "$wt/verdict.json")"
    verdict="$(jq -r '.verdict // "no verdict text"' "$wt/verdict.json")"
  fi
fi
rm -f "$wt/verdict.json"

# Logged AFTER verification, with the wrapper's own final outcome — never the
# model's claimed status. Logging the claim here would let a lying run record
# "fixed" in the very TSV that's the stated input for retuning the token
# brakes, over-reporting successes.
log_cost() { # <outcome>
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$PACKAGE" "$1" "$duration" \
    "$(grep -oE '[0-9]+ tokens' "$session_log" 2>/dev/null | tail -1 | tr -d ' tokens')" \
    >> "$REPO/logs/escalation-costs.tsv"
}

if [[ "$status" != "fixed" ]]; then
  echo "escalate: $PACKAGE $status — $verdict"
  quarantine_set_escalation "$PACKAGE" "$status" "$verdict"
  log_cost "$status"
  exit 1
fi

# ── Independent verification — the wrapper's build, not Claude's claim ────
if [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
  echo "escalate: verdict claimed 'fixed' but nothing changed — treating as gave-up" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "claimed fixed but produced no diff: $verdict"
  log_cost "gave-up"
  exit 1
fi

# Scope the staging now (rather than at commit time below) so the landing
# gates that follow can inspect the cached diff. `git add -A` would sweep in
# any scratch file the model left behind, and everything from here through
# the cherry-pick fires the post-commit mirror hook, which publishes to a
# PUBLIC repo on a denylist basis — so an unlisted stray file auto-publishes
# with no human in the loop.
git -C "$wt" add -- overlays/

# The scoped build below uses `--impure --expr` against the live worktree
# filesystem, so it validates a tree that includes any file the model wrote
# ANYWHERE, not just what we stage. A repair that (also) needs a file outside
# overlays/ would therefore be "verified" and then committed WITHOUT that
# file — an incomplete repair, published. Refuse loudly and attributably
# instead of silently shipping it. Cheap filesystem check, so it runs before
# either build.
stray="$(git -C "$wt" status --porcelain -- . ':(exclude)overlays/')"
if [[ -n "$stray" ]]; then
  echo "escalate: repair touched files outside overlays/ (not supported):" >&2
  printf '%s\n' "$stray" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "repair needs files outside overlays/ (not supported): $(printf '%s' "$stray" | tr '\n' ' ')"
  log_cost "gave-up"
  exit 1
fi

# The worktree starts from the rolled-back, KNOWN-GOOD tree, so both builds
# below pass trivially for any change that doesn't break them. Without these
# gates a model could write overlays/NOTES.md, claim "fixed", and get it
# committed and published while the overlay still pins the broken version --
# and because success clears the ledger, that loop repeats daily forever.
# "Verified" has to mean the bump actually landed.
if ! git -C "$wt" diff --cached --name-only | grep -qx "$overlay_rel"; then
  echo "escalate: 'fixed' but $overlay_rel itself was not modified" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "claimed fixed without touching $overlay_rel: $verdict"
  log_cost "gave-up"
  exit 1
fi
if ! grep -qF "$VERSION" "$wt/$overlay_rel"; then
  echo "escalate: 'fixed' but $overlay_rel does not pin $VERSION" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "overlay does not pin $VERSION after repair: $verdict"
  log_cost "gave-up"
  exit 1
fi
# "Version present" is not "version pinned": a comment mentioning the new
# version satisfies the substring test above while `version = "<old>"` sits
# untouched. The load-bearing check is that the OLD version is gone — which
# also catches the realistic case of a multi-platform overlay (ngrok/mise/uv
# pin the version in several per-platform URLs) where only some entries were
# bumped.
#
# Comment lines are excluded from this check (audited against every overlay
# in the repo): 55-go.nix, 20-ngrok.nix and 96-tmux.nix each carry a header
# comment that hardcodes the currently-pinned version in prose ("bump to
# 1.26.5 until nixpkgs catches up"), and 91-yt-dlp.nix's yt-dlp-ejs section
# has narrative comments hardcoding its current version ("Bump yt-dlp-ejs to
# 0.8.0 ..."). Nothing in the routine or in bump-overlays keeps those header
# comments in sync with the pinned version on every bump (50-trailbase.nix's
# and 30-mise.nix's headers are ALREADY stale relative to their real pinned
# versions, proving it) — so requiring the old version to vanish from prose
# comments would fail a fully correct functional repair. The old version must
# still vanish from actual code (including every per-platform entry), which
# is what makes this catch real partial bumps.
#
# Also strip occurrences of the NEW version first: when the old version is a
# proper prefix of the new one (mise 2026.7.1 -> 2026.7.14; tmux 3.7 -> 3.7b,
# tmux's actual release convention for 3.3a/3.5a-style point releases) the new
# pin's own text contains the old version as a substring, and a completely
# correct repair would otherwise be rejected. A leftover old pin from a real
# partial bump is never inside a new-version match, so this still catches it.
if grep -v '^[[:space:]]*#' "$wt/$overlay_rel" | sed "s/${VERSION//./\\.}//g" | grep -qF "$known_good"; then
  echo "escalate: 'fixed' but $overlay_rel still references the old version $known_good" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "overlay still references $known_good after repair — a partial bump: $verdict"
  log_cost "gave-up"
  exit 1
fi
manifest_version="$(jq -r --arg n "$PACKAGE" \
  '.packages[] | select(.name==$n) | .current_version' "$wt/overlays/updates.json")"
if [[ "$manifest_version" != "$VERSION" ]]; then
  echo "escalate: 'fixed' but updates.json still says $manifest_version, not $VERSION" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "updates.json current_version is $manifest_version, expected $VERSION: $verdict"
  log_cost "gave-up"
  exit 1
fi
# Skipped when the manifest was already broken before the repair started
# (recorded pristine, above) — that drift is not attributable to this repair,
# and blaming it on $PACKAGE would produce a misleading gave-up verdict for
# an unrelated package's problem.
if [[ "$pristine_manifest_ok" -eq 1 ]]; then
  if ! bash "$wt/scripts/check-overlay-manifest.sh" "$wt" >>"$session_log" 2>&1; then
    echo "escalate: 'fixed' but the overlay manifest check failed" >&2
    quarantine_set_escalation "$PACKAGE" "gave-up" \
      "repair left overlays/updates.json inconsistent with the overlay: $verdict"
    log_cost "gave-up"
    exit 1
  fi
else
  echo "escalate: skipping post-repair manifest gate — check-overlay-manifest.sh already failed before repair started (pre-existing drift, not attributable to $PACKAGE)" >>"$session_log"
fi

overlay_rel_wt="$overlay_rel"
if ! ( cd "$wt" && nix build --no-link --impure --expr \
        "let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./$overlay_rel_wt) ]; }; in pkgs.${PACKAGE}" ) \
      >>"$session_log" 2>&1; then
  echo "escalate: 'fixed' verdict did not reproduce — scoped build failed. Treating as gave-up." >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" \
    "verdict claimed fixed but the wrapper's scoped build failed to reproduce it: $verdict"
  log_cost "gave-up"
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
  log_cost "gave-up"
  exit 1
fi

# ── Commit in the worktree, cherry-pick into the real checkout ────────────
# overlays/ was already staged above so the landing gates could inspect it;
# this is a final belt-and-suspenders check (should be unreachable given the
# gates above already require $overlay_rel to be staged), and the stray-file
# gate above (Finding 2) already guarantees the working tree has nothing
# outside overlays/ left to worry about.
if [[ -z "$(git -C "$wt" diff --cached --name-only)" ]]; then
  echo "escalate: verdict claimed 'fixed' but nothing under overlays/ changed" >&2
  quarantine_set_escalation "$PACKAGE" "gave-up" "claimed fixed but touched nothing under overlays/: $verdict"
  log_cost "gave-up"
  exit 1
fi
git -C "$wt" -c core.hooksPath=/dev/null commit -q \
  -m "overlays: repair $PACKAGE bump to $VERSION

Escalated repair, verified by scoped + full system build.
Verdict: $verdict"
fix_sha="$(git -C "$wt" rev-parse HEAD)"

# hooksPath=/dev/null: do NOT fire the post-commit mirror hook here. Under
# scheduled-check nothing may be published until the post-activation health
# check passes, and this cherry-pick lands during the propose half — a repair
# published now would reach GitHub even if the full system build then failed.
# The single explicit sync-to-public.sh call after the health check covers it.
if ! git -C "$REPO" -c core.hooksPath=/dev/null cherry-pick "$fix_sha" >>"$session_log" 2>&1; then
  git -C "$REPO" cherry-pick --abort >/dev/null 2>&1 || true
  echo "escalate: cherry-pick of the verified fix failed" >&2
  # infra-error, not gave-up: the model produced a build-verified fix — the
  # cherry-pick failure is a git-mechanics problem (e.g. the real checkout
  # drifted from the worktree's base), not a verdict about the repair
  # itself, so it must not arm the fingerprint-dedup brake.
  quarantine_set_escalation "$PACKAGE" "infra-error" "verified fix could not be cherry-picked cleanly"
  log_cost "infra-error"
  exit 1
fi

# Clear the ledger entry entirely: a repaired package must not carry a live
# entry forward, because escalation_status="fixed" is not a dedup brake
# (quarantine_should_escalate only refuses on "gave-up") — an unfrozen entry
# left in place would get escalated again the next day, hit attempts>=3, and
# freeze against every future version. The durable record of this repair
# lives in logs/escalation-costs.tsv and in the commit itself.
quarantine_clear "$PACKAGE"
log_cost "fixed"
echo "escalate: $PACKAGE repaired and committed as $(git -C "$REPO" rev-parse --short HEAD)"
echo "escalate: verdict — $verdict"
exit 0
