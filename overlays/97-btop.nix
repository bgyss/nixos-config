# Pin btop to 1.4.8 ahead of nixpkgs. 1.4.6/1.4.7 hang on macOS ("Stall in Runner
# thread" -> pthread_cancel -> main thread stuck in pthread_join, aristocratos/btop#1349);
# 1.4.8 carries the fix (#1662).
final: prev: {
  btop = prev.btop.overrideAttrs (_old: {
    version = "1.4.8";
    src = prev.fetchFromGitHub {
      owner = "aristocratos";
      repo = "btop";
      tag = "v1.4.8";
      hash = "sha256-NujxQ6d8K+cRlwPfcoJk9XC0GDeh6Omx8x+WkCbxTcs=";
    };
    patches = [ ];
  });
}
