# Disable checks for python313/python314 packages whose tests/runtime-dep-checks
# fail in the Nix build sandbox (timing, dbus, network, missing optional deps).
#
# We override the interpreters with packageOverrides so the fix propagates
# everywhere – both to pythonXPackages consumers AND to non-Python packages
# that use pythonX.withPackages (e.g. thrift → arrow-cpp). overrideScope alone
# does NOT cover the latter case because withPackages resolves from the
# interpreter's own scope.
#
# Both python313 and python314 need patching: our own package list
# (modules/shared/packages.nix) uses python314, but nixpkgs' own python3
# alias is still python313 and several nixpkgs derivations (glances, semgrep,
# curl-cffi, fastapi, mcp, jetbrains-mono, yt-dlp, ...) build against it
# internally.
#
# This overlay also subsumes 82-python313-httpcore.nix to avoid conflicts
# between overrideScope and packageOverrides.

final: prev:
let
  # Helper to concisely disable checks
  noCheck = pkg: pkg.overridePythonAttrs { doCheck = false; };

  pyOverrides = pyFinal: pyPrev: {
    # ── async / networking (timing-sensitive, need real sockets) ──
    aiohappyeyeballs = noCheck pyPrev.aiohappyeyeballs;
    aiohttp           = noCheck pyPrev.aiohttp;
    aiosignal         = noCheck pyPrev.aiosignal;
    httpcore          = noCheck pyPrev.httpcore;
    httpx             = noCheck pyPrev.httpx;
    anyio             = noCheck pyPrev.anyio;
    uvloop            = noCheck pyPrev.uvloop;
    watchfiles        = noCheck pyPrev.watchfiles;  # pytest-timeout in sandbox

    # ── dbus / system-service tests (no dbus-daemon in sandbox) ──
    jeepney = pyPrev.jeepney.overridePythonAttrs {
      doCheck = false;
      pythonImportsCheck = [ ];  # trio.io needs 'outcome' module
    };
    secretstorage = noCheck pyPrev.secretstorage;
    keyring       = noCheck pyPrev.keyring;

    # ── crypto / ssh (need agents, hardware, or network) ──
    paramiko = pyPrev.paramiko.overridePythonAttrs {
      doCheck = false;
      dontCheckRuntimeDeps = true;
    };
    cryptography = noCheck pyPrev.cryptography;

    # ── packages with sandbox-incompatible test suites ──
    twisted        = noCheck pyPrev.twisted;
    ffmpeg-python  = noCheck pyPrev.ffmpeg-python;
    black          = noCheck pyPrev.black;
    tornado        = noCheck pyPrev.tornado;

    # ── AI/ML ecosystem (network-dependent or very slow tests) ──
    openai     = noCheck pyPrev.openai;
    anthropic  = noCheck pyPrev.anthropic;
    tiktoken   = noCheck pyPrev.tiktoken;
    tokenizers = noCheck pyPrev.tokenizers;
    datasets   = noCheck pyPrev.datasets;
    huggingface-hub = noCheck pyPrev.huggingface-hub;
    llm        = noCheck pyPrev.llm;
    fsspec     = noCheck pyPrev.fsspec;

    # ── misc commonly-flaky in sandbox ──
    elasticsearch    = noCheck pyPrev.elasticsearch;
    elastic-transport = noCheck pyPrev.elastic-transport;
    inline-snapshot = pyPrev.inline-snapshot.overridePythonAttrs {
      doCheck = false;
      dontCheckRuntimeDeps = true;  # pytest is a runtime dep but not propagated
    };
    # ── cocotb ──
    # cocotb 2.0.1's setup.py hard-caps at Python 3.13 (RuntimeError unless
    # COCOTB_IGNORE_PYTHON_REQUIRES is set); it otherwise builds and runs fine
    # under 3.14, so we set that env var unconditionally.
    #
    # Upstream also marks cocotb broken on Darwin because its test suite pulls
    # ghdl, and ghdl has no aarch64-darwin support (mcode backend is x86-only).
    # cocotb itself builds fine on Apple Silicon, so on Darwin we additionally
    # unset `broken` and skip the ghdl-dependent check phase. The key is always
    # defined (value guarded) to avoid overlay key-set recursion.
    cocotb =
      if prev.stdenv.hostPlatform.isDarwin then
        pyPrev.cocotb.overridePythonAttrs (old: {
          doCheck = false;
          nativeCheckInputs = [ ];
          env = (old.env or { }) // { COCOTB_IGNORE_PYTHON_REQUIRES = "1"; };
          meta = old.meta // { broken = false; };
        })
      else
        pyPrev.cocotb.overridePythonAttrs (old: {
          env = (old.env or { }) // { COCOTB_IGNORE_PYTHON_REQUIRES = "1"; };
        });
  };

  python313-patched = prev.python313.override {
    packageOverrides = pyOverrides;
  };
  python314-patched = prev.python314.override {
    packageOverrides = pyOverrides;
  };
in
{
  python313 = python313-patched;
  python313Packages = python313-patched.pkgs;
  python314 = python314-patched;
  python314Packages = python314-patched.pkgs;
}
