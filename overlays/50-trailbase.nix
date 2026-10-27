# trailbase overlay – ship upstream release binaries (v0.31.0)

final: prev:

let
  inherit (prev)
    autoPatchelfHook
    fetchurl
    lib
    stdenv
    stdenvNoCC
    unzip
    ;

  version = "0.35.5";
  sources = {
    "aarch64-darwin" = {
      url = "https://github.com/trailbaseio/trailbase/releases/download/v${version}/trailbase_v${version}_aarch64_apple_darwin.zip";
      hash = "sha256-I7vGnw/77n28f1md+QB2NJ/BwBRTKzbAFSpJcQ0ANIc=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/trailbaseio/trailbase/releases/download/v${version}/trailbase_v${version}_x86_64_apple_darwin.zip";
      hash = "sha256-+zXj6dp9QT/dFlOfjP+2zMDSi1eJqGiLEIRTq/2V9sA=";
    };
    "x86_64-linux" = {
      url = "https://github.com/trailbaseio/trailbase/releases/download/v${version}/trailbase_v${version}_x86_64_linux.zip";
      hash = "sha256-HG9jhqwkwYT0iSnVgS7elxIT88QUFhDWRpCMLIq0Gs0=";
    };
  };

  source = lib.attrByPath [ stdenv.hostPlatform.system ] null sources;
in
if source == null then
  { }
else
  {
    trailbase = stdenvNoCC.mkDerivation {
      pname = "trailbase";
      inherit version;
      src = fetchurl source;

      nativeBuildInputs = [ unzip ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
      buildInputs = lib.optionals stdenv.isLinux [
        stdenv.cc.cc.lib
        stdenv.cc.libc
      ];

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontPatch = true;
      dontStrip = true;

      installPhase = ''
        runHook preInstall

        workdir="$TMPDIR/trailbase"
        mkdir -p "$workdir"

        unzip -j "$src" trail LICENSE CHANGELOG.md -d "$workdir"

        mkdir -p "$out/bin" "$out/share/doc/trailbase"
        install -m755 "$workdir/trail" "$out/bin/trail"
        install -m644 "$workdir/LICENSE" "$out/share/doc/trailbase/LICENSE"
        install -m644 "$workdir/CHANGELOG.md" "$out/share/doc/trailbase/CHANGELOG.md"

        runHook postInstall
      '';

      meta = with lib; {
        description = "Composable backend for building data applications (prebuilt binary)";
        homepage = "https://github.com/trailbaseio/trailbase";
        license = licenses.osl3;
        mainProgram = "trail";
        platforms = builtins.attrNames sources;
        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      };
    };
  }
