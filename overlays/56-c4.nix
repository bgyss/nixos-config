final: prev: {
  c4 = final.buildGo127Module rec {
    pname = "c4";
    version = "0-unstable-2026-11-26";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "4e94c2746eb2fa2c6538e1dc39245469b86106a3";
      hash = "sha256-OomzWldcON+cIcCUObOz851F6V4pbCoaXIZ3PQcOu+U=";
    };

    vendorHash = null;

    # Upstream's TestLogLongChainLinear asserts a wall-clock bound (log_perf_test.go),
    # which is flaky in the sandbox / under load; not a correctness failure.
    doCheck = false;

    subPackages = [ "cmd/c4" ];

    meta = with prev.lib; {
      description = "C4 ID - Universally Unique and Consistent Identification (SMPTE ST 2114:2017)";
      homepage = "https://github.com/Avalanche-io/c4";
      license = licenses.mit;
      mainProgram = "c4";
    };
  };
}
