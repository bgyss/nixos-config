# Disable checks for python313 packages whose tests/runtime-dep-checks fail
# in the Nix build sandbox (timing, dbus, network, missing optional deps).
#
# We override the python313 *interpreter* with packageOverrides so the fix
# propagates everywhere – both to python313Packages consumers AND to
# non-Python packages that use python313.withPackages (e.g. thrift →
# arrow-cpp).  overrideScope alone does NOT cover the latter case because
# withPackages resolves from the interpreter's own scope.
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
  };

  python313-patched = prev.python313.override {
    packageOverrides = pyOverrides;
  };
in
{
  python313 = python313-patched;
  python313Packages = python313-patched.pkgs;
}
