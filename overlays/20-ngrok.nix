# ngrok overlay – bump to 3.33.0 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.33.0";
      url = "https://bin.equinox.io/a/mZfsaaeMsA5/ngrok-v3-3.33.0-linux-386";
      sha256 = "9ea932413dab2c76936507f3b09a4c9a7d8061c19b1befc0391bedd1aa7685f1";
    };
    "linux-amd64" = {
      version = "3.33.0";
      url = "https://bin.equinox.io/a/5YQQVmB7EWB/ngrok-v3-3.33.0-linux-amd64";
      sha256 = "78acfd0b189e7a1a532262f1e758616c76057b09c31119b6d112c4203e06c6ed";
    };
    "linux-arm" = {
      version = "3.33.0";
      url = "https://bin.equinox.io/a/kwFcrKfn2Yh/ngrok-v3-3.33.0-linux-arm";
      sha256 = "048997ddbfc48a7ae06a35e37e1ba10e5f224e293e6ec36245e8be50450c56ea";
    };
    "linux-arm64" = {
      version = "3.33.0";
      url = "https://bin.equinox.io/a/giKZm5JgTc6/ngrok-v3-3.33.0-linux-arm64";
      sha256 = "937d391edbd1f124ef83437b85f662a9afc61342aa140e04a0cee8ac69c3dfa8";
    };
    "darwin-amd64" = {
      version = "3.33.0";
      url = "https://bin.equinox.io/a/8hr2Fm99xMk/ngrok-v3-3.33.0-darwin-amd64";
      sha256 = "788cc93f96c694f744ae30048f8d480a995ae5d1a5558af7d9aa2ac045762c46";
    };
    "darwin-arm64" = {
      version = "3.33.0";
      url = "https://bin.equinox.io/a/bDBdUvrwnme/ngrok-v3-3.33.0-darwin-arm64";
      sha256 = "c19e909148481f02fd3879d7443b1a7822538b6d06055389e8cedff7f5604b6a";
    };
  };

  arch =
    if stdenv.hostPlatform.isi686 then
      "386"
    else if stdenv.hostPlatform.isx86_64 then
      "amd64"
    else if stdenv.hostPlatform.isAarch32 then
      "arm"
    else if stdenv.hostPlatform.isAarch64 then
      "arm64"
    else
      throw "ngrok: unsupported architecture ${stdenv.hostPlatform.system}";

  os =
    if stdenv.hostPlatform.isLinux then
      "linux"
    else if stdenv.hostPlatform.isDarwin then
      "darwin"
    else
      throw "ngrok: unsupported OS ${stdenv.hostPlatform.system}";

  versionInfo =
    lib.attrByPath [ "${os}-${arch}" ]
      (throw "ngrok: unsupported platform ${os}-${arch}")
      versions;
in {
  ngrok = prev.ngrok.overrideAttrs (_: {
    inherit (versionInfo) version;
    src = fetchurl { inherit (versionInfo) url sha256; };
  });
}
