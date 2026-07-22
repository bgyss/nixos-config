# ngrok overlay – bump to 3.39.10 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-98wQpuwot9+eb3KNsqjvsSR0gnpdEUYFaKFre+pk68w=";
    };
    "linux-amd64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-qUROgslBGN0MPo6vx9vWVLnZ+bvc/Jp7HxIrItdiRGk=";
    };
    "linux-arm" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-PVi1vym1+dSkQUaO5mNCTbEDGSfnvbIv6iUjg9cfj+Y=";
    };
    "linux-arm64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-ejAv5PlQicGl9vb0OVrtN3rXXtejAZojQYxctp3ob7k=";
    };
    "darwin-amd64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-ZsYXfNU1/zMphQ1S5MF5DfGeYH2J3OIbvs5Iowp6dgs=";
    };
    "darwin-arm64" = {
      version = "3.39.10";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-QBzntdlS6i3LG5p1in5to2C2QZH+Mk4RK4qT4Ojn8Qw=";
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
