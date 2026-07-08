# go overlay – bump to 1.26.5 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl lib stdenv;

  version = "1.26.5";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-77h/8or5oYjQU2711C5j3VK6gmPNc0Spk8xI3RHe22o=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-YjHY07j1VS7Gy/bWhb3VSC4ecDIUsSDomzvw178e9yU=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-XCw7FsrvodloqUwdrKBKfKMBpJbZsIbhetd7uBOT8FM=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-/keJ6SsfMzWGgIZLvocEKJ57tfwgfYBiPDCJNb1pbUk=";
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
