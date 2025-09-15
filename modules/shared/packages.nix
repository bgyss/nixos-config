{ pkgs }:

with pkgs; [
  # General packages for development and system management
  alacritty
  aspell
  aspellDicts.en
  autojump
  autossh
  bash-completion
  bat
  btop
  coreutils
  difftastic
  direnv
  du-dust
  eza
  gcc
  gh
  just
  killall
  ncdu
  neofetch
  ngrok
  nix-direnv
  openssh
  sqlite
  uv
  wget
  zip
  
  # Emulation
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
  ffmpeg_7
  fd
  font-awesome
  hack-font
  iina
  imagemagick
  noto-fonts
  noto-fonts-emoji
  meslo-lgs-nf

  # Node.js development tools
  nodejs_24

  # development tools
  cmake

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
  python312
  python312Packages.huggingface-hub # huggingface cli 
  python312Packages.llm             # llm cli util from datasette
  python312Packages.openai          # openai cli
  python312Packages.virtualenv      # globally install virtualenv
  python312Packages.git-filter-repo # git filter repo

  # AI / machine learning packages
  koboldcpp
  llama-cpp
  lmstudio
  codex-openai
  ccusage

  # bittorent
  transmission_4
]
