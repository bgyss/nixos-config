# go overlay – bump to 1.26.3 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "1.26.3";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-DlC/SLQju9nx7yuUAeZB9oWx1Yj+j/c3xm9haN7w9bU=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-jDVYt1zId7iBAfM62wN9oeWQV+h10GMjzoIyZMTbnNk=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-9mVlxqOCGfBun1+8RSroOnGR4sGBOwlQZungQdgCdYk=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-Vxj+jCTLCVhx8q/OwsoaGFWPGt5wgHCnSBQBMFORYRY=";
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
