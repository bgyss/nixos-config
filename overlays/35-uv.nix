# uv overlay - override to version 0.8.13

final: prev:

{
  uv = prev.uv.overrideAttrs (oldAttrs: rec {
    version = "0.8.13";
    
    src = final.fetchFromGitHub {
      owner = "astral-sh";
      repo = "uv";
      rev = version;
      hash = "sha256-U7Y3byjXxRpIZ2QS1QfZC51FF7PnyAKV0DKYC1LImzA=";
    };
    
    cargoDeps = prev.rustPlatform.importCargoLock {
      lockFile = "${src}/Cargo.lock";
      outputHashes = {
        "async_zip-0.0.17" = "sha256-gkpyrCvEQyKur5jmyZhbgMsMrzX8j6goNRoi+c+WN2M=";
        "pubgrub-0.3.0" = "sha256-yE846sfqNpOUNoHtoxkSiZ8tUCEFYbt9Lpat6OTd7oc=";
        "reqwest-middleware-0.4.2" = "sha256-0ugWuOPncxs+rw4Qas9u//M6DLLlaXzbTjzw34YJtIg=";
        "tl-0.7.8" = "sha256-F06zVeSZA4adT6AzLzz1i9uxpI1b8P1h+05fFfjm3GQ=";
      };
    };
  });
}