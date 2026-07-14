# nixos-config

A unified configuration for macOS (Darwin) and NixOS systems using Nix Flakes and Home
Manager. This is my personal, actively-used config — the root of this repo is not a generic
template, it's my actual system. See [CLAUDE.md](./CLAUDE.md) for day-to-day usage, workflow,
and troubleshooting notes.

## Bootstrapping a new machine from this repo

The root of this repo is personalized (hardcoded username, hostname, git identity, and a
private `nix-secrets` repo reference). To start your **own** config derived from this one,
use the `starter` flake template instead of cloning the root directly — it's the same
structure with your personal details filled in.

1. **Install Nix** (recommended: [Determinate Nix Installer](https://install.determinate.systems/)):
   ```bash
   curl -L https://install.determinate.systems/nix | sh -s -- install
   ```
   Open a new terminal afterward so `nix` is on PATH.

2. **Scaffold a new config from the template:**
   ```bash
   mkdir -p nixos-config && cd nixos-config
   nix --extra-experimental-features 'nix-command flakes' flake init -t github:bgyss/nixos-config#starter
   ```

3. **Create a private GitHub repo for your secrets** (e.g. `nix-secrets`), with at least a
   `README.md` so it's non-empty. See [secrets/README.md](./secrets/README.md) (also copied
   into the template) for what belongs in it — `secrets.nix` (recipient list) plus one `.age`
   file per secret, all encrypted with raw SSH public keys as recipients (**not**
   `ssh-to-age`-converted values — see this repo's `docs/troubleshooting.md` for why that
   distinction matters for `agenix`).

4. **Personalize the template** by running its `apply` app. It prompts for your username,
   git name/email, a hostname, and your GitHub secrets repo, then substitutes those into every
   file (`%USER%`, `%NAME%`, `%EMAIL%`, `%HOST%`, `%GITHUB_USER%`, `%GITHUB_SECRETS_REPO%`):
   ```bash
   nix run .#apply
   ```

5. **Lock and build:**
   ```bash
   nix flake lock
   nix run .#build-switch   # macOS, needs sudo for nix-darwin activation
   ```

Make the `apps/` scripts executable first if `nix flake init` didn't preserve the bit:
```bash
chmod +x apps/**/*
```

## Repo layout

```
flake.nix              # Flake inputs, outputs, overlay loading
hosts/darwin/           # macOS system configuration
hosts/nixos/            # NixOS system configuration
modules/shared/         # Cross-platform home-manager and system config
modules/darwin/         # macOS-specific modules
modules/nixos/          # NixOS-specific modules
overlays/               # Package overlays and customizations (auto-loaded)
apps/                   # nix run .#<cmd> entry points (build-switch, apply, rollback, ...)
secrets/                # Pointer to the separate, private nix-secrets repo (see above)
templates/starter/       # Genericized copy of this config for bootstrapping a new machine
docs/                   # Detailed troubleshooting, overlay-update recipes, setup notes
```

## License

BSD 3-Clause (see [LICENSE](./LICENSE)) — this config is structurally derived from
[dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config), which the license
carries forward.
