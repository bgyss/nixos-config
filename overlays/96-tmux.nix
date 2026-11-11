# Pin tmux to 3.7b (latest upstream bugfix release as of 2026-07,
# supersedes 3.6b) ahead of the next nixpkgs bump.
final: prev: {
  tmux = prev.tmux.overrideAttrs (old: {
    version = "3.7b";
    src = prev.fetchFromGitHub {
      owner = "tmux";
      repo = "tmux";
      tag = "3.7b";
      hash = "sha256-CTq06XP997M0ODxQihTq34dI9H6jSRLUXLYuTWOwDpc=";
    };
    # The NULL-deref control-mode fix nixpkgs backports onto 3.6a is
    # already part of the 3.7 release; nothing to patch on top.
    patches = [ ];
    # tmux 3.8's configure refuses to run on macOS unless told what to do about
    # jemalloc (system calloc misbehaves on some allocations). nixpkgs does not
    # pass either flag, so choose: no jemalloc. Older releases just ignore it.
    configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-jemalloc" ];
  });
}
