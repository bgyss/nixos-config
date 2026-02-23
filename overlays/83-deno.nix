final: prev: {
  deno = prev.deno.overrideAttrs {
    doCheck = false;
  };
}
