# Troubleshooting

Detailed fixes for problems that come up when building/switching this config. See
[CLAUDE.md](../CLAUDE.md) for day-to-day commands and workflow.

## Package Conflicts

If you encounter package collision errors (like the whisper-cpp/llama-cpp issue), check for
duplicate packages providing the same files. Remove conflicting packages from
`modules/shared/packages.nix`.

## Package Version Issues

If a package isn't getting the expected version from nixpkgs-unstable, check the overlay
configuration in `flake.nix`. Packages explicitly inherited from the `nixpkgs-master` overlay
will use the master branch version instead of the unstable version.

## Build Failures

- Check that all required inputs are available
- Verify flake.lock is up to date: `nix flake update`
- Review error logs: `nix log /nix/store/[derivation-hash]`

## Python Test Failures in Nix Sandbox

**Default: don't add `doCheck = false` overrides.** Every override changes the derivation hash of
that package *and everything downstream*, so cache.nixos.org can no longer substitute any of it
and the whole slice rebuilds locally (an earlier ~30-package override list in
`overlays/81-python-disable-checks.nix` did exactly this and was removed). The same applies to
`fmt`, `deno` and `nodejs`, whose `doCheck = false` overlays were also removed. Measure with
`nix build .#darwinConfigurations.garmonbozia.system --dry-run --store /tmp/emptystore` — the
"derivations will be built" count is what a cold machine must compile.

If a package genuinely fails its tests in the sandbox after a bump, override **just that one**
in `overlays/81-python-disable-checks.nix` (inside `pyOverrides`), preferring leaf packages
nothing else depends on. The file patches `python314` only (our own package list uses it);
nixpkgs' internal `python3` alias is still python313 and is intentionally left stock so it is
substituted from the cache.

**Diagnosing which phase failed**:

| Error message | Failing phase | Fix |
| --- | --- | --- |
| `FAILED tests/...` or `X failed, Y passed` | `checkPhase` (tests) | `doCheck = false` |
| `- <pkg> not installed` | `pythonRuntimeDepsCheck` | `dontCheckRuntimeDeps = true` |
| `ModuleNotFoundError` during import check | `pythonImportsCheck` | `pythonImportsCheck = [ ]` |

```nix
mypackage = pyPrev.mypackage.overridePythonAttrs {
  doCheck = false;
  dontCheckRuntimeDeps = true; # only if the runtime dep check fails
  pythonImportsCheck = [ ]; # only if the import check fails
};
```

## Upstream Hash Mismatches

When a prebuilt binary is re-published under the same version (e.g., `uv`), the build fails
with `hash mismatch in fixed-output derivation`. The error message provides the correct hash
on the `got:` line — just update the `sha256` attribute in the relevant file (overlay or
`modules/shared/packages.nix`).

**Standard fix procedure** (takes ~30 seconds):

1. Read the error output — it contains both lines:
   ```
   specified: sha256-<old-hash>=
      got:    sha256-<new-hash>=
   ```
2. Find the overlay that holds the stale hash:
   ```bash
   grep -r "<old-hash>" overlays/ --include="*.nix" -l
   ```
3. Replace the `sha256` value with the `got:` hash in that file.
4. Re-run `nix run .#build-switch`.

**Overlays with pinned hashes** (check these after every `nix flake update` if the build fails):

| Overlay | Package | Note |
| --- | --- | --- |
| `20-ngrok.nix` | ngrok | aarch64-darwin binary |
| `25-uv.nix` | uv | aarch64-darwin binary; nixpkgs used on other platforms |
| `30-mise.nix` | mise | multi-platform prebuilt |
| `40-codex-openai.nix` | codex-openai | prebuilt binary |
| `41-claude-code.nix` | claude-code | prebuilt binary |
| `50-trailbase.nix` | trailbase | multi-platform prebuilt |
| `70-igir.nix` | igir | multi-platform prebuilt |
| `96-tmux.nix` | tmux | pinned to 3.7b, GitHub source archive |

**Proactive check after `nix flake update`**: if the bump commit message says a
prebuilt-binary overlay was bumped (e.g., `overlays: bump uv to X.Y.Z`), verify the hash in
that overlay matches the newly released artifact before running build-switch. You can
prefetch to confirm:
```bash
nix-prefetch-url --unpack https://github.com/astral-sh/uv/releases/download/X.Y.Z/uv-aarch64-apple-darwin.tar.gz
# then: nix hash convert --hash-algo sha256 --to sri <printed hash>
```

Or run `nix run .#fix-hashes`, which automates this check across all prebuilt-binary overlays.

## Upstream Download Failures (HTTP 429 / 404)

When upstream servers rate-limit or remove downloads (e.g., Spotify), temporarily comment out
the package in `modules/shared/packages.nix` if it's also available via Homebrew cask on
macOS. Re-enable later when the download stabilizes.

## Stale Dock Entry ("?" icon) After Removing an App

Removing an entry from `local.dock.entries` (`modules/darwin/home-manager.nix`) and running
`build-switch` can still leave a "?" tile in the Dock for the removed app after the rebuild
completes. Root cause: `modules/darwin/dock/default.nix`'s activation script does
`dockutil --remove all` → re-add configured entries → `killall Dock`, but `killall Dock`
returns before macOS finishes writing/reloading `com.apple.dock.plist`, so the reset can lose
the race and a removed app's tile survives. The activation script now runs the remove+add pass
twice (with a `sleep 2` between) as a verification pass to close this race. If a stale tile
still appears after `build-switch`, fix it directly and it won't come back:
```bash
/opt/homebrew/bin/dockutil --remove "<App Name>" --no-restart
killall Dock
```

## macOS Specific

- Ensure nix-darwin is properly installed
- Check that the user is in the trusted-users list
- Verify Homebrew integration is working

## Emacs org-config fallback bug

`modules/shared/config/emacs/init.el`'s `org-config-file` variable must point at this repo's
actual clone path (`~/nixos-config/modules/shared/config/emacs/config.org`). If it points
anywhere else, `file-exists-p` silently fails and Emacs falls back to downloading the
template author's stale default config from GitHub instead of loading local customizations —
this can look like org-mode "not picking up" changes to `config.org`.

## agenix secrets silently never decrypt (ssh-to-age / age incompatibility)

**Symptom**: `age.secrets.<name>` is configured, `nix flake check` passes, `build-switch`
succeeds, `/run/agenix.d/` exists (a root-only-listable mountpoint; `/run/agenix` is a symlink
to a versioned subdirectory under it, e.g. `/run/agenix.d/1/<name>`), but the individual
secret at `/run/agenix/<name>` never appears. A consumer guarding with
`[[ -r /run/agenix/<name> ]]` silently never fires (e.g. `OPENAI_API_KEY` never gets set, with
no error anywhere).

**Root cause**: `agenix` (both the CLI and the nix-darwin/NixOS activation script) decrypts by
shelling out to `age --identity <ssh-private-key-file>` directly — it does **not** run the key
through `ssh-to-age` first. `age`'s own built-in ed25519→X25519 conversion for SSH identities
is a *different* conversion than what the standalone `ssh-to-age` tool produces. If
`secrets.nix`'s recipients were generated by running `ssh-to-age -i host_key.pub` (as older
versions of this repo's docs recommended), the resulting `age1...` recipient can never be
decrypted by `age --identity <that same ssh key>` — encryption and decryption use mismatched
key derivations. This is reproducible with any ed25519 SSH key, not specific to any one
machine or key.

**Fix**: use the raw SSH public key string (`"ssh-ed25519 AAAA... comment"`) directly as the
recipient in `secrets.nix` instead of an `ssh-to-age`-converted value. `age` accepts
`ssh-ed25519`/`ssh-rsa` public keys natively as `-r` recipients, and this is self-consistent
with `age --identity <ssh-private-key>` on decrypt. Re-encrypt every existing secret after
changing a recipient (`age -r "<pubkey1>" -r "<pubkey2>" -o <name>.age <plaintext>`).
Secrets and `secrets.nix` now live in the separate
[bgyss/nix-secrets](https://github.com/bgyss/nix-secrets) repo — see this repo's `CLAUDE.md`
Secrets Management section.

**Always verify a secret actually decrypts** after adding or re-keying it — don't trust
`nix flake check` or a successful `build-switch` alone, since neither of those exercises the
runtime `age --identity` decrypt path:
```bash
age -d -i ~/.ssh/id_ed25519 -o /dev/null <name>.age && echo OK
```

## Detailed overlay-update recipes

Step-by-step version-bump procedures for every pinned overlay (prebuilt binaries, cargo
source builds, go source builds, python overrides) live in
[docs/overlay-update-routine.md](overlay-update-routine.md).
