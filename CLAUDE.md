# NixOS Configuration

A unified configuration for macOS (Darwin) and NixOS systems using Nix Flakes and Home Manager.

## Repository Guidelines

### Project Structure & Module Organization

- `flake.nix` defines inputs, overlays, and exposes `devShells`, `packages`, and system apps.
- `hosts/darwin` and `hosts/nixos` hold host-level modules; keep host-specific secrets out of git.
- `modules/` is split into `shared`, `darwin`, and `nixos` directories; prefer extending shared modules before diverging per platform.
- `apps/<system>/` contains shell wrappers invoked via `nix run .#<system>.<command>`; update both Darwin and Linux variants when adding a workflow.
- `overlays/` provides package customizations such as `30-ccusage.nix`; changes here affect every system build.

### Coding Style & Naming Conventions

- Format Nix files with `nix fmt` (uses the repository's pinned formatter); commits should never contain mixed indentation.
- Use two-space indentation and align attribute sets; keep inputs and module lists alphabetized when practical.
- Attribute names and filenames follow kebab-case (e.g., `create-keys.nix`); host directories mirror architecture strings.

### Testing Guidelines

- Extend tests in `flakes check` by adding `nixosTests` modules when new services are introduced.
- When modifying activation scripts, run the relevant `nix run .#<system>.apply` to exercise them without switching.
- Capture configuration diffs with `nix store diff-closures $(nix path-info ...)` when debugging large rebuilds.

### Commit & Pull Request Guidelines

- Existing commits use a concise, imperative subject (e.g., `modules: enable ghostty profile`) followed by optional detail in the body; mirror that voice.
- Reference related issues with `Refs: #123` in the message body and link them again in the PR description.
- PRs should describe platform impact, affected hosts, and manual verification steps (commands run, screenshots for UI tweaks).
- Draft PRs until `nix flake check` and the relevant `nix run` invocations succeed; include logs for failures when seeking review.

### Version Control State

- Repository initialized locally with `git init`; current branch is `main`.
- No remotes configured yet—keep work local unless the user specifies otherwise.

## Quick Start

### Build and Switch

```bash
nix run .#build-switch
```

### Other Commands

```bash
nix run .#apply      # Apply configuration changes
nix run .#rollback   # Rollback to previous generation (macOS)
nix run .#fix-hashes # Verify and patch stale hashes in prebuilt-binary overlays
nix run .#update     # Full update: flake update → fix-hashes → build-switch
```

### Update Workflow (IMPORTANT)

Prebuilt-binary overlays (codex-openai, claude-code, uv, trailbase, igir, ngrok) pin
`sha256` hashes that can become stale whenever a publisher re-uploads a release artifact.
**Always run `fix-hashes` after `nix flake update` and before `build-switch`.**

Preferred all-in-one command:
```bash
nix run .#update
```

Or step-by-step:
```bash
nix flake update
nix run .#fix-hashes   # downloads each artifact and patches any stale hashes in overlays/
nix run .#build-switch
```

If you see a `hash mismatch in fixed-output derivation` error during `build-switch`, run
`nix run .#fix-hashes` first — it will auto-patch the affected overlay(s).

## Architecture

This configuration uses a modular approach with shared components between macOS and NixOS:

```nixos-config/
├── flake.nix              # Main flake configuration
├── hosts/                 # Host-specific configurations
│   ├── darwin/            # macOS system configuration
│   └── nixos/             # NixOS system configuration
├── modules/               # Modular configurations
│   ├── shared/            # Cross-platform modules
│   ├── darwin/            # macOS-specific modules
│   └── nixos/             # NixOS-specific modules
├── overlays/              # Package overlays and customizations
└── apps/                  # Build and deployment scripts
```

## Key Features

### Cross-Platform Package Management

- **Shared packages**: Common development tools, CLI utilities, media tools
- **Platform-specific packages**: macOS homebrew casks, NixOS packages
- **AI/ML tools**: llama-cpp, claude-code, koboldcpp

### Development Environment

- **Languages**: Python 3.12, Node.js 24, Rust, Go, Odin
- **Editors**: Emacs (with daemon), VS Code, Cursor, Devin (formerly Windsurf)
- **Terminals**: Alacritty, Warp, Ghostty
- **Version control**: Git with advanced tools

### System Services (macOS)

- **Emacs daemon**: Auto-starting Emacs server
- **Llama server**: (Commented out) Local language model server

### Package Categories

#### Development Tools

- `gcc`, `cmake`, `rustup`, `nodejs_24`, `python312`
- `gh` (GitHub CLI), `docker`, `docker-compose`
- Code editors and IDEs via homebrew casks

#### CLI Utilities

- `bat`, `eza`, `ripgrep`, `fd`, `jq`, `tmux`
- `btop`, `htop`, `glances` for system monitoring
- `autojump`, `direnv`, `nix-direnv`

#### Media & Entertainment

- `ffmpeg_7`, `imagemagick`, `mpv`, `iina`
- `yt-dlp`, `mediainfo`, `spotify`
- Font packages: `hack-font`, `jetbrains-mono`, `meslo-lgs-nf`

#### AI & Machine Learning

- `llama-cpp` - CPU-optimized LLM inference
- `claude-code` - Claude Code CLI (native binary via overlay)
- `koboldcpp` - Alternative LLM backend
- `ccusage` - Claude Code usage analytics

## Configuration Management

### Flake Structure

- **Multi-architecture support**: `aarch64-darwin`, `x86_64-darwin`, `aarch64-linux`, `x86_64-linux`
- **Home Manager integration**: User-space configuration management
- **Homebrew integration**: macOS package management via nix-homebrew

### Build Scripts

Located in `apps/`, these provide convenient commands:

- `build-switch`: Build and activate new system generation
- `build`: Build without switching
- `apply`: Apply configuration changes
- `rollback`: Revert to previous generation

### Overlays

Custom package definitions and patches in `overlays/`:

- `10-feather-font.nix`: Custom feather font (fixed version, no bumps)
- `20-ngrok.nix`: ngrok prebuilt binaries (stable CDN URLs at `bin.equinox.io`)
- `25-uv.nix`: uv prebuilt binary (aarch64-darwin only; nixpkgs elsewhere)
- `30-mise.nix`: mise prebuilt binaries (multi-platform; was source-built via `fetchCargoVendor` until crates.io began 403ing the default `python-requests` User-Agent)
- `40-codex-openai.nix`: codex-openai prebuilt binary
- `41-claude-code.nix`: claude-code prebuilt binary
- `50-trailbase.nix`: trailbase prebuilt binaries (multi-platform)
- `55-go.nix`: Go version override (bumped to 1.26.x, ahead of nixpkgs)
- `56-c4.nix`: c4 from git commit (no tagged releases)
- `60-beads.nix`: beads from source (Go, uses `buildGoModule`)
- `70-igir.nix`: igir prebuilt binaries (multi-platform)
- `80-llm.nix`: Disables checks for python312 llm
- `81-python313-disable-checks.nix`: **Consolidated** doCheck overrides for flaky Python 3.13 packages (see Troubleshooting)
- `82-python313-httpcore.nix`: Neutralized (now handled by `81-*`)
- `82-fmt.nix`: Disables checks for fmt
- `83-deno.nix`: Disables checks for deno
- `90-svg-term-cli.nix`: svg-term-cli from npm

Overlays are **auto-loaded** from `overlays/` by `modules/shared/default.nix` (glob scan for `*.nix` files). No need to register them in `flake.nix`.

### System Defaults (macOS)

- Fast key repeat and short initial delay
- Dock customization (no recents, bottom orientation)
- Trackpad tap-to-click and three-finger drag
- Show all file extensions in Finder

## Running from Anywhere: build-switch

To run your rebuild from anywhere on your system (outside the flake directory), we made three changes:

1. **Flake registry entry**

   - Added a named registry entry pointing to this repo
   - Command: nix registry add nixos-config path:/Users/briangyss/nixos-config
   - Why: Lets you refer to this flake by name from any directory, e.g. nix run nixos-config#build-switch

1. **Darwin app calls darwin-rebuild directly**

   - The flake app build-switch now executes the darwin-rebuild binary from the nix-darwin input and targets this flake path
   - It no longer depends on the current working directory
   - It invokes: `darwin-rebuild switch --flake <this flake>`

1. **Activation requires root**

   - Recent nix-darwin requires activation as root; the app runs via sudo
   - You will be prompted for your password when switching generations

How to use it

- From anywhere: nix run nixos-config#build-switch
- Pass extra flags after a --: nix run nixos-config#build-switch -- --show-trace

Notes

- The host attribute is defined as darwinConfigurations.garmonbozia. If your hostname changes, you can target it explicitly with:
  sudo darwin-rebuild switch --flake nixos-config#garmonbozia

## Setup from scratch (macOS)

These steps bootstrap a fresh macOS machine to use this flake.

1. **Install Nix** (recommended: Determinate Nix Installer)

   - Determinate (recommended):
     `curl -L https://install.determinate.systems/nix | sh -s -- install`
   - Or official multi-user installer:
     `sh <(curl -L https://nixos.org/nix/install) --daemon`
   - After install, open a new terminal to ensure nix is on PATH.

1. **Add a flake registry entry** for this repo (so you can run from anywhere)

   - nix registry add nixos-config path:/Users/briangyss/nixos-config
   - Verify: nix registry list | grep '^user\s\+flake:nixos-config'

1. **First build and switch** (will prompt for sudo due to nix-darwin activation)

   - nix run nixos-config#build-switch
   - This will: build the system, apply nix-darwin modules, set up Home Manager, and install Homebrew casks via nix-homebrew.

1. **Optional:** run again to ensure idempotence

   - nix run nixos-config#build-switch

Notes

- If you move the repo, update the registry: nix registry add nixos-config path:/new/path
- To target the host explicitly (if hostname differs):
  sudo $(nix build --no-link --print-out-paths nixos-config#darwinPackages.aarch64-darwin.darwin-rebuild)/bin/darwin-rebuild switch --flake nixos-config#garmonbozia
- On very new macOS versions, Homebrew may warn about “Tier 2” support; that’s informational.

## Troubleshooting

### Package Conflicts

If you encounter package collision errors (like the whisper-cpp/llama-cpp issue), check for duplicate packages providing the same files. Remove conflicting packages from `modules/shared/packages.nix`.

### Package Version Issues

If a package isn't getting the expected version from nixpkgs-unstable, check the overlay configuration in `flake.nix`. Packages explicitly inherited from `nixpkgs-master` overlay (lines 159-169) will use the master branch version instead of the unstable version.

### Build Failures

- Check that all required inputs are available
- Verify flake.lock is up to date: `nix flake update`
- Review error logs: `nix log /nix/store/[derivation-hash]`

### Python 3.13 Test Failures in Nix Sandbox

After `nix flake update`, Python 3.13 packages frequently fail to build because their test suites are incompatible with the Nix build sandbox (no network, no dbus, no real timers). The fix is **not** to pin nixpkgs — instead, disable checks for the offending package.

**How it works**: `overlays/81-python313-disable-checks.nix` uses `python313.override { packageOverrides = ...; }` to propagate `doCheck = false` through the interpreter's own scope. This is critical — `overrideScope` alone does NOT propagate to `python313.withPackages` consumers.

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

**To add a new package**, edit `overlays/81-python313-disable-checks.nix` and add to the `pyOverrides` set:

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

### Upstream Hash Mismatches

When a prebuilt binary is re-published under the same version (e.g., `uv`), the build fails with `hash mismatch in fixed-output derivation`. The error message provides the correct hash on the `got:` line — just update the `sha256` attribute in the relevant file (overlay or `modules/shared/packages.nix`).

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

**Proactive check after `nix flake update`**: if the bump commit message says a prebuilt-binary overlay was bumped (e.g., `overlays: bump uv to X.Y.Z`), verify the hash in that overlay matches the newly released artifact before running build-switch. You can prefetch to confirm:
```bash
nix-prefetch-url --unpack https://github.com/astral-sh/uv/releases/download/X.Y.Z/uv-aarch64-apple-darwin.tar.gz
# then: nix hash convert --hash-algo sha256 --to sri <printed hash>
```

### Upstream Download Failures (HTTP 429 / 404)

When upstream servers rate-limit or remove downloads (e.g., Spotify), temporarily comment out the package in `modules/shared/packages.nix` if it's also available via Homebrew cask on macOS. Re-enable later when the download stabilizes.

### macOS Specific

- Ensure nix-darwin is properly installed
- Check that the user is in the trusted-users list
- Verify Homebrew integration is working

## Customization

### Adding Packages

- **Cross-platform**: Add to `modules/shared/packages.nix`
- **macOS only**: Add to `modules/darwin/packages.nix` or `modules/darwin/casks.nix`
- **NixOS only**: Add to `modules/nixos/packages.nix`

### Updating Package Overlays

When updating package versions in overlays:

1. Fetch the new tarball hash: `nix-prefetch-url --unpack https://github.com/owner/repo/archive/refs/tags/VERSION.tar.gz`
2. Convert to SRI format: `nix hash convert --hash-algo sha256 --to sri HASH`
   - **Always use `nix hash convert`** — the old `nix hash to-sri` subcommand is deprecated
3. Update the version and hash in the overlay file
4. **Rust/Cargo packages** (source-built via `fetchCargoVendor`): set `cargoHash = "";`, run a build to get the expected hash from the error output, then replace it with the printed `sha256-...` value. Note: crates.io now returns HTTP 403 for the default `python-requests` User-Agent used by nixpkgs' `fetch-cargo-vendor-util`, so source-building Rust crates may fail at the vendor step — prefer a prebuilt-binary overlay when the publisher ships one (this is why `30-mise.nix` was converted).
5. **Go packages** (e.g., `60-beads.nix`): set `vendorHash = "";`, same process as Rust — build, grab hash from error, replace
6. **Prebuilt binary overlays** (e.g., `20-ngrok.nix`, `30-mise.nix`, `41-claude-code.nix`, `50-trailbase.nix`, `70-igir.nix`): prefetch each platform's URL individually with `nix-prefetch-url` (raw file hash, **not** `--unpack`, since they use `fetchurl`) and convert to SRI
7. Test individual overlays without a full rebuild: `nix build --impure --expr 'let pkgs = import <nixpkgs> { overlays = [ (import ./overlays/FOO.nix) ]; }; in pkgs.PACKAGE'`
8. Apply with `nix run .#build-switch`

### Configuration Files

- Static files: Add to appropriate `files.nix`
- Home Manager configs: Edit `home-manager.nix` files
- System-level: Modify host-specific `default.nix`

### Services

Add launchd services (macOS) or systemd services (NixOS) in the respective host configurations.

## Security Notes

- GPG and age encryption tools included
- YubiKey support via `age-plugin-yubikey` and `libfido2`
- Trusted public keys configured for binary caches
- Regular garbage collection configured (weekly, 30-day retention)

## Known Workarounds

### Claude Code Native Binary

The `claude-code` package in `overlays/41-claude-code.nix` is a native binary that self-identifies as a "native" install. It requires:

1. `~/.local/bin` in PATH (configured in `modules/shared/home-manager.nix`)
2. A symlink at `~/.local/bin/claude` pointing to the Nix binary: `ln -sf $(which claude) ~/.local/bin/claude`

Without these, the binary emits warnings about missing native installation or PATH issues.

## Memories

- Always use "nix run .#build-switch" to rebuild the nix config
- After `nix flake update`, always run `nix run .#fix-hashes` before `build-switch` to pre-emptively patch stale sha256 hashes in prebuilt-binary overlays. Use `nix run .#update` to do all three steps in one command.
- When a `hash mismatch in fixed-output derivation` error occurs during build-switch, run `nix run .#fix-hashes` — it auto-patches the affected overlay file(s) in place.
