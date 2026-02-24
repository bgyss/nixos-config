# Disable checks for python313 packages whose tests/runtime-dep-checks fail
# in the Nix build sandbox.
#
# We override the python313 *interpreter* with packageOverrides so the fix
# propagates everywhere – both to python313Packages consumers AND to
# non-Python packages that use python313.withPackages (e.g. thrift →
# arrow-cpp).  overrideScope alone does NOT cover the latter case because
# withPackages resolves from the interpreter's own scope.
# Keep the list minimal to limit rebuild scope.

final: prev:
let
  pyOverrides = pyFinal: pyPrev: {
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
    jeepney = pyPrev.jeepney.overridePythonAttrs {
      doCheck = false;
    };
  };
  python313-patched = prev.python313.override {
    packageOverrides = pyOverrides;
  };
in
{
  python313 = python313-patched;
  python313Packages = python313-patched.pkgs;
}
