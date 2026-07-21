{ pkgs }:

with pkgs;
let
  shared-packages = import ../shared/packages.nix { inherit pkgs; };
in
shared-packages
++ [
  apple-sdk_15
  fswatch
  # dockutil  # moved to Homebrew to avoid Swift build failure
]
