# secrets

Encrypted secrets used to live here directly; they've moved to a separate repo,
[bgyss/nix-secrets](https://github.com/bgyss/nix-secrets), pulled in as the `secrets` flake
input (`flake = false`, in `flake.nix`) so a new machine can be bootstrapped without
re-encrypting everything from scratch.

Host configs reference secrets as `"${secrets}/<name>.age"` (see `hosts/darwin/default.nix`).
To add or edit a secret, or add a new host as a recipient, see the `nix-secrets` repo's own
README. General agenix usage and the ssh-to-age pitfall are documented in this repo's
[CLAUDE.md](../CLAUDE.md) and [docs/troubleshooting.md](../docs/troubleshooting.md).
