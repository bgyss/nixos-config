final: prev: {
  c4 = prev.buildGoModule rec {
    pname = "c4";
    version = "0-unstable-2026-07-13";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "136d74d1bb6b889ef7eb160b3c7529cbde02c45d";
      hash = "sha256-RrTJlYVFkV/1tqkylhKujpG+VxICKAsojif/hAgsmsc=";
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
