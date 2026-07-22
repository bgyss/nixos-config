# Interactive zsh init (imperative fragment).
# Sourced early (mkBefore) from programs.zsh.initContent in
# modules/shared/home-manager.nix. Kept as a real .zsh file rather than a Nix
# heredoc so it is editable, testable and free of `''${...}` escaping (F7 in
# docs/config-survey-2026-07.md). Contains only logic that must run in the
# shell; static env vars live in programs.zsh.sessionVariables and aliases in
# programs.zsh.shellAliases.

if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
fi

# Homebrew (only for interactive shells)
if [[ -o interactive ]] && [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
fi

# Prepend user package/bin directories to PATH
export PATH=$HOME/.pnpm-packages/bin:$HOME/.pnpm-packages:$PATH
export PATH=$HOME/.npm-packages/bin:$HOME/bin:$PATH
export PATH=$HOME/.local/bin:$HOME/.local/share/bin:$PATH

# macOS: Set LIBRARY_PATH for Nix + Rust builds (ring crate needs libiconv)
if [[ "$(uname)" == "Darwin" ]]; then
  export LIBRARY_PATH="$(xcrun --show-sdk-path)/usr/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
fi

e() {
  emacsclient -t "$@"
}

# nix shortcuts
shell() {
  nix-shell '<nixpkgs>' -A "$1"
}

# Update flake lock then rebuild this host
nix-update-switch() {
  emulate -L zsh
  local repo_root=""
  local flake_ref="${NIXOS_CONFIG_FLAKE:-nixos-config}"
  if command -v git >/dev/null 2>&1; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return $?
      if [ -f "$repo_root/flake.nix" ]; then
        flake_ref="$repo_root"
      else
        repo_root=""
      fi
    fi
  fi

  if [ -n "${NIX_UPDATE_SWITCH_DEBUG:-}" ]; then
    set -x
  fi

  if [ -n "$repo_root" ]; then
    if ! git -C "$repo_root" diff --cached --quiet; then
      echo "Refusing to auto-commit flake.lock: you already have staged changes"
      return 1
    fi
    if [ -n "$(git -C "$repo_root" status --porcelain)" ]; then
      echo "Refusing to auto-commit flake.lock: git tree is dirty"
      return 1
    fi
  fi

  nix flake update --flake "$flake_ref" --commit-lock-file || return $?
  nix run "$flake_ref"#build-switch -- "$@"
}

# ssh for warp
ssh() { command ssh "$@"; }

# brew completions
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH

  autoload -Uz compinit
  compinit
fi

# OpenAI API key, decrypted at activation by agenix (see secrets/secrets.nix)
if [[ -r /run/agenix/openai-api-key ]]; then
  export OPENAI_API_KEY="$(< /run/agenix/openai-api-key)"
fi

# Activate mise for interactive shells
if [[ -o interactive ]] && command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# Auto-attach to a shared tmux session for every new interactive shell.
# Skip when already inside tmux, inside Emacs' shell, or in a non-interactive
# context (e.g. scp, rsync, CI) so this never breaks non-terminal use.
if [[ -o interactive ]] && [[ -z "$TMUX" ]] && [[ -z "$INSIDE_EMACS" ]] && command -v tmux &>/dev/null; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
