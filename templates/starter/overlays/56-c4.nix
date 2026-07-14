final: prev: {
  c4 = prev.buildGoModule rec {
    pname = "c4";
    version = "0-unstable-2026-07-12";

    src = prev.fetchFromGitHub {
      owner = "Avalanche-io";
      repo = "c4";
      rev = "9e38151a198c3cf8fc46e2fbe49062c06fedc0e2";
      hash = "sha256-IOjkjtsWIHuau1lHXgcTIDuY/aXfl0LcFJvnCfs7HxE=";
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
