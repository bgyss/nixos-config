# beads overlay – package bd CLI from steveyegge/beads

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib sqlite go icu;
  version = "0.63.3";
  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-1AcsSDQXLcPLwIvV3dJ2DXYpeR2PAQCgUodclDMwg/s=";
  };
in {
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-GYPfvsI8eNJbdzrbO7YnMkN2Yt6KZNB7w/2SJD2WdFY=";

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
      homepage = "https://github.com/steveyegge/beads";
      license = licenses.asl20;
      mainProgram = "bd";
      platforms = platforms.unix;
    };
  };
}
