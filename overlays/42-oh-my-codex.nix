final: prev:

let
  inherit (prev) fetchurl lib buildNpmPackage;
  nodejs = prev.nodejs;
  version = "0.11.11";

in {
  oh-my-codex = buildNpmPackage {
    pname = "oh-my-codex";
    inherit version nodejs;

    src = fetchurl {
      url = "https://registry.npmjs.org/oh-my-codex/-/oh-my-codex-${version}.tgz";
      hash = "sha256-ciWh7CdlU9lA7T1joeMG4QKShUqWA+IdCf8XxDQgRQo=";
    };

    sourceRoot = "package";

    npmDepsHash = "sha256-yhb0X+oU/wRE2Z5QydI3mhfUCDgUUygihQUGQaiB8Fo=";

    npmInstallFlags = [ "--omit=dev" "--legacy-peer-deps" ];
    npmFlags = [ "--ignore-scripts" ];
    dontNpmBuild = true;
    dontNpmPrune = true;

    postPatch = ''
      cp ${./oh-my-codex-package-lock.json} package-lock.json
      ${prev.lib.getExe prev.jq} 'del(.scripts.prepack, .scripts.postpack, .scripts.prepare)' package.json > package.json.tmp
      mv package.json.tmp package.json
    '';

    meta = with lib; {
      description = "OMX - workflow layer for OpenAI Codex CLI";
      homepage = "https://github.com/Yeachan-Heo/oh-my-codex";
      license = licenses.mit;
      platforms = platforms.unix;
      mainProgram = "omx";
    };
  };
}
