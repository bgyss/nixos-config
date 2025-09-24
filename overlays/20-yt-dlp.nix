final: prev: {
  yt-dlp = prev.yt-dlp.overridePythonAttrs (old: {
    version = "2025.09.23";
    src = prev.fetchFromGitHub {
      owner = "yt-dlp";
      repo = "yt-dlp";
      rev = "2025.09.23";
      hash = "sha256-pqdR1JfiqvBs5vSKF7bBBKqq0DRAi3kXCN1zDvaW3nQ=";
    };
  });
} 