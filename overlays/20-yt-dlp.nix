final: prev: {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: rec {
    version = "2025.10.14";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      rev = version;
      hash = "sha256-x7vpuXUihlC4jONwjmWnPECFZ7xiVAOFSDUgBNvl+aA=";
    };
  });
} 