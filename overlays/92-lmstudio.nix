# lmstudio overlay – fix codesign --deep deprecation on newer macOS
final: prev:

if prev.stdenv.hostPlatform.system == "aarch64-darwin" then {
  lmstudio = prev.lmstudio.overrideAttrs (old: {
    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications
      cp -r *.app $out/Applications

      # Bypass the /Applications path check in the main index.js
      local indexJs="$out/Applications/LM Studio.app/Contents/Resources/app/.webpack/main/index.js"
      substituteInPlace "$indexJs" --replace-quiet "'/Applications'" "'/'"

      # Re-sign the app bundle after patching (without --deep which is deprecated)
      codesign --force --sign - "$out/Applications/LM Studio.app"

      runHook postInstall
    '';
  });
}
else {}
