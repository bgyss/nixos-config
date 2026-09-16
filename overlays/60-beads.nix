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
  version = "1.3.0";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-QryUnK04c9Wm9/VgWoaOJW9M2HoZVZzSDMSMBtjKiyc=";
  };
in
{
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-DFS9dSZX3v3q3Yk6+bfnoEN1uIULs2h8t/P9W2tk6l8=";

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
