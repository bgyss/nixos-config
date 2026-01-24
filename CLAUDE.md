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
```

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
- **Editors**: Emacs (with daemon), VS Code, Cursor, Windsurf
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

- `30-ccusage.nix`: Custom ccusage package from npm registry
- `20-yt-dlp.nix`: yt-dlp customizations
- Package version overrides from nixpkgs-master

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

When updating package versions in overlays (e.g., `20-yt-dlp.nix`, `35-uv.nix`):

1. Fetch the new tarball hash: `nix-prefetch-url --unpack https://github.com/owner/repo/archive/refs/tags/VERSION.tar.gz`
2. Convert to SRI format: `nix hash convert --hash-algo sha256 --to sri HASH`
   - **Always use `nix hash convert`** — the old `nix hash to-sri` subcommand is deprecated
3. Update the version and hash in the overlay file
4. Apply with `nix run .#build-switch`

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
