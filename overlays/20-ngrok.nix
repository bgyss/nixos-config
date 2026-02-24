# ngrok overlay – bump to 3.36.1 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.36.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-1ByPhGX5MfRatChsmFjkgd03hTXMoZKtQxyh9Zp+O44=";
    };
    "linux-amd64" = {
      version = "3.36.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-T+nSG+OP6NQ2C2klQ6LMc0X8KRtUqC6pnn0z5Gytt2U=";
    };
    "linux-arm" = {
      version = "3.36.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-TWE/SVTG9WKqg5sxiLdQC0I2bSXw0MDhxHCjKIx1nCM=";
    };
    "linux-arm64" = {
      version = "3.36.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-0EzEZQiW5PMk5iQkdmn3sNRboooZU1/DYV0Rx7cmqX4=";
    };
    "darwin-amd64" = {
      version = "3.36.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-RC/GWitX9daOiDOdUhj0nfPRytKwnDJqMIQ0kmDE2tc=";
    };
    "darwin-arm64" = {
      version = "3.36.1";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-jbfkhO/HO8OBrngBky2ifzKBtZ5BWEcrYVqmvqMJR9o=";
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
