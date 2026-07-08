# uv overlay – use prebuilt binary on aarch64-darwin, nixpkgs elsewhere

final: prev:

if prev.stdenv.hostPlatform.system == "aarch64-darwin" then {
  uv = prev.stdenvNoCC.mkDerivation rec {
    pname = "uv";
    version = "0.11.28";

    src = prev.fetchurl {
      url = "https://github.com/astral-sh/uv/releases/download/${version}/uv-aarch64-apple-darwin.tar.gz";
      sha256 = "sha256-M1QOt8iDq4V+/3m9WsKqMf4ntZWr7LSpwAOiyZhEcjI=";
    };

    sourceRoot = "uv-aarch64-apple-darwin";

    dontConfigure = true;
    dontBuild = true;
    dontPatch = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      install -m755 uv $out/bin/uv
      install -m755 uvx $out/bin/uvx
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "An extremely fast Python package installer and resolver, written in Rust";
      homepage = "https://github.com/astral-sh/uv";
      license = with licenses; [ mit asl20 ];
      platforms = [ "aarch64-darwin" ];
      mainProgram = "uv";
    };
  };
}
else {}
