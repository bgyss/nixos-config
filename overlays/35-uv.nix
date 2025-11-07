# uv overlay – try release tarball for aarch64-darwin while keeping source build elsewhere

final: prev:

let
  inherit (final) fetchFromGitHub fetchurl stdenvNoCC;
  version = "0.8.23";

  uvSource = prev.uv.overrideAttrs (_old: rec {
    inherit version;

    src = fetchFromGitHub {
      owner = "astral-sh";
      repo = "uv";
      rev = version;
      hash = "sha256-I0Oe6vaH7iQh+Ubp5RIk8Ol6Ni7OPu8HKX0fqLdewyk=";
    };

    cargoDeps = prev.rustPlatform.importCargoLock {
      lockFile = "${src}/Cargo.lock";
      outputHashes = {
        "async_zip-0.0.17" = "sha256-gkpyrCvEQyKur5jmyZhbgMsMrzX8j6goNRoi+c+WN2M=";
        "pubgrub-0.3.0" = "sha256-6A3XWOIYOSnQCz80yPGrcCeH3r/9BxX80+58Y0Hgzlg=";
        "reqwest-middleware-0.4.2" = "sha256-GZorxPq1rWu7guTuq72PgNVwsZxGk23sbCZ4UewRKBE=";
        "tl-0.7.8" = "sha256-F06zVeSZA4adT6AzLzz1i9uxpI1b8P1h+05fFfjm3GQ=";
      };
    };

    # Use the same build system as the original package
    cargoRoot = "uv";
    useNextest = true;
  });

  uvDarwinBinary = stdenvNoCC.mkDerivation rec {
    pname = "uv";
    inherit version;

    src = fetchurl {
      url = "https://github.com/astral-sh/uv/releases/download/${version}/uv-aarch64-apple-darwin.tar.gz";
      sha256 = "sha256-NVcrlhn8FNZ/wc1yWCw8/FycZtl/MQGS4E8m+z/pYAU=";
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

    meta = uvSource.meta // {
      platforms = [ "aarch64-darwin" ];
    };
  };
in {
  uv = if prev.stdenv.hostPlatform.system == "aarch64-darwin" then uvDarwinBinary else uvSource;
}
