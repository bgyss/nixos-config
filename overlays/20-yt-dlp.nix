final: prev: {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: rec {
    version = "2025.10.22";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      rev = version;
      hash = "sha256-jQaENEflaF9HzY/EiMXIHgUehAJ3nnDT9IbaN6bDcac=";
    };
  });
} 