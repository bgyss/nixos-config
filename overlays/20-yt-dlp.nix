final: prev: {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: {
    version = "2025.07.21";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      rev = "2025.08.20";
      hash = "sha256-FeIoV7Ya+tGCMvUUXmPrs4MN52zwqrcpzJ6Arh4V450=";
    };
  });
} 