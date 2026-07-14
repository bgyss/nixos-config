{ lib, osConfig, ... }:

let
  nixEnabled = osConfig.nix.enable or false;
in
{
  # nix-darwin errors when nix.package is read while nix.enable is false.
  # Guard the lookup so Home Manager skips nix.conf generation on Determinate Nix.
  nix = {
    enable = lib.mkForce nixEnabled;
    package = lib.mkForce (if nixEnabled then osConfig.nix.package else null);
  };
}
