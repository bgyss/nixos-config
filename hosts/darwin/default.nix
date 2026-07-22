{
  config,
  pkgs,
  user,
  secrets,
  ...
}:

{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
  ];

  # Set the primary user for the new nix-darwin multi-user setup
  system.primaryUser = user;

  age.secrets.openai-api-key = {
    file = "${secrets}/openai-api-key.age";
    owner = user;
    mode = "0400";
  };

  age.secrets.ssh-key = {
    file = "${secrets}/ssh-key.age";
    path = "/Users/${user}/.ssh/id_ed25519";
    symlink = true;
    owner = user;
    mode = "0600";
  };

  age.secrets.aws-credentials = {
    file = "${secrets}/aws-credentials.age";
    path = "/Users/${user}/.aws/credentials";
    symlink = true;
    owner = user;
    mode = "0600";
  };

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
    svg-term-cli
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

  # To run a persistent local llama-server as a launchd agent, see the recipe
  # in docs/recipes.md.

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
