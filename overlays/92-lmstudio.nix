# lmstudio overlay – fix codesign --deep deprecation on newer macOS
# Skip re-signing since sigtool's codesign can't handle complex bundles
# and the app works fine with ad-hoc signature from /usr/bin/codesign
final: prev:

if prev.stdenv.hostPlatform.system == "aarch64-darwin" then
  {
    lmstudio = prev.lmstudio.overrideAttrs (old: {
      # Remove sigtool from nativeBuildInputs - we'll use system codesign
      nativeBuildInputs = prev.lib.filter (p: p.pname or "" != "sigtool") (old.nativeBuildInputs or [ ]);

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications
        # The bundle sits at the source root on the pinned nixpkgs (hdiutil
        # unpackCmd) but one level down on newer nixpkgs (7zz unpacks the DMG
        # into a "LM Studio <version>/" volume directory). Accept both: a bare
        # `cp -r *.app` failed on the newer layout, which was what kept the
        # weekly nixpkgs unpin probe from ever passing.
        find . -maxdepth 2 -name '*.app' -prune -exec cp -R {} $out/Applications/ \;
        [ -d "$out/Applications/LM Studio.app" ] || {
          echo "LM Studio.app not found in the unpacked DMG" >&2
          exit 1
        }

        # Bypass the /Applications path check in the main index.js
        local indexJs="$out/Applications/LM Studio.app/Contents/Resources/app/.webpack/main/index.js"
        substituteInPlace "$indexJs" --replace-quiet "'/Applications'" "'/'"

        # Re-sign the app bundle using system codesign with --deep
        /usr/bin/codesign --force --deep --sign - "$out/Applications/LM Studio.app"

        runHook postInstall
      '';
    });
  }
else
  { }
