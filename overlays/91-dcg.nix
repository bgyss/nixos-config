# destructive_command_guard (dcg) – prebuilt binary, no nixpkgs package exists
# https://github.com/Dicklesworthstone/destructive_command_guard

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "0.9.2";
  base = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${version}";

  versions = {
    "aarch64-darwin" = {
      url = "${base}/dcg-aarch64-apple-darwin.tar.xz";
      sha256 = "sha256-0TbHT4IWoaM/XgqcolKO3lmQVUr5Eprg8NoV4L6ZHrg=";
    };
    "x86_64-darwin" = {
      url = "${base}/dcg-x86_64-apple-darwin.tar.xz";
      sha256 = "sha256-rFJvHTjOI7AECIr3BfUt4r2/vfwWxqqOJUioqGmFyhw=";
    };
    "aarch64-linux" = {
      url = "${base}/dcg-aarch64-unknown-linux-gnu.tar.xz";
      sha256 = "sha256-LDOAkRDRskZ7v2lrXmIw0ke77OP0ltX5NKZmbcKx+sE=";
    };
    "x86_64-linux" = {
      url = "${base}/dcg-x86_64-unknown-linux-musl.tar.xz";
      sha256 = "sha256-yJ1YqEQuniTMG3fhxTXsvGmdjuKPIXvKl4qsP0ZfYSE=";
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
