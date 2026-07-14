# direnv overlay – fix CGO requirement for linkmode=external on Darwin
# The upstream package sets CGO_ENABLED=0 but the Makefile uses -linkmode=external
# which requires CGO. Override env to enable CGO.
final: prev: {
  direnv = prev.direnv.overrideAttrs (old: {
    env = (old.env or {}) // {
      CGO_ENABLED = "1";
    };
  });
}
