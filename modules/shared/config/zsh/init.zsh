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

# ssh for warp. Hosts whose terminfo lacks tmux-256color / xterm-ghostty (the Synology
# NAS, blacklodge) get TERM=xterm-256color so interactive sessions render correctly.
ssh() {
  local host
  host=$(command ssh -G "$@" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')
  case $host in
    blacklodge) TERM=xterm-256color command ssh "$@" ;;
    *) command ssh "$@" ;;
  esac
}

# Root shell on blacklodge; the ssh() wrapper above handles the local TERM hop. DSM has no
# zsh, so a small bash rcfile (red root prompt, colors, aliases) is shipped inline as base64
# and read through process substitution — nothing is written to the NAS.
nasroot() {
  local rc b64
  rc=$(cat <<'EOF'
export PATH="$PATH:/usr/syno/sbin:/usr/syno/bin"
PS1='\[\e[1;31m\]root\[\e[0m\]@\[\e[1;35m\]blacklodge\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] \[\e[1;31m\]#\[\e[0m\] '
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'
HISTCONTROL=ignoreboth
HISTSIZE=10000
shopt -s checkwinsize histappend
EOF
)
  b64=$(printf '%s\n' "$rc" | base64 | tr -d '\n')
  ssh -t blacklodge "sudo TERM=xterm-256color /bin/bash -c 'exec /bin/bash --noprofile --rcfile <(echo $b64 | base64 -d) -i'"
}

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

# Typesafe API key, decrypted at activation by agenix
if [[ -r /run/agenix/typesafe-api-key ]]; then
  export TYPESAFE_API_KEY="$(< /run/agenix/typesafe-api-key)"
fi

# Activate mise for interactive shells
if [[ -o interactive ]] && command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# Auto-attach to a shared tmux session for every new interactive shell.
# Skip when already inside tmux, inside Emacs' shell, or in a non-interactive
# context (e.g. scp, rsync, CI) so this never breaks non-terminal use.
if [[ -o interactive ]] && [[ -z "$TMUX" ]] && [[ -z "$INSIDE_EMACS" ]] && command -v tmux &>/dev/null; then
  # If no tmux server is running yet (e.g. right after a reboot/login), this
  # is about to start one, which triggers tmux-continuum's restore hook in
  # the background (it sleeps 1s, then replays the last saved session via
  # tmux-resurrect). Give that a head start before falling back to creating
  # a brand-new "main" session, or the fallback wins the race and leaves you
  # with an empty session instead of your restored one.
  #
  # After a login several terminal windows can reopen at once. continuum
  # skips its restore when it sees more than one other tmux process, so
  # exactly one shell (the mkdir-lock winner) starts the server and, if
  # continuum didn't restore, runs resurrect's restore itself; the rest wait.
  if ! tmux info &>/dev/null; then
    _tmux_lock="${TMPDIR:-/tmp}/tmux-startup.lock"
    # Drop a stale lock left by a crash/reboot (older than a minute).
    [[ -d $_tmux_lock && -n $(find "$_tmux_lock" -maxdepth 0 -mmin +1 2>/dev/null) ]] && rmdir "$_tmux_lock" 2>/dev/null
    if mkdir "$_tmux_lock" 2>/dev/null; then
      tmux start-server
      sleep 2
      if ! tmux has-session -t main 2>/dev/null && [[ -e ~/.cache/tmux/resurrect/last ]]; then
        _tmux_restore="$(tmux show -gv @resurrect-restore-script-path 2>/dev/null)"
        [[ -x $_tmux_restore ]] && "$_tmux_restore" &>/dev/null
        sleep 1
      fi
      rmdir "$_tmux_lock" 2>/dev/null
    else
      for _ in {1..20}; do
        [[ -d $_tmux_lock ]] || break
        sleep 0.5
      done
    fi
    unset _tmux_lock _tmux_restore
  fi
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
