# ngrok overlay – bump to 3.37.6 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.37.6";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-iZ2lIj4xedE+Wt8SLb0lTWdDTYvBAyahAWOWKIWqOQ0=";
    };
    "linux-amd64" = {
      version = "3.37.6";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-ywCl0wiW9G2tc3dsqDpO+AIuimfvY7ODOicaH2N57rA=";
    };
    "linux-arm" = {
      version = "3.37.6";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-i/Ifcot6cibO85Cg7lIT614cqFF2FLbJ+1UiRiIJt6A=";
    };
    "linux-arm64" = {
      version = "3.37.6";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-+es4qDYCRjKPbFdU+hQ1BjKIotyZ/pqbAWNU4BIIm7Q=";
    };
    "darwin-amd64" = {
      version = "3.37.6";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-CSvrtEErq5L2z0BzmaBV2B0NaM+CUEZWqjeVRvMqEOc=";
    };
    "darwin-arm64" = {
      version = "3.37.6";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-K7XXP8stGrFvH4eZZYhj9hKYSb1NzhTPW6MqByjmXuA=";
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
