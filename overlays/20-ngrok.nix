# ngrok overlay – bump to 3.38.0 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.38.0";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-mE9saQ3JCN5NLBe9Xf/nYcqKRCM0w9bWJfwqU+o4sjY=";
    };
    "linux-amd64" = {
      version = "3.38.0";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-aMFbyj4zT+VvbeCSwNA8lZ74oBL0J7eX9TYIPCmDAeY=";
    };
    "linux-arm" = {
      version = "3.38.0";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-WzP700E72jJIW7/Kqe2BcYojFXm7HKIQbSKdxQc4sE4=";
    };
    "linux-arm64" = {
      version = "3.38.0";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-JtdS58NZyn8g56M7Mc1U8UTHP6J/QTdIzaxR0MhG8JQ=";
    };
    "darwin-amd64" = {
      version = "3.38.0";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-PCE4kqqZPbyLi1H0ZK90FBcWMezFQPcd86XzXUybEuk=";
    };
    "darwin-arm64" = {
      version = "3.38.0";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-AgNccsivR6aA25rqpAxBwYMDB0ukcP1yG5QdLun8Uyo=";
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
