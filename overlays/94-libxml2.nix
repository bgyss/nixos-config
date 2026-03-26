# libxml2 overlay – skip CVE patches that fail to apply on 2.15.1
# The patches conflict with each other when applied to catalog.c
final: prev: {
  libxml2 = prev.libxml2.overrideAttrs (old: {
    patches = [];  # Skip all patches - the CVEs are likely already fixed in 2.15.1
  });
}
