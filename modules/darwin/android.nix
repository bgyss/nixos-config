{ pkgs }:

let
  # Version pins checked against pkgs/development/mobile/androidenv/repo.json for the
  # pinned nixpkgs (2026-09) — bump these together with a repo.json re-check, since an
  # unlisted version string fails eval with a missing-attribute error rather than a
  # helpful "version not found" message.
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    cmdLineToolsVersion = "19.0";
    platformToolsVersion = "36.0.2";
    platformVersions = [
      "36"
      "35"
    ];
    buildToolsVersions = [ "36.1.0" ];
    includeEmulator = true;
    emulatorVersion = "36.4.2";
    includeSystemImages = true;
    # arm64-v8a is the only system image that runs natively (no emulation-of-emulation
    # penalty) on Apple Silicon; x86_64 images exist upstream but are unusably slow here.
    systemImageTypes = [ "google_apis_playstore" ];
    abiVersions = [ "arm64-v8a" ];
    includeNDK = true;
    ndkVersion = "27.0.12077973";
    includeSources = false;
    includeExtras = [ "extras;google;gcm" ];
  };

  sdkRoot = "${androidComposition.androidsdk}/libexec/android-sdk";
in
{
  # home.packages entry: a single derivation containing the full composed SDK
  # (platform-tools, build-tools, emulator, platforms, system images, NDK).
  package = androidComposition.androidsdk;

  sessionVariables = {
    ANDROID_HOME = sdkRoot;
    ANDROID_SDK_ROOT = sdkRoot;
    ANDROID_NDK_ROOT = "${sdkRoot}/ndk/27.0.12077973";
  };

  sessionPath = [
    "${sdkRoot}/cmdline-tools/latest/bin"
    "${sdkRoot}/platform-tools"
    "${sdkRoot}/emulator"
  ];
}
