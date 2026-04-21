final: prev:

let
  inherit (final) lib stdenvNoCC fetchurl;

  version = "5.0.0";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-macOS-arm64.tar.gz";
      hash = "sha256-m0zO3/UylY4EgXJQqvy1CwYc16E0h2kMag0JPffRNN0=";
    };
    x86_64-darwin = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-macOS-x64.tar.gz";
      hash = "sha256-yOO3xhFjL9nnJcNY7NLANwe3HV6VJ8OvRoRiKuKyZWA=";
    };
    aarch64-linux = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-Linux-arm64v8.tar.gz";
      hash = "sha256-e11rcbG31G5+9MEVMnknx9Z3jDMisZ6wejdqHL2Z7w0=";
    };
    x86_64-linux = {
      url = "https://github.com/emmercm/igir/releases/download/v${version}/igir-${version}-Linux-amd64.tar.gz";
      hash = "sha256-1irk5YuWI3EzU4sMiUpmfJ4ZtKJId3jIxlQpl8T2Vlk=";
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
