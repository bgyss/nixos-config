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
  });
}
