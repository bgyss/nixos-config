# go overlay – bump to 1.25.6 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "1.25.6";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-mEUhrpeKU3fH14L9LdlTKRhA19PQvZV4Gh8y8W2UoAY=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-ZoXpJo2pU/CzOyGxD2A/+nkta1xgkh3tWLZv+DaRnPw=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-VZbvo2iYTA2BvnVEWALF6B6cnc+MAx7wMgx4mxQV3/o=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-k7IHU8orGY/gkxHpG5InxQ4BAf46tmObuMkWbt8WyX4=";
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
