# ngrok overlay – bump to 3.39.5 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.5";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-KIWpVc1RYr7YxQvrTNmDllP4jNxSebJhupwr6LnWxzI=";
    };
    "linux-amd64" = {
      version = "3.39.5";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-bvx9WwVa8ZlXoWZ7xMegj96TGFjhIqTCyN7OR2ZFjWE=";
    };
    "linux-arm" = {
      version = "3.39.5";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-b8a0EGSbkbMRkBq2zP9EJyBVX2PuQAAiZ6sSZoS/OFc=";
    };
    "linux-arm64" = {
      version = "3.39.5";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-27It+Fem/YJ8e1sgI+VS3pejcVrwUhgzuORxnFS9KQQ=";
    };
    "darwin-amd64" = {
      version = "3.39.5";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-BTbN8qOxcTLy1NbRNZHjn3gm/v6liT4907fmcUm8shM=";
    };
    "darwin-arm64" = {
      version = "3.39.5";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-DV3P7opp9veMvmAeVmLRaiwVgcY6ZSAlR6W05uJMu5Q=";
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
