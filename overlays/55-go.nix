# go overlay – bump to 1.26.5 until nixpkgs catches up

final: prev:

let
  inherit (prev) fetchurl stdenv;

  version = "1.26.7";

  sources = {
    "aarch64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-arm64.tar.gz";
      hash = "sha256-AgoegiSBG+dRY+kgvHfgkmoTkKau6hm9zyP3S510n20=";
    };
    "x86_64-darwin" = {
      url = "https://go.dev/dl/go${version}.darwin-amd64.tar.gz";
      hash = "sha256-kuizS/88iasWQExZVmmsjLAEzC9nbcvR9bh6a43vO0c=";
    };
    "x86_64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-amd64.tar.gz";
      hash = "sha256-/7X43hDGJVDf3atms2tXAwch4KRKMhjp4Rgde1nxIco=";
    };
    "aarch64-linux" = {
      url = "https://go.dev/dl/go${version}.linux-arm64.tar.gz";
      hash = "sha256-Wk7IgzedUe6c4QQNXof4014gOHV03YyUf+sB6rw8Gzc=";
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
