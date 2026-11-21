_:

[
  # Development Tools
  "cursor"
  "devin-desktop" # formerly "windsurf"; renamed upstream
  "zed"
  "docker-desktop"
  "insomnia"
  "tableplus"
  "ngrok"
  "postico"
  "miniconda"
  "visual-studio-code"
  "rive"

  # Terminals
  "ghostty"

  # backup / restore
  "backblaze"

  # Virtualization
  "parallels"
  "parallels-toolbox"

  # Productivity Tools
  "figma"
  "obsidian"

  # Communication Tools
  "discord"
  "loom"
  "notion"
  "slack"
  "zoom"

  # Utilities
  "appcleaner"
  "syncthing-app"
  "dropbox"

  # Encryption
  "keybase"

  # Entertainment Tools
  "spotify"
  "vlc"
  "iina"
  "yacreader"
  "simple-comic"

  # Productivity Tools
  "raycast"

  # Browsers
  "google-chrome"
  "orion"
  "firefox" # required by browsh (headless Marionette driver)

  # 3D / CAD / EDA
  # blender: unmanaged (2026-07-14) -- download.blender.org 403s behind a
  # Cloudflare bot challenge that brew/curl can't pass; install manually from
  # the DMG instead.
  "touchdesigner"
  "freecad"
  "kicad"

  # Microsoft Applications
  "microsoft-auto-update"
  "microsoft-excel"
  "microsoft-onenote"
  "microsoft-outlook"
  "microsoft-powerpoint"
  "microsoft-word"
  "microsoft-teams"

  # Adobe Applications
  "adobe-creative-cloud"

  # Games
  "gog-galaxy"
  "steam"
  "epic-games"
  "dolphin"
  "xemu"
  "multipatch"

  # GIS
  # "qgis" # temporarily disabled – upstream re-published DMG, Homebrew checksum mismatch

  # AI
  "diffusionbee"
  "chatgpt"
  "claude"
  "upscayl"
  "llama-app"

  # Bittorrent
  "transmission"

  # Animation
  # Kept deliberately: Homebrew disabled this cask on 2026-09-01 (fails
  # Gatekeeper), so it can't be reinstalled, but the installed copy still
  # works. Removing it here would uninstall it (homebrew cleanup = "uninstall").
  "opentoonz"
]
