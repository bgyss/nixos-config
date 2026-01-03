# svg-term-cli overlay - terminal recording to SVG animation

final: prev:

let
  inherit (prev) fetchFromGitHub lib stdenv buildNpmPackage;
  nodejs = prev.nodejs_16;

in {
  svg-term-cli = buildNpmPackage rec {
    pname = "svg-term-cli";
    version = "2.1.1";

    src = fetchFromGitHub {
      owner = "marionebl";
      repo = "svg-term-cli";
      rev = "v${version}";
      sha256 = "sha256-sB4/SM48UmqaYKj6kzfjzITroL0l/QL4Gg5GSrQ+pdk=";
    };

    npmDepsHash = "sha256-7AT5HktW3YnCEhgDjwrsmEQGczbjsNSfRD49zX4+5R4=";

    makeCacheWritable = true;
    npmFlags = [ "--legacy-peer-deps" ];
    dontNpmBuild = true;

    postPatch = ''
      cp ${./package-lock.json} package-lock.json
    '';

    meta = with lib; {
      description = "Terminal recording to SVG animation";
      homepage = "https://github.com/marionebl/svg-term-cli";
      license = licenses.mit;
      maintainers = with maintainers; [ ];
      platforms = platforms.unix;
    };
  };
}
