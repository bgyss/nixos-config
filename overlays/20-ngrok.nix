# ngrok overlay – bump to 3.37.3 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.37.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-FFtHMzoCYTetS11F5RrfiNbRyL9UwAnbC75mxWcPsDs=";
    };
    "linux-amd64" = {
      version = "3.37.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-9x2/BkztJX+Yc81fbxqSy3+WkLiQJgzopc9OdgDpMtA=";
    };
    "linux-arm" = {
      version = "3.37.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-3i3FehgyOhxrVlZnKUKEmeokB2OA9RjAYf+dXuadc5Y=";
    };
    "linux-arm64" = {
      version = "3.37.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-F6BuTxKAs5XBLvVuYC2nWh16fH3cIfn9JuIEbK1iwco=";
    };
    "darwin-amd64" = {
      version = "3.37.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-K/PKul8UFwoJr0IscHuK4sb4oLLsx+KX77dgwbcRHoQ=";
    };
    "darwin-arm64" = {
      version = "3.37.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-qclaJjKL/Dux/sdj73z56t+fEpzke+dkjUpSaRYSBXc=";
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
