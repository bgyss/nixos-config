# cocotb build fix for python314.
#
# cocotb 2.0.1's setup.py hard-caps at Python 3.13 (RuntimeError unless
# COCOTB_IGNORE_PYTHON_REQUIRES is set); it otherwise builds and runs fine
# under 3.14, so we set that env var unconditionally.
#
# Upstream also marks cocotb broken on Darwin because its test suite pulls
# ghdl, and ghdl has no aarch64-darwin support (mcode backend is x86-only).
# cocotb itself builds fine on Apple Silicon, so on Darwin we additionally
# unset `broken` and skip the ghdl-dependent check phase.
#
# This used to also disable checks on ~30 other Python packages (aiohttp,
# httpx, cryptography, ...). That was dropped on purpose: the stock outputs are
# in cache.nixos.org, and changing any of them changes the derivation hash of
# everything downstream, forcing a local rebuild of a large slice of the Python
# ecosystem (plus jetbrains-mono, semgrep, glances, ...) for no benefit. If a
# package genuinely fails its tests in the sandbox, override just that one here.

final: prev:
let
  pyOverrides = _pyFinal: pyPrev: {
    cocotb =
      if prev.stdenv.hostPlatform.isDarwin then
        pyPrev.cocotb.overridePythonAttrs (old: {
          doCheck = false;
          nativeCheckInputs = [ ];
          env = (old.env or { }) // {
            COCOTB_IGNORE_PYTHON_REQUIRES = "1";
          };
          meta = old.meta // {
            broken = false;
          };
        })
      else
        pyPrev.cocotb.overridePythonAttrs (old: {
          env = (old.env or { }) // {
            COCOTB_IGNORE_PYTHON_REQUIRES = "1";
          };
        });
  };

  python314-patched = prev.python314.override {
    packageOverrides = pyOverrides;
  };
in
{
  python314 = python314-patched;
  python314Packages = python314-patched.pkgs;
}
