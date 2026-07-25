---
name: nix-secrets
description: Use when adding a new agenix secret to this nixos-config, or adding a new host as a recipient of existing secrets. Covers encrypting with age, wiring age.secrets.<name>, updating the secrets flake input, and rekeying every .age file for a new machine.
---

# Adding / rekeying agenix secrets

Background (recipient format, `age.secrets.<name>` wiring, where the encrypted files live) is
in `CLAUDE.md`'s **Secrets Management** section. This skill is the step-by-step procedure.

**Never commit a plaintext secret to a `.nix` file.** Recipients must be the raw
`ssh-ed25519 AAAA...` public key string, not an `ssh-to-age`-converted `age1...` value.

## Adding a new secret

Clone [bgyss/nix-secrets](https://github.com/bgyss/nix-secrets), then from inside it:

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

## Adding a new host as a recipient

In the `nix-secrets` clone, get the new host's raw public key
(`cat /etc/ssh/ssh_host_ed25519_key.pub` on that host, or `ssh-keyscan`), add the
`"ssh-ed25519 AAAA..."` string (not an `ssh-to-age` conversion) to `allKeys` in `secrets.nix`,
then re-run the `age -r ... -o <name>.age` command above for every existing secret to rekey
it, and push.
