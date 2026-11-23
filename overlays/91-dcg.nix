# destructive_command_guard (dcg) – prebuilt binary, no nixpkgs package exists
# https://github.com/Dicklesworthstone/destructive_command_guard

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "0.17.1";
  base = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${version}";

  versions = {
    "aarch64-darwin" = {
      url = "${base}/dcg-aarch64-apple-darwin.tar.xz";
      sha256 = "sha256-oJYpbPZOgTqCyRFxfJstSyUqeFg1OaxHJAFAnRa9m+k=";
    };
    "x86_64-darwin" = {
      url = "${base}/dcg-x86_64-apple-darwin.tar.xz";
      sha256 = "sha256-TVxd1Wg2zFi5DUCazuKqrkr6MnW/9sAQbIo43maUefM=";
    };
    "aarch64-linux" = {
      url = "${base}/dcg-aarch64-unknown-linux-gnu.tar.xz";
      sha256 = "sha256-y76UZAUkm8N22v3EHC2el8pfHqFagb8o6cAFPLCswVw=";
    };
    "x86_64-linux" = {
      url = "${base}/dcg-x86_64-unknown-linux-musl.tar.xz";
      sha256 = "sha256-NO3oN9XvA98f2YdpcYpvbqrK9vygHSRVKBVnzNLhr94=";
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
