final: prev: {
  libxml2 = prev.libxml2.overrideAttrs (old: {
    patches = builtins.filter
      (p: !(builtins.match ".*CVE-2026-0989.*" (toString p) != null))
      (old.patches or []);
  });
}
