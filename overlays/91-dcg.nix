# destructive_command_guard (dcg) – prebuilt binary, no nixpkgs package exists
# https://github.com/Dicklesworthstone/destructive_command_guard

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "0.14.1";
  base = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${version}";

  versions = {
    "aarch64-darwin" = {
      url = "${base}/dcg-aarch64-apple-darwin.tar.xz";
      sha256 = "sha256-2cCql73VL7yjUAUmCexUSHDvkzN725z8cmFk5kTqOH0=";
    };
    "x86_64-darwin" = {
      url = "${base}/dcg-x86_64-apple-darwin.tar.xz";
      sha256 = "sha256-OWvXczEjWc3bGy4ObwR12P2voo6grO3y5krDhLtaS1s=";
    };
    "aarch64-linux" = {
      url = "${base}/dcg-aarch64-unknown-linux-gnu.tar.xz";
      sha256 = "sha256-ZpZXjQZNh9ASAdh1btypaFBWXzBsEnXPf/sXu9GQTFQ=";
    };
    "x86_64-linux" = {
      url = "${base}/dcg-x86_64-unknown-linux-musl.tar.xz";
      sha256 = "sha256-57Ob4HCtmPdKHt1Z/vuKxBhlqyqixaQlLrccVBPz+d8=";
    };
  };

  versionInfo = lib.attrByPath [
    stdenv.hostPlatform.system
  ] (throw "dcg: unsupported platform ${stdenv.hostPlatform.system}") versions;
in
{
  dcg = stdenv.mkDerivation {
    pname = "dcg";
    inherit version;

    src = fetchurl { inherit (versionInfo) url sha256; };

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      install -m755 dcg $out/bin/dcg
    '';

    meta = with lib; {
      description = "Destructive Command Guard - multi-agent safety hook that blocks destructive shell commands";
      homepage = "https://github.com/Dicklesworthstone/destructive_command_guard";
      license = licenses.mit;
      platforms = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      mainProgram = "dcg";
    };
  };
}
