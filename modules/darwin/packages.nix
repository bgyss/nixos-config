{ pkgs }:

with pkgs;
let
  shared-packages = import ../shared/packages.nix { inherit pkgs; };
  android = import ./android.nix { inherit pkgs; };
in
shared-packages
++ [
  apple-sdk_15
  fswatch
  jdk17
  android.package
  # dockutil  # moved to Homebrew to avoid Swift build failure
]
