final: prev: {
  c4 = prev.buildGoModule rec {
    pname = "c4";
    version = "0-unstable-2026-03-26";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "2b9e7edde6828b38da15c3985e0b97bdd74b73d2";
      hash = "sha256-K4CBGM9AjEktkJgdp9q/c37Ep5bCQBzSj8FlO2BLa4M=";
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
