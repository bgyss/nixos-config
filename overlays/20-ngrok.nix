# ngrok overlay – bump to 3.39.7 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-m20X7hKNx29moiYkyattCX+MCHtOkL1rhYNBDi1THnw=";
    };
    "linux-amd64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-5dMSHreLl6IOwt7xep1x1XQF2xsKFPohJSN4SMByQ2w=";
    };
    "linux-arm" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-8alX2chFoB4dGZbBKb2FhX8vhiJl+E7oZTfIa8JdHIc=";
    };
    "linux-arm64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-NJ6/viAKBMPhJlFGzRXIh7cs40Y7g4HRCsy3r4uuoPw=";
    };
    "darwin-amd64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-DIXoPo45Y5f/xoGmTVwl/PzwQkYk29+KTBXN7Ve6W4w=";
    };
    "darwin-arm64" = {
      version = "3.39.7";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-h/Zvh1bYzhUsr3q8zbnIwHnTv/W1o4UHjIjW+UydpR0=";
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
