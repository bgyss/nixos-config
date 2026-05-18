final: prev: {
  c4 = prev.buildGoModule rec {
    pname = "c4";
    version = "0-unstable-2026-05-15";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "95d3611e537b209ce34c87438f0e1ae13813a539";
      hash = "sha256-DvkoyEbDCT/EiOgmQXzp90XKBJEhCKCj/lKkNEUZdG0=";
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
