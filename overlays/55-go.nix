# go overlay – bump to 1.25.7 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "1.25.7";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-/xg2n/rQXFfVvtiItmCzE4XzyRNnCoPvVXzf2Y6prhs=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-v1BQohUvQFODe4hujZZAyCnbrLwzcPkTNR6wkEy3BvU=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-EubWoZEJGuJ9wx9u/GMOOjuLpAm681c9lVsZb98IYAU=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-umEaU1NBNagQZyQO/5UIzX4lbFYO3V2ML+9U8IPAcSk=";
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
