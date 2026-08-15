# go overlay – bump to 1.26.5 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl stdenv;

  version = "1.26.6";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-Lclc5GdYKfLfDoayi87zKDY1kCBipfBYDKZZv1cPMgQ=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-CLZaY/JEEVEhztbDtVrTjYAadEKsrVyUmheq2Erm1oQ=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-cI7/t3S+gjdXDQrdFjIlq7369PyiiyYR3xZ766T+74k=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-0FB+np1/4BKq5XAQjL12wV3oeeFxMKuMuQ1NdEXLHy4=";
    };
  };

  source = sources.${stdenv.hostPlatform.system} or null;

in
if source == null then
  { }
else
  {
    go_1_26 = prev.go_1_26.overrideAttrs (old: {
      inherit version;
      src = fetchurl {
        inherit (source) url hash;
      };
    });

    # Override the default 'go' package
    go = final.go_1_26;

    # Override buildGoModule to use the new Go version
    buildGoModule = prev.buildGoModule.override {
      go = final.go_1_26;
    };
  }
