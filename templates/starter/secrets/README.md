# secrets

This config doesn't keep encrypted secrets in-repo. Instead it pulls them from a separate
private repo, referenced as the `secrets` flake input (`flake = false`) in `flake.nix`:

```nix
secrets = {
  url = "git+ssh://git@github.com/%GITHUB_USER%/%GITHUB_SECRETS_REPO%.git";
  flake = false;
};
```

`nix run .#apply` fills in `%GITHUB_USER%`/`%GITHUB_SECRETS_REPO%` for you (see the repo root
README's setup steps).

Create that repo yourself (private, on GitHub) with at least:
- `secrets.nix` — recipient list: which age public keys can decrypt which `.age` file. Use the
  **raw SSH public key string** (`"ssh-ed25519 AAAA... you@example.com"`) as each recipient —
  not an `ssh-to-age`-converted value. `agenix` decrypts by calling
  `age --identity <ssh-key-file>` directly, and `age`'s own built-in ssh-key handling uses a
  *different* ed25519→X25519 conversion than the standalone `ssh-to-age` tool, so a recipient
  derived via `ssh-to-age` will silently never decrypt.
- One `.age` file per secret you want, encrypted directly with `age`:
  ```bash
  age -r "$(cat ~/.ssh/id_ed25519.pub)" -o <name>.age <plaintext-source-file>
  # verify it actually decrypts before committing/pushing:
  age -d -i ~/.ssh/id_ed25519 -o /dev/null <name>.age && echo OK
  ```

Wire each secret up in `hosts/darwin/default.nix` (or the equivalent NixOS host file) as
`age.secrets.<name> = { file = "${secrets}/<name>.age"; owner = user; mode = "0400"; };` —
add `path`/`symlink = true` if you want it deployed to a real filesystem path (e.g.
`~/.ssh/id_ed25519`) instead of read from `/run/agenix/<name>`.
