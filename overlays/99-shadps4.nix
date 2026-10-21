# shadps4 overlay – nixpkgs only builds shadps4 on x86_64-linux, so repackage the official macOS
# SDL build (a bare binary plus bundled MoltenVK-alternative Vulkan dylibs, no .app).
# Version bumps are manual: see docs/overlay-update-routine.md.
final: prev:

if prev.stdenv.hostPlatform.isDarwin then
  let
    version = "0.20.0";
  in
  {
    shadps4 = prev.stdenvNoCC.mkDerivation {
      pname = "shadps4";
      inherit version;

      src = prev.fetchurl {
        url = "https://github.com/shadps4-emu/shadPS4/releases/download/v.${version}/shadps4-macos-sdl-2026-${version}.zip";
        hash = "sha256-UKw7GPKtC1LdpOrpsvbFSkwmwEJcAMBTBz//TadNfGA=";
      };

      nativeBuildInputs = [ prev.unzip ];
      sourceRoot = ".";
      dontFixup = true; # keep the upstream signature intact

      # The binary finds its bundled libvulkan next to itself, so keep the files together in
      # libexec and expose a launcher that execs the real path (a symlink would break lookup).
      installPhase = ''
        runHook preInstall
        mkdir -p $out/libexec/shadps4 $out/bin
        cp -r . $out/libexec/shadps4
        chmod +x $out/libexec/shadps4/shadps4
        printf '#!/bin/sh\nexec %s/libexec/shadps4/shadps4 "$@"\n' "$out" > $out/bin/shadps4
        chmod +x $out/bin/shadps4
        runHook postInstall
      '';

      meta = {
        description = "PlayStation 4 emulator (prebuilt macOS SDL build)";
        homepage = "https://shadps4.net/";
        license = prev.lib.licenses.gpl2Only;
        platforms = [ "aarch64-darwin" ];
        sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
        mainProgram = "shadps4";
      };
    };
  }
else
  { }
