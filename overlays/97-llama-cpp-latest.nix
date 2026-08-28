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
#
# IMPORTANT: nixpkgs' package.nix bakes `LLAMA_BUILD_NUMBER` into both
# `cmakeFlags` and `preConfigure` (the npm build step) from `finalAttrs.version`
# at the point the BASE derivation is constructed — before this overlay's
# overrideAttrs ever runs. Overriding only `version`/`src` above does NOT
# retroactively rewrite those two already-interpolated strings, so the built
# `llama-server --version` silently keeps reporting nixpkgs' own pinned build
# number instead of this overlay's `version`. That mismatch fails the
# post-activation health check (overlays/health-checks.json expects
# `version`) even though the binary itself built and runs fine — caught this
# way on 2026-08-28 (revision 2afe4ef, quarantined). Both must be explicitly
# force-overridden below to keep the health check's version assertion true.
final: prev: {
  llama-cpp = prev.llama-cpp.overrideAttrs (
    old:
    let
      # The base derivation's actual baked-in build number, read back out of
      # its own cmakeFlags rather than trusted from `old.version` — nixpkgs'
      # `pname`/`version` attrs and the finalAttrs.version baked into
      # cmakeFlags/preConfigure are not guaranteed to be the same string once
      # this overlay's own overrideAttrs has already run once (e.g. via
      # `nix why-depends`/repl re-evaluation), so deriving it from the flag
      # itself is the only value guaranteed to match what preConfigure embeds.
      oldBuildNumberMatches = builtins.filter (m: m != null) (
        map (final.lib.match "-DLLAMA_BUILD_NUMBER:STRING=([0-9]+)") old.cmakeFlags
      );
      oldBuildNumber = builtins.elemAt (builtins.head oldBuildNumberMatches) 0;
    in
    rec {
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
      cmakeFlags = map (
        flag:
        if final.lib.hasPrefix "-DLLAMA_BUILD_NUMBER" flag then
          "-DLLAMA_BUILD_NUMBER:STRING=${version}"
        else
          flag
      ) old.cmakeFlags;
      preConfigure =
        builtins.replaceStrings
          [ "LLAMA_BUILD_NUMBER=${oldBuildNumber} " ]
          [
            "LLAMA_BUILD_NUMBER=${version} "
          ]
          old.preConfigure;
    }
  );
}
