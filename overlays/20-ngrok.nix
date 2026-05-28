# ngrok overlay – bump to 3.39.3 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-2hkSC5Nt+MFlh4eKwWrbRikbMl7LX1Yv9GeEgRzH7Fk=";
    };
    "linux-amd64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-5nwtslD8sMqAspo4KpO2CBwS1A6aLEIOLUohDaQm7q8=";
    };
    "linux-arm" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-rCZZgyCeWvjWp0VlMCnc5O74ZgEdCUlJytgYWSegqIc=";
    };
    "linux-arm64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-9mbYwsjaaZaoUMwfX3r1TveuBIOmc7AD1/mEcOywbFg=";
    };
    "darwin-amd64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-1RXZYBtdxa2SzocSao4PFaegUU1FrpDCUeJ/Ur4mhnE=";
    };
    "darwin-arm64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-jovXhnI6ZnR8ehzdvZVE4BePzhKnUukGnlQYn92Pgxo=";
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
