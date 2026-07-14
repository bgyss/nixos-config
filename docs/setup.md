# Setup from Scratch (macOS)

Bootstrap a fresh macOS machine to use this flake.

1. **Install Nix** (recommended: Determinate Nix Installer)
   - `curl -L https://install.determinate.systems/nix | sh -s -- install`
   - Or official multi-user installer: `sh <(curl -L https://nixos.org/nix/install) --daemon`
   - Open a new terminal afterward to ensure `nix` is on PATH.

2. **Add a flake registry entry** so you can run `nix run nixos-config#<cmd>` from anywhere:
   ```bash
   nix registry add nixos-config path:/Users/briangyss/nixos-config
   nix registry list | grep '^user\s\+flake:nixos-config'
   ```

3. **First build and switch** (prompts for sudo — nix-darwin activation requires root):
   ```bash
   nix run nixos-config#build-switch
   ```
   This builds the system, applies nix-darwin modules, sets up Home Manager, and installs
   Homebrew casks via nix-homebrew.

4. **Optional:** run again to confirm idempotence.

## Running build-switch from anywhere

Three things make this work without `cd`-ing into the repo:

1. A flake registry entry (`nix registry add nixos-config path:/Users/briangyss/nixos-config`).
2. The `build-switch` app invokes `darwin-rebuild` directly against this flake path, so it
   doesn't depend on the working directory.
3. Activation runs via `sudo` (recent nix-darwin requires root).

```bash
nix run nixos-config#build-switch
nix run nixos-config#build-switch -- --show-trace   # pass extra flags after --
```

The host attribute is `darwinConfigurations.garmonbozia`. If the hostname changes, target it
explicitly:
```bash
sudo darwin-rebuild switch --flake nixos-config#garmonbozia
```

If you move the repo, update the registry entry:
```bash
nix registry add nixos-config path:/new/path
```

On very new macOS versions, Homebrew may warn about "Tier 2" support — that's informational.
