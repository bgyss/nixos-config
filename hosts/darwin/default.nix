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

  # darwin-rebuild forces HOME=~root when run as root (needed for `switch`),
  # so root's ssh can't see the user's ~/.ssh/config or key, and fetching the
  # private nix-secrets flake input fails with "Permission denied (publickey)".
  # Nix's fetcher doesn't honor git's core.sshCommand, but the ssh it spawns
  # does read root's own ~/.ssh/config — so point that at the agenix-decrypted
  # key (root can read it despite the user ownership/0600 mode).
  system.activationScripts.postActivation.text = ''
    mkdir -p /var/root/.ssh
    chmod 700 /var/root/.ssh
    cat > /var/root/.ssh/config <<'EOF'
    Host github.com
      IdentityFile /run/agenix/ssh-key
      IdentitiesOnly yes
    EOF
    chmod 600 /var/root/.ssh/config
  '';

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

  # Cheap insurance against macOS Automatic Termination quitting the app when
  # its window is hidden/closed (_kLSApplicationWouldBeTerminatedByTALKey=1 in
  # the unified log). This wasn't actually the cause of the "randomly closing
  # every 1-4 min" symptom (that was the app's own menu-bar/startup setting,
  # since fixed in-app), but it's a harmless opt-out to keep.
  # See docs/notion-calendar-auto-termination.md.
  system.defaults.CustomUserPreferences."com.cron.electron" = {
    NSDisableAutomaticTermination = true;
  };

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

  # Daily self-healing update pipeline (Task 9, §5.4/§5.5): runs
  # `scheduled-check`, which runs `prepare` (unprivileged build+commit gated
  # on actual overlay/input drift) and posts an osascript notification when a
  # new revision lands or the run fails.
  #
  # This is a root DAEMON, not a user agent, specifically to avoid a
  # passwordless-sudo rule for `darwin-rebuild switch`: that rule would
  # convert any code execution as ${user} into silent root, because
  # `switch --flake` runs arbitrary activation scripts as root. Running the
  # pipeline as root and dropping to ${user} for the unprivileged 90% (bump,
  # build, commit, mirror, escalation, via `scheduled-check --propose-only`)
  # keeps the privileged path — activation, health check, rollback, via
  # `scheduled-check --activate-only <sha>` — a root-owned script instead,
  # with no standing sudo grant.
  #
  # Root already has /var/root/.ssh/config -> /run/agenix/ssh-key wired up
  # (see system.activationScripts.postActivation above), so it can fetch the
  # private `secrets` flake input.
  #
  # Deliberately an ABSOLUTE path into the live checkout rather than
  # `nix run nixos-config#scheduled-check` via the flake registry: launchd
  # daemons run with a minimal environment (bare NSGlobalDomain-ish PATH, no
  # guarantee the interactive shell's `nix registry add` state is what a
  # from-scratch daemon process sees), and the rest of this file already
  # hardcodes `/Users/${user}/...` for exactly this kind of
  # environment-independence (see the ssh-key/aws-credentials paths above).
  # `nix` itself is still invoked by absolute store path, same as the emacs
  # agent does for `pkgs.emacs`.
  launchd.daemons.nixos-auto-update = {
    script = ''
      set -uo pipefail
      REPO=/Users/${user}/nixos-config
      /usr/bin/sudo -u ${user} ${pkgs.nix}/bin/nix run "$REPO#scheduled-check" -- --propose-only
      rc=$?
      [[ $rc -ne 0 ]] && exit $rc
      rev="$(cat "$REPO/logs/proposed-revision" 2>/dev/null)"
      [[ -z "$rev" ]] && exit 0   # nothing proposed; nothing to activate
      exec ${pkgs.nix}/bin/nix run "$REPO#scheduled-check" -- --activate-only "$rev"
    '';
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [
        {
          Hour = 9;
          Minute = 0;
        }
      ];
      # Logs live inside the repo (gitignored under logs/) rather than /tmp
      # so they survive reboots/tmp-cleanup and are easy to check from the
      # config checkout itself. Keep these paths in sync with the
      # truncation loop in apps/*/scheduled-check, which truncates both the
      # old nixos-update-check names and these nixos-auto-update names.
      StandardErrorPath = "/Users/${user}/nixos-config/logs/nixos-auto-update.err.log";
      StandardOutPath = "/Users/${user}/nixos-config/logs/nixos-auto-update.out.log";
    };
    path = [ config.environment.systemPath ];
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
