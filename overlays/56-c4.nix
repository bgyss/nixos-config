final: prev: {
  c4 = prev.buildGoModule rec {
    pname = "c4";
    version = "0-unstable-2026-07-09";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "028e262fbba0ae72b9aed315e07b7668882ee85a";
      hash = "sha256-i2N5muoPZq/Evme1S4OrAUaszr7fs6Kkf8y7ZVP1+aA=";
    };

    vendorHash = null;

    subPackages = [ "cmd/c4" ];

    meta = with prev.lib; {
      description = "C4 ID - Universally Unique and Consistent Identification (SMPTE ST 2114:2017)";
      homepage = "https://github.com/Avalanche-io/c4";
      license = licenses.mit;
      mainProgram = "c4";
    };
  };
}
