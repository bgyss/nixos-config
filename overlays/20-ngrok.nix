# ngrok overlay – bump to 3.39.3 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-JTDb8BzkdBXHbtPmK/G0K2QNoUqN8TMuXP2DIrbHbng=";
    };
    "linux-amd64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-brTO8AYXbzkNDwFr5hqh3o5M0VSSjDD3yUo4Drj+htw=";
    };
    "linux-arm" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-x6rdmOcf67S4avEoW1Z44VNk5wF7CXQXysCDm/oOByg=";
    };
    "linux-arm64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-Jmu05NRS9ubXouZ43UaDiA9bz7r5eUouHkpTIW9Swdg=";
    };
    "darwin-amd64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-46Pgb3iVPyk8XhZscJfMBOnbK8kUWGqWr9qBsJUH87M=";
    };
    "darwin-arm64" = {
      version = "3.39.3";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-LvzNgec6RSksFZE7VJqTl97g6+ul9tQkJ3cvFZJ7Ucc=";
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
