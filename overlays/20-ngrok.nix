# ngrok overlay – bump to 3.34.1 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.34.1";
      url = "https://bin.equinox.io/a/6e3LZpuWwCX/ngrok-v3-3.34.1-linux-386";
      sha256 = "0gxggk93zwpk2ixk7pj39aca99mfwz0r71qbizb676h6m9jllxzp";
    };
    "linux-amd64" = {
      version = "3.34.1";
      url = "https://bin.equinox.io/a/bBYEdiLV5M5/ngrok-v3-3.34.1-linux-amd64";
      sha256 = "1s1lxla3p356g65lbjsqq4qi05b84rdhglsvry512g4v7wmz1flc";
    };
    "linux-arm" = {
      version = "3.34.1";
      url = "https://bin.equinox.io/a/jagmTLBGLEq/ngrok-v3-3.34.1-linux-arm";
      sha256 = "0mp9l2a0vjjhgkwdacn4gpnfxpf1xiyyg0dqdjy44hzam20p2qp2";
    };
    "linux-arm64" = {
      version = "3.34.1";
      url = "https://bin.equinox.io/a/bh3Snix5V6e/ngrok-v3-3.34.1-linux-arm64";
      sha256 = "1n6hbmxq8z5gscrhljfdayndxb8rxvyb8graqrdh0vjci4194l0h";
    };
    "darwin-amd64" = {
      version = "3.34.1";
      url = "https://bin.equinox.io/a/kGStVejYdBP/ngrok-v3-3.34.1-darwin-amd64";
      sha256 = "1k6rqc3dam37kb5giw466fmikw78n81zlkqc94pkr943mmzn4xnb";
    };
    "darwin-arm64" = {
      version = "3.34.1";
      url = "https://bin.equinox.io/a/hA4j9pEcs11/ngrok-v3-3.34.1-darwin-arm64";
      sha256 = "19j4jcv3n7f3365g8nkzss53iwg5v828cxbf3n2pw17d7yd6kr2n";
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
