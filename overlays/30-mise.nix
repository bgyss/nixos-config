# mise overlay – ship upstream release binaries (v2026.6.10)
#
# Previously built from source via fetchCargoVendor, but crates.io now returns
# HTTP 403 for the default `python-requests` User-Agent used by nixpkgs'
# fetch-cargo-vendor-util, breaking the vendor step. Using the published
# prebuilt binaries sidesteps crates.io entirely (and is much faster to build).

final: prev:

let
  inherit (prev) autoPatchelfHook fetchurl gzip lib stdenv stdenvNoCC;

  version = "2026.6.14";
  sources = {
    "aarch64-darwin" = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-macos-arm64.tar.gz";
      hash = "sha256-bY04m9cp9cRAlKXY6d9cQQrPQwTiVA63mkhUvdItCpE=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-macos-x64.tar.gz";
      hash = "sha256-2o+IcrqWLWiT8Lq2i1qJTKopbx0XwoUMpAdplEG0SyY=";
    };
    "aarch64-linux" = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-arm64.tar.gz";
      hash = "sha256-bXG6AfILt8x7//rFIU6eeIoI+lF8B165VaWzHcpmfKc=";
    };
    "x86_64-linux" = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-x64.tar.gz";
      hash = "sha256-xbtFRrotUVTpyCNuJ3S9gom2TECTMO1By21rjrwx+1Y=";
    };
  };

  source = lib.attrByPath [ stdenv.hostPlatform.system ] null sources;
in
if source == null then
  { }
else
  {
    mise = stdenvNoCC.mkDerivation {
      pname = "mise";
      inherit version;
      src = fetchurl source;

      nativeBuildInputs = [ gzip ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
      buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib stdenv.cc.libc ];

      dontConfigure = true;
      dontBuild = true;
      dontPatch = true;
      dontStrip = true;

      # Tarball unpacks to a top-level `mise/` directory.
      sourceRoot = "mise";

      installPhase = ''
        runHook preInstall

        install -Dm755 bin/mise "$out/bin/mise"
        install -Dm644 man/man1/mise.1 "$out/share/man/man1/mise.1"
        install -Dm644 LICENSE "$out/share/doc/mise/LICENSE"

        runHook postInstall
      '';

      meta = with lib; {
        description = "Polyglot dev tool & runtime version manager (prebuilt binary)";
        homepage = "https://github.com/jdx/mise";
        license = licenses.mit;
        mainProgram = "mise";
        platforms = builtins.attrNames sources;
        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      };
    };
  }
