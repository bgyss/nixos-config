{ config, pkgs, user, ... }:

{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
  ];

  # Set the primary user for the new nix-darwin multi-user setup
  system.primaryUser = user;

  # Disable nix-darwin's Nix management to work with Determinate Nix
  nix.enable = false;
  
  # Note: Nix settings like garbage collection and substituters should be
  # configured through Determinate's configuration instead

  system.checks.verifyNixPath = false;
  environment.etc."nix/nix.conf".enable = false;

  security.sudo.extraConfig = ''
    briangyss ALL=(root) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';

  environment.systemPackages = with pkgs; [
    beads
    emacs-unstable
  ];

  launchd.user.agents.emacs.path = [ config.environment.systemPath ];
  launchd.user.agents.emacs.serviceConfig = {
    KeepAlive = true;
    ProgramArguments = [
      "/bin/sh"
      "-c"
      "/bin/wait4path ${pkgs.emacs}/bin/emacs && exec ${pkgs.emacs}/bin/emacs --fg-daemon"
    ];
    StandardErrorPath = "/tmp/emacs.err.log";
    StandardOutPath = "/tmp/emacs.out.log";
  };

  # disabling to test Cline in vscode with deepseek r1
  # launchd.user.agents.llama-server.serviceConfig = {
  #   KeepAlive = true;
  #   RunAtLoad = true;
  #   ProgramArguments = [
  #     "/bin/sh"
  #     "-c"
  #     "/bin/wait4path ${pkgs.llama-cpp}/bin/llama-server && exec ${pkgs.llama-cpp}/bin/llama-server -hf ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF --port 8012 -ngl 99 -fa -ub 1024 -b 1024 -dt 0.1 --ctx-size 0 --cache-reuse 256"
  #   ];
  #   StandardErrorPath = "/tmp/llama-server.err.log";
  #   StandardOutPath = "/tmp/llama-server.out.log";
  #   EnvironmentVariables = {
  #     PATH = config.environment.systemPath;
  #   };
  # };

  system = {
    stateVersion = 4;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        KeyRepeat = 2; # Values: 120, 90, 60, 30, 12, 6, 2
        InitialKeyRepeat = 15; # Values: 120, 94, 68, 35, 25, 15

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 1.0;
        "com.apple.sound.beep.feedback" = 1;
      };

      dock = {
        autohide = false;
        show-recents = false;
        launchanim = true;
        mouse-over-hilite-stack = true;
        orientation = "bottom";
        tilesize = 48;
      };

      finder = {
        _FXShowPosixPathInTitle = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
