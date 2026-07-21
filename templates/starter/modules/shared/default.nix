{
  config,
  pkgs,
  nixpkgs-master,
  emacs-overlay,
  ...
}:

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
      let
        path = ../../overlays;
      in
      with builtins;
      map (n: import (path + ("/" + n))) (
        filter (n: match ".*\\.nix" n != null || pathExists (path + ("/" + n + "/default.nix"))) (
          attrNames (readDir path)
        )
      )

      # Add emacs overlay from flake input
      ++ [ emacs-overlay.overlays.default ]

      # Make nixpkgs-master packages available.
      # Import master with the nodejs check-skip overlay so llama-cpp's
      # build-time nodejs_26 dependency doesn't fail on sandbox-incompatible
      # network tests (see overlays/84-nodejs-skip-flaky-tests.nix).
      ++ [
        (
          final: prev:
          let
            masterPkgs = import nixpkgs-master {
              inherit (prev.stdenv.hostPlatform) system;
              config = {
                allowUnfree = true;
                allowBroken = true;
                allowInsecure = false;
                allowUnsupportedSystem = true;
              };
              overlays = [ (import ../../overlays/84-nodejs-skip-flaky-tests.nix) ];
            };
          in
          {
            inherit (masterPkgs) llama-cpp aegisub;
          }
        )
      ];
  };
}
