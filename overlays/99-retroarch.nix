# retroarch overlay – nixpkgs marks retroarch-bare broken on Darwin, so repackage the
# official universal Metal build from libretro's buildbot (replaces the Homebrew cask).
# Version bumps are manual: see docs/overlay-update-routine.md.
final: prev:

if prev.stdenv.hostPlatform.isDarwin then
  let
    version = "1.22.2";
  in
  {
    retroarch = prev.stdenvNoCC.mkDerivation {
      pname = "retroarch";
      inherit version;

      src = prev.fetchurl {
        url = "https://buildbot.libretro.com/stable/${version}/apple/osx/universal/RetroArch_Metal.dmg";
        hash = "sha256-gbeRIbom1TkGSuE7TQQZoSDD0WWvvmVs9fVBKxX9tDQ=";
      };

      nativeBuildInputs = [ prev.undmg ];
      sourceRoot = ".";
      dontFixup = true; # keep the upstream signature intact

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications
        cp -r *.app $out/Applications
        runHook postInstall
      '';

      meta = {
        description = "Frontend for emulators, game engines and media players (prebuilt Metal build)";
        homepage = "https://www.retroarch.com/";
        license = prev.lib.licenses.gpl3Plus;
        platforms = [ "aarch64-darwin" ];
        sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
      };
    };
  }
else
  { }
