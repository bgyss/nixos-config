# mise overlay – bump to v2026.4.28 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.4.28";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-jf7KEsGYb8jRVdD2NpKJo/NRxXL1iO9jGj1PJZOAvno=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-8iKltAl7Vft1Bb2ftif9fdoQqaSDGhJImHeE7AW6O+Q=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
  });
}
