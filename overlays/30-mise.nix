# mise overlay – bump to v2026.1.9 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;

  version = "2026.1.9";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = lib.fakeSha256;
  };
in {
  mise = prev.mise.overrideAttrs (_old: {
    inherit version src;
    cargoHash = lib.fakeSha256;
  });
}
