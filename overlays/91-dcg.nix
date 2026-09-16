# destructive_command_guard (dcg) – prebuilt binary, no nixpkgs package exists
# https://github.com/Dicklesworthstone/destructive_command_guard

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "0.14.4";
  base = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${version}";

  versions = {
    "aarch64-darwin" = {
      url = "${base}/dcg-aarch64-apple-darwin.tar.xz";
      sha256 = "sha256-twT+AZC/7sUbwmSlc/o9YgWQKGsrK2OyyiKTqiSq0BM=";
    };
    "x86_64-darwin" = {
      url = "${base}/dcg-x86_64-apple-darwin.tar.xz";
      sha256 = "sha256-2bTi5WXx4YUwObfJVvpM51dse7ZBOC/kHsRKDeq7Xwc=";
    };
    "aarch64-linux" = {
      url = "${base}/dcg-aarch64-unknown-linux-gnu.tar.xz";
      sha256 = "sha256-DLak6FG7FiaAfhxfv9bVZSdTg6diQihnj4WFcL9Bbm8=";
    };
    "x86_64-linux" = {
      url = "${base}/dcg-x86_64-unknown-linux-musl.tar.xz";
      sha256 = "sha256-Cdr3ZeIUV6dW5pzJ+LzkFjWDbGuVj1snx6amo3bL3iE=";
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
