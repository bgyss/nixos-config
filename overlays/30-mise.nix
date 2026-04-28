# mise overlay – bump to v2026.4.25 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.4.25";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-DJdCktuI6QKxnXv46FjvRXY+eXuroZ+DpnLKh1+ovrE=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-QjvGHFs4yLUNWMQHPNYVB4RB+hSBykNMimYN+pq4m2g=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
  });
}
