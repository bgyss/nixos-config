final: prev:

let
  inherit (final) lib stdenvNoCC fetchurl;

  version = "5.8.0";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-macOS-arm64.tar.gz";
      hash = "sha256-8UmB9MHdYTH2y1Fx0hCrnqpXyjWZtegElrvKrqUpul8=";
    };
    x86_64-darwin = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-macOS-x64.tar.gz";
      hash = "sha256-xe3SFvumSRwLZXZJv0gz5Uk1pSgyGMDQPRTkCZsUDxg=";
    };
    aarch64-linux = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-Linux-arm64v8.tar.gz";
      hash = "sha256-UEWD9WUgb5kDHyi7BmbeS4CssIfETEOP+pNjft2QfF0=";
    };
    x86_64-linux = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-Linux-amd64.tar.gz";
      hash = "sha256-Tq2Ww9aW/NVnCFiiQHy7bbCQs3ng7EVHE67Xj0vUznI=";
    };
  };

  inherit (final.stdenv.hostPlatform) system;
  source = sources.${system} or null;

  igirPrebuilt = stdenvNoCC.mkDerivation {
    pname = "igir";
    inherit version;

    src = fetchurl {
      inherit (source) url hash;
    };

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      tar -xzf "$src"
    '';

    installPhase = ''
      mkdir -p "$out/bin"

      bin=""
      if [ -f "igir" ]; then
        bin="igir"
      else
        bin="$(find . -maxdepth 3 -type f -name igir -print -quit)"
      fi

      if [ -z "$bin" ]; then
        echo "Could not find igir binary in archive" >&2
        find . -maxdepth 3 -type f -print >&2
        exit 1
      fi

      install -m755 "$bin" "$out/bin/igir"
    '';

    meta = with lib; {
      description = "Igir ROM collection manager (prebuilt release binary)";
      homepage = "https://github.com/emmercm/igir";
      license = licenses.mit;
      mainProgram = "igir";
      platforms = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  };

in
{
  igir = if source == null then prev.igir else igirPrebuilt;
}
