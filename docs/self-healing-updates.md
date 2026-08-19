# Self-Healing Daily Updates — Operator Guide

This is the runbook for the daily update pipeline: what it does, how to read its state,
how to un-stick something, and how to recover from a bad activation. For the design
rationale (why it's shaped this way, what was rejected and why), see
[`docs/superpowers/specs/2026-07-25-self-healing-updates-design.md`](superpowers/specs/2026-07-25-self-healing-updates-design.md).

The short version: everything auto-bumps, auto-builds, auto-activates, and auto-health-checks
every day at 09:00. A human is paged only when something breaks in a way the machine can't
route around. **On a normal day you should hear nothing at all** — see "Notification policy"
below before assuming silence means the automation isn't running.

## What the 09:00 run does

The pipeline is `launchd.user.agents.nixos-auto-update` (label `org.nixos.nixos-auto-update`,
declared in `hosts/darwin/default.nix`) — a **user** agent, not a root daemon. It fires at
09:00 and runs two `scheduled-check` invocations back to back:

```
nix run "$REPO#scheduled-check" -- --propose-only
# on success, if a revision was built:
nix run "$REPO#scheduled-check" -- --activate-only <sha>
```

**Step 1 — `scheduled-check --propose-only`** (also the bare/no-argument default — this is
deliberate, so a launchd agent invoking the script with no arguments can never activate by
accident):

1. `bump-overlays --no-public-sync` — attempts every overlay whose quarantine and cadence
   gates allow it (see below). Each successful bump is verified by a scoped build and
   committed individually; each failure is quarantined and rolled back.
2. Escalates up to 3 quarantined packages (every `kind: overlay` entry is a candidate, not
   just this run's — `escalate.sh` decides via per-(package, fingerprint) dedup) to a budgeted headless
   Claude repair session (`scripts/escalate.sh`) — see "Reading `logs/escalation-costs.tsv`"
   below for the budget in detail.
3. `prepare` — updates whichever flake inputs (`nixpkgs`, `home-manager`, `darwin`, `secrets`)
   are due per their `cadence_hours`, including one speculative unpin *probe* per pinned
   input's `retry_cadence_hours` (see "The unpin retry is a probe" below), builds the system
   as evidence, and commits.
4. If anything moved (and it's more than just quarantine-ledger churn), a full
   `nix build .#darwinConfigurations.garmonbozia.system` runs as final evidence.
5. On success, the built revision's sha is written to `logs/proposed-revision`.

This half is unprivileged (no `sudo`) and never touches `/run/current-system`.

**Step 2 — `scheduled-check --activate-only <sha>`** (the launchd wrapper script runs this
automatically, reading the sha from `logs/proposed-revision`; it is the only path that ever
switches the live system):

1. `activate <sha>` — `sudo darwin-rebuild switch --flake git+file://...?rev=<sha>`.
2. `scripts/post-activate-health.sh` — package-version and launchd-agent assertions
   (`overlays/health-checks.json`).
3. **On health-check failure**: `rollback` (to the immediately-previous generation), record a
   `frozen` entry keyed `revision-<sha>` in `overlays/quarantine.json`, and send a failure
   notification. This is deliberately **not** escalated to Claude — after a multi-package bump
   the culprit is ambiguous, the machine is already rolled back and healthy again, and the
   frozen revision entry stops the pipeline from re-proposing the exact same broken commit. The
   notification names the range to bisect by hand if you want to find the culprit.
4. **On health-check success**: `scripts/sync-to-public.sh` mirrors the revision to
   `~/src/nixos-config`. Nothing is ever published before the machine that produced it is
   confirmed healthy.

Activation *requires* the pre-existing passwordless-sudo rule in `hosts/darwin/default.nix`'s
`security.sudo.extraConfig`:

```
briangyss ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
```

This rule predates the self-healing pipeline (it already existed for interactive
`build-switch`) and the pipeline deliberately reuses it rather than running as a root daemon —
see the comment block above `launchd.user.agents.nixos-auto-update` in
`hosts/darwin/default.nix` for the three concrete problems a root daemon caused (root-owned
ledger writes, root-owned public-mirror git objects, and GUI notifications from a root
LaunchDaemon silently never reaching the logged-in session). **Removing that sudoers rule
breaks unattended activation**: the propose half still runs and builds, but
`--activate-only` would then hit an interactive password prompt that has nowhere to go in a
launchd agent, and every day's run fails at that step.

### Notification policy — what's silent, what pages you

Per the design spec, "you should hear from this system roughly never." Concretely:

- **A healthy activation sends no notification at all.** Nothing. If you want to confirm the
  agent ran today, don't wait for a notification — read `logs/nixos-scheduled-check.log` (see
  below). It records "activated `<sha>`, healthy" on every silent success.
- Notifications *do* fire for: a package newly promoted to `frozen`, a Claude-authored repair
  landing (review it — `git log -p`), a build failure, a health-check failure + rollback, and a
  revision-level `frozen` entry.

### Where to look

- `logs/nixos-scheduled-check.log` — the full run log for the most recent invocation
  (truncated at the start of every run, so it only ever covers the last run, not history).
  This is the first place to look after any run, healthy or not.
- `logs/nixos-auto-update.out.log` / `.err.log` — launchd's stdout/stderr capture for the
  wrapper script itself (also truncated per run; the truncation loop in `scheduled-check`
  covers both these names and the old `nixos-update-check` names, for continuity across the
  Task 9 rename).
- `logs/bump-<pkg>.log` — per-package bump output, also what gets fed into an escalation brief.
- `logs/health.log` — the most recent `post-activate-health.sh` output (only written on the
  activate-only path).
- `logs/proposed-revision` — the sha the propose half most recently built; consumed and then
  left in place by the activate half.

## Reading `overlays/quarantine.json`

This is a **git-tracked, machine-written** ledger — authoritative state, not a cache (unlike
`.update-state.json`, which is gitignored and deletable). Never hand-edit it while the daily
pipeline may be running; use `scripts/quarantine.sh`'s functions instead (see below).

Each entry:

```json
{
  "name": "some-pkg",
  "kind": "overlay",
  "blocked_version": "1.2.3",
  "known_good_version": "1.2.2",
  "first_failed": "2026-07-20T09:03:11Z",
  "last_attempt": "2026-07-20T09:03:11Z",
  "attempts": 1,
  "phase": "package-build",
  "fingerprint": "...",
  "error_excerpt": "...",
  "retry_policy": "next-version-only"
}
```

`kind` is `"overlay"` for a package, `"input"` for a `pinned_inputs[]` unpin attempt, or
`"revision"` for a system-build/health-check failure attributed to a whole commit rather than
one package.

**The core rule: quarantine is per-version.** `blocked_version` is the exact version (or, for
a pinned input, the pin ref) that failed — not the package as a whole. The next day, if
upstream ships a newer version, `quarantine_is_blocked` sees a different `blocked_version` and
lets the new attempt through automatically. A quarantine **self-heals** the moment upstream
moves; nobody has to clear it by hand just because time passed.

`retry_policy` values:

- **`next-version-only`** — blocks exactly `blocked_version`; anything else (older or newer)
  is eligible. This is the default after a first failure.
- **`retry-after:<H>`** — blocks `blocked_version` until `H` hours have elapsed since
  `last_attempt` (used for classified-transient failures, e.g. a flaky network fetch, and for
  a failed unpin-probe attempt, which re-tries the *same* pin ref after its
  `retry_cadence_hours`).
- **`frozen`** — blocks **every** version, forever, until a human clears the entry. Two ways
  to reach `frozen`: (1) `attempts >= 3` on the same `blocked_version` auto-promotes
  (`quarantine_record` in `scripts/quarantine.sh`), or (2) a revision-level failure
  (system-build or health-check) is recorded `frozen` immediately, on the first failure — see
  above for why those are never escalated or auto-retried.

## Un-sticking a package

**Bypass the quarantine (and cadence) gate as an explicit human override:**

```bash
nix run .#bump-overlays -- --only <pkg>
```

`--only` skips both `quarantine_is_blocked` and `cadence_due` — verified by reading
`apps/aarch64-darwin/bump-overlays`, where both gates are wrapped in
`[[ -z "$ONLY" ]] && ...`. Use this after you've fixed the underlying problem by hand (or
just want to retry immediately rather than waiting for tomorrow's run).

**Clear a ledger entry by hand** (e.g. after a manual bump that didn't go through
`bump-overlays`, so nothing cleared it automatically):

```bash
QUARANTINE_FILE=overlays/quarantine.json bash -c \
  'source scripts/update-state.sh; source scripts/quarantine.sh; quarantine_clear <pkg>'
```

Verified directly: this removes exactly the named entry from `entries[]` and leaves the rest
of the ledger untouched. Remember to `git add overlays/quarantine.json` and commit — clearing
the entry does not commit for you when run this way (the pipeline's own commit-on-exit traps
only fire inside `bump-overlays`/`prepare`/`escalate.sh`).

## Reading `logs/escalation-costs.tsv` and the five token brakes

Each `escalate.sh` run appends one line: `timestamp<TAB>package<TAB>outcome<TAB>duration_seconds<TAB>tokens`,
where `outcome` is `fixed`, `gave-up`, `stalled`, or `infra-error` — logged *after* the
wrapper's own independent verification, never the model's self-reported claim (see
`scripts/escalate.sh`'s `log_cost` and the block above it). `stalled` means the session ended
with no `verdict.json` at all (e.g. it backgrounded a step and waited on a "scheduled wakeup"
that a headless one-shot session has no scheduler to ever deliver) — it is a session failure,
not a diagnosis that the package can't be fixed, and unlike `gave-up` it does **not** arm the
fingerprint-dedup brake below, so the package stays eligible for escalation on the next run.
The file doesn't exist until the first escalation runs.

The five brakes, and where each actually lives (verified against the current code — the plan
document `docs/superpowers/plans/2026-07-25-self-healing-updates.md` still names a constant
`ESCALATE_MAX_PER_RUN` that was never implemented that way; do not look for it):

1. **Per-run escalation cap** — a literal `3` in `apps/aarch64-darwin/scheduled-check`'s
   escalation loop (`[[ $escalated -ge 3 ]] && break`). At most 3 packages get a Claude
   session per day, no matter how many are quarantined.
2. **`--max-turns`** — `MAX_TURNS=40` in `scripts/escalate.sh`, overridable via
   `--max-turns`. Bounds how much back-and-forth a single repair session can do.
3. **`timeout`** — `TIMEOUT=900` (seconds) in `scripts/escalate.sh`, overridable via
   `--timeout`. Bounds wall-clock time per session.
4. **Attempt ceiling → `frozen`** — `[[ $attempts -ge 3 ]] && policy="frozen"` inside
   `quarantine_record` in `scripts/quarantine.sh`. Three real failures on the same
   `blocked_version` (whether from `bump-overlays` itself or from a failed escalation)
   permanently freezes the package until a human intervenes.
5. **Fingerprint dedup** — `quarantine_should_escalate` in `scripts/quarantine.sh` refuses a
   new escalation when the *same* package already produced a `gave-up` verdict for the *same*
   failure fingerprint. A package failing the identical way every day costs one Claude session
   total, not one per day; a genuinely new failure signature is still escalated.

To retune, edit the constant in the file named above and commit — there is no separate
environment-variable override for any of the five today.

## Resolved: scoped-verify false negatives for cross-overlay dependencies

**Status: fixed (`f480b98`).** `scripts/escalate.sh` now falls through to the full-system
build whenever the scoped build fails, and only records `gave-up` if the full build fails too
(see the `scoped_build_ok` block around its two `nix build` calls). The false-negative
mechanism below is kept for context — it's what motivated the fix — but Option 1 from the list
at the end of this section is the current, live behavior, not a proposal.

`scripts/escalate.sh`'s *scoped* verification build is scoped to the ONE overlay file being
repaired:

```bash
nix build --no-link --impure --expr \
  'let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./overlays/<file>.nix) ]; }; in pkgs.<attr>'
```

That means a package whose build depends on something another overlay provides — most
concretely, a `buildGoModule` derivation relying on the Go 1.26.5 pin from
`overlays/55-go.nix` — is built against nixpkgs' *unpinned* default instead, because that
other overlay was never loaded. If upstream bumps its `go.mod` `go` directive to a version
newer than nixpkgs' default (but still ≤ this repo's 1.26.5 pin), the scoped build fails with
something like `could not resolve vendorHash from build error`, even though the real fix is
completely correct.

Worse, this is not just a wasted retry: `scripts/escalate.sh` treats *any* scoped-build
failure as an immediate `gave-up` (see the block around its `nix build --impure --expr` call)
and never falls through to its own full-system-build check
(`nix build ".#darwinConfigurations.garmonbozia.system"`), which loads every overlay
together and would have caught that the fix actually works. The repair session's correct
diagnosis gets recorded as a failure, and the package stays quarantined.

**Confirmed case:** `hey-cli` (`overlays/94-hey-cli.nix`), 2026-07-30. The automated escalation
correctly bumped the overlay to rev `4a35066f8dfebade0fa3470d9e11ceb932a853f3` and resolved the
real `vendorHash`, but the scoped build failed on nixpkgs' default `go` and the wrapper recorded
`gave-up`. Verifying manually with the full system attr showed the fix was right all along:

```bash
nix build --no-link --print-out-paths ".#darwinConfigurations.garmonbozia.pkgs.hey-cli"
```

**How to spot it:** the quarantine entry's `escalation.verdict` says something like *"verdict
claimed fixed but the wrapper's scoped build failed to reproduce it"*, and the underlying error
in `logs/escalation-<pkg>-<ts>.session.log` names a toolchain/version constraint (Go, Rust,
etc.) that the failing overlay doesn't itself pin. That combination is the signature of this
false negative rather than a genuinely broken package.

**Immediate mitigation (manual):** re-run the full-system build yourself
(`nix build ".#darwinConfigurations.garmonbozia.pkgs.<attr>"`); if it passes, apply the same
rev/hash/vendorHash the escalation session found (read it out of the session log or verdict),
commit, `nix flake check`, `build-switch`, then clear the quarantine entry per "Un-sticking a
package" above. `.claude/skills/overlay-repair/SKILL.md` documents this same workaround for
future repair sessions to recognize the pattern (though a repair session still cannot make the
wrapper accept it — only a human bypassing the wrapper can).

**Options considered** (Option 1 is implemented; 2 and 3 remain possible future refinements if
the extra full-system build ever proves too expensive to run on every scoped-build failure):

1. **Fall through instead of short-circuiting (implemented).** On a scoped-build failure, don't
   immediately record `gave-up` — attempt the full-system build first, and only give up if
   *that* also fails. This directly closes the gap without weakening any other gate, at the
   cost of one extra build (only on the already-rare scoped-build-failure path).
2. **Widen the scoped build to include known cross-cutting overlays.** Load `55-go.nix` (and
   any other overlay that overrides a builder rather than defining one leaf package) alongside
   the package's own overlay in the scoped expression. Cheaper than a full system build, but
   requires maintaining a list of "builder-override" overlays that must always be included and
   will drift if a new one is added without updating this list.
3. **Classify by fingerprint.** Detect toolchain-version-mismatch errors (e.g. `vendorHash`
   resolution failures paired with a `go.mod`/`go` directive bump) and route them straight to
   the full-system build, skipping the scoped one entirely for that fingerprint. More precise
   than (1) but adds a new failure-classification path to maintain.

## Disabling the automation

The agent is a **user** LaunchAgent, not a system daemon, so the scope is `gui/<uid>`, not
`system/`:

```bash
launchctl bootout gui/$(id -u)/org.nixos.nixos-auto-update
```

Check whether it's currently loaded with:

```bash
launchctl list org.nixos.nixos-auto-update
```

(exits non-zero / prints "Could not find service" when not loaded — this is what you'll see on
a fresh checkout that hasn't run `build-switch` since the agent was added, since `launchd.user.agents`
is only realized into an actual loaded agent after activation).

To re-enable, `nix run .#build-switch` re-activates the `launchd.user.agents.nixos-auto-update`
definition from `hosts/darwin/default.nix`, which reloads it.

## Running a propose-only pass by hand

There is no `SCHEDULED_ACTIVATE` environment variable — that was an earlier design that
didn't ship. The actual mechanism is the `--propose-only` flag (also the bare-invocation
default):

```bash
nix run .#scheduled-check -- --propose-only
```

This runs the full bump → escalate → prepare → build sequence and writes
`logs/proposed-revision` on success, but never calls `sudo` and never touches
`/run/current-system`. To then activate that specific reviewed revision:

```bash
nix run .#scheduled-check -- --activate-only "$(cat logs/proposed-revision)"
```

or, equivalently, the lower-level single-purpose command:

```bash
nix run .#activate -- "$(cat logs/proposed-revision)"
```

(`activate` doesn't run the health-check/rollback/public-mirror steps that
`--activate-only` does — it's the bare privileged switch. Prefer `--activate-only` unless
you specifically want just the switch.)

## Recovering from a bad activation

The automated health-check-and-rollback should catch most breakage before you ever see it, but
if the machine still ends up on a bad generation:

```bash
nix run .#rollback -- --list      # list generations (needs root to read the profile lock — see note)
nix run .#rollback -- <gen>       # roll back to a specific generation number
nix run .#rollback                # roll back to the immediately-previous generation (no arg)
```

`apps/aarch64-darwin/rollback` is idempotent — rolling back to the generation that's already
current is a no-op switch. Note: on this machine, even `--list-generations` needs to read
`/nix/var/nix/profiles/system.lock`, which requires root — if a bare `nix run .#rollback --
--list` reports "Permission denied" opening that lock file, that's this, not a bug in the
listing logic; run it with `sudo` in front, or from a terminal where you can answer the
password prompt.

## Troubleshooting

**`bump-overlays` exits 3 immediately, refusing to run.**
It refuses to start whenever `overlays/` has *any* uncommitted changes — this is a hard
precondition, checked before the state lock is even acquired, so it can never mix an automated
bump with an in-progress manual edit. Usually this means a previous run (or a manual `escalate.sh`
invocation, or a manual `quarantine_clear`) left the ledger dirty. Fix:
```bash
git status --porcelain -- overlays/
# commit or discard whatever's there, e.g.:
git add overlays/quarantine.json && git commit -m "quarantine: update ledger"
```

**A package is stuck `frozen` and every version gets skipped, even a version far newer than
the one that originally failed.** `frozen` blocks *every* version unconditionally (unlike
`next-version-only`/`retry-after:<H>`, which key off `blocked_version`) — that's the intended
behavior once a package hits the 3-attempt ceiling or a revision-level failure freezes it
immediately. To un-stick it: fix the underlying problem (or confirm the newer version actually
builds), then either `nix run .#bump-overlays -- --only <pkg>` (which bypasses the gate
entirely and, on success, clears the entry itself) or clear it by hand with the
`quarantine_clear` command above.

**`post-activate-health.sh` reports a version mismatch, but the package is actually fine.**
The health check is a strict *equality* comparison between `overlays/updates.json`'s
`current_version` and what the binary reports right now — deliberately not a substring match,
because some of this repo's version schemes (mise/yt-dlp's date-shaped versions, tmux's
`3.7`/`3.7b` point releases) have real prefix collisions between different releases that a
substring match would silently paper over. If you run `post-activate-health.sh` at some moment
*other than* immediately after an activation — e.g., days later, after `mise` or another
self-updating tool has quietly moved itself past what the manifest says — it will report a
`FAIL` that has nothing to do with the activation at all. The manifest's `current_version` is
only a promise about what `bump-overlays`/`escalate.sh` last verified and committed; it is not
continuously reconciled against what's actually running. Re-run it right after an activation
for a meaningful signal, and treat a lag detected long after the fact as "some tool
self-updated," not "the pipeline broke."
