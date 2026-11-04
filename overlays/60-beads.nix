# beads overlay – package bd CLI from gastownhall/beads

final: prev:

let
  inherit (final)
    buildGo127Module
    fetchFromGitHub
    lib
    sqlite
    icu
    ;
  version = "1.3.4";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-nfPAhOrqmEMHHmkrLzxFHbldeUrRRyJiPYtwOVoC6ao=";
  };
in
{
  beads = buildGo127Module {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-nSOmq+SQ5d2rtS1XwetSN8i9rxlqlECgeofPKf0PjW0=";

    buildInputs = [
      sqlite
      icu
    ];
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
