# ngrok overlay – bump to 3.39.10 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-z/W25wQJDZ/MycQ7RNZBjKhEXv8hh0M0ZqIjrayBNTo=";
    };
    "linux-amd64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-nfvhqRTmnMfpgNYea9WmQgJZGBAsW8aZBdHFdwOso+g=";
    };
    "linux-arm" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-oj6E1HBlh3QKXVkPpX/ELiifL9I8hpTpJlo5iJDvt1M=";
    };
    "linux-arm64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-cXb15dWi9sMy/5Ee+JV0HxMWjx8MIlSSxEEr3osvmg0=";
    };
    "darwin-amd64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-6vcFI9kjXwmizRRfbg3nLvhoFkSMNCaP5xwq9UP0/Dg=";
    };
    "darwin-arm64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-kHy2G2+lg346ws+kq46LHv6FxufNEcmZdKVge16iHOs=";
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

  versionInfo = lib.attrByPath [
    "${os}-${arch}"
  ] (throw "ngrok: unsupported platform ${os}-${arch}") versions;
in
{
  ngrok = prev.ngrok.overrideAttrs (_: {
    inherit (versionInfo) version;
    src = fetchurl { inherit (versionInfo) url sha256; };
  });
}
