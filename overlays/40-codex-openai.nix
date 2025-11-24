final: prev: {
  codex-openai = prev.stdenvNoCC.mkDerivation rec {
    pname = "codex-openai";
    version = "0.63.0";

    src = prev.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v0.63.0/codex-aarch64-apple-darwin.tar.gz";
      sha256 = "11hygrmaa2zv33l5444xgm47vsk7pgrpkjzwvx667i9jw67nr9m7";
    };

    # It's a prebuilt binary tarball
    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      tar -xzf "$src"
    '';

    installPhase = ''
      mkdir -p "$out/bin"
      # The archive contains a binary named 'codex-aarch64-apple-darwin'
      install -m755 codex-aarch64-apple-darwin "$out/bin/codex"
    '';

    meta = with prev.lib; {
      description = "OpenAI Codex CLI (prebuilt binary)";
      homepage = "https://github.com/openai/codex";
      license = licenses.mit;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "codex";
    };
  };
}
