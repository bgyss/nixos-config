{ pkgs }:

let
  inherit (pkgs) stdenv;
  inherit (pkgs.lib) optionals;

  # Custom uv 0.9.18 for aarch64-darwin
  uv-custom = if stdenv.hostPlatform.system == "aarch64-darwin" then
    pkgs.stdenvNoCC.mkDerivation rec {
      pname = "uv";
      version = "0.9.18";

      src = pkgs.fetchurl {
        url = "https://github.com/astral-sh/uv/releases/download/${version}/uv-aarch64-apple-darwin.tar.gz";
        sha256 = "sha256-3DvuSruzusJno5haI+p2F9GdQf84Hbr1YLpBWtZa9o8=";
      };

      sourceRoot = "uv-aarch64-apple-darwin";

      dontConfigure = true;
      dontBuild = true;
      dontPatch = true;
      dontStrip = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        install -m755 uv $out/bin/uv
        install -m755 uvx $out/bin/uvx
        runHook postInstall
      '';

      meta = {
        description = "An extremely fast Python package installer and resolver, written in Rust";
        homepage = "https://github.com/astral-sh/uv";
        license = with pkgs.lib.licenses; [ pkgs.lib.licenses.mit pkgs.lib.licenses.asl20 ];
        platforms = [ "aarch64-darwin" ];
        mainProgram = "uv";
      };
    }
  else
    pkgs.uv;
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
  just
  killall
  ncdu
  neofetch
  nix-prefetch-git # should this be installed by default
  ngrok
  nix-direnv
  openssh
  pocketbase
  sqlite
  uv-custom
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
  mesen
  scummvm

  # Encryption and security tools
  age
  age-plugin-yubikey
  gnupg
  libfido2

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
  cmake
  devenv
  ruff

  # Rust development tools
  rustup

  # golang
  go
  gox

  # odln
  odin

  # OCR
  tesseract

  # Text and terminal utilities
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
  mpv
  spotify

  # Media tools
  yt-dlp
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

  # svg-term
  svg-term-cli

  # AI / machine learning packages
  koboldcpp
  llama-cpp
  lmstudio
  claude-code
  claude-monitor
  codex-openai
  ccusage

  # bittorrent
  transmission_4
] ++ optionals (!stdenv.isDarwin) [
  dolphin-emu
]
