# Recipes

Optional configuration snippets that are intentionally *not* active, kept here
instead of as commented-out dead code in the `.nix` files (F9 in
`docs/config-survey-2026-07.md`). Copy a block into the referenced file to
enable it.

## llama-server launchd agent (macOS)

A persistent local [`llama-cpp`](https://github.com/ggml-org/llama.cpp)
`llama-server` running a coding model, wired as a user launchd agent. Add to
`hosts/darwin/default.nix` alongside the `emacs` agent:

```nix
launchd.user.agents.llama-server.serviceConfig = {
  KeepAlive = true;
  RunAtLoad = true;
  ProgramArguments = [
    "/bin/sh"
    "-c"
    "/bin/wait4path ${pkgs.llama-cpp}/bin/llama-server && exec ${pkgs.llama-cpp}/bin/llama-server -hf ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF --port 8012 -ngl 99 -fa -ub 1024 -b 1024 -dt 0.1 --ctx-size 0 --cache-reuse 256"
  ];
  StandardErrorPath = "/tmp/llama-server.err.log";
  StandardOutPath = "/tmp/llama-server.out.log";
  EnvironmentVariables = {
    PATH = config.environment.systemPath;
  };
};
```

## Homebrew taps (macOS)

Declare explicit taps in the `homebrew` block of
`modules/darwin/home-manager.nix` (taps are otherwise managed by `nix-homebrew`
in `flake.nix`):

```nix
taps = [
  "homebrew/cask"
  "homebrew/core"
  "dagger/tap"
];
```

## Mac App Store apps (`masApps`)

Install Mac App Store apps declaratively in the `homebrew` block of
`modules/darwin/home-manager.nix`. App IDs come from the
[`mas`](https://github.com/mas-cli/mas) CLI:

```console
$ nix shell nixpkgs#mas
$ mas search <app name>
```

```nix
masApps = {
  "1password" = 1333542190;
  "hidden-bar" = 1452453066;
  "wireguard" = 1451685025;
};
```

If an app was added to your Mac App Store profile but not installed on this
system, you may see *"Redownload Unavailable with This Apple ID"* — safe to
ignore ([dustinlyons/nixos-config#83](https://github.com/dustinlyons/nixos-config/issues/83)).

## zsh on the Synology NAS (`nasroot`) — future option

`nasroot` (in `modules/shared/config/zsh/init.zsh`) opens a root **bash** shell on
`blacklodge` with a styled prompt shipped inline as an rcfile. DSM has no zsh, no Entware
(`opkg`), and `/volume1` is ~100% full, so if real zsh (completion, globbing) is wanted later:

- **Static zsh binary in the NAS home dir (preferred).** Fetch a trustworthy static x86_64 zsh
  (reputable release + checksum, or build one), copy it to `~/` on the NAS, and have `nasroot`
  `exec` it via `sudo ... ~/zsh -f` with an inline rc (same trick as the bash rcfile). Doesn't
  touch DSM, survives DSM updates. A simplified prompt only — no p10k plugins/fonts.
- **Entware** (`opkg install zsh`): works but mounts `/opt` and runs boot scripts; DSM updates
  sometimes break it. Avoid on a NAS you rely on.

Also relevant: the NAS terminfo only has `xterm*`/`vt*` (hence the `TERM` override in the
`ssh()` wrapper), and its OpenSSH 8.2 lacks post-quantum KEX (`WarnWeakCrypto no` in the
`blacklodge` ssh block silences the warning).
