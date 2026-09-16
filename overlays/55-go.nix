# go overlay – track go_1_27 from nixpkgs-master until the pinned nixpkgs
# catches up.
#
# The pinned nixpkgs (as of 2026-09) doesn't expose a go_1_27 attribute yet.
# Rather than overrideAttrs-ing go_1_26's src/version forward (which breaks:
# nixpkgs' go_1_26 derivation carries patches, e.g. go_no_vendor_checks, that
# are hand-fitted to 1.26's source layout and fail to apply against 1.27's),
# this takes the whole go_1_27 derivation from nixpkgs-master — see
# `masterPkgs`/`go_1_27` in modules/shared/default.nix — so its patches
# already match its source. Once the pinned nixpkgs grows a go_1_27
# attribute, switch `final.go_1_27` below back to `prev.go_1_27` and drop
# the nixpkgs-master plumbing for this package.

final: prev: {
  go = final.go_1_27;

  buildGoModule = prev.buildGoModule.override {
    go = final.go_1_27;
  };
}
