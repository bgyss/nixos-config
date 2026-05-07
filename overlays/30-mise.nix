# mise overlay – bump to v2026.5.2 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.5.2";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-XJ5y+SvNLSYyrdSQcCxh36AMKI4hLvmu2WTPpFmZ8cc=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-K4/0Oev4P+xaNZKxuzooxWRovdz45xIeEkf0pza8K6I=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
    # git clone test requires git-upload-pack, unavailable in Nix sandbox
    doCheck = false;
  });
}
