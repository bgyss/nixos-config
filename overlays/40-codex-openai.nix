final: prev: {
  codex-openai = prev.stdenvNoCC.mkDerivation rec {
    pname = "codex-openai";
    version = "0.72.0";

    src = prev.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-aarch64-apple-darwin.tar.gz";
      sha256 = "1y3smjqwj3cmvzn81wcr5c2c8d0f7jb02b4cwvbmf2h53y3vdizr";
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
