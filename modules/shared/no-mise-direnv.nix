# Guard: never enable mise's direnv integration.
#
# `programs.direnv.mise.enable` makes home-manager write
# ~/.config/direnv/lib/hm-mise.sh, which runs `mise direnv activate` in every
# direnv-enabled directory. That integration is deprecated: mise prints
#   mise WARN deprecated [cli.direnv]: `mise direnv` and the `use mise` direnv
#   integration are deprecated ... This will be removed in mise 2027.10.4.
# on every `cd`, and it will stop working entirely in mise 2027.10.4.
#
# The supported setup instead: mise is activated in zsh (`mise activate zsh`,
# modules/shared/config/zsh/init.zsh); project `.envrc` files contain only
# `use flake` (nix-direnv); project env vars go in `mise.toml` `[env]`.
#
# This was re-enabled once by accident (606b786d "direnv: enable mise
# integration"), so it is an assertion rather than a comment.
{ config, lib, ... }:
{
  assertions = [
    {
      assertion = !config.programs.direnv.mise.enable;
      message = ''
        programs.direnv.mise.enable must stay false: mise's direnv integration is
        deprecated (removed in mise 2027.10.4) and prints a warning in every
        direnv directory. mise is activated in zsh instead; keep project .envrc
        files to `use flake` and put env vars in mise.toml [env].
        See modules/shared/no-mise-direnv.nix.
      '';
    }
  ];
}
