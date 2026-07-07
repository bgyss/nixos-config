# yt-dlp overlay – bump to latest version with yt-dlp-ejs 0.8.0 for YouTube challenge solving
final: prev: let
  # Bump yt-dlp-ejs to 0.8.0 (required by yt-dlp 2026.06.09)
  yt-dlp-ejs = prev.python313Packages.yt-dlp-ejs.overridePythonAttrs (old: rec {
    version = "0.8.0";
    src = prev.fetchPypi {
      pname = "yt_dlp_ejs";
      inherit version;
      hash = "sha256-1foWOfY7XEr42TJJX2BonVNw8aCVeCyUT39iowPrEE4=";
    };
  });
in {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: rec {
    version = "2026.07.04";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      tag = version;
      hash = "sha256-+oHcVylLXFJTRR6jXF6IXvgntXJz0tRdtnwTruRPkoc=";
    };
    # Replace yt-dlp-ejs 0.3.2 with 0.8.0 for YouTube challenge solving
    dependencies = builtins.filter (dep: (dep.pname or "") != "yt-dlp-ejs") (old.dependencies or []) ++ [ yt-dlp-ejs ];
    # Update postPatch for new curl_cffi version check pattern (0, 16) instead of (0, 15)
    postPatch = ''
      substituteInPlace yt_dlp/version.py \
        --replace-fail "UPDATE_HINT = None" 'UPDATE_HINT = "Nixpkgs/NixOS likely already contain an updated version.\n       To get it run nix-channel --update or nix flake update in your config directory."'
      # yt-dlp 2026.06.09 supports curl-cffi up to 0.15.x (< 0.16)
      substituteInPlace yt_dlp/networking/_curlcffi.py \
        --replace-fail "if curl_cffi_version != (0, 5, 10) and not (0, 10) <= curl_cffi_version < (0, 16)" \
        "if curl_cffi_version != (0, 5, 10) and not (0, 10) <= curl_cffi_version"
      # deno is required for full YouTube support
      substituteInPlace yt_dlp/utils/_jsruntime.py \
        --replace-fail "path = _determine_runtime_path(self._path, 'deno')" "path = '${prev.deno}/bin/deno'"
    '';
  });
}
