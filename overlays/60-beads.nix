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
  version = "1.2.2";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-HSZ1z4WaHQDPomW6nNs8iUnld36BuHnOVaODD5mxY00=";
  };
in
{
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-WWEwGpCwMPD7jaz02zN745RQQqYTQttehbcT3J9hayM=";

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
