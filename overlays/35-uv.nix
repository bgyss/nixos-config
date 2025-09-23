# uv overlay - override to version 0.8.13

final: prev:

{
  uv = prev.uv.overrideAttrs (oldAttrs: rec {
    version = "0.8.18";
    
    src = final.fetchFromGitHub {
      owner = "astral-sh";
      repo = "uv";
      rev = version;
      hash = "sha256-e6UrCx2QalJhi9aGHj1LRWFwZIQz/IQzn1haZXpXVr8=";
    };
    
    cargoDeps = prev.rustPlatform.importCargoLock {
      lockFile = "${src}/Cargo.lock";
      outputHashes = {
        "async_zip-0.0.17" = "sha256-gkpyrCvEQyKur5jmyZhbgMsMrzX8j6goNRoi+c+WN2M=";
        "pubgrub-0.3.0" = "sha256-yE846sfqNpOUNoHtoxkSiZ8tUCEFYbt9Lpat6OTd7oc=";
        "reqwest-middleware-0.4.2" = "sha256-GZorxPq1rWu7guTuq72PgNVwsZxGk23sbCZ4UewRKBE=";
        "tl-0.7.8" = "sha256-F06zVeSZA4adT6AzLzz1i9uxpI1b8P1h+05fFfjm3GQ=";
      };
    };
  });
}