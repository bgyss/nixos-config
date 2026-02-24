# mise overlay – bump to v2026.2.19 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.2.19";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-ajIijwnCpdp4fZzubO5B0cLrZ4Puzm/s0rWx03EFG40=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-8ONfV25bgPPjFJA5HoBj+ESYaxvns2O13AeNbr4A9Fs=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
  });
}
