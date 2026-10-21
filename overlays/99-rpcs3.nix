# rpcs3 overlay – nixpkgs only builds rpcs3 on Linux, so repackage the official macOS arm64
# build from RPCS3/rpcs3-binaries-mac. Version bumps are manual: see docs/overlay-update-routine.md.
final: prev:

if prev.stdenv.hostPlatform.isDarwin then
  let
    version = "0.0.43-20291";
    rev = "ffba2bf09ef3980638f9327b25240d81414034ab";
  in
  {
    rpcs3 = prev.stdenvNoCC.mkDerivation {
      pname = "rpcs3";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/RPCS3/rpcs3-binaries-mac/releases/download/build-${rev}/rpcs3-v${version}-${builtins.substring 0 8 rev}_macos.7z";
        hash = "sha256-gnkEp9tJIfzVqy34ix99131yKwzay7vo3xFniFYdbLE=";
      };

      nativeBuildInputs = [ prev.p7zip ];
      sourceRoot = ".";
      unpackPhase = "7z x $src";
      dontFixup = true; # keep the upstream signature intact

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications
        cp -r RPCS3.app $out/Applications
        runHook postInstall
      '';

      meta = {
        description = "PlayStation 3 emulator (prebuilt macOS arm64 build)";
        homepage = "https://rpcs3.net/";
        license = prev.lib.licenses.gpl2Only;
        platforms = [ "aarch64-darwin" ];
        sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
        mainProgram = "rpcs3";
      };
    };
  }
else
  { }
