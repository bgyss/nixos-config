# Nix configuration survey & optimization recommendations

**Date:** 2026-07-21
**Scope:** `~/nixos-config` (this daily-driver working copy) benchmarked against current
public Nix flake / nix-darwin / home-manager practice.

This is a point-in-time survey. It records what the configuration does well, where it
diverges from current community conventions, and a prioritized set of optimizations —
with a bias toward making the configuration legible to and safely operable by agents.

---

## 1. What this configuration is

A dustinlyons-lineage unified flake for macOS (`nix-darwin`) and NixOS + Home Manager.
It drives one live host (`garmonbozia`, `aarch64-darwin`) and keeps a NixOS path warm.
~3,600 lines of Nix across `flake.nix`, `hosts/`, `modules/{shared,darwin,nixos}/`, and
26 overlays. Notable local additions over the upstream template:

- **`overlays/updates.json`** — a machine-readable manifest of every pinned prebuilt /
  source overlay with its upstream check method (GitHub release, PyPI, go.dev, commit, …).
- **`scripts/check-overlay-versions.sh`** — queries upstream, prints current-vs-latest,
  non-zero exit if anything is stale.
- **`apps/*/fix-hashes`** — re-derives stale `sha256` for prebuilt-binary overlays after a
  flake bump, editing the overlay files in place.
- **`apps/*/update`** — one command: `flake update` → `fix-hashes` → commit → `build-switch`.
- **agenix** secrets pulled from a *separate private* `bgyss/nix-secrets` flake input, so a
  fresh machine bootstraps without re-encrypting.
- **Determinate Nix** in charge of the daemon (`nix.enable = false` in nix-darwin).

## 2. Architecture at a glance

```
flake.nix                 inputs, overlay-less outputs, mkApp wrappers, darwin/nixos configs
hosts/darwin|nixos        per-host system config (garmonbozia is the only real host)
modules/shared            cross-platform HM (zsh/git/tmux/vim/alacritty/ghostty/ssh) + nixpkgs cfg
modules/darwin            nix-darwin system defaults, homebrew, AeroSpace, dock, packages
modules/nixos             NixOS system + polybar/rofi/sway-era desktop config
overlays/*.nix            auto-loaded by modules/shared/default.nix (glob), numeric-prefixed
apps/<system>/*           imperative bash entrypoints behind `nix run .#<name>`
```

Overlays are auto-discovered (`readDir` glob in `modules/shared/default.nix`) — a genuinely
nice property: dropping a file in `overlays/` registers it, no wiring in `flake.nix`.

## 3. What this config does better than most public configs

1. **The `updates.json` + `check-overlay-versions.sh` + `fix-hashes` triad.** Most public
   configs carry stale prebuilt-binary overlays with hand-copied hashes and no drift
   detection. Having a *declarative manifest of every out-of-tree pin plus a machine that
   checks and repairs it* is ahead of the curve and is the single most agent-friendly asset
   in the repo. Keep and extend it (see §5).
2. **`nix run .#update` as a single reconciling command.** Update → fix-hashes → commit →
   switch, working-directory-independent (resolved via `nix registry` then git). This is the
   right shape for unattended/agentic operation.
3. **Secrets split into a separate private flake input.** Cleaner than in-repo `.age` blobs;
   the raw-`ssh-ed25519`-recipient gotcha is documented in CLAUDE.md/troubleshooting.
4. **Determinate Nix ownership is explicit** (`nix.enable = false`, `nix.conf` disabled),
   avoiding the common nix-darwin-vs-Determinate daemon fight.
5. **Honest, dated inline comments** explaining *why* pins exist (libxml2 CVE OOM,
   home-manager services-modular break, homebrew `upgrade=false` after repeated activation
   aborts). This institutional memory is worth more than it looks.

## 4. Findings vs. current best practice (prioritized)

### High value

- **F1 — No `nix flake check` / `checks` outputs / CI gate.** There is no automated
  verification that the flake even evaluates or that the darwin config builds. For a config
  meant to be operated by agents this is the biggest gap: agents need a *fast, deterministic
  pass/fail* before `build-switch`. Add `checks.<system>` (at minimum a `darwin-build` that
  builds `darwinConfigurations.garmonbozia.system`, plus `treefmt`/`statix`/`deadnix`) and a
  GitHub Actions workflow that runs `nix flake check` on the public mirror.

- **F2 — Formatting/linting not enforced.** Inconsistent indentation is visible in
  `modules/shared/home-manager.nix` (trailing whitespace, mixed 2/4-space blocks). Adopt
  **`treefmt-nix`** with `nixfmt-rfc-style`, plus **`statix`** (anti-pattern lint) and
  **`deadnix`** (dead code). Wire them into `checks` so §F1 enforces them.

- **F3 — The pinned-input tech debt is accumulating silently.** Three inputs are frozen to
  escape upstream breakage:
  - `nixpkgs` → `af45a5c` (pre-libxml2-CVE-patch OOM),
  - `home-manager` → `9ce9f7f` (pre-services-modular),
  - `darwin` → `nix-darwin-26.05` (to match the nixpkgs release).
  These are individually justified and dated, but there is no *tracked* trigger to unpin.
  Add each to `updates.json` with an `unpin_when` note and a check, or open tracking issues,
  so the freeze is a decision with an exit rather than drift. `nixpkgs-master` is *also*
  imported and evaluated inline in `modules/shared/default.nix` purely for `llama-cpp` and
  `aegisub` — a second full nixpkgs eval on every build. Prefer a narrowly-scoped
  `nixpkgs-master` follows-based input or a dedicated overlay input over importing master
  inside an overlay.

### Medium value

- **F4 — `flake.nix` output plumbing is hand-rolled where `flake-parts` would flatten it.**
  `forAllSystems`, `mkApp`, `mkDarwinApps`, `mkLinuxApps`, and the packages `extend` block
  are all bespoke. This is fine and readable, but **`flake-parts`** (or at least
  `flake-utils`) would remove the per-system boilerplate and give a conventional structure
  that other tools and agents recognize. Optional, but it pays off as host count grows.

- **F5 — `nixosConfigurations` is `genAttrs linuxSystems` with no real host.** It builds an
  identically-configured NixOS system keyed by *system string* rather than by *hostname*.
  When you actually stand up a NixOS box (or the adaptive-computer VM), switch to
  hostname-keyed configs (`nixosConfigurations.<hostname>`) with a `hosts/<name>/` dir and
  per-host hardware. Today's shape will collide the moment there are two NixOS machines.

- **F6 — `fix-hashes` / `apps` are duplicated per architecture and parse Nix with regex.**
  `apps/aarch64-darwin/fix-hashes` embeds a Python regex extractor for `url`/`hash` pairs.
  It works, but it is brittle (assumes one `version`, positional `zip`), and the `apps/`
  scripts are copy-pasted across `aarch64-darwin` / `x86_64-darwin`. Consider consolidating
  the app logic into a single `pkgs.writeShellApplication` derivation shared across systems,
  and consider **`nvfetcher`** or **`nix-update`** for the hash-bumping — both are the
  community-standard tools for exactly the "pinned out-of-tree source with an upstream check"
  problem `updates.json` solves by hand. `updates.json` is a *better manifest* than either
  ships with; the ideal is your manifest driving a standard fetcher rather than a bespoke
  sed-in-place.

- **F7 — The zsh `initContent` is a 100-line heredoc.** PATH mangling, editor setup, the
  `nix-update-switch` function, tmux auto-attach, brew completions, and the agenix key export
  all live in one `mkBefore` string. It works but is untestable and hard for both humans and
  agents to modify surgically. Break it into `home.sessionVariables`, `programs.zsh.shellAliases`,
  `programs.zsh.initExtra` fragments, and standalone script files under `modules/shared/config/`.

- **F8 — agenix is fine; note the maintenance ergonomics.** agenix is a good choice. If
  rekeying across hosts becomes frequent, evaluate **`agenix-rekey`** (host-key-derived
  rekeying) or **`sops-nix`** (better multi-secret/one-file ergonomics, `nix-secrets`-in-repo
  patterns). Not urgent — current setup is sound and the private-input split is good.

### Low value / cleanup

- **F9 — Commented-out dead config** (llama-server launchd agent, `masApps`, `taps`) should
  either move to a documented "recipes" doc or be deleted; `deadnix` won't catch commented
  blocks. Small readability tax.
- **F10 — `allowBroken = true` and `allowUnsupportedSystem = true` globally** widen the blast
  radius of a bad bump (a broken package builds instead of failing fast). Consider scoping
  these to the specific packages that need them via `permittedInsecurePackages`-style
  allowlists rather than global flags.
- **F11 — `security.sudo` NOPASSWD for `darwin-rebuild`** is a deliberate ergonomics choice
  for unattended `build-switch`. It is also the single largest standing privilege in the
  config. Fine for a personal machine; flagged because it is exactly the boundary the
  adaptive-computer work wants to formalize (see the private integration plan).

## 5. Optimizing for an agent-operated future

The thesis behind this survey — that system configuration will increasingly be *run by
agents* — has concrete, near-term implications. The config already leans this way; these
sharpen it.

1. **Make `nix flake check` the contract.** An agent's safety depends on a cheap, total,
   deterministic gate. Everything an agent must not break should be expressed as a `checks`
   output: config evaluates, darwin system builds, formatters pass, `updates.json` parses and
   matches the overlays it references. "Green check = safe to attempt switch" is the invariant
   to build toward.

2. **Promote `updates.json` to the source of truth, not a side-manifest.** Today it *mirrors*
   the overlays and a script reconciles them. Invert it: generate/verify overlay pins *from*
   the manifest in `nix flake check`, so the manifest and the tree can never silently diverge.
   Add fields agents need: `unpin_when`, `risk`, `last_verified`, `rollback_hint`.

3. **Expose safe, read-only preview operations as first-class apps.** Add `nix run .#build`
   (already present on darwin) and a `nix run .#diff` / `nix run .#dry-activate` that show an
   agent exactly what a change *would* do (closure delta, services to restart) without
   activating. Agents should be able to *propose and preview* before they *switch*.

4. **Separate "propose" from "activate."** The current `update` app does flake-update →
   fix-hashes → commit → **switch** in one shot. For agentic operation, split the pipeline so
   the build+commit+evidence step is distinct from the privileged activation step, and the
   activation step consumes a *specific committed revision* rather than "whatever is in the
   working tree." This mirrors the adaptive-computer candidate/activation-ticket design and is
   good hygiene regardless.

5. **Keep the rollback story explicit and machine-invocable.** `nix run .#rollback` exists on
   darwin; document the exact generation semantics and make it idempotent, because it is the
   agent's undo button.

## 6. Suggested sequencing

| Step | Change | Effort | Payoff |
|---|---|---|---|
| 1 | Add `treefmt-nix` + `statix` + `deadnix`, format the tree | S | F2, F7 groundwork |
| 2 | Add `checks.<system>` (build darwin config + treefmt) + CI on public mirror | M | F1 (biggest) |
| 3 | Make `nix flake check` verify `updates.json` ↔ overlays consistency | M | §5.1, §5.2 |
| 4 | Split `update` into `prepare` (build+commit+evidence) vs `activate` | M | §5.4, F11 |
| 5 | Consolidate `apps/` into one shared `writeShellApplication`; evaluate `nix-update` | M | F6 |
| 6 | Hostname-key `nixosConfigurations`; add `hosts/<name>/` when a NixOS box lands | S | F5 |
| 7 | Add `unpin_when` tracking for the three frozen inputs | S | F3 |
| 8 | (Optional) migrate outputs to `flake-parts` | L | F4 |

Steps 1–4 are the high-leverage core; 5–8 are cleanup and scale prep.

---

## 7. Implementation status (2026-07-21)

The recommendations above were implemented in this pass. Summary:

| Finding | Status | Where |
|---|---|---|
| **F1** flake check / CI gate | Done | `checks.<system>` (treefmt, overlays-manifest, darwin-build) + `.github/workflows/check.yml` |
| **F2** formatting/linting | Done | `treefmt.nix` (nixfmt-rfc-style + statix + deadnix), `nix fmt`, tree formatted |
| **F3** frozen inputs / master eval | Done | `pinned_inputs` in `updates.json` (risk/last_verified/unpin_when/rollback_hint); single DRY master eval in `modules/shared/default.nix` |
| **F4** flake-parts | **Deferred (decision)** | Optional/L in this survey; current hand-rolled plumbing is "fine and readable" and host count is 1. Revisit when a second real host lands. |
| **F5** hostname-keyed nixos | Done | `nixosHosts` + `mkNixos` in `flake.nix`; hostname from the flake key |
| **F6** consolidate apps / nix-update | Partial (decision) | Shared `apps/aarch64-darwin/_common.sh` removes the copy-pasted locate-flake block. `nvfetcher`/`nix-update` **not** adopted: this survey notes `updates.json` is a *better* manifest than either ships with, so the bespoke manifest-driven flow is kept. |
| **F7** zsh initContent heredoc | Done | `programs.zsh.{sessionVariables,shellAliases}` + `modules/shared/config/zsh/init.zsh` |
| **F8** agenix ergonomics | **Kept (decision)** | Survey: "current setup is sound … not urgent." agenix + private `nix-secrets` input retained; `agenix-rekey`/`sops-nix` revisit only if cross-host rekeying becomes frequent. |
| **F9** dead commented config | Done | Moved to `docs/recipes.md`; pointers left in place |
| **F10** global allowBroken/unsupported | Done | Scoped to lmstudio + wkhtmltopdf via `overlays/05-permit-marked-packages.nix`; global flags now `false` (byte-identical system derivation) |
| **F11** sudo NOPASSWD for darwin-rebuild | **Kept (documented)** | Deliberate ergonomics choice for unattended `build-switch`/`activate`. It remains the single largest standing privilege; the `prepare`/`activate` split (below) narrows *when* it is exercised — only the `activate` step is privileged, and it consumes a specific committed revision. |
| **§5.1** flake check as contract | Done | see F1 |
| **§5.2** updates.json as source of truth | Done | `scripts/check-overlay-manifest.sh` fails the build on any manifest↔tree drift |
| **§5.3** read-only preview apps | Done | `nix run .#diff`, `nix run .#dry-activate` |
| **§5.4** separate propose/activate | Done | `nix run .#prepare` (build+commit, unprivileged) vs `nix run .#activate -- <rev>` (privileged, specific committed rev) |
| **§5.5** explicit machine-invocable rollback | Done | `nix run .#rollback` rewritten: non-interactive, idempotent, `[<gen>|--list]` |

New agent-facing commands: `nix fmt`, `nix flake check` (or the secret-free
subset `nix build .#checks.<system>.{treefmt,overlays-manifest}`), and
`nix run .#{diff,dry-activate,prepare,activate,rollback}`.

---

*Companion document (private working copy only): `docs/adaptive-computer-integration-plan.md`
maps these patterns onto the adaptive-computer system-side architecture.*
