# ngrok overlay – bump to 3.37.2 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.37.2";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-IKM2cPTRLsf64vIqA85/Sgk5ZXM1slUlN/fcY/dQ7A8=";
    };
    "linux-amd64" = {
      version = "3.37.2";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-+wEl/tbrX5GM2AUy8QhXT27046oOFYzuddo2qNnxcyU=";
    };
    "linux-arm" = {
      version = "3.37.2";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-AxadTrXIQ3bmASu6YkTPG9XIiwLayZFc+2CUTfFby58=";
    };
    "linux-arm64" = {
      version = "3.37.2";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-DuDf+EptE/iiT1bEelzzOF11gEmKaFXuyC7L2+IJQSU=";
    };
    "darwin-amd64" = {
      version = "3.37.2";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-4zHexpEe6KnJtVAn75LZFOmINJhO9dW5HFEgzM+MZtI=";
    };
    "darwin-arm64" = {
      version = "3.37.2";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-os2HfT9IrKFE8D0My3B7LCGabUGvPws1E5Rz1haGtMg=";
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
