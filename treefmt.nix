# treefmt configuration — drives `nix fmt`, the `formatter` output, and the
# `treefmt` flake check. Formats Nix with nixfmt-rfc-style and lints with
# statix (anti-patterns) and deadnix (dead code). See docs on F2 in
# docs/config-survey-2026-07.md.
_: {
  projectRootFile = "flake.nix";

  programs = {
    # nixfmt-rfc-style (the current `nixfmt`) is the canonical Nix formatter.
    nixfmt.enable = true;

    # Anti-pattern lint with autofix (e.g. `a: a.b` -> `.b`, inherit hoisting).
    statix.enable = true;

    # Dead-code removal. Conservative: only remove genuinely-dead let bindings,
    # never touch lambda args / pattern names (module signatures like
    # `{ config, pkgs, lib, ... }` and overlay `final: prev:` intentionally keep
    # their full arg list even when an arg is unused).
    deadnix = {
      enable = true;
      no-lambda-arg = true;
      no-lambda-pattern-names = true;
    };
  };

  settings.global.excludes = [
    "flake.lock"
    "*.json"
    "*.md"
    "*.lock"
    "LICENSE"
    ".gitignore"
    # Imperative bash entrypoints and shell config fragments are out of scope
    # for the Nix formatter; keep them as-is.
    "apps/**"
    "scripts/**"
    "modules/shared/config/**"
  ];
}
