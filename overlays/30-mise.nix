# mise overlay – bump to v2026.6.0 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.6.0";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-UE+Mo6AtNiVgKOfLS7khAoVNJGyomL5Vb/pfcCke5fI=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-f3cdfkQ5gguwoENO+1gNRnt7/qOAv+OfAwxEPQvQX+Q=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
    # git clone test requires git-upload-pack, unavailable in Nix sandbox
    doCheck = false;
  });
}
