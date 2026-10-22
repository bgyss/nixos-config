# ngrok overlay – bump to 3.39.12 until nixpkgs catches up

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
      version = "3.39.12";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-386.tgz";
      sha256 = "sha256-JGYZ68UuessiMqwEoSBkLcAIia+XiGp2c1yQLDC2MlI=";
    };
    "linux-amd64" = {
      version = "3.39.12";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
      sha256 = "sha256-AfeXSbx1JzoMY0xZ7sTmI1w6tyZtW8agLLrGx/5kcrA=";
    };
    "linux-arm" = {
      version = "3.39.12";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz";
      sha256 = "sha256-fIrIJdMdoQBdY0+RMP11EqL0qy0Ttj7uDtEtxqFucn0=";
    };
    "linux-arm64" = {
      version = "3.39.12";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
      sha256 = "sha256-mK26xIeETgAiOyPJb2gx3T9iELKwRreOeKe9NLwKxzQ=";
    };
    "darwin-amd64" = {
      version = "3.39.12";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip";
      sha256 = "sha256-85OuZy5buBE1UFqm+ZM6ilK3ixJ4ZDx1iSfSiT4TqoQ=";
    };
    "darwin-arm64" = {
      version = "3.39.12";
      url = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip";
      sha256 = "sha256-xJfnP+iT/3WcVOSBkWSfbE3EL04N/UjdSNXHgTUBaDg=";
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
