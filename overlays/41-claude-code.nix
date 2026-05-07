final: prev: {
  claude-code = prev.stdenvNoCC.mkDerivation rec {
    pname = "claude-code";
    version = "2.1.132";

    src = prev.fetchurl {
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/darwin-arm64/claude";
      hash = "sha256-LOa5AH849crw0RauNdWfGm1A6QKuf58ZrKbsSDaXt2Q=";
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p "$out/bin"
      install -m755 "$src" "$out/bin/claude"
    '';

    meta = with prev.lib; {
      description = "Claude Code - agentic coding tool (native binary)";
      homepage = "https://github.com/anthropics/claude-code";
      license = licenses.unfree;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "claude";
    };
  };
}
