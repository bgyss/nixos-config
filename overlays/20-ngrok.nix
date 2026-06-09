# ngrok overlay – bump to 3.39.7 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-mrPDN0wItKtc3CNBhBxT4DoCMPW+i6KkYdagZZzREYU=";
    };
    "linux-amd64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-289IHtIeAJ+daPMNWbCXv4oAo0uZqIjUntGpEQRAH+w=";
    };
    "linux-arm" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-2qsT1jjaza1MjZS1phvSJqQ9j4+9NN+NIU2Lmz/FEhQ=";
    };
    "linux-arm64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-qGHgBJNSWnFZBxgnXQPqZDud/Bw68PCjDgSSjNr5KdY=";
    };
    "darwin-amd64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-9r29WuujXoxT19yYQjT+I1JdqGf3nnHk9THfRgV1hac=";
    };
    "darwin-arm64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-M+u0HDeiYNjhFMEBaheFHQ0NCJJTpeUGCJxIB8TbdQ4=";
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
