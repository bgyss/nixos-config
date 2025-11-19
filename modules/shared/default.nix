{ config, pkgs, nixpkgs-master, emacs-overlay, ... }:

{
  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = true;
      allowInsecure = false;
      allowUnsupportedSystem = true;
      permittedInsecurePackages = [
        "libtiff-4.0.3-opentoonz"
      ];
    };

    overlays =
      # Apply each overlay found in the /overlays directory
      let path = ../../overlays; in with builtins;
      map (n: import (path + ("/" + n)))
          (filter (n: match ".*\\.nix" n != null ||
                      pathExists (path + ("/" + n + "/default.nix")))
                  (attrNames (readDir path)))

      # Add emacs overlay from flake input
      ++ [ emacs-overlay.overlays.default ]

      # Make nixpkgs-master packages available
      ++ [
        (final: prev: {
          inherit (nixpkgs-master.legacyPackages.${prev.stdenv.hostPlatform.system}) llama-cpp aegisub;
        })
      ];
  };
}
