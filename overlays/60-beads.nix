# beads overlay – package bd CLI from gastownhall/beads

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib sqlite go icu;
  version = "1.0.3";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-K3X67XgUl55mZS4r4V/KTbXPNqCV7fPHi8HnrDime+E=";
  };
in {
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-Rn1MnasYUOBbIgjFx0E6R2Zak6la1VajDkHqoiFpHtw=";

    buildInputs = [ sqlite icu ];
    preBuild = ''
      export CGO_ENABLED=1
    '';

    # Tests require git in the sandbox
    doCheck = false;

    ldflags = [
      "-s"
      "-w"
      "-X main.Build=${version}"
    ];

    meta = with lib; {
      description = "Dependency-aware issue tracker CLI";
      homepage = "https://github.com/gastownhall/beads";
      license = licenses.asl20;
      mainProgram = "bd";
      platforms = platforms.unix;
    };
  };
}
