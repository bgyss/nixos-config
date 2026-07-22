{
  pkgs,
  nixpkgs-master,
  emacs-overlay,
  ...
}:

let
  # Single source of truth for nixpkgs config, reused for both the main
  # instance and the one narrow nixpkgs-master instance below (F3).
  nixpkgsConfig = {
    allowUnfree = true;
    allowBroken = true;
    allowInsecure = false;
    allowUnsupportedSystem = true;
    permittedInsecurePackages = [
      "libtiff-4.0.3-opentoonz"
    ];
  };

  # nixpkgs-master is instantiated exactly once, here, purely to pull two
  # packages that need to be newer than the pinned nixpkgs (llama-cpp, aegisub).
  # It is NOT sufficient to use `nixpkgs-master.legacyPackages`: llama-cpp's
  # build-time nodejs_26 dependency fails on sandbox-incompatible network tests,
  # so master must carry the nodejs check-skip overlay (see
  # overlays/84-nodejs-skip-flaky-tests.nix). That forces this one extra eval;
  # keep it to these two packages so the cost stays bounded.
  masterFor =
    system:
    import nixpkgs-master {
      inherit system;
      config = nixpkgsConfig;
      overlays = [ (import ../../overlays/84-nodejs-skip-flaky-tests.nix) ];
    };
in
{
  nixpkgs = {
    config = nixpkgsConfig;

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

      # Pull the two master-only packages from the single master instance above.
      ++ [
        (
          _final: prev:
          let
            masterPkgs = masterFor prev.stdenv.hostPlatform.system;
          in
          {
            inherit (masterPkgs) llama-cpp aegisub;
          }
        )
      ];
  };
}
