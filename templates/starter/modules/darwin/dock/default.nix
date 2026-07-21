{
  config,
  pkgs,
  lib,
  ...
}:

# Original source: https://gist.github.com/antifuchs/10138c4d838a63c0a05e725ccd7bccdd

with lib;
let
  cfg = config.local.dock;
  inherit (pkgs) stdenv;
  # Use Homebrew dockutil to avoid building Swift from source
  dockutil = "/opt/homebrew/bin/dockutil";
in
{
  options = {
    local.dock.enable = mkOption {
      description = "Enable dock";
      default = stdenv.isDarwin;
      example = false;
    };

    local.dock.entries = mkOption {
      description = "Entries on the Dock";
      type =
        with types;
        listOf (submodule {
          options = {
            path = lib.mkOption { type = str; };
            section = lib.mkOption {
              type = str;
              default = "apps";
            };
            options = lib.mkOption {
              type = str;
              default = "";
            };
          };
        });
      readOnly = true;
    };
  };

  config = mkIf cfg.enable (
    let
      normalize = path: if hasSuffix ".app" path then path + "/" else path;
      # Run each dockutil call directly under `sudo -u` (the activation
      # script already runs as root). Do NOT wrap these in `bash -c '...'`:
      # each `--add '<path>'` contains its own single quotes, which would
      # prematurely close the wrapper quote and mangle every entry.
      createEntries = concatMapStrings (
        entry:
        "sudo -u ${config.system.primaryUser} ${dockutil} --no-restart --add '${normalize entry.path}' --section ${entry.section} ${entry.options}\n"
      ) cfg.entries;
    in
    {
      system.activationScripts.postActivation.text = ''
        echo >&2 "Setting up the Dock (declarative reset)..."
        echo >&2 "Removing all existing Dock items."
        sudo -u ${config.system.primaryUser} ${dockutil} --no-restart --remove all || true
        echo >&2 "Adding configured Dock entries."
        ${createEntries}
        echo >&2 "Restarting Dock."
        sudo -u ${config.system.primaryUser} killall Dock || true
        # `killall Dock` returns before macOS finishes writing/reloading
        # com.apple.dock.plist, so a stale entry (e.g. a removed app,
        # showing as a "?" tile) can survive the reset. Re-run the same
        # remove+add pass once more after a short delay as a verification
        # pass, then do a final Dock restart.
        sleep 2
        sudo -u ${config.system.primaryUser} ${dockutil} --no-restart --remove all || true
        ${createEntries}
        sudo -u ${config.system.primaryUser} killall Dock || true
      '';
    }
  );
}
