final: prev:

let
  inherit (final) lib stdenvNoCC fetchurl;

  version = "5.3.0";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-macOS-arm64.tar.gz";
      hash = "sha256-yEowT3oCwhQjMP9TUe9VhWM5AXNMwzyd8iMKTagWCP8=";
    };
    x86_64-darwin = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-macOS-x64.tar.gz";
      hash = "sha256-b7jiMJQQCvR/flp0m7MtkcNzetbckkUg8R7S2tXtJ+s=";
    };
    aarch64-linux = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-Linux-arm64v8.tar.gz";
      hash = "sha256-6AxPNDS4HwnM1dbm/R7e7ZlRcCcGaWvtYwsMtktN1Bw=";
    };
    x86_64-linux = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-Linux-amd64.tar.gz";
      hash = "sha256-rCaU+yPlJs+2JRK5I1ncppFrkWej+6uJ+N+StU6le5s=";
    };
  };

  system = final.stdenv.hostPlatform.system;
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
      platforms = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
    };
  };

in {
  igir = if source == null then prev.igir else igirPrebuilt;
}
