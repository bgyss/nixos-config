# mise overlay – bump to v2026.5.5 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.5.5";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-QFLjJV8yCvB+MBrfjUQpykmfUwosYs+DPShKwUQQDP4=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-iYogkoSAtk2rXpY2mW8XAR3aeB1me0FI1Hr9oKnsqog=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
    # git clone test requires git-upload-pack, unavailable in Nix sandbox
    doCheck = false;
  });
}
