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
    allowBroken = false;
    allowInsecure = false;
    allowUnsupportedSystem = false;
    permittedInsecurePackages = [
      "libtiff-4.0.3-opentoonz"
    ];
  };

  # nixpkgs-master is instantiated exactly once, here, purely to pull the few
  # packages that need to be newer than the pinned nixpkgs (llama-cpp, aegisub,
  # yt-dlp).
  #
  # yt-dlp must come from master as a WHOLE package, not as an override on the
  # pinned nixpkgs. It is tightly coupled to `curl_cffi` and native
  # `curl-impersonate`: yt-dlp picks a Chrome impersonation target, and if the
  # native library predates that Chrome profile every request fails. The old
  # overlays/91-yt-dlp.nix bumped yt-dlp alone on top of a January nixpkgs pin,
  # which produced exactly that skew (yt-dlp 2026.07.04 selecting Chrome 142
  # against curl-impersonate 1.2.0, which only ships through Chrome 136 —
  # downloads failed, and `--impersonate chrome-136` did not help because
  # extractors do their own target selection). Taking yt-dlp from master brings
  # master's matched curl_cffi/curl-impersonate closure with it.
  #
  # Consequence, accepted deliberately: yt-dlp's version now floats with the
  # nixpkgs-master input instead of being pinned in overlays/updates.json, so
  # the quarantine ledger cannot pin or roll it back. For a tool that breaks
  # whenever a site changes and must stay current, that is the right trade.
  #
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

      # Pull the master-only packages from the single master instance above.
      ++ [
        (
          _final: prev:
          let
            masterPkgs = masterFor prev.stdenv.hostPlatform.system;
          in
          {
            inherit (masterPkgs) llama-cpp aegisub;
            # Deliberately a NEW attribute rather than replacing `yt-dlp`.
            # nixpkgs' `gallery-dl` propagates `yt-dlp`, and master's is built
            # against a newer Python than the pinned nixpkgs — substituting it
            # into gallery-dl's environment breaks its build outright. Only the
            # CLI we install (modules/shared/packages.nix) uses this one.
            yt-dlp-master = masterPkgs.yt-dlp;
          }
        )
      ];
  };
}
