# ngrok overlay – bump to 3.35.0 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  versions = {
    "linux-386" = {
      version = "3.35.0";
      url = "https://bin.equinox.io/a/3xL4uaGye2K/ngrok-v3-3.35.0-linux-386.tar.gz";
      sha256 = "0n2chdlqkp9k5k5gjsyybabv8hz8kkb3jys49iqakj0bg654i520";
    };
    "linux-amd64" = {
      version = "3.35.0";
      url = "https://bin.equinox.io/a/76vdzhNjs7e/ngrok-v3-3.35.0-linux-amd64.tar.gz";
      sha256 = "1sj6la2bx3z3z80g1k4j7b13j3xywcnla3x0f4r3di5mrryr4i77";
    };
    "linux-arm" = {
      version = "3.35.0";
      url = "https://bin.equinox.io/a/a26G6Jn2Sti/ngrok-v3-3.35.0-linux-arm.tar.gz";
      sha256 = "173qm1w70kpfs576fgj92l6pn6bg8q0r678dz5vlzmj7hwygdmwf";
    };
    "linux-arm64" = {
      version = "3.35.0";
      url = "https://bin.equinox.io/a/d7vz8B9YEE3/ngrok-v3-3.35.0-linux-arm64.tar.gz";
      sha256 = "14qzgd5ldzpd5sy2kv9b9ny9q313l3wn26lpj8p68gxyxi0h2qyi";
    };
    "darwin-amd64" = {
      version = "3.35.0";
      url = "https://bin.equinox.io/a/uQRUsybuCY/ngrok-v3-3.35.0-darwin-amd64.zip";
      sha256 = "0539w1y8icx90rx6lm8hnagaa9p8dn5jaa01l53crrf7g119kq6d";
    };
    "darwin-arm64" = {
      version = "3.35.0";
      url = "https://bin.equinox.io/a/6S1r8a6kUrQ/ngrok-v3-3.35.0-darwin-arm64.zip";
      sha256 = "0vd1vmgcwscyp4fq8f460lp8abildyrqwhywlcwvbyjn67gjj37z";
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
