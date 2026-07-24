# NixOS Configuration

A unified configuration for macOS (Darwin) and NixOS systems using Nix Flakes and Home
Manager. This checkout (`~/src/nixos-config`) is the copy pushed to
[github.com/bgyss/nixos-config](https://github.com/bgyss/nixos-config) (public). The daily
working copy actually driving system config on this machine is `~/nixos-config`, which has no
git remote. A **post-commit hook mirrors public-safe files from there into this checkout and
pushes automatically** — so package/cask/overlay/module changes reach GitHub on every commit
with no manual sync (see "Public Mirror Sync" below). See `templates/starter/` and the root
`README.md` for the flake-template flow used to bootstrap a *new* machine from this repo.

For agent-specific guidance, see [AGENTS.md](./AGENTS.md) (currently just points back here).

## Quick Start

```bash
nix run .#build-switch   # Build and activate new system generation (requires sudo)
nix run .#apply          # Apply configuration changes without a full rebuild
nix run .#rollback       # Rollback: `rollback [<gen>|--list]` (idempotent, macOS)
nix run .#update         # Full update: prepare (build+commit) then activate HEAD
nix run .#bump-overlays  # Mechanically bump the automated-subset overlays (see docs/overlay-bump-tutorial.md)

# Preview / propose / activate (agent-friendly; see "Update Workflow" below)
nix run .#check          # Read-only: preview what `prepare` would change (incremental gating)
nix run .#diff           # Read-only: build the config + show the closure delta
nix run .#dry-activate   # Read-only: what activation would do, without switching
nix run .#prepare        # Propose: flake update → fix-hashes → build → commit (no sudo)
nix run .#activate -- <rev>   # Activate a specific committed revision (privileged)

# Verification (run before committing / activating)
nix fmt                  # Format the tree (nixfmt-rfc-style + statix + deadnix)
nix flake check          # Gate: treefmt, overlays-manifest, darwin-build all green
```

Can be run from anywhere via the `nixos-config` flake registry entry (see `nix registry list`)
— no need to `cd` into this repo first. Fresh-machine bootstrap steps and registry details are
in [docs/setup.md](docs/setup.md).

### Update Workflow (IMPORTANT)

Prebuilt-binary overlays (codex-openai, claude-code, uv, trailbase, igir, ngrok, tmux) pin
`sha256`/source hashes that can go stale whenever a publisher re-uploads a release artifact.
**Always run `fix-hashes` after `nix flake update` and before `build-switch`** — or just use
`nix run .#update`, which does all the steps. If you see a `hash mismatch in fixed-output
derivation` error during `build-switch`, run `nix run .#fix-hashes` first.

**Propose vs. activate (agentic).** `update` is now `prepare` + `activate HEAD`. For unattended
/ agent operation, run the two halves separately: `nix run .#prepare` probes flake inputs
(respecting cadence/frozen pins), updates only the ones actually due → **build (evidence)** →
commit, and prints a closure diff and the proposed revision (outdated overlays are reported but
never auto-updated — see "Smart incremental updates" below); then `nix run .#activate -- <rev>`
does the single privileged switch, consuming that *specific committed revision* rather than the
working tree. Preview first with `nix run .#diff` / `nix run .#dry-activate` (both read-only, no
activation).

**Smart incremental updates (new).** `nix run .#check` is a read-only gate that previews what
`prepare` would actually change — it probes each flake input and overlay against upstream,
respecting per-input cadence and frozen `pinned_inputs[]`, caches the result in `.update-state.json`
(a gitignored, deletable file), and reports which packages have real new versions available.
`prepare` builds/commits only if a flake input actually moved (per its cadence) — overlay
version bumps are reported informationally only and are **never** auto-applied by `prepare`;
bumping a pinned overlay's version still requires the manual routine in
[docs/overlay-update-routine.md](docs/overlay-update-routine.md) (it has to rewrite the
overlay's pinned version/hash *and* `updates.json`'s `current_version` together — auto-doing
only the latter previously left the manifest permanently lying about what's pinned). Per-input
update cadence is configured in `overlays/updates.json` under `inputs.*` (e.g., `"nixpkgs":
{"cadence_hours": 168}`) — `pinned_inputs[]` entries are always frozen regardless of cadence. A
**daily launchd agent** (`nixos-update-check`) runs `scheduled-check`, which runs `prepare`
itself (propose only: build + commit, no privileged switch) and notifies you via macOS
notification of the proposed revision, but **never activates** — you review and run `nix run
.#activate -- <rev>` manually. If `prepare` can't acquire its lock (another run already in
progress) it exits 2 and `scheduled-check` stays silent rather than firing a failure
notification. This design separates read-only checks (cheap, safe to automate) from privileged
activation.

**Checks / formatting.** `nix flake check` is the pass/fail gate: `treefmt` (nixfmt-rfc-style +
statix + deadnix), `overlays-manifest` (`updates.json` ↔ overlays consistency, enforced by
`scripts/check-overlay-manifest.sh`), and `darwin-build`. Run `nix fmt` before committing any
`.nix` change. Public CI (`.github/workflows/check.yml`) runs the secret-free checks
(`treefmt`, `overlays-manifest`) on a Linux runner — the full `nix flake check` / `darwin-build`
needs the private `secrets` input and so runs locally or behind a deploy key. Every overlay must
appear in `overlays/updates.json` (as a `packages[]` pin or a `skip[]` entry) or the
`overlays-manifest` check fails.

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
[docs/overlay-update-routine.md](docs/overlay-update-routine.md). claude-code, codex-openai, uv, trailbase, igir, dcg, aws-cdk-cli, mise, go (patch bumps), beads, c4, and hey-cli can be bumped automatically with `nix run .#bump-overlays` — see [docs/overlay-bump-tutorial.md](docs/overlay-bump-tutorial.md); everything else still follows the manual routine.

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

The encrypted secrets and recipient list live in a **separate repo**,
[bgyss/nix-secrets](https://github.com/bgyss/nix-secrets), pulled in as the `secrets` flake
input (`flake = false` in `flake.nix`, `git+ssh://git@github.com/bgyss/nix-secrets.git`) —
this way a new machine can be bootstrapped without re-encrypting everything from scratch.
`secrets/README.md` in *this* repo just points there.

- `nix-secrets/secrets.nix` — recipient list: which age public keys can decrypt which `.age`
  file (currently keyed to the `briangyss` user and `garmonbozia` host SSH keys).
  **Recipients must be the raw `ssh-ed25519 AAAA...` public key string, not an
  `ssh-to-age`-converted `age1...` value** — `ssh-to-age` uses a different ed25519→X25519
  conversion than `age`'s own built-in ssh handling, and agenix decrypts by calling
  `age --identity <ssh-key-file>` directly, so an `ssh-to-age`-derived recipient silently
  never decrypts. (This repo hit exactly that bug — see `docs/troubleshooting.md`.)
- `nix-secrets/*.age` — encrypted secrets; safe to commit even though the repo is private.
  Currently: `openai-api-key`, `ssh-key` (personal `~/.ssh/id_ed25519`), `aws-credentials`
  (`~/.aws/credentials`).
- `age.secrets.<name>` (declared per-host in `hosts/darwin/default.nix`) references
  `"${secrets}/<name>.age"` and wires it to `/run/agenix/<name>` (a symlink into a versioned
  subdir of the root-only `/run/agenix.d/` mountpoint). Set `path`/`symlink = true` to also
  place the decrypted secret at a real filesystem path (e.g. `~/.ssh/id_ed25519`); otherwise
  consumers read `/run/agenix/<name>` directly, guarding with `[[ -r ... ]]`.

**Adding a new secret:** clone `nix-secrets`, then from inside it:
```bash
# add "<name>.age".publicKeys = allKeys; to secrets.nix, then encrypt directly with age
# (recipients are raw ssh-ed25519 pubkey strings, so no ssh-to-age/agenix -e round-trip needed):
age -r "$(cat ~/.ssh/id_ed25519.pub)" -r "<host-ssh-pubkey-string>" -o <name>.age <plaintext-source-file>
# verify it actually decrypts before pushing:
age -d -i ~/.ssh/id_ed25519 -o /dev/null <name>.age && echo OK
git add secrets.nix <name>.age && git commit && git push
```
Back in `nixos-config`: wire `age.secrets.<name>` to `"${secrets}/<name>.age"` in the relevant
host file, run `nix flake lock --update-input secrets` to pick up the new commit, and commit
the updated `flake.lock` alongside the host-config change. **Untracked `.nix` changes are
invisible to the flake evaluator**, so stage everything before building.

**Adding a new host as a recipient:** in the `nix-secrets` clone, get the new host's raw
public key (`cat /etc/ssh/ssh_host_ed25519_key.pub` on that host, or `ssh-keyscan`), add the
`"ssh-ed25519 AAAA..."` string (not an `ssh-to-age` conversion) to `allKeys` in `secrets.nix`,
then re-run the `age -r ... -o <name>.age` command above for every existing secret to rekey
it, and push.

## Known Workarounds

**Claude Code native binary** (`overlays/41-claude-code.nix`): requires `~/.local/bin` in PATH
and a symlink `ln -sf $(which claude) ~/.local/bin/claude`, or it emits warnings about a
missing native install.

**Emacs org-config path**: `modules/shared/config/emacs/init.el`'s `org-config-file` must
point at this repo's actual clone path or it silently falls back to a stale upstream default
— see `docs/troubleshooting.md`.

For everything else — build failures, hash mismatches, Python sandbox test failures, stale
Dock icons, etc. — see [docs/troubleshooting.md](docs/troubleshooting.md).

## Public Mirror Sync

A **post-commit hook** in the private daily-driver checkout (`~/nixos-config`) automatically
mirrors public-safe files into the public checkout (`~/src/nixos-config`) and pushes to GitHub
after every commit — so package, cask, overlay, and module changes go public with no manual
step. Wired via `git config core.hooksPath scripts/git-hooks` (set in the private repo only, so
the public repo receives the hook file but never runs it → no sync loop).

- **`scripts/sync-to-public.sh`** — the engine (also runnable by hand). Publishes every
  `git ls-files` path **minus** the denylist, then commits (mirroring the private commit's
  subject) and pushes. Anything tracked in public but not in the published set is `git rm`ed, so
  denylisted files can never linger and deletions propagate. A commit touching only private
  paths produces no public commit. Push failures (offline) warn but never block the commit.
- **`scripts/public-sync-denylist.txt`** — one path per line (trailing `/` = whole dir) of files
  that must stay private. It lists **itself**, so private filenames never reach the public repo.
  Add a line here *before* committing any new private note — the model is a denylist, so an
  unlisted new file auto-publishes (the hook prints `Publishing NEW files: …` as a safety net).

## Memories

- Always commit any changes made to this configuration in Claude Code (commit each change,
  with a concise imperative subject, after making it).
- Always use `nix run .#build-switch` to rebuild the nix config.
- After `nix flake update`, always run `nix run .#fix-hashes` before `build-switch` (or just
  `nix run .#update`).
- On a `hash mismatch in fixed-output derivation` error, run `nix run .#fix-hashes`.
- Run `nix fmt` before committing any `.nix` change, and keep `nix flake check` green
  (`treefmt` + `overlays-manifest` + `darwin-build`). Every overlay must be registered in
  `overlays/updates.json`.
- Optional/example config snippets live in `docs/recipes.md`, not as commented-out dead code.
- Commits in `~/nixos-config` auto-mirror + push to the public repo via a post-commit hook
  (see "Public Mirror Sync"). Before committing a **new private note**, add its path to
  `scripts/public-sync-denylist.txt` or it will be published to GitHub.
