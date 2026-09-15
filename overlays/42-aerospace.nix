# aerospace overlay – bump to 0.21.3-Beta ahead of the pinned nixpkgs input,
# to pick up Tahoe-era fixes (window-id-0 phantom windows, focus-follows-mouse
# fullscreen/menu-dropdown bugs) without waiting for the nixpkgs pin to move.

final: prev:

let
  inherit (prev) fetchzip;
  version = "0.21.3-Beta";
in
{
  aerospace = prev.aerospace.overrideAttrs (old: {
    inherit version;
    src = fetchzip {
      url = "https://github.com/nikitabobko/AeroSpace/releases/download/v${version}/AeroSpace-v${version}.zip";
      hash = "sha256-JHXtF3IKUbge7z2cMBi4L9IruiByNPCIKugLe4ymvys=";
    };
  });
}
