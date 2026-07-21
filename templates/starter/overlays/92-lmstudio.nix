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
        cp -r *.app $out/Applications

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
