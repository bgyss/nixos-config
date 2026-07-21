# svg-term-cli overlay - terminal recording to SVG animation

final: prev:

let
  inherit (prev) fetchurl lib buildNpmPackage;
  inherit (prev) nodejs;
  version = "2.1.1";

in
{
  svg-term-cli = buildNpmPackage {
    pname = "svg-term-cli";
    inherit version nodejs;

    src = fetchurl {
      url = "https://registry.npmjs.org/svg-term-cli/-/svg-term-cli-${version}.tgz";
      sha256 = "sha256-rmX5I0sxto7Rwnyijv9N3fWZJopY8itBUHEbws6Ueuw=";
    };

    sourceRoot = "package";

    npmDepsHash = "sha256-7AT5HktW3YnCEhgDjwrsmEQGczbjsNSfRD49zX4+5R4=";

    npmInstallFlags = [
      "--omit=dev"
      "--legacy-peer-deps"
    ];
    dontNpmBuild = true;
    dontNpmPrune = true;

    postPatch = ''
      cp ${./svg-term-cli-package-lock.json} package-lock.json
    '';

    meta = with lib; {
      description = "Terminal recording to SVG animation";
      homepage = "https://github.com/marionebl/svg-term-cli";
      license = licenses.mit;
      maintainers = with maintainers; [ ];
      platforms = platforms.unix;
      mainProgram = "svg-term";
    };
  };
}
