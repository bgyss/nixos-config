{ config, pkgs, lib, home-manager, user, ... }:

let
  # Define the content of your file as a derivation
  myEmacsLauncher = pkgs.writeScript "emacs-launcher.command" ''
    #!/bin/sh
    emacsclient -c -n &
  '';
  sharedFiles = import ../shared/files.nix { inherit config pkgs; };
  additionalFiles = import ./files.nix { inherit user config pkgs; };
in
{
  imports = [
   ./dock
  ];

  # It me
  users.users.${user} = {
    name = "${user}";
    home = "/Users/${user}";
    isHidden = false;
    shell = pkgs.zsh;
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;      
      upgrade = true;         
      cleanup = "uninstall";
      extraFlags = ["--force" "--quiet"];
    };

    # Update taps to use a list of strings
    # taps = [
    #   "homebrew/cask"
    #   "homebrew/core"
    #   "dagger/tap"
    # ];
    
    global = {
      brewfile = true;
    };

    casks = pkgs.callPackage ./casks.nix {};
    brews = pkgs.callPackage ./brews.nix {};
    
    # These app IDs are from using the mas CLI app
    # mas = mac app store
    # https://github.com/mas-cli/mas
    #
    # $ nix shell nixpkgs#mas
    # $ mas search <app name>
    #
    # If you have previously added these apps to your Mac App Store profile (but not installed them on this system),
    # you may receive an error message "Redownload Unavailable with This Apple ID".
    # This message is safe to ignore. (https://github.com/dustinlyons/nixos-config/issues/83)
    # masApps = {
    #   "1password" = 1333542190;
    #   "hidden-bar" = 1452453066;
    #   "wireguard" = 1451685025;
    # };
  };

  # Enable home-manager
  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-bak";
    sharedModules = [ ./hm-nix-darwin-fix.nix ];
    users.${user} = { pkgs, config, lib, ... }:{
      home = {
        enableNixpkgsReleaseCheck = false;
        packages = pkgs.callPackage ./packages.nix {};
        file = lib.mkMerge [
          sharedFiles
          additionalFiles
          { "emacs-launcher.command".source = myEmacsLauncher; }
        ];
        stateVersion = "24.11";
      };
      # Use Determinate Nix; avoid Home Manager's nix module to prevent nix.package access when nix.enable is false.
      nix.enable = false;
      programs = {
        home-manager.enable = true;

        aerospace = {
          enable = true;
          launchd.enable = true;
          settings = {
            gaps = {
              inner.horizontal = 8;
              inner.vertical = 8;
              outer.left = 8;
              outer.bottom = 8;
              outer.top = 8;
              outer.right = 8;
            };

            default-root-container-layout = "tiles";
            default-root-container-orientation = "auto";
            accordion-padding = 30;

            on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

            on-window-detected = [
              {
                "if".app-id = "com.google.Chrome";
                run = "move-node-to-workspace 2";
              }
              {
                "if".app-id = "com.openai.atlas";
                run = "move-node-to-workspace 2";
              }
            ];

            mode.main.binding = {
              # Focus
              alt-h = "focus left";
              alt-j = "focus down";
              alt-k = "focus up";
              alt-l = "focus right";

              # Move windows
              alt-shift-h = "move left";
              alt-shift-j = "move down";
              alt-shift-k = "move up";
              alt-shift-l = "move right";

              # Resize
              alt-minus = "resize smart -50";
              alt-equal = "resize smart +50";

              # Layout
              alt-slash = "layout tiles horizontal vertical";
              alt-comma = "layout accordion horizontal vertical";
              alt-f = "fullscreen";
              alt-shift-space = "layout floating tiling";

              # Workspaces
              alt-1 = "workspace 1";
              alt-2 = "workspace 2";
              alt-3 = "workspace 3";
              alt-4 = "workspace 4";
              alt-5 = "workspace 5";
              alt-6 = "workspace 6";
              alt-7 = "workspace 7";
              alt-8 = "workspace 8";
              alt-9 = "workspace 9";

              # Move window to workspace
              alt-shift-1 = "move-node-to-workspace 1";
              alt-shift-2 = "move-node-to-workspace 2";
              alt-shift-3 = "move-node-to-workspace 3";
              alt-shift-4 = "move-node-to-workspace 4";
              alt-shift-5 = "move-node-to-workspace 5";
              alt-shift-6 = "move-node-to-workspace 6";
              alt-shift-7 = "move-node-to-workspace 7";
              alt-shift-8 = "move-node-to-workspace 8";
              alt-shift-9 = "move-node-to-workspace 9";

              # Monitors
              alt-tab = "workspace-back-and-forth";
              alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

              # Service mode
              alt-shift-semicolon = "mode service";
            };

            mode.service.binding = {
              esc = [ "reload-config" "mode main" ];
              r = [ "flatten-workspace-tree" "mode main" ];
              f = [ "layout floating tiling" "mode main" ];
              backspace = [ "close-all-windows-but-current" "mode main" ];
              enter = "mode main";
            };
          };
        };
      } // import ../shared/home-manager.nix { inherit config pkgs lib; };

      # Marked broken Oct 20, 2022 check later to remove this
      # https://github.com/nix-community/home-manager/issues/3344
      manual.manpages.enable = false;
    };
  };

  # Fully declarative dock using the latest from Nix Store
  local.dock.enable = true;
  local.dock.entries = [
    { path = "/System/Applications/Messages.app/"; }
    { path = "/Applications/Ghostty.app/"; }
    { path = "/Applications/Slack.app/"; }
    { path = "/Applications/Discord.app/"; }
    { path = "/Applications/HEY.app/"; }
    { path = "/Applications/Notion Calendar.app/"; }
    { path = "/Applications/Notion.app/"; }
    { path = "/Applications/Devin.app/"; }
    { path = "/Applications/ChatGPT Atlas.app/"; }
    { path = "/Applications/Google Chrome.app/"; }
    { path = "/Applications/ChatGPT.app/"; }
    { path = "/Applications/Claude.app/";}
    { path = "/Applications/Docker.app/"; }
    { path = "/Applications/Microsoft Excel.app/"; }
    { path = "/System/Applications/FaceTime.app/"; }
    { path = "/Applications/Spotify.app/"; }
    { path = "/System/Applications/News.app/"; }
    { path = "/System/Applications/Photos.app/"; }
    { path = "/Applications/Steam.app/"; }
    { path = "${pkgs.iina}/Applications/IINA.app"; }
    { path = "/Applications/1Password.app/"; }
    { path = "/Applications/Tailscale.app/"; }
    { path = "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app";}
    {
      path = "${config.users.users.${user}.home}/Downloads";
      section = "others";
      options = "--sort name --view fan --display stack --sort datemodified";
    }
  ];
}
