# ccusage overlay – fetch pre-built npm tarball to avoid network in Nix sandbox

final: prev:

let
  inherit (final) stdenv lib fetchurl nodejs makeWrapper;
  version = "15.2.0";
  src = fetchurl {
    url = "https://registry.npmjs.org/ccusage/-/ccusage-${version}.tgz";
    sha256 = "0cz0d84pjlkqvq7625a53in1d9c81mfm8gcz59ifqdw64xclgi5c";
  };
in {
  ccusage = stdenv.mkDerivation {
    pname = "ccusage";
    inherit version src;

    nativeBuildInputs = [ nodejs makeWrapper ];

    unpackPhase = ''
      tar -xzf $src --strip-components=1
    '';

    installPhase = ''
      mkdir -p $out/lib/node_modules/ccusage
      cp -R * $out/lib/node_modules/ccusage
      mkdir -p $out/bin
      makeWrapper ${nodejs}/bin/node $out/bin/ccusage \
        --add-flags "$out/lib/node_modules/ccusage/dist/index.js"
    '';

    meta = with lib; {
      description = "CLI tool for analyzing Claude Code usage";
      homepage    = "https://github.com/ryoppippi/ccusage";
      license     = licenses.mit;
      platforms   = platforms.all;
    };
  };
}