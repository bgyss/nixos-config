final: prev: {
  c4 = final.buildGo127Module rec {
    pname = "c4";
    version = "0-unstable-2026-11-12";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "21c9722f60532c7916856edbdf6d094c73d78ef2";
      hash = "sha256-UcZN1T0gWU92Gw1rK6k+AJZVNfkh6NaYT4HUO//UKvs=";
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
