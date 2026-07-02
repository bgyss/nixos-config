# ngrok overlay – bump to 3.39.9 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.9";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-na9LId0rl0OUmZJwbB70RFex39RFQvGCosVepZEVxSs=";
    };
    "linux-amd64" = {
      version = "3.39.9";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-C3TbQo9lWUQpLPbFVNNciUH67M/4fVpoNRUseggoH/A=";
    };
    "linux-arm" = {
      version = "3.39.9";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-sPnjlmhAbTYdRKJCVG67pBRCVv88MgAyIFN5wYoerYM=";
    };
    "linux-arm64" = {
      version = "3.39.9";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-l/tw2IyD7kTZZVtn6HdwKh/A51ZW0z1BQEN3LNN1DB8=";
    };
    "darwin-amd64" = {
      version = "3.39.9";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-lPXumWzabOyLF5xdq4FseQpkAjKETNZd2eX4MOpSj44=";
    };
    "darwin-arm64" = {
      version = "3.39.9";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-hAoGaAoKaM3ylQEr1SRNZFpNQjXEUcA1QpOsJNsJbow=";
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
