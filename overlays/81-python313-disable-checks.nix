# Disable checks for python313 packages whose tests/runtime-dep-checks fail
# in the Nix build sandbox.
#
# We use overrideScope so the fix propagates to reverse dependencies (e.g.
# ffmpeg-python → gftools → jetbrains-mono).  The trade-off is that every
# python313 package gets a new derivation hash and loses its binary-cache
# hit, but this is the only reliable way to fix transitive build failures.
# Keep the list minimal to limit rebuild scope.

final: prev: {
  python313Packages = prev.python313Packages.overrideScope (
    pyFinal: pyPrev: {
      ffmpeg-python = pyPrev.ffmpeg-python.overridePythonAttrs {
        doCheck = false;
      };
      paramiko = pyPrev.paramiko.overridePythonAttrs {
        doCheck = false;
        dontCheckRuntimeDeps = true;
      };
      twisted = pyPrev.twisted.overridePythonAttrs {
        doCheck = false;
      };
    }
  );
}
