# Self-Healing Daily Updates — Design

**Date:** 2026-07-25
**Status:** Approved, not yet implemented

## Problem

The current daily automation (`launchd.user.agents.nixos-update-check` →
`scheduled-check` → `bump-overlays --mechanical-only` + `prepare`) proposes a built
revision and notifies, but stops there. That leaves four recurring manual costs:

1. **Activation is manual.** Nearly every day ends with a human running
   `nix run .#activate -- <rev>`.
2. **Most overlays are excluded from auto-bumping.** `--mechanical-only` skips the
   go-source packages (`beads`, `c4`, `hey-cli`) and the fiddly ones (`yt-dlp`,
   `ngrok`, `tmux`, `mise`'s non-mechanical paths), all of which then follow
   `docs/overlay-update-routine.md` by hand.
3. **`pinned_inputs[]` is a permanent freeze.** Nothing ever retries an unpin, so
   `nixpkgs`/`home-manager`/`darwin` stay pinned until a human remembers to test.
4. **No memory of failure.** Because nothing records *why* a bump failed, the system
   cannot distinguish "this version is broken, skip it" from "this package is
   broken, stop trying" — so the safe default has been to not try at all.

Frequently-released software (claude-code, codex, mise, uv) means this manual tax is
paid most days.

## Goal

Invert the default. Everything auto-bumps and auto-activates; a human is involved
**only when something breaks in a way the machine cannot resolve or route around**.
A broken upstream version must not block anything else, and must self-heal the moment
upstream ships a fix.

Secondary goal: token frugality. Clean days must cost nothing.

## Non-Goals

- Replacing `nix flake check` / `treefmt` / `overlays-manifest` as the correctness
  gate. They stay exactly as they are.
- Changing the public-mirror model (denylist + post-commit hook).
- Automating the NixOS (non-Darwin) hosts. This design targets `garmonbozia`.
- Making Claude a daily participant. See §7 for why the daily-loop shape was rejected.

## 1. Architecture — Two Layers, One Seam

### Layer 1 — deterministic pipeline (zero tokens)

A root `launchd.daemons.nixos-auto-update` fires at 09:00 and runs, in order:

1. **`bump-overlays --all`**, with per-package `cadence_hours` honoured, skipping any
   package whose upstream-offered version is quarantined.
2. **`prepare`** for flake inputs, including **unpin retry**: any `pinned_inputs[]`
   entry past its retry cadence gets a speculative bump attempt.
3. **Full system build** as evidence.
4. **Activate** (`darwin-rebuild switch`) — the only root-privileged step besides
   rollback.
5. **Health check** (§3).
6. On health failure: **rollback**, quarantine the revision, escalate.

Failures in steps 1–3 are attributed to a specific package, quarantined, and the
pipeline **continues with the remaining packages**. This is the core of "stay on the
current version": a broken package simply does not move, and everything else lands.

### Layer 2 — Claude escalation (tokens only on breakage)

A failure the deterministic layer cannot attribute-and-skip past invokes
`claude -p --model sonnet` with the `overlay-repair` skill, a bounded budget, and a
pre-assembled brief (§4). Claude may edit overlays; the wrapper — not Claude —
verifies and commits. Claude never activates, so an LLM-authored `.nix` change waits
for human review while a mechanical bump self-activates.

### The seam

`overlays/quarantine.json`. Layer 1 writes failures into it; Layer 2 reads them and
writes back either a verified fix or a `gave-up` verdict with a diagnosis.

## 2. The Quarantine Ledger

New file `overlays/quarantine.json` — machine-written, git-tracked, public-safe.

### Why a separate file

`updates.json` is a hand-curated manifest whose internal consistency
`scripts/check-overlay-manifest.sh` enforces. Quarantine state is high-churn machine
output. Keeping them separate preserves the manifest check's meaning and makes
`git log overlays/quarantine.json` a readable history of upstream breakage.
`pinned_inputs[]` migrates in over time as a `frozen` entry carrying a retry cadence.

### Schema

```json
{
  "entries": [
    {
      "name": "yt-dlp",
      "kind": "overlay",
      "blocked_version": "2026.07.19",
      "known_good_version": "2026.07.04",
      "first_failed": "2026-07-25T09:03:11Z",
      "last_attempt": "2026-07-25T09:03:11Z",
      "attempts": 1,
      "phase": "package-build",
      "fingerprint": "curl_cffi-version-bound",
      "error_excerpt": "…curl_cffi>=0.13,<0.14 not satisfied…",
      "retry_policy": "next-version-only",
      "escalation": {
        "status": "gave-up",
        "verdict": "postPatch bound rewrite applied but upstream also renamed the ejs entrypoint; needs manual review",
        "at": "2026-07-25T09:14:02Z"
      }
    }
  ]
}
```

Field notes:

- `kind`: `overlay` | `input` | `revision`. A `revision` entry is written when a
  post-activation health check fails and the culprit among several bumped packages is
  ambiguous.
- `phase`: which pipeline step failed — `prefetch` | `package-build` | `system-build`
  | `flake-check` | `activation` | `health-check`. Determines classification.
- `fingerprint`: a short stable slug derived from the classified error, used for
  dedup (§5.4). Not the raw message.
- `error_excerpt`: truncated and store-path-stripped, so local paths never reach the
  public mirror.

### Retry-forward semantics — the core rule

**Quarantine is per-version, not per-package.** An entry blocks exactly
`blocked_version`. When upstream publishes anything newer, the package becomes
eligible again automatically and the next daily run tries it, with no human
involvement. A quarantine therefore self-heals the moment upstream ships a fix.

`retry_policy` values:

| Value | Meaning | Used for |
|---|---|---|
| `next-version-only` | Never retry `blocked_version`; any newer version is eligible. | Default. Eval errors, compile failures, test failures. |
| `retry-after: <hours>` | Retry the *same* version after a delay. | Transient smells: network/HTTP errors, hash mismatch from a re-uploaded artifact. |
| `frozen` | Never retry without human action; carries an optional retry cadence for speculative attempts. | Migrated `pinned_inputs[]`; auto-promotion at `attempts >= 3`. |

### Failure classification

Done in the shell layer, before any token is spent, by matching the build log against
a small regex table:

| Pattern | Action |
|---|---|
| `hash mismatch in fixed-output derivation` | Run `fix-hashes`, retry once in-process. No quarantine if it then passes. |
| Network / HTTP / TLS / timeout | `retry-after: 6h`. **No escalation.** |
| `attribute … missing`, eval errors | Quarantine `next-version-only`, **escalate**. |
| Compile failure, test failure | Quarantine `next-version-only`, **escalate**. |
| Unmatched | Quarantine `next-version-only`, **escalate** with `fingerprint: unclassified`. |

This table is the main mechanism keeping Claude from being woken for problems the
shell can already solve. It is expected to grow; `unclassified` escalations are the
signal for what to add.

### Notification policy

Inverted from today's. Silent on: success, a quarantine that resolved itself, a
transient retry. Notifies on: Claude landed a fix awaiting review; an entry was
promoted to `frozen`; a health check failed and the system was rolled back.

## 3. Privilege, Health Check, Rollback

### Privilege — user agent, via the pre-existing sudoers rule

An earlier revision of this spec argued for a root `launchd.daemons.nixos-auto-update`
specifically to avoid a passwordless-sudo rule for `darwin-rebuild switch`, on the
reasoning that such a rule would convert *any* code execution as `briangyss` into
silent root (since `switch --flake` runs arbitrary activation scripts as root). That
argument turned out to be moot: `hosts/darwin/default.nix` already carries

```
briangyss ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
```

predating this work, for unrelated reasons. The root daemon therefore bought no
security beyond what this repo's config already implicitly relies on, while causing
three concrete problems: (1) `quarantine_record` on the activate path writes
`overlays/quarantine.json` as root with nothing to commit it, leaving a root-owned
dirty file that wedges `bump-overlays`; (2) `sync-to-public.sh` running as root would
create root-owned git objects and push with root's SSH identity in the user's own
checkouts; (3) `osascript` notifications sent from a root LaunchDaemon never reach the
logged-in user's GUI session, so the failed-health-check-and-rolled-back
notification — the most important one this system sends — would silently vanish.

The pipeline instead runs as **`launchd.user.agents.nixos-auto-update`** (09:00,
${user}), for both halves — propose and activate — with no privilege drop. Activation
goes through the pre-existing passwordless `darwin-rebuild` sudoers rule above. This
couples the two: the agent depends on that rule staying in place for unattended
activation to work, so removing it would break the daily run at the activate step.

Root already has the `/var/root/.ssh/config` → `/run/agenix/ssh-key` wiring needed to
fetch the `secrets` flake input, so flake evaluation during `darwin-rebuild switch` is
unaffected even though the agent invoking it runs as the user.

### Health check

`scripts/post-activate-health.sh` — a table of assertions, each with a timeout, run
after the switch:

- Every binary an overlay pins responds to its version flag, **and the reported
  version matches that package's `current_version` in `updates.json`.** The version
  comparison is the point: a plain exit-0 check misses the silent-wrong-binary case.
- `launchctl list` shows the expected user agents loaded, none in a crash-loop exit
  state.
- `nix flake check` is deliberately **not** re-run — it already gated the build.

Anything unlisted is unchecked. The list lives beside the pins so that adding a
package to `updates.json` prompts adding its smoke assertion. The
`overlays-manifest` check is extended to require an assertion per pinned package.

### Rollback

Health failure calls the existing idempotent `rollback` app, then writes a
`kind: revision` quarantine entry with `retry_policy: frozen` and notifies, naming the
commit range. It does **not** escalate: after a multi-package bump the culprit is
ambiguous, and a bisect-and-attribute mode is real additional scope for the rarest
failure path — one that leaves the machine already rolled back and healthy. Bisecting
`before..after` by hand takes a few minutes, and the frozen entry stops the pipeline
from re-proposing the same revision meanwhile. Escalation stays scoped to per-package
repair, where the culprit is unambiguous by construction. It still consumes one of the three escalation slots in §5.2.

### Ordering fix

Today `scheduled-check` mirrors to public *before* activation is attempted. Under
auto-activate that is backwards. The mirror push moves to **after** the health check
passes, so GitHub never shows a revision that failed on the machine that produced it.

`overlays/quarantine.json` is published (public-safe, and useful as a record of
upstream breakage) with `error_excerpt` truncated and store-path-stripped.

### Failure isolation

Every stage writes its outcome to the ledger before proceeding, so a crash mid-run
(laptop sleeps, network drops) leaves a resumable state. The next run reconciles from
the ledger rather than assuming a clean start.

## 4. Escalation Contract

### Invocation

The shell layer never hands Claude the repo to explore. It assembles a brief at
`logs/escalation-<pkg>-<ts>.md` and runs, as the user, in a throwaway git worktree:

```bash
timeout 900 claude -p --model sonnet \
  --max-turns 40 \
  --permission-mode acceptEdits \
  --allowedTools 'Read,Edit,Write,Bash(nix build:*),Bash(nix-prefetch-url:*),Bash(nix hash:*),Bash(nix fmt),Bash(git diff:*)' \
  "$(cat logs/escalation-<pkg>-<ts>.md)"
```

### The brief

Assembled deterministically, target **under 3k tokens**:

- Package name and its `updates.json` entry.
- The exact diff `bump-overlays` attempted and reverted.
- The classified failure `phase` and `fingerprint`.
- Last ~80 lines of the build log, store paths collapsed.
- This package's prior ledger entries.
- A pointer to the relevant section of `docs/overlay-update-routine.md` for that
  `update_type`.

No repo tour, no `git log`, no speculative reading.

### Isolation

The session runs in a throwaway git worktree, never the daily-driver checkout.
`bump-overlays` exits 3 when `overlays/` is dirty, so a failed repair leaving edits
behind in `~/nixos-config` would silently disable the next day's entire run. In a
worktree, giving up costs nothing — the worktree is deleted. On success the verified
commit is cherry-picked into `~/nixos-config`, firing the normal post-commit mirror
hook.

### Allowed tools are the contract

Absent by design: `Bash(sudo:*)`, `Bash(git commit:*)`, `Bash(git push:*)`, and any
network fetch beyond the two prefetch commands. Claude cannot activate, cannot commit,
and cannot reach the public repo.

**The wrapper commits, and only after independently re-running the scoped build plus a
full system build itself.** Claude's claim of success is never the evidence; the
wrapper's own build is.

### Verdict

Claude writes `verdict.json` into the worktree:

```json
{
  "status": "fixed | gave-up",
  "package": "yt-dlp",
  "fingerprint": "curl_cffi-version-bound",
  "verdict": "one-paragraph diagnosis",
  "files_changed": ["overlays/91-yt-dlp.nix", "overlays/updates.json"]
}
```

A missing or malformed verdict file is treated as `gave-up`. A `fixed` verdict whose
build does not reproduce is also `gave-up`, and the discrepancy is recorded in the
ledger — a pattern of those means the skill needs work.

### The `overlay-repair` skill

Carries the durable knowledge so the brief need not:

- How each `update_type` is bumped (mirrors `docs/overlay-update-routine.md`).
- A blanked `vendorHash`/`cargoHash` yields the real hash in the build error.
- A `go` minor bump also renames the `go_1_26` attribute in the overlay.
- `yt-dlp`'s `postPatch` `curl_cffi` bounds routinely need widening.
- An overlay's pinned version and `updates.json`'s `current_version` must be rewritten
  **together**.
- **Standing rule:** if the mechanical path does not work within two attempts, write
  `gave-up` with a precise diagnosis rather than inventing a creative workaround. A
  wrong-but-building overlay is worse than a frozen one.

## 5. Token Budget

Five independent brakes — "it only runs on failure" is not by itself a bound.

1. **Zero tokens on a clean day.** The common case starts no session.
2. **Max 3 escalations per daily run**, one per package, hard-capped in the shell.
3. **Per-session ceiling**: `--max-turns 40` and a 900s `timeout`, whichever first.
4. **Fingerprint dedup**: a `(package, fingerprint)` pair that already produced
   `gave-up` does not escalate again — even for a new upstream version — until the
   fingerprint changes. This kills the groundhog-day burn where one package fails
   identically for a week.
5. **`attempts >= 3` → `frozen`**, stopping both bumping and escalating until a human
   intervenes.

### Cost estimate

An estimate, not a measurement: a typical repair is a brief plus 10–25 tool calls on
Sonnet, so order-of-magnitude **150–400k tokens** including cache reads — less than
one interactive session. Worst realistic day, all three slots spent, approaches 1M.
Expected monthly volume is a handful of escalations, because dedup means recurring
breakage costs one session rather than thirty.

### Instrumentation

Each escalation appends its reported token usage and duration to
`logs/escalation-costs.tsv`. After a month there are real numbers; all five brakes are
single constants in one script, so retuning is a one-line change.

## 6. Cadence Configuration

`updates.json` gains per-package `cadence_hours` alongside the existing `inputs.*`
cadences:

- Default (unset): daily. Covers claude-code, codex-openai, uv, mise, trailbase, igir,
  dcg, aws-cdk-cli, go patch bumps, beads.
- `c4`, `hey-cli`: **weekly** (`cadence_hours: 168`). Both track a branch with no
  releases; daily bumping would chase HEAD and produce churn commits with no release
  gate.
- `pinned_inputs[]` entries: retried on their own cadence (default weekly) rather than
  frozen forever. A failed unpin attempt is silent and re-freezes; a successful one
  unpins and removes the entry.

## 7. Rejected Alternatives

**Daily Claude loop driving the whole pipeline.** Rejected: burns tokens every day
including the ~95% of days when nothing breaks, and adds LLM nondeterminism to a
pipeline that is already correct and cheap in shell. The escalation-only shape gets
the same self-healing for near-zero steady-state cost.

**Quarantine state inside `updates.json`.** Rejected: fuses curated policy with
high-churn machine state, and every quarantine event dirties the file the
`overlays-manifest` check guards.

**Deriving quarantine state from git log / commit trailers.** Rejected: slow and
fragile to query, and no clean home for a retry counter.

**Passwordless-sudo `darwin-rebuild switch`.** Rejected: silently converts local code
execution as the user into root. See §3.

**Auto-activating Claude-authored fixes.** Rejected: mechanical bumps are a value
substitution verified by a build; an LLM-authored `.nix` edit is a different risk
class and gets human review.

## 8. Implementation Surface

New:

- `overlays/quarantine.json` + `scripts/quarantine.sh` (read/write/query helpers)
- `scripts/classify-failure.sh` (the regex table)
- `scripts/post-activate-health.sh`
- `scripts/escalate.sh` (brief assembly, worktree, `claude -p`, verdict handling,
  independent verification, cherry-pick)
- `.claude/skills/overlay-repair/SKILL.md`
- `logs/escalation-costs.tsv` (gitignored)

Modified:

- `apps/*/scheduled-check` → the full pipeline including activate + health + rollback
- `apps/*/bump-overlays` → per-package cadence, quarantine-aware skipping, quarantine
  writes on failure. (Note: go-source bumping incl. automated `vendorHash` refetch is
  **already implemented** in `bump_gosource`; it is merely excluded by
  `--mechanical-only`. Dropping that flag from the scheduled run is the whole change.)
- `apps/*/prepare` → unpin-retry for `pinned_inputs[]`
- `hosts/darwin/default.nix` → `launchd.user.agents.nixos-update-check` becomes
  `launchd.daemons.nixos-auto-update`
- `overlays/updates.json` → per-package `cadence_hours`
- `scripts/check-overlay-manifest.sh` → require a health assertion per pinned package
- `scripts/sync-to-public.sh` invocation point → after health check
- `CLAUDE.md` → document the new model

## 9. Open Risks

- **Auto-activation on a laptop.** A switch at 09:00 can restart launchd agents
  mid-workday. Mitigation: the health check verifies agents came back; consider
  skipping activation when on battery.
- **The classification table is the weak point.** Every unmatched error costs an
  escalation. Expect to iterate on it for the first month using `unclassified`
  fingerprints as the worklist.
- **`nixpkgs` unpin attempts are expensive builds.** A weekly speculative full rebuild
  against nixpkgs HEAD is a large, likely-failing build. Mitigation: cap it to one
  attempt per week and let it fail fast on the known OOM signature.
- **Cost estimate is unvalidated.** §5's numbers are inferred, not measured; the
  instrumentation exists specifically to correct them.
