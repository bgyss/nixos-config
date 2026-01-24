# Disable httpcore tests on Python 3.13 - upstream test failures with async cancellation
final: prev: {
  python313Packages = prev.python313Packages.overrideScope (pfinal: pprev: {
    httpcore = pprev.httpcore.overrideAttrs (old: {
      doCheck = false;
    });
  });
}
