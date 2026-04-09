# go overlay – bump to 1.25.9 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "1.25.9";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-lSi+cym5dwYxpr0Jyi86c+1zMr7AHYdDXnXpLY8TA2M=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-kst4+6R5biGMGsyw6gohTvIJTDggSaJErWUFUF0BX74=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-AIWde9be/ov4TZ255XuaRGeyiHwYzZOudGDnE9t3S8E=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-7DQuc4m39IlWTtVGPGOxbPgEACPavHhhJWZ3FlqMDis=";
    };
  };

  source = sources.${stdenv.hostPlatform.system} or null;

in
if source == null then
  { }
else
  {
    go_1_25 = prev.go_1_25.overrideAttrs (old: {
      inherit version;
      src = fetchurl {
        inherit (source) url hash;
      };
    });

    # Override the default 'go' package
    go = final.go_1_25;

    # Override buildGoModule to use the new Go version
    buildGoModule = prev.buildGoModule.override {
      go = final.go_1_25;
    };
  }
