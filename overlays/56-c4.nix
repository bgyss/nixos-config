final: prev: {
  c4 = final.buildGo127Module rec {
    pname = "c4";
    version = "0-unstable-2026-11-08";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "6aa19d8d7f512f76d0ba0b87896d7d141c768bfa";
      hash = "sha256-Vuo9gxnlSnoRthn+H7LH1/v5uwOQnxCIN3VXPSPXtfk=";
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
