final: prev: {
  codex-openai = prev.stdenvNoCC.mkDerivation rec {
    pname = "codex-openai";
    version = "0.165.0";

    src = prev.fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-aarch64-apple-darwin.tar.gz";
      hash = "sha256-NNEjhNkPjgmwuauqvyoKwCpSCTsTFQSuryghB/VKRLI=";
    };

    # Official packaged layout (codex-package.json, bin/, codex-resources/, codex-path/).
    # Codex >= 0.165 requires it intact for the app-server daemon that Rex starts;
    # the bare binary fails with "this CLI has no complete local package".
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true; # leave the signed Mach-O binaries untouched

    sourceRoot = ".";

    installPhase = ''
      mkdir -p "$out/bin" "$out/libexec/codex"
      cp -R bin codex-package.json codex-path codex-resources "$out/libexec/codex/"
      ln -s "$out/libexec/codex/bin/codex" "$out/bin/codex"
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
