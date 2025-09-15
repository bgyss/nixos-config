# Ollama v0.11.0 overlay
final: prev:

{
  ollama = prev.ollama.overrideAttrs (old: rec {
    version = "0.11.0";
    src = prev.fetchFromGitHub {
      owner = "ollama";
      repo = "ollama";
      rev = "v${version}";
      hash = "sha256-po7BxJAj9eOpOaXsLDmw6/1RyjXPtXza0YUv0pVojZ0=";
      fetchSubmodules = true;
    };
  });
}