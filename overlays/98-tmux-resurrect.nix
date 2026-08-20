# nixpkgs pins tmuxPlugins.resurrect to unstable-2022-05-01 -- bump to the
# latest upstream commit (project has had no releases; master is the
# reference point) so restore-time bugfixes since then are picked up.
final: prev: {
  tmuxPlugins = prev.tmuxPlugins // {
    resurrect = prev.tmuxPlugins.resurrect.overrideAttrs (old: {
      version = "0-unstable-2023-03-06";
      src = prev.fetchFromGitHub {
        owner = "tmux-plugins";
        repo = "tmux-resurrect";
        rev = "cff343cf9e81983d3da0c8562b01616f12e8d548";
        fetchSubmodules = true;
        hash = "sha256-2ZM23RQps2XO2OYX9NTZj5yIUZEv4ggYzjrJ9RxxLLg=";
      };
    });
  };
}
