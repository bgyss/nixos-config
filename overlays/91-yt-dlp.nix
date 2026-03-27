# yt-dlp overlay – bump to latest version
final: prev: {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: rec {
    version = "2026.03.17";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      tag = version;
      hash = "sha256-A4LUCuKCjpVAOJ8jNoYaC3mRCiKH0/wtcsle0YfZyTA=";
    };
    # Update postPatch for new curl_cffi version check pattern (0, 15) instead of (0, 14)
    postPatch = ''
      substituteInPlace yt_dlp/version.py \
        --replace-fail "UPDATE_HINT = None" 'UPDATE_HINT = "Nixpkgs/NixOS likely already contain an updated version.\n       To get it run nix-channel --update or nix flake update in your config directory."'
      # yt-dlp 2026.03.17 supports curl-cffi up to 0.14.x (< 0.15)
      substituteInPlace yt_dlp/networking/_curlcffi.py \
        --replace-fail "if curl_cffi_version != (0, 5, 10) and not (0, 10) <= curl_cffi_version < (0, 15)" \
        "if curl_cffi_version != (0, 5, 10) and not (0, 10) <= curl_cffi_version"
      # deno is required for full YouTube support
      substituteInPlace yt_dlp/utils/_jsruntime.py \
        --replace-fail "path = _determine_runtime_path(self._path, 'deno')" "path = '${prev.deno}/bin/deno'"
    '';
  });
}
