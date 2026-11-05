final: prev: {
  c4 = final.buildGo127Module rec {
    pname = "c4";
    version = "0-unstable-2026-11-05";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "e2fd9c5fe452b3d93ec9327fcf99dc8a3611c1fd";
      hash = "sha256-zFCRwDPgLkDlXaIOw+TeOgV3zTUlLHXCNLue8Z+auOg=";
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
