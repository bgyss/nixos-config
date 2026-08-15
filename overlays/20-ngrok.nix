# ngrok overlay – bump to 3.39.11 until nixpkgs catches up

final: prev:

let
  inherit (prev)
    fetchurl
    lib
    stdenv
    unzip
    ;

  versions = {
    "linux-386" = {
      version = "3.39.11";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-reDZ/AabmQ0BA7uHYA1pkx2FyxO7aNlKTfy2uK1U1xQ=";
    };
    "linux-amd64" = {
      version = "3.39.11";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-zsC0mX/MX1Kd/HS6yJBQNU0RqRX5aHIGAAOXOP3zMM8=";
    };
    "linux-arm" = {
      version = "3.39.11";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-Os5R7VfRjrjTVARykSFlTqoZrhp/0sNx65kcrBHA6ts=";
    };
    "linux-arm64" = {
      version = "3.39.11";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-O2ugWp2VhcNBV/oIGfqVzbE4OfW1BrnmMgRwXPf3nik=";
    };
    "darwin-amd64" = {
      version = "3.39.11";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-xrmz2RhPwIwz+4sYHZ8kHY9dYRYqC+BSG238HxGBOpY=";
    };
    "darwin-arm64" = {
      version = "3.39.11";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-kySmVS104l1b39vtxLMkIslvBE/aN4d0mK2O8Qvd9/c=";
    };
  };

  arch =
    if stdenv.hostPlatform.isi686 then
      "386"
    else if stdenv.hostPlatform.isx86_64 then
      "amd64"
    else if stdenv.hostPlatform.isAarch32 then
      "arm"
    else if stdenv.hostPlatform.isAarch64 then
      "arm64"
    else
      throw "ngrok: unsupported architecture ${stdenv.hostPlatform.system}";

  os =
    if stdenv.hostPlatform.isLinux then
      "linux"
    else if stdenv.hostPlatform.isDarwin then
      "darwin"
    else
      throw "ngrok: unsupported OS ${stdenv.hostPlatform.system}";

  versionInfo = lib.attrByPath [
    "${os}-${arch}"
  ] (throw "ngrok: unsupported platform ${os}-${arch}") versions;

  isZip = lib.hasSuffix ".zip" versionInfo.url;
in
{
  # nixpkgs' own by-name/ng/ngrok derivation pins bin.ngrok.com URLs that
  # serve a RAW binary (no extension), so its unpackPhase is just
  # `cp $src ngrok`. This overlay pins the older bin.equinox.io CDN instead
  # (see the header comment), whose URLs are REAL .tgz/.zip archives — so
  # inheriting that `cp`-only unpackPhase installed the archive itself as
  # "ngrok", producing an unexecutable zip/tar blob (`ngrok version` fails
  # with "Exec format error"). Both formats extract to a flat top-level
  # `ngrok` file (verified: `unzip -l` on the darwin-arm64 .zip shows a
  # single `ngrok` entry, no subdirectory), so replacing just the unpack
  # step — while keeping the parent's buildPhase (chmod +x) and installPhase
  # (install -D ngrok $out/bin/ngrok) — is enough; no hash changes needed.
  ngrok = prev.ngrok.overrideAttrs (old: {
    inherit (versionInfo) version;
    src = fetchurl { inherit (versionInfo) url sha256; };
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ lib.optionals isZip [ unzip ];
    unpackPhase = ''
      runHook preUnpack
      if [[ "$src" == *.zip ]]; then
        unzip -q "$src"
      else
        tar xzf "$src"
      fi
      runHook postUnpack
    '';
  });
}
