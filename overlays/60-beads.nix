# beads overlay – package bd CLI from gastownhall/beads

final: prev:

let
  inherit (final)
    buildGoModule
    fetchFromGitHub
    lib
    sqlite
    icu
    ;
  version = "1.3.1";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-k3WUy0FWPoO7Ymu+FFgS2yYZ4u10Fb7mPBYqs17IP2U=";
  };
in
{
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-mnQo3S7JLrx0nY5EIP3qQVqWLTlisYhjJFzqgPD/xu8=";

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
