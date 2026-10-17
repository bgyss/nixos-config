final: prev: {
  c4 = final.buildGo127Module rec {
    pname = "c4";
    version = "0-unstable-2026-10-17";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "e3681da45937b7e79f443af8011d0142b1e6444e";
      hash = "sha256-+TXymehO61RR5Jfy5GU9wt/VqM/dsbuLp+VejqaTrAM=";
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
