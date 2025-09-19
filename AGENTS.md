# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` defines inputs, overlays, and exposes `devShells`, `packages`, and system apps.
- `hosts/darwin` and `hosts/nixos` hold host-level modules; keep host-specific secrets out of git.
- `modules/` is split into `shared`, `darwin`, and `nixos` directories; prefer extending shared modules before diverging per platform.
- `apps/<system>/` contains shell wrappers invoked via `nix run .#<system>.<command>`; update both Darwin and Linux variants when adding a workflow.
- `overlays/` provides package customizations such as `30-ccusage.nix`; changes here affect every system build.

## Build, Test & Development Commands
- `nix develop` (in repo root) spawns the mkShell with git, bash, and shared env defaults.
- `nix flake check` validates module evaluation across supported architectures; run before opening a PR.
- `nix run .#aarch64-darwin.build-switch` (or matching system attribute) builds and activates the macOS configuration.
- `nix run .#x86_64-linux.build-switch -- --dry-run` safely simulates a NixOS switch; drop the flag when ready to apply.
- `nix build .#packages.$SYSTEM.ccusage` produces the custom package output for spot checks.

## Coding Style & Naming Conventions
- Format Nix files with `nix fmt` (uses the repository’s pinned formatter); commits should never contain mixed indentation.
- Use two-space indentation and align attribute sets; keep inputs and module lists alphabetized when practical.
- Attribute names and filenames follow kebab-case (e.g., `create-keys.nix`); host directories mirror architecture strings.

## Testing Guidelines
- Extend tests in `flakes check` by adding `nixosTests` modules when new services are introduced.
- When modifying activation scripts, run the relevant `nix run .#<system>.apply` to exercise them without switching.
- Capture configuration diffs with `nix store diff-closures $(nix path-info ...)` when debugging large rebuilds.

## Commit & Pull Request Guidelines
- Existing commits use a concise, imperative subject (e.g., `modules: enable ghostty profile`) followed by optional detail in the body; mirror that voice.
- Reference related issues with `Refs: #123` in the message body and link them again in the PR description.
- PRs should describe platform impact, affected hosts, and manual verification steps (commands run, screenshots for UI tweaks).
- Draft PRs until `nix flake check` and the relevant `nix run` invocations succeed; include logs for failures when seeking review.

## Version Control State
- Repository initialized locally with `git init`; current branch is `main`.
- No remotes configured yet—keep work local unless the user specifies otherwise.
