# Overlay Bump Tutorial

This repo pins ~16 overlays to specific upstream versions (see
`overlays/updates.json`). Keeping them current has three tiers of
automation — knowing which tier a package is in tells you which command to
reach for.

## The three tiers

1. **Detection only, everything** — `nix run .#check` (read-only) probes
   every pinned overlay and every cadence-gated flake input, and prints
   what's outdated. Nothing is ever changed by this command.
2. **Detection + application, mechanical subset** — `nix run .#bump-overlays`
   actually applies the bump for the overlays where doing so is a pure,
   verifiable value substitution: fetch a new hash, substitute a literal
   version/hash string, verify with a scoped `nix build`, commit. In scope
   today: **claude-code, codex-openai, uv, trailbase, igir, dcg,
   aws-cdk-cli, mise** (prebuilt binaries), **go** (only on a patch-level
   bump — a minor bump needs a manual attribute rename, see below), and
   **beads, c4, hey-cli** (Go-source overlays; one extra automated step to
   resolve `vendorHash` from a build-error probe).
3. **Detection automated, application manual** — everything else:
   **yt-dlp/yt-dlp-ejs** (needs human review of `curl_cffi` version bounds
   in release notes), **ngrok** (its overlay declares a separate `version =
   "X";` per platform block rather than one shared value — six matches, not
   one — so `bump-overlays` *attempts* it, but `bump_version_string()`'s
   safety net requires exactly one match, correctly rejects the substitution,
   and reverts the file cleanly via `git checkout --`; it shows up under
   "Failed", not "Skipped". No structured single-URL data exists to fix this
   without restructuring the overlay itself), **tmux** (different shape —
   `overrideAttrs` + `fetchFromGitHub` tag, not automated), and **go on a
   minor bump** (renaming `go_1_26` → `go_1_27` throughout the overlay is a
   structural edit, not a substitution). For all of these, follow
   `docs/overlay-update-routine.md` by hand.

## Day-to-day usage

```bash
nix run .#bump-overlays -- --dry-run   # preview: what would be bumped, no writes
nix run .#bump-overlays                # apply — one commit per successfully bumped package
git log --oneline -5                   # review what landed
nix run .#build-switch                 # actually switch the running system to the new binaries
```

`bump-overlays`'s own verification (`nix build --impure --expr
'...pkgs.PACKAGE'`) only proves the package builds in isolation — it does
**not** switch your running system. Run `nix run .#build-switch` afterward
to actually pick up the new binaries, same as after any other overlay
change.

`--only <name>[,<name>...]` restricts a run to specific packages, e.g. `nix
run .#bump-overlays -- --only uv,aws-cdk-cli`.

## When it reports a skip or a failure

- **Skipped** — the package's `update_type` isn't in the automated subset
  (tier 3 above), or it's `go` on a minor-version move. The summary line
  names the package and points here. Follow the matching recipe in
  `docs/overlay-update-routine.md`.
- **Failed** — something in the mechanical path itself broke: a hash fetch
  404'd, the version-substitution safety net found zero or more than one
  match (it never guesses), or the verification build failed. The script
  reverts that package's overlay file with `git checkout --` before moving
  to the next package, so a failure never leaves a half-edited file behind
  and never blocks other packages in the same run. Re-run with `--only
  <name>` after investigating, or fall back to the manual routine for that
  one package.

The go-source path (beads, c4, hey-cli) has been tested against fixtures but
not yet exercised end-to-end against a real outdated package (none has gone
outdated since this tool was built) — so `resolve_vendor_hash()`, the GitHub
full-SHA fetch, and the final verify build have never all run together
against live upstream data. The first time one of these three does go
outdated, run it supervised — `nix run .#bump-overlays -- --only <name>` —
and watch the output, rather than trusting it blind in a larger batch run.

## Extending the automation later

A package can move from "manual" (tier 3) to "mechanical" (tier 2) once its
overlay file has exactly one `version = "X";` assignment (plus exactly one
`hash =`/`sha256 =` field per platform) — the invariant
`bump_version_string()`'s safety net checks. Note that `update_type` alone
isn't sufficient: it only gates whether `bump-overlays` *attempts* a
package, not whether the attempt succeeds. ngrok's `update_type` already
matches the mechanical set, but its overlay still declares 6 separate
`version = "3.39.10";` assignments (one per platform block) rather than one
shared value, so every attempt fails the single-match check. Moving it to
tier 2 in practice would mean refactoring `overlays/20-ngrok.nix` to a
single shared `version` (as trailbase/igir/dcg/go already do), not an
`updates.json` change.

## Relationship to the daily launchd job

The daily `scheduled-check` launchd job runs `bump-overlays --mechanical-only`
**before** `prepare`, so the mechanical tier bumps itself unattended. Details
that differ from a manual `nix run .#bump-overlays`:

- **`--mechanical-only`** drops the go-source packages (`beads`, `c4`,
  `hey-cli`) from scope, listing them as skipped. `c4` and `hey-cli` are
  commit-tracked with no upstream releases, so an unattended run would chase
  branch HEAD every day with nothing gating it. Run the command by hand to
  bump those.
- **Ordering.** The bump runs first so that, if `prepare` then finds a flake
  input due, its build already covers the bumped overlays. When `prepare` has
  nothing to do (the normal case while nixpkgs is pinned), `scheduled-check`
  runs the full `darwinConfigurations.<host>.system` build itself before
  notifying — `bump-overlays`' own build is scoped to one package and won't
  catch a system-level eval error or file collision. Every revision the daily
  job proposes has been built.
- **Locking.** `bump-overlays` now takes the same `.update-state.json.lock.d`
  lock as `prepare` and exits **2** on contention, so a manual run and the
  scheduled run can never interleave. Exit **3** means `overlays/` had
  uncommitted changes; exit **1** means at least one package failed to bump
  (the rest still committed).
- **Notifications.** A partial failure produces two: the normal "revision
  ready" for what landed, and a bump-FAILED naming the packages that need
  [the manual routine](overlay-update-routine.md). If the full system build
  fails, the bump commits are left in place (not auto-reset — a hard reset
  could take unrelated work with it) and the notification gives you the
  `git reset --hard <before>` to discard them.

The job still **never activates**; it only proposes.
