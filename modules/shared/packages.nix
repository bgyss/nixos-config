{ pkgs }:

with pkgs; [
  # General packages for development and system management
  alacritty
  aspell
  aspellDicts.en
  autojump
  bash-completion
  bat
  btop
  coreutils
  difftastic
  du-dust
  gcc
  direnv
  eza
  killall
  neofetch
  ngrok
  nix-direnv
  openssh
  sqlite
  wget
  zip

  # Encryption and security tools
  age
  age-plugin-yubikey
  gnupg
  libfido2

  # Cloud-related tools and SDKs
  docker
  docker-compose

  # Media-related packages
  emacs-all-the-icons-fonts
  dejavu_fonts
  ffmpeg_7
  fd
  font-awesome
  hack-font
  noto-fonts
  noto-fonts-emoji
  meslo-lgs-nf

  # Node.js development tools
  nodePackages.npm      # globally install npm
  nodePackages.prettier
  nodejs

  # Rust development tools
  rustup

  # Text and terminal utilities
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

  # Media players
  mpv
  spotify

  # Media tools
  yt-dlp

  # Python packages
  python312
  python312Packages.huggingface-hub # huggingface cli 
  python312Packages.llm             # llm cli util from datasette
  python312Packages.openai          # openai cli
  python312Packages.virtualenv      # globally install virtualenv

  # AI / machine learning packages
  ollama

  # bittorent
  transmission_4
]