# Automated Overlay Bump Routine — Design

**Date:** 2026-07-23
**Status:** Approved design, pending implementation plan
**Scope:** A new `nix run .#bump-overlays` command that mechanically applies
version bumps for the subset of pinned overlays where doing so is a pure,
verifiable value substitution — plus a tutorial documenting the automated
path and what's still manual.

## Problem

`docs/overlay-update-routine.md` documents, in detail, how to bump each
pinned overlay: fetch the new hash, edit the `.nix` file, update
`overlays/updates.json`, verify, commit. Detection is already automated
(`scripts/check-overlay-versions.sh`, `nix run .#check`), but *applying* a
detected bump is 100% manual today — by design (see "Smart Incremental
Updates" section of the doc): a bump requires rewriting the overlay's pinned
version/hash **and** `updates.json`'s `current_version` together, and the
project deliberately never auto-applies only one half of that (it would leave
the manifest lying about what's pinned).

That reasoning is sound but overbroad: for a subset of overlays the bump is
*fully mechanical* — fetch a URL, hash it, substitute a literal value, verify
with a scoped build. This design automates exactly that subset, leaves
everything else exactly as manual as it is today, and adds a tutorial so the
line between the two is unambiguous next time someone (human or agent) reaches
for this.

## Scope decision

**In scope** (mechanical, safe to automate):
- `prebuilt-binary` / `prebuilt-binary-multiplatform` / `prebuilt-npm`
  overlays that have a `platforms{}.url_template` (or single implicit
  platform) in `overlays/updates.json`: **claude-code, codex-openai, uv,
  trailbase, igir, dcg, aws-cdk-cli**.
- `go-source` overlays: **beads, c4, hey-cli** — one extra step (resolve
  `vendorHash` from a build-error probe) but still fully mechanical.
- `go` overlay (`overlays/55-go.nix`) — **only** on a patch-level bump (same
  major.minor). A minor bump requires renaming the `go_1_26` attribute
  throughout the file, which is a structural edit, not a substitution — the
  script detects a minor/major version change and skips it (reports it as
  needing the manual routine).

**Explicitly out of scope, and why:**
- **ngrok** — `update_type` says `prebuilt-binary-multiplatform`, but
  `updates.json` has no `platforms{}` entry for it; the 6 platform URLs only
  exist as hardcoded shell in the doc. The doc also explicitly says "skip
  auto-applying in automated runs." No structured data to drive it safely.
- **tmux** (`source-override`) — not requested in scope; different shape
  (`overrideAttrs` + `fetchFromGitHub` `tag`/`hash`, no version-string
  interpolation pattern matching the others).
- **mise** (`cargo-source`) — doc explicitly forbids: cargo hash resolution
  needs a real ~15 min local build the doc says not to wait for in an
  automated run.
- **yt-dlp / yt-dlp-ejs** (`python-override`) — doc explicitly forbids:
  postPatch `curl_cffi` version bounds need human review of release notes.

This mirrors exactly the doc's own risk classification — the "semi-automated,
apply manually" and "most complex, do not auto-update" categories stay
manual; the fully mechanical categories get automated.

## Key design decision: literal value substitution, not Nix parsing

Overlay files are hand-written and not structurally uniform (some use
`sha256 =`, others `hash =`; some are flat attrsets, some `let`-bound, some
multiplatform dicts keyed by system string). Rather than parsing Nix, the
script substitutes **known old value → newly fetched value** as literal text:

1. **Version**: every in-scope overlay has exactly one `version = "X.Y.Z";`
   declaration. Replace that literal string. Downstream URLs are built via
   `${version}` interpolation in the source, so they never appear as literal
   text and never need touching.
2. **Hash(es)**: this is the only structurally-varying part.
   - **Single-platform overlays** (uv, claude-code, codex-openai,
     aws-cdk-cli): exactly one `(sha256|hash) = "sha256-...";` field in the
     file — replace it directly.
   - **Multiplatform dict-style overlays** (trailbase, igir, dcg): match each
     platform's block by its `"system-name" = { ... };` anchor and replace
     only the `hash =`/`sha256 =` line inside that block.
   - **go-source overlays** (beads, c4, hey-cli): replace the `fetchFromGitHub`
     `hash =` (source hash) the same way, plus a separate `vendorHash =` step
     (below).

**Safety net:** if a substitution doesn't find *exactly one* match for a
field it expects to replace, the script aborts that package (reverts the
file with `git checkout --`, does not commit) and reports it as needing the
manual routine. It never guesses or does a fuzzy match.

## `go-source` extra step: vendorHash resolution

For beads / c4 / hey-cli, after updating `version`/`rev`/source `hash`:

1. Set `vendorHash = "";` (blank).
2. Run a scoped build:
   ```bash
   nix build --impure --expr \
     'let pkgs = import <nixpkgs> { overlays = [ (import ./overlays/OVERLAY.nix) ]; }; in pkgs.PACKAGE' \
     2>&1 | grep 'got:' | awk '{print $2}'
   ```
3. Substitute the printed `sha256-...` into `vendorHash =`.
4. Re-run the same build to verify it now succeeds — this *is* the
   verification step for go-source packages (no separate second build).

This is exactly the doc's existing manual recipe, scripted.

## Command flow

```
nix run .#bump-overlays [--dry-run] [--only <name>[,<name>...]]
```

1. **Precondition check** — refuse to start if `git status --porcelain
   overlays/` is non-clean (never mixes with in-progress manual edits).
2. **Detect** — run `scripts/check-overlay-versions.sh --json`, filter to
   `outdated: true` entries whose `update_type` is in the supported set
   (and, for `go`, whose bump is patch-level only).
3. **Per package** (in the filtered set, or just `--only` names):
   a. Compute the new hash(es) via `nix-prefetch-url` (`--unpack` iff the
      URL extension is an archive: `.tar.gz`/`.tgz`/`.zip`/`.tar.xz`) →
      `nix hash convert --hash-algo sha256 --to sri`.
   b. Rewrite the overlay file via the substitution rules above.
   c. For go-source: also resolve `vendorHash` (above).
   d. Verify: `nix build --impure --expr '...pkgs.PACKAGE'` (scoped build —
      this was your chosen verification level; go-source's step above
      doubles as its verification).
   e. On success: update `current_version` (and `current_rev` for
      c4/hey-cli) in `overlays/updates.json`; `git add` exactly the overlay
      file + `updates.json`; commit `overlays: update PKG to vX.Y.Z`
      (matches existing commit style — check `git log --oneline` for
      precedent).
   f. On failure at any step: `git checkout --` the overlay file (and
      `updates.json` if touched), print the failure, continue to the next
      package. One package's failure never blocks the others.
4. **Summary**: `Bumped: N. Failed: M. Skipped (unsupported/minor-go): K.`
   Failed/skipped packages are listed by name with a pointer to
   `docs/overlay-update-routine.md` for the manual path.
5. **`--dry-run`**: performs steps 1–3a (fetch + compute what *would*
   change) and prints a diff-like preview; writes nothing, builds nothing,
   commits nothing.

Because each successful bump is its own commit, the existing post-commit
public-mirror hook in this (private, no-remote) checkout mirrors and pushes
each one to the public repo automatically — no separate publishing step is
needed. (Verified: `~/nixos-config` has no git remote; the hook is what
carries commits to `github.com/bgyss/nixos-config`.)

## New files

- `scripts/bump-overlays.sh` — the engine (bash, calling `check-overlay-versions.sh
  --json`, `nix-prefetch-url`, `nix hash convert`, `nix build`, plus small
  Python-via-`python3 -c` or `sed`/`perl` for the anchored substitutions —
  final choice made in the implementation plan).
- `apps/aarch64-darwin/bump-overlays` (+ other supported systems, mirroring
  how `apps/*/check` is wired) — flake app entry point, same pattern as
  existing `check`/`prepare`.
- `docs/overlay-bump-tutorial.md` — the new tutorial (below).

## Tutorial document

New file: `docs/overlay-bump-tutorial.md`. Walks through the full picture
end to end for a human (or a future agent) landing on this for the first
time:

1. **The three tiers**, stated plainly:
   - Fully automated *detection*: `nix run .#check` (all overlays + inputs).
   - Automated *detection + application*: `nix run .#bump-overlays` (the
     mechanical subset listed above).
   - *Detection automated, application manual*: everything else (mise,
     yt-dlp, ngrok, tmux, `go` minor bumps) — link to
     `docs/overlay-update-routine.md` for the step-by-step.
2. **Day-to-day usage**: run `nix run .#bump-overlays` (optionally
   `--dry-run` first), review the resulting commit(s) with `git show`, then
   `nix run .#build-switch` locally to actually pick up the new binaries (the
   script's verification build doesn't switch the running system).
3. **When it reports a skip/fail**: what that means, and the exact manual
   recipe in `docs/overlay-update-routine.md` to fall back to for that
   package.
4. **Extending the automation**: how to move a package from "manual" to
   "in-scope" later (what structural properties it needs — single/multi hash
   field pattern, `platforms{}.url_template` present in `updates.json`) —
   short, since this is a reference for a future decision, not a build guide.
5. **Relationship to the daily launchd job**: explicitly states
   `bump-overlays` is a separate, manually-triggered command and is **not**
   wired into `scheduled-check` — the daily job still only proposes flake-input
   moves and reports (not applies) overlay bumps, unchanged.

`docs/overlay-update-routine.md` gets a short pointer added at the top:
"Packages in the automated subset can be bumped with `nix run
.#bump-overlays` instead of following this by hand — see
`docs/overlay-bump-tutorial.md`. This document remains the source of truth
for every overlay, including the ones bump-overlays doesn't touch."

## Error handling

- **Upstream fetch failure** (`nix-prefetch-url` times out/404s): treated as
  a per-package failure, same revert-and-continue path as a bad substitution
  or failed build.
- **`nix build` verification failure**: revert the overlay file, do not
  touch `updates.json`, do not commit, continue.
- **go-source `vendorHash` probe finds no `got:` line**: treated as a
  failure for that package (upstream's Go module graph may have changed in a
  way that needs eyes) — revert, continue.
- **Precondition failure** (dirty `overlays/`): exit immediately before
  touching anything, point the user at `git status`.
- **Partial run** (some succeed, some fail): each success is already
  committed independently, so a partial run leaves a clean, bisectable
  history — no rollback step needed.

## Testing

- **Substitution logic**: unit-test the single-hash and multiplatform-dict
  substitution against fixture copies of a real overlay file (e.g. a copy of
  `25-uv.nix` and `50-trailbase.nix`), asserting exactly-one-match enforcement
  (including a deliberately-broken fixture with zero/two matches → expect
  abort, not corruption).
- **go-source vendorHash step**: test the `got:` line parser against a
  fixture build-failure transcript.
- **Dry-run**: assert `--dry-run` never calls `git add`/`git commit`/writes
  any file.
- **`--only` filter**: assert it restricts to exactly the named package(s).
- **Manual smoke test**: run `nix run .#bump-overlays --dry-run` against the
  two currently-outdated packages (uv 0.11.31→0.11.32, aws-cdk-cli
  2.1132.1→2.1133.0) and confirm the preview matches what the manual routine
  would produce; then run it for real on one of them as the first live
  validation before trusting it on the rest.

## Out of scope (YAGNI)

- Wiring into the daily `scheduled-check` launchd job (explicitly deferred —
  you chose "new manual command only" for now).
- ngrok, tmux, mise, yt-dlp automation (explicitly excluded above).
- A `--all-including-risky` escape hatch to force-run excluded types — if
  that's ever wanted, it's a deliberate future decision, not a default.
