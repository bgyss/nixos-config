final: prev: {
  claude-code = prev.claude-code.overrideAttrs (oldAttrs: rec {
    version = "2.1.15";
    src = prev.fetchurl {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      hash = "sha256-6B3q0Z2AXqD8UCvuCjyx90LxYrjZDgfa7y6htBicqL4=";
    };
    npmDepsHash = "";
  });
}
