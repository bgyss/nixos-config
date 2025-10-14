# ccusage overlay – fetch pre-built npm tarball to avoid network in Nix sandbox

final: prev:

let
  inherit (final) stdenv lib fetchurl nodejs makeWrapper;
  version = "17.1.3";
  src = fetchurl {
    url = "https://registry.npmjs.org/ccusage/-/ccusage-${version}.tgz";
    sha256 = "0p14h8qcj5y2n6n1knhfjxgq8b786daj97qbs0cg89q4ajrlkbn8";
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