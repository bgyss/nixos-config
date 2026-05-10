# beads overlay – package bd CLI from gastownhall/beads

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib sqlite go icu;
  version = "1.0.4";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-a356lk3dWJg2VzXmvBL0xVYUMgICDY/6s6A5km8cjBU=";
  };
in {
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-gTOYABrdQ9T5uxW5QEE8hRWH6AnCPFE/hbB2t1OJTrY=";

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
