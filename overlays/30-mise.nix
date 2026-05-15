# mise overlay – bump to v2026.5.9 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchFromGitHub lib;
  inherit (prev.rustPlatform) fetchCargoVendor;

  version = "2026.5.9";
  src = fetchFromGitHub {
    owner = "jdx";
    repo = "mise";
    rev = "v${version}";
    hash = "sha256-v1F79jUpnrSRBkA6JMviGMiwBV12u2Wtw4qTS9RfI2k=";
  };
in {
  mise = prev.mise.overrideAttrs (old: rec {
    pname = old.pname or "mise";
    inherit version src;
    name = "${pname}-${version}";
    cargoHash = "sha256-Pm15W2YpF5hVtmkvwC5oW98h7WHHoiG2D5wZynHajR4=";
    cargoDeps = fetchCargoVendor {
      inherit src pname version;
      hash = cargoHash;
    };
    # git clone test requires git-upload-pack, unavailable in Nix sandbox
    doCheck = false;
  });
}
