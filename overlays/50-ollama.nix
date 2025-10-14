# Ollama v0.12.5 overlay
final: prev:

{
  ollama = prev.ollama.overrideAttrs (old: rec {
    version = "0.12.5";
    src = prev.fetchFromGitHub {
      owner = "ollama";
      repo = "ollama";
      rev = "v${version}";
      hash = "sha256-X5xxM53DfN8EW29hfJiAeADKLvKdmdNYE2NBa05T82k=";
      fetchSubmodules = true;
    };
  });
}
