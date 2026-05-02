# ngrok overlay – bump to 3.39.1 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-6Kq/CmfYpJQBJPrpZjTnE457OXRt4Izypb4mWIuGc1I=";
    };
    "linux-amd64" = {
      version = "3.39.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-RSg197JKXVA1Tgurb2PQ+q4kqjzUFud8bojCAXXkJ30=";
    };
    "linux-arm" = {
      version = "3.39.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-gEP+66AI6q8mt6bPa/zEML33xwExvSAuDnjqAYJ20M0=";
    };
    "linux-arm64" = {
      version = "3.39.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-e8p9fZybooanrz222tEN2dJFtDX6xMyuQFL2xtc1kR4=";
    };
    "darwin-amd64" = {
      version = "3.39.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-wTsX64v7kzuNsoCntwj73DpW50lL60ajnowjtg31SII=";
    };
    "darwin-arm64" = {
      version = "3.39.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-jepwuxQpFTu62sxI+hIxjrIxIgqwm7vDnQlk0OM5I98=";
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
