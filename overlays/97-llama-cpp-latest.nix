# Pin llama-cpp ahead of nixpkgs (currently b8667) so the `llama`/`llama-server`
# binaries on PATH support newer model architectures (e.g. muse-glimmer, added
# upstream after b8667) without a manual from-source build.
#
# Bumping this overlay requires TWO hashes, both computed against the new tag:
#   - `src.hash`     — the fetchFromGitHub source tree (leaveDotGit, matches
#                       nixpkgs' own postFetch so LLAMA_BUILD_COMMIT still works)
#   - `npmDepsHash`  — the webui's npm lockfile deps; this changes whenever the
#                       webui's package-lock.json changes upstream (common
#                       between releases), and the webui's path within the repo
#                       (`npmRoot`) has moved before (tools/server/webui ->
#                       tools/ui as of b10375) — check it still exists at the
#                       new tag before assuming the old npmRoot is still right.
# Blank either hash and run a build to read the correct value from the
# "hash mismatch" error, same as the cargoHash/vendorHash routine.
final: prev: {
  llama-cpp = prev.llama-cpp.overrideAttrs (old: {
    version = "10375";
    src = prev.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "b10375";
      hash = "sha256-/AWjgH96UlRaOGwqA3z7eiPGnB73evRNwBuUoL/1rgw=";
      leaveDotGit = true;
      postFetch = ''
        git -C "$out" rev-parse --short HEAD > $out/COMMIT
        find "$out" -name .git -print0 | xargs -0 rm -rf
      '';
    };
    npmRoot = "tools/ui";
    npmDepsHash = "sha256-2Q7XhaLAArmviOLdQsNbYTfdyDE5pW9lR26cRHEVl9k=";
  });
}
