---
name: overlay-repair
description: Use when repairing a failed nixos-config overlay version bump — invoked by scripts/escalate.sh with a prepared brief naming the package, the attempted version, and the classified build failure.
---

# Overlay Repair

You are repairing ONE failed overlay version bump in the throwaway git worktree
that is your current working directory. The brief names the package, the
attempted version, the overlay file, its `update_type`, and the classified
failure.

**Never use absolute paths, and never edit outside this worktree.** In
particular, do not touch `~/nixos-config` or any other absolute path to the
daily-driver checkout — that repo refuses to start its next automated run
while `overlays/` is dirty, so an edit landing there instead of in this
worktree silently wedges every future run.

## Hard rules

- **This is a headless, single-shot session with no scheduler behind it.** Never background a
  command and wait for it, and never wait on a "scheduled wakeup" or any other asynchronous
  signal — nothing will ever arrive, and the session just ends with nothing accomplished. Every
  command you run must complete synchronously before you move to the next step.
- **You cannot commit, push, activate, or sudo.** Those tools are not available
  to you by design. The wrapper commits — and only after independently
  re-running your build. Your claim of success is not evidence.
- **Bump the overlay's pinned version/hash AND `overlays/updates.json`'s
  `current_version` together.** Doing only one leaves the manifest lying about
  what is pinned, which masks the package as up-to-date on every later probe.
- **Replace EVERY occurrence of the old version in code, not just the primary
  `version =` field.** The wrapper rejects a repair if the previous version
  string still appears on any non-comment line of the overlay. Multi-platform
  overlays (`ngrok`, `mise`, `uv`) pin the version in several per-platform URLs
  and hashes — bumping only the darwin entry is a partial bump and will be
  refused. Comments are exempt, so narrative comments naming the old version
  are fine to leave.
- **Two attempts maximum.** If the mechanical path does not work, write
  `gave-up` with a precise diagnosis. A wrong-but-building overlay is worse
  than a frozen one — it ships silently broken software.
- **Do not disable checks to make a build pass** unless the failure is
  demonstrably a sandbox-only test issue, and say so explicitly in the verdict.
- **Do not widen scope.** Repair this one package. Do not refactor, reformat
  unrelated files, or "improve" neighbouring overlays.
- **Only files under `overlays/` may be modified.** The wrapper only ever
  stages and commits `overlays/`, but its verification build is `--impure`
  against the whole worktree — so a fix needing a file elsewhere (a patch
  file, a shared module, anything outside `overlays/`) would "verify" and
  then get committed without that file. The wrapper refuses this outright
  (exit 1, `gave-up`) rather than ship an incomplete repair. If a real fix
  needs something outside `overlays/`, write `status: "gave-up"` and say so
  precisely — don't attempt it, the wrapper will only reject it anyway.

## Getting a hash

```bash
# Archives (tar.gz, tar.xz, zip):
nix-prefetch-url --unpack <url>
# Single prebuilt binaries:
nix-prefetch-url <url>
# Then convert to SRI:
nix hash convert --hash-algo sha256 --to sri <raw-hash>
```

For Go/Cargo source builds, blank `vendorHash`/`cargoHash` to `""`, run the
scoped build, and read the expected hash out of the error message.

## Failure playbook by fingerprint

| fingerprint | usual cause | first thing to try |
|---|---|---|
| `eval-error` | upstream renamed something the overlay references | For `go`, a minor bump renames the `go_1_26` attribute — rename it to match. Otherwise read the overlay and fix the reference the error names. |
| `compile-failure` | genuine break in the new version | Check whether upstream changed the artifact layout (a moved binary path, a new archive root). If the code itself is broken, `gave-up`. |
| `test-failure` | sandbox-hostile test suite | Only if clearly sandbox-related (network access, timing), add `doCheck = false;` and say so in the verdict. Otherwise `gave-up`. |
| `hash-mismatch` | should not reach you — `fix-hashes` handles it | If it does, re-prefetch and substitute manually. |
| `unclassified` | unknown | Read the log carefully. If you cannot state a cause in one sentence, `gave-up`. |

## Package-specific knowledge

- **yt-dlp** (`overlays/91-yt-dlp.nix`): the `postPatch` section pins `curl_cffi`
  version bounds that routinely need widening on each release. `yt-dlp-ejs` is
  bundled in the same file and versioned separately (PyPI package `yt_dlp_ejs`).
- **go** (`overlays/55-go.nix`): a minor bump (1.26 → 1.27) requires renaming the
  `go_1_26` attribute as well as the version and hashes.
- **tmux** (`overlays/96-tmux.nix`): `overrideAttrs` with a `fetchFromGitHub` src
  where the tag equals the version (e.g. `3.7b`). `fix-hashes` does not touch it.
- **ngrok** (`overlays/20-ngrok.nix`): stable CDN URLs from `bin.equinox.io`, no
  versioned release pages. Six platform hashes must be fetched.
- **mise** (`overlays/30-mise.nix`): now prebuilt binaries; use raw
  `nix-prefetch-url` (not `--unpack`) per platform.
- **hey-cli** (`overlays/94-hey-cli.nix`): a `buildGoModule` derivation. Its
  `go.mod` `go` directive tracks upstream closely, so a bump can start
  requiring a newer Go than nixpkgs' default the moment it lands — this repo
  pins Go via `overlays/55-go.nix`, but that pin is a SEPARATE overlay. See the
  cross-overlay-dependency note under Verify below: the scoped single-overlay
  build can spuriously fail on a `go.mod` bump even when the real fix is
  correct, because it builds against nixpkgs' unpinned `go` instead of this
  repo's pin — the wrapper now falls through to the full-system build in that
  case (see Verify), so a scoped-build failure here is not fatal on its own.

Full recipes: `docs/overlay-update-routine.md`.

## Verify

```bash
nix build --no-link --impure --expr \
  'let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./overlays/<file>.nix) ]; }; in pkgs.<attr>'
```

Run `nix fmt` if you changed a `.nix` file.

**Cross-overlay dependencies can make this scoped build a false negative.**
It loads ONLY the one overlay file, so any package whose build depends on
another overlay's package override — e.g. `buildGoModule` derivations built
against the pinned `go` from `overlays/55-go.nix` — sees nixpkgs' unpinned
default instead. `hey-cli` hit this in July 2026: its `go.mod` required a
newer Go than nixpkgs' default, the repo already pins a sufficient version via
`55-go.nix`, but the scoped verify build used nixpkgs' older default `go` and
failed with `could not resolve vendorHash from build error`, even though the
fix was correct.

**This is no longer fatal on its own.** The wrapper (`scripts/escalate.sh`)
falls through to a full-system build whenever the scoped build fails, and only
records `gave-up` if that full build fails too — so write `verdict.json` with
`status: "fixed"` as normal; you do not need to give up just because the
scoped build above failed. It's still worth verifying with the real host attr
yourself before writing the verdict, both to confirm your fix actually works
and because it loads every overlay together the same way the wrapper's
fallback does:

```bash
nix build --no-link --print-out-paths \
  ".#darwinConfigurations.garmonbozia.pkgs.<attr>"
```

If even that fails, the fix is genuinely broken (or broken by something this
overlay can't control) — write `gave-up` with a precise diagnosis.

## Write the verdict

Write `verdict.json` in the worktree root. This is your only output channel:

```json
{
  "status": "fixed",
  "package": "yt-dlp",
  "fingerprint": "compile-failure",
  "verdict": "One paragraph: what was wrong, what you changed, and what you verified. If gave-up, state precisely what a human needs to decide.",
  "files_changed": ["overlays/91-yt-dlp.nix", "overlays/updates.json"]
}
```

`status` is `fixed` or `gave-up`. Claiming `fixed` without a passing scoped
build wastes a whole day of automation — the wrapper will catch it, record the
discrepancy against you, and quarantine the package anyway.
