# go overlay – bump to 1.26.2 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "1.26.2";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-Mq8VIr8+P/OXWGR4CkKcwLQdGQ7Hv5D6pmHW1kVm568=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-vD8VANmWjDbXBUQtkLqRrd+ScWZQM3SLglMmgukKeWY=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-mQ5rS7uoFtw+4Snq6vS0LxfCgAuIohZsJlrBogAmIoI=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-yVih/hs2E5HbFjpIXiH18igULW+LWE9r74myb2bcWyM=";
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
