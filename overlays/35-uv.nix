# uv overlay - override to version 0.8.22

final: prev:

{
  uv = prev.uv.overrideAttrs (oldAttrs: rec {
    version = "0.8.22";

    src = final.fetchFromGitHub {
      owner = "astral-sh";
      repo = "uv";
      rev = version;
      hash = "sha256-7/WOjsyfkDTZLNJY0+rNdRUmMabJsSFvKi2yh/WqViQ=";
    };
    
    cargoDeps = prev.rustPlatform.importCargoLock {
      lockFile = "${src}/Cargo.lock";
      outputHashes = {
        "async_zip-0.0.17" = "sha256-gkpyrCvEQyKur5jmyZhbgMsMrzX8j6goNRoi+c+WN2M=";
        "pubgrub-0.3.0" = "sha256-6A3XWOIYOSnQCz80yPGrcCeH3r/9BxX80+58Y0Hgzlg=";
        "reqwest-middleware-0.4.2" = "sha256-GZorxPq1rWu7guTuq72PgNVwsZxGk23sbCZ4UewRKBE=";
        "tl-0.7.8" = "sha256-F06zVeSZA4adT6AzLzz1i9uxpI1b8P1h+05fFfjm3GQ=";
      };
    };
  });
}