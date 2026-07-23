# Smart Incremental Updates — Design

**Date:** 2026-07-23
**Status:** Approved design, pending implementation plan
**Scope:** Make the Nix update cycle do work proportional to what actually
changed upstream, add a change-detection core, then a scheduler/notifier on top.
Delivered in two phases (B = core, C = scheduler) as one design.

## Problem

The current update cycle (`nix run .#update` → `prepare` → `activate`) does a
fixed amount of work every run regardless of whether anything changed:

- `nix flake update` bumps **every** flake input (nixpkgs, home-manager,
  secrets, …) unconditionally. nixpkgs churns daily and drives large closure
  rebuilds even when no package the user cares about moved.
- `fix-hashes` loops over **all ~15** prebuilt-binary / pinned-source overlays
  and re-downloads each via `nix-prefetch-url` to recompute hashes — even for
  overlays whose upstream version never changed.
- `nix build` rebuilds the whole closure as evidence.
- `scripts/check-overlay-versions.sh` already queries upstream and exits
  non-zero when something is outdated, but **nothing in the update path consumes
  it** — the "check before pulling" capability exists but is unwired.

Goal: each run should detect what actually changed and only re-fetch / re-hash /
rebuild those pieces; run automatically on a cadence; and never force the user
to manually kick off a full cycle. Fast interactive runs fall out for free.

## Architecture

A single orchestrator (a new `--gate` mode reused by `prepare`, plus a
standalone `check` entry) sits over **two independent probe subsystems** and
**one shared state cache**:

```
                    ┌─────────────────────┐
                    │  orchestrator/gate  │  decides: pull? build?
                    └──────────┬──────────┘
              ┌────────────────┴────────────────┐
      ┌───────▼────────┐              ┌──────────▼─────────┐
      │ overlay probe  │              │ flake-input probe  │
      │ (upstream APIs)│              │ (locked rev vs ref)│
      └───────┬────────┘              └──────────┬─────────┘
              └───────────────┬──────────────────┘
                     ┌────────▼────────┐
                     │  state cache    │  .update-state.json (gitignored)
                     └─────────────────┘
```

Each unit has one job:

- **overlay probe** — answers "which overlays have a newer upstream version?"
- **flake-input probe** — answers "which flake inputs are due for a refresh and
  have actually moved upstream?"
- **state cache** — remembers what was last seen, so probes can skip work and
  cadence can be enforced. Non-authoritative; deletable.
- **orchestrator/gate** — combines both probe verdicts into two decisions:
  *pull?* (update lock / re-hash overlays) and *build?* (only if something
  actually changed).

## State cache — `.update-state.json`

Repo-root file, added to `.gitignore`. A **cache, never authoritative** —
deleting it forces a full check on the next run; `overlays/updates.json` remains
the source of truth for pinned versions.

```json
{
  "overlays": {
    "claude-code": { "known_latest": "2.1.218", "checked_at": "2026-07-23T10:00:00Z" }
  },
  "inputs": {
    "nixpkgs": { "updated_at": "2026-07-20T09:00:00Z" },
    "codex":   { "updated_at": "2026-07-23T09:00:00Z" }
  },
  "last_gate": "2026-07-23T10:00:00Z"
}
```

- `overlays.<name>.known_latest` / `checked_at` — last upstream version the probe
  observed and when, so the probe can throttle upstream API calls.
- `inputs.<name>.updated_at` — last time this input's lock entry was refreshed;
  compared against its cadence to decide if it is "due".
- `last_gate` — bookkeeping / debugging.

Cadence values are **not** stored here — they live in `updates.json` (source of
truth). The cache stores only observed state and timestamps.

## Subsystem 1 — overlays (selective)

### `check-overlay-versions.sh --json`

Add a `--json` flag. Same upstream probes as today; instead of the pretty table
it emits a machine-readable array:

```json
[ { "name": "claude-code", "current": "2.1.218", "latest": "2.1.219", "outdated": true }, … ]
```

The existing human-readable table stays the default (no flag). `ERROR` /
`MANUAL` statuses are represented as `outdated: false` with a `status` field so
transient upstream failures never trigger a spurious fetch.

### `fix-hashes --only <name,name,…>`

Add an `--only` filter. Today `fix-hashes` re-fetches every overlay's hash;
with `--only` it processes just the named overlays. A run where only
`claude-code` bumped fetches exactly one binary instead of ~15.

- No `--only` → current behavior (all overlays), preserved for manual use.
- The orchestrator passes the outdated set from the overlay probe.

### Overlay probe flow

`check-overlay-versions.sh --json` → collect names where `outdated == true` →
that set is the overlay work list. The probe updates
`state.overlays.<name>.known_latest` / `checked_at` for every overlay it
successfully queried.

## Subsystem 2 — flake inputs (per-input cadence)

### Cadence policy in `updates.json`

Add a top-level `inputs` object to `overlays/updates.json` (the single manifest;
`overlays-manifest` check may need a tolerance for the new key):

```json
{
  "inputs": {
    "nixpkgs":      { "cadence_hours": 168 },
    "home-manager": { "cadence_hours": 168 },
    "codex":        { "cadence_hours": 24 },
    "secrets":      { "cadence_hours": 0, "on_demand": true }
  },
  "packages": [ … existing … ]
}
```

- `cadence_hours` — minimum interval between refreshes of this input.
- `on_demand: true` (or `cadence_hours: 0`) — never auto-refreshed by the probe;
  only touched when explicitly requested (e.g. `secrets`).
- Inputs absent from this object get a default cadence (proposed: 24h) so a
  newly added input is never silently ignored.

### Flake-input probe flow

For each input in `flake.lock`:

1. **Cadence gate** — if `state.inputs.<name>.updated_at + cadence_hours` has not
   elapsed, skip. (`on_demand` inputs always skip here.)
2. **Movement check** — for a due input, compare the **locked rev**
   (`nix flake metadata --json`) against the upstream ref (e.g. GitHub branch
   HEAD for github inputs). If unmoved, record a fresh `checked` timestamp and
   skip. If moved, run `nix flake lock --update-input <name>` and set
   `updated_at`.

**Net effect:** nixpkgs stops churning the closure daily — it refreshes at most
weekly, and only when actually moved. Tool inputs stay current daily. `secrets`
is never auto-touched.

Inputs whose movement can't be cheaply probed (non-github, or probe error) fall
back to "update when due" rather than being skipped, so correctness never
depends on the probe succeeding.

## The gate (orchestrator)

`prepare` gains a preamble that runs both probes:

1. Overlay probe → outdated overlay set.
2. Flake-input probe → performs due/moved `--update-input`s, reports whether the
   lock changed.
3. If overlays are outdated → `fix-hashes --only <set>`, bump `current_version`
   in `updates.json` for those, re-verify.
4. **Build only if** the lock changed **or** an overlay bumped. Otherwise print
   "nothing to do" and exit **before** `nix build`.
5. On a real change: `nix build` (evidence) → closure diff → commit (as today).

A standalone `check` entry (`nix run .#check`) runs steps 1–2 read-only and
reports what *would* happen, without mutating the lock or overlays — a dry
preview built from the same probes.

This delivers the pre-flight gate and the fast interactive run as side effects
of the change-detection core, with no separate code path.

## Phase 2 — scheduler / notifier

A launchd **user agent**, declared in `modules/darwin/` alongside the config's
other services, runs the gate on a timer (default: daily).

- On each fire it runs the gate (`prepare`'s probe+decide logic).
- **Only when something real changed** it completes `prepare` — unprivileged:
  updates lock/overlays, builds evidence, commits the proposed revision — and
  fires a **macOS notification via `osascript`**:
  *"nixos-config: 3 overlays + nixpkgs updated, revision abc123 ready to
  activate."*
- It **never activates.** Activation stays the single privileged step the user
  triggers manually (`nix run .#activate -- <rev>`).
- On no change: silent, no commit, no notification.

The commit it produces flows through the existing post-commit public-mirror hook
like any other, so scheduled updates reach the public repo automatically.

Notification mechanism: `osascript -e 'display notification "…" with title "…"'`.

## Error handling

- **Upstream probe failure** (GitHub API down, curl timeout): treated as "no
  change detected" for that item — never a spurious fetch or update. Overlay
  `ERROR`/`MANUAL` statuses are non-outdated. Logged, not fatal.
- **State cache missing / corrupt**: rebuilt from scratch (full check this run);
  never fatal.
- **`updates.json` inputs key malformed**: fall back to default cadence, warn.
- **Scheduler build failure**: notify with the failure, do not commit, leave the
  tree clean for the next run.
- **Concurrent runs** (scheduler fires while a manual run is active): a simple
  lockfile in the state dir; second runner exits early.

## Testing

- **`check-overlay-versions.sh --json`**: golden-output test with a stubbed
  `curl` (fixture responses) → assert the JSON shape and `outdated` flags,
  including an `ERROR` case that must not mark anything outdated.
- **`fix-hashes --only`**: assert only named overlays are processed (dry-run /
  trace mode counting `nix-prefetch-url` invocations).
- **Flake-input probe**: unit-test the cadence gate (due vs not-due from a fixed
  `now` and a fixture state file) and the movement check (locked rev == vs !=
  upstream) with stubbed metadata.
- **Gate decision**: table test over {overlays changed?, lock changed?} →
  {build?, commit?} — the core four-quadrant truth table.
- **State cache**: round-trip read/modify/write; corrupt-file recovery.
- **Manual smoke**: `nix run .#check` with everything up to date prints
  "nothing to do" and never builds.

## Phasing

- **Phase B (core):** state cache, `--json`, `--only`, flake-input cadence
  probe, gate wired into `prepare`, `check` entry.
- **Phase C (scheduler):** launchd agent + `osascript` notifier in
  `modules/darwin/`.

Each phase keeps `nix fmt` clean and `nix flake check` green
(`treefmt` + `overlays-manifest` + `darwin-build`); the `overlays-manifest`
check is updated to accept the new `inputs` key.

## Out of scope (YAGNI)

- Auto-activation (privileged switch stays manual, by design).
- Non-macOS scheduler (NixOS systemd timer) — add later if needed.
- Notification channels beyond `osascript` (hey-cli, log tailing).
- Rollback automation on failed scheduled builds beyond "don't commit + notify".
