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

After `nix flake update`, Python packages frequently fail to build because their test suites
are incompatible with the Nix build sandbox (no network, no dbus, no real timers). The fix is
**not** to pin nixpkgs — instead, disable checks for the offending package.

**How it works**: `overlays/81-python-disable-checks.nix` uses
`pythonX.override { packageOverrides = ...; }` to propagate `doCheck = false` through the
interpreter's own scope, for **both** python313 and python314. This is critical —
`overrideScope` alone does NOT propagate to `pythonX.withPackages` consumers. Both
interpreters must be patched: our own package list (`modules/shared/packages.nix`) uses
python314, but nixpkgs' internal `python3` alias is still python313, and several nixpkgs
derivations (`glances`, `semgrep`, `curl-cffi`, `fastapi`, `mcp`, `jetbrains-mono`, `yt-dlp`,
...) build against it internally.

**Diagnosing which phase failed**:

| Error message | Failing phase | Fix |
| --- | --- | --- |
| `FAILED tests/...` or `X failed, Y passed` | `checkPhase` (tests) | `doCheck = false` |
| `- <pkg> not installed` | `pythonRuntimeDepsCheck` | `dontCheckRuntimeDeps = true` |
| `ModuleNotFoundError` during import check | `pythonImportsCheck` | `pythonImportsCheck = [ ]` |

**Categories of known-flaky packages** (already covered in overlay):

- **Async/networking** (timing assertions fail in sandbox): `aiohappyeyeballs`, `aiohttp`, `aiosignal`, `httpcore`, `httpx`, `anyio`, `uvloop`
- **D-Bus/system services** (no `dbus-daemon`): `jeepney` (also needs `pythonImportsCheck = []`), `secretstorage`, `keyring`
- **Crypto/SSH** (need agents or hardware): `paramiko` (also needs `dontCheckRuntimeDeps`), `cryptography`
- **Sandbox-incompatible test suites**: `twisted`, `ffmpeg-python`, `black`, `tornado`
- **AI/ML ecosystem** (network-dependent tests): `openai`, `anthropic`, `tiktoken`, `tokenizers`, `datasets`, `huggingface-hub`, `llm`, `fsspec`
- **Misc**: `elasticsearch`, `elastic-transport`, `inline-snapshot` (needs `dontCheckRuntimeDeps` for pytest)

**To add a new package**, edit `overlays/81-python-disable-checks.nix` and add to the
`pyOverrides` set:

```nix
# Simple case (flaky tests):
mypackage = noCheck pyPrev.mypackage;

# Runtime dep check failure:
mypackage = pyPrev.mypackage.overridePythonAttrs {
  doCheck = false;
  dontCheckRuntimeDeps = true;
};

# Import check failure:
mypackage = pyPrev.mypackage.overridePythonAttrs {
  doCheck = false;
  pythonImportsCheck = [ ];
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

## Detailed overlay-update recipes

Step-by-step version-bump procedures for every pinned overlay (prebuilt binaries, cargo
source builds, go source builds, python overrides) live in
[docs/overlay-update-routine.md](overlay-update-routine.md).
