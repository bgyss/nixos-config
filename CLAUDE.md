# NixOS Configuration

A unified configuration for macOS (Darwin) and NixOS systems using Nix Flakes and Home
Manager. This is the repo actually driving system config on this machine.
`~/src/nixos-config` is the original template it was derived from — treat it as reference
only, not a source of ongoing changes.

For agent-specific guidance, see [AGENTS.md](./AGENTS.md) (currently just points back here).

## Quick Start

```bash
nix run .#build-switch   # Build and activate new system generation (requires sudo)
nix run .#apply          # Apply configuration changes without a full rebuild
nix run .#rollback       # Rollback to previous generation (macOS)
nix run .#update         # Full update: flake update → fix-hashes → build-switch
```

Can be run from anywhere via the `nixos-config` flake registry entry (see `nix registry list`)
— no need to `cd` into this repo first. Fresh-machine bootstrap steps and registry details are
in [docs/setup.md](docs/setup.md).

### Update Workflow (IMPORTANT)

Prebuilt-binary overlays (codex-openai, claude-code, uv, trailbase, igir, ngrok, tmux) pin
`sha256`/source hashes that can go stale whenever a publisher re-uploads a release artifact.
**Always run `fix-hashes` after `nix flake update` and before `build-switch`** — or just use
`nix run .#update`, which does all three steps. If you see a `hash mismatch in fixed-output
derivation` error during `build-switch`, run `nix run .#fix-hashes` first.

## Architecture

```
flake.nix              # Flake inputs, outputs, overlay loading
hosts/darwin/          # macOS system configuration
hosts/nixos/           # NixOS system configuration
modules/shared/        # Cross-platform home-manager and system config
modules/darwin/        # macOS-specific modules
modules/nixos/         # NixOS-specific modules
overlays/               # Package overlays and customizations (auto-loaded, see below)
apps/                  # nix run .#<cmd> entry points (build-switch, apply, rollback, update)
secrets/                # agenix-encrypted secrets (see Secrets Management below)
```

Prefer extending `modules/shared/` before diverging per platform.

## Overlays

Overlays are **auto-loaded** from `overlays/` by `modules/shared/default.nix` (glob scan for
`*.nix` files) — no need to register them in `flake.nix`. Pinned/notable ones:

- `20-ngrok.nix` / `25-uv.nix` / `30-mise.nix` / `40-codex-openai.nix` / `41-claude-code.nix` / `50-trailbase.nix` / `70-igir.nix` / `96-tmux.nix`: prebuilt binaries or pinned source builds with hashes that go stale (see `docs/troubleshooting.md`)
- `55-go.nix`: Go version override ahead of nixpkgs
- `56-c4.nix` / `60-beads.nix`: built from source (git commit / Go module)
- `80-llm.nix`, `81-python-disable-checks.nix`, `82-fmt.nix`, `83-deno.nix`, `84-nodejs-skip-flaky-tests.nix`: `doCheck = false` workarounds for packages whose tests don't survive the Nix sandbox
- `90-svg-term-cli.nix`: npm package with vendored lock file

Step-by-step version-bump recipes for every pinned overlay live in
[docs/overlay-update-routine.md](docs/overlay-update-routine.md).

## Customization

- **Add a package**: cross-platform → `modules/shared/packages.nix`; macOS only →
  `modules/darwin/packages.nix` or `casks.nix`; NixOS only → `modules/nixos/packages.nix`.
- **Add/update an overlay**: prefetch the new hash with `nix-prefetch-url` (`--unpack` for
  archives, plain for prebuilt binaries), convert with
  `nix hash convert --hash-algo sha256 --to sri` (the old `nix hash to-sri` is deprecated),
  update the overlay, then `nix run .#build-switch`. Cargo/Go source builds: blank
  `cargoHash`/`vendorHash`, run a build, copy the hash from the error. Full recipes in
  [docs/overlay-update-routine.md](docs/overlay-update-routine.md).
- **Static config files**: add to the relevant `files.nix`; Home Manager settings go in
  `home-manager.nix`; system-level settings in the host-specific `default.nix`.
- **Services**: add launchd services (macOS) or systemd services (NixOS) in the respective
  host configurations.

## Secrets Management

Secrets (API keys, tokens, etc.) are encrypted at rest with
[agenix](https://github.com/ryantm/agenix) and decrypted at system activation — **never
commit a plaintext secret to a `.nix` file**.

- `secrets/secrets.nix` — recipient list: which age public keys can decrypt which `.age`
  files (currently keyed to the `briangyss` user and `garmonbozia` host SSH keys).
  **Recipients must be the raw `ssh-ed25519 AAAA...` public key string, not an
  `ssh-to-age`-converted `age1...` value** — `ssh-to-age` uses a different ed25519→X25519
  conversion than `age`'s own built-in ssh handling, and agenix decrypts by calling
  `age --identity <ssh-key-file>` directly, so an `ssh-to-age`-derived recipient silently
  never decrypts. (This repo hit exactly that bug — see `docs/troubleshooting.md`.)
- `secrets/*.age` — encrypted secrets; safe to commit. Currently: `openai-api-key`,
  `ssh-key` (personal `~/.ssh/id_ed25519`), `aws-credentials` (`~/.aws/credentials`).
- `age.secrets.<name>` (declared per-host in `hosts/darwin/default.nix`) wires an encrypted
  file to `/run/agenix.d/<name>` (the "`/run/agenix`" path in older notes is a simplification
  — the real mountpoint has a `.d` suffix). Set `path`/`symlink = true` to also place the
  decrypted secret at a real filesystem path (e.g. `~/.ssh/id_ed25519`); otherwise consumers
  read `/run/agenix.d/<name>` directly, guarding with `[[ -r ... ]]`.

**Adding a new secret:**
```bash
cd secrets
# add "<name>.age".publicKeys = allKeys; to secrets.nix, then encrypt directly with age
# (recipients are raw ssh-ed25519 pubkey strings, so no ssh-to-age/agenix -e round-trip needed):
age -r "$(cat ~/.ssh/id_ed25519.pub)" -r "<host-ssh-pubkey-string>" -o <name>.age <plaintext-source-file>
```
Then wire `age.secrets.<name>` into the relevant host file, and `git add` the new `.age` file
before building — **untracked files are invisible to the flake evaluator**. Verify it actually
decrypts before relying on it: `age -d -i ~/.ssh/id_ed25519 -o /dev/null secrets/<name>.age`.

**Adding a new host as a recipient:** read its raw public key directly —
`ssh-keyscan` or `cat /etc/ssh/ssh_host_ed25519_key.pub` on that host — and add the
`"ssh-ed25519 AAAA..."` string (not an `ssh-to-age` conversion) to `allKeys` in
`secrets/secrets.nix`, then re-run the `age -r ... -o <name>.age` command above for each
existing secret to rekey it.

## Known Workarounds

**Claude Code native binary** (`overlays/41-claude-code.nix`): requires `~/.local/bin` in PATH
and a symlink `ln -sf $(which claude) ~/.local/bin/claude`, or it emits warnings about a
missing native install.

**Emacs org-config path**: `modules/shared/config/emacs/init.el`'s `org-config-file` must
point at this repo's actual clone path or it silently falls back to a stale upstream default
— see `docs/troubleshooting.md`.

For everything else — build failures, hash mismatches, Python sandbox test failures, stale
Dock icons, etc. — see [docs/troubleshooting.md](docs/troubleshooting.md).

## Memories

- Always commit any changes made to this configuration in Claude Code (commit each change,
  with a concise imperative subject, after making it).
- Always use `nix run .#build-switch` to rebuild the nix config.
- After `nix flake update`, always run `nix run .#fix-hashes` before `build-switch` (or just
  `nix run .#update`).
- On a `hash mismatch in fixed-output derivation` error, run `nix run .#fix-hashes`.
