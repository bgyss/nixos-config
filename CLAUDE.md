# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Building and Applying Configuration

**macOS (Darwin)**
- `nix run .#build` - Build configuration without applying
- `nix run .#build-switch` - Build and apply configuration changes
- `nix run .#apply` - Apply user info to configuration templates
- `nix run .#rollback` - Rollback to previous generation

**NixOS (Linux)**
- `nix run .#build-switch` - Build and apply configuration changes
- `nix run .#build-switch-emacs` - Build and apply with specific Emacs configuration
- `nix run .#install` - Install NixOS configuration
- `nix run .#install-with-secrets` - Install NixOS configuration with secrets

### Key Management (when using secrets)
- `nix run .#create-keys` - Generate SSH keys for secrets management
- `nix run .#copy-keys` - Copy SSH keys from USB drive
- `nix run .#check-keys` - Verify SSH keys are properly installed

### Development Workflow
1. Make changes to configuration files
2. Run `nix run .#build` to test build (macOS) or test locally
3. Run `nix run .#build-switch` to apply changes
4. Configuration changes take effect immediately

### Quick Package Testing
- `nix shell nixpkgs#<package-name>` - Temporarily install a package for testing

## Architecture Overview

### Directory Structure
- `flake.nix` - Main Nix flake configuration entry point
- `hosts/` - Host-specific configurations (darwin/ for macOS, nixos/ for Linux)
- `modules/` - Reusable configuration modules
  - `darwin/` - macOS-specific modules (packages, casks, dock, etc.)
  - `nixos/` - NixOS-specific modules (packages, systemd, etc.)
  - `shared/` - Cross-platform modules (packages, home-manager, emacs config)
- `apps/` - Platform-specific shell scripts for common operations
- `overlays/` - Nix package overlays (auto-loaded)
- `templates/` - Starter templates for new configurations

### Key Architectural Concepts

**Nix Flakes System**: This configuration uses Nix flakes for reproducible builds. The main entry point is `flake.nix` which defines:
- Input dependencies (nixpkgs, home-manager, nix-darwin, etc.)
- Darwin configurations for macOS
- NixOS configurations for Linux systems
- Apps for common development tasks

**Home Manager Integration**: User-level configuration is managed through Home Manager, providing consistent dotfiles and user packages across systems.

**Secrets Management**: Uses `agenix` for declarative secrets management with SSH key encryption.

**Multi-Platform Support**: Single configuration supports both macOS (via nix-darwin) and NixOS systems with shared modules.

**Overlay System**: Drop any `.nix` file in the `overlays/` directory and it automatically loads, useful for package patches or custom derivations.

### Configuration Flow
1. `flake.nix` defines system configurations
2. Host files in `hosts/` import appropriate modules
3. Modules in `modules/` provide specific functionality
4. Apps in `apps/` provide convenient commands for common tasks
5. Changes are applied via `build-switch` commands

### Package Management
- System packages: Defined in `modules/*/packages.nix` files
- User packages: Managed through Home Manager
- macOS apps: Uses nix-homebrew for Homebrew integration and cask management
- Overlays: Custom packages and patches in `overlays/` directory

### Emacs Configuration
Special emphasis on Emacs with:
- Bleeding-edge Emacs via community overlay
- Literate configuration in `modules/shared/config/emacs/config.org`
- Daemon mode for instant startup