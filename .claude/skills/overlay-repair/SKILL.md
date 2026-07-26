---
name: overlay-repair
description: Use when repairing a failed nixos-config overlay version bump — invoked by scripts/escalate.sh with a prepared brief naming the package, the attempted version, and the classified build failure.
---

# Overlay Repair

You are repairing ONE failed overlay version bump in `~/nixos-config`. The brief
names the package, the attempted version, the overlay file, its `update_type`,
and the classified failure. You are running in a throwaway git worktree.

## Hard rules

- **You cannot commit, push, activate, or sudo.** Those tools are not available
  to you by design. The wrapper commits — and only after independently
  re-running your build. Your claim of success is not evidence.
- **Bump the overlay's pinned version/hash AND `overlays/updates.json`'s
  `current_version` together.** Doing only one leaves the manifest lying about
  what is pinned, which masks the package as up-to-date on every later probe.
- **Two attempts maximum.** If the mechanical path does not work, write
  `gave-up` with a precise diagnosis. A wrong-but-building overlay is worse
  than a frozen one — it ships silently broken software.
- **Do not disable checks to make a build pass** unless the failure is
  demonstrably a sandbox-only test issue, and say so explicitly in the verdict.
- **Do not widen scope.** Repair this one package. Do not refactor, reformat
  unrelated files, or "improve" neighbouring overlays.

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

Full recipes: `docs/overlay-update-routine.md`.

## Verify

```bash
nix build --no-link --impure --expr \
  'let pkgs = import <nixpkgs> { config.allowUnfree = true; overlays = [ (import ./overlays/<file>.nix) ]; }; in pkgs.<attr>'
```

Run `nix fmt` if you changed a `.nix` file.

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
