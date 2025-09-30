final: prev: {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: {
    version = "2025.09.26";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      rev = "2025.09.26";
      hash = "sha256-/uzs87Vw+aDNfIJVLOx3C8RyZvWLqjggmnjrOvUX1Eg=";
    };
  });
} 