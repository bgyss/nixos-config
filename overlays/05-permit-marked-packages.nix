# Scope the former global `allowBroken` / `allowUnsupportedSystem` flags down to
# exactly the packages that need them (F10 in docs/config-survey-2026-07.md).
#
# Both flags widen the blast radius of a bad bump: with them on, a newly-broken
# or newly-unsupported package silently builds instead of failing fast. Instead
# of the global flags, un-gate only the specific packages this config genuinely
# pulls in, so ANY other package that becomes broken/unsupported fails the
# build (and `nix flake check`) immediately.
#
# Overriding meta only changes the evaluation gate, not the build itself, so
# this cannot change what these packages produce — only whether nixpkgs refuses
# to look at them.
final: prev:
let
  unbreak =
    pkg:
    pkg.overrideAttrs (old: {
      meta = (old.meta or { }) // {
        broken = false;
      };
    });
  permitPlatform =
    pkg:
    pkg.overrideAttrs (old: {
      meta = (old.meta or { }) // {
        platforms = prev.lib.platforms.all;
        badPlatforms = [ ];
      };
    });
in
{
  # marked broken on aarch64-darwin (used via overlays/92-lmstudio.nix)
  lmstudio = unbreak prev.lmstudio;
  # meta.platforms excludes aarch64-darwin, but it is wanted here
  wkhtmltopdf = permitPlatform prev.wkhtmltopdf;
}
