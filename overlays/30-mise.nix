# mise overlay – bump to v2026.5.15 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.5.15";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-0yf6OlPJ8/Oa9tNZRhIW/hX5qMwpz//Q9Df8LqPWR9k=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-o9o4kIjNNnbMaY3i/onrAaT/f0zgz9xE27SURlUtGik=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
    # git clone test requires git-upload-pack, unavailable in Nix sandbox
    doCheck = false;
  });
}
