{ pkgs }:

let
  inherit (pkgs) stdenv;
  inherit (pkgs.lib) optionals;
in
with pkgs;
[
  # General packages for development and system management
  alacritty
  aspell
  aspellDicts.en
  autojump
  autossh
  bash
  bash-completion
  bat
  beads
  btop
  coreutils
  deno
  difftastic
  direnv
  dust
  eza
  gcc
  gh
  ghidra
  hcloud
  just
  jujutsu
  jjui
  killall
  ncdu
  fastfetch
  nix-prefetch-git # should this be installed by default
  nix-prefetch-github
  ngrok
  nix-direnv
  mise
  openssh
  pocketbase
  sqlite
  uv
  wget
  zip
  
  # buildroot stuff
  gnupatch
  findutils
  e2fsprogs
  flock

  # Emulation
  qemu
  dosbox-staging
  # mesen  # disabled: depends on dotnet which depends on Swift (build failure)
  scummvm

  # Encryption and security tools
  age
  age-plugin-yubikey
  gnupg
  libfido2
  semgrep

  # Cloud-related tools and SDKs
  kubectl
  rclone

  # Docker tools
  docker-client
  docker-compose
  docker-buildx
  docker-credential-helpers

  # Media-related packages
  aegisub
  emacs-all-the-icons-fonts
  dejavu_fonts
  ffmpeg-full
  fd
  font-awesome
  hack-font
  iina
  imagemagick
  noto-fonts
  noto-fonts-color-emoji
  meslo-lgs-nf

  # Node.js development tools
  nodejs_24

  # development tools
  clang-tools
  cmake
  devenv
  nixd
  ruff
  rustup
  verilator
  iverilog

  # golang
  c4
  go
  gox

  # odln
  odin

  # OCR
  tesseract

  # Text and terminal utilities
  pandoc
  tectonic
  typst
  zsh
  htop
  hunspell
  iftop
  jetbrains-mono
  jq
  ripgrep
  tree
  tmux
  unrar
  unzip
  zsh-powerlevel10k
  pv
  glances

  # Media players
  # mpv  # disabled: depends on Swift which fails to build on aarch64-darwin
  # spotify  # disabled: upstream download rate-limited (429), re-enable later

  # Media tools
  yt-dlp
  gallery-dl
  mediainfo
  asciinema
  asciinema-agg

  # Python packages
  python313
  python313Packages.huggingface-hub # huggingface cli
  python313Packages.llm             # llm cli util from datasette
  python313Packages.anthropic       # anthropic
  python313Packages.openai          # openai cli
  python313Packages.virtualenv      # globally install virtualenv
  python313Packages.git-filter-repo # git filter repo
  python313Packages.tiktoken        # tiktoken
  python313Packages.reportlab       # PDF generation library
  python313Packages.cocotb          # coroutine cosimulation testbench for HDL

  # Qt6 development
  qt6.qtbase
  qt6.qttools
  qt6.qtdeclarative
  qt6.qmake

  # PDF tools
  poppler

  # svg-term
  svg-term-cli

  # AI / machine learning packages
  koboldcpp
  llama-cpp
  lmstudio
  claude-code
  claude-monitor
  codex-openai
  hey-cli

] ++ optionals stdenv.isDarwin [
  # macOS-specific libraries needed for Rust builds (ring crate, etc.)
  # libiconv  # disabled: Rust now managed by mise, not Nix
  # Note: darwin.apple_sdk.frameworks removed in nixpkgs; frameworks now provided via stdenv
] ++ optionals (!stdenv.isDarwin) [
  dolphin-emu
  # bittorrent (use Homebrew cask on Darwin)
  transmission_4
]
