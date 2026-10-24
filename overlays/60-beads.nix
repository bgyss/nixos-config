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
  version = "1.3.2";
  src = fetchFromGitHub {
    owner = "gastownhall";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-f36v59+mSjI0SkwmUditpZwob0tqNosKUrRywEXxUQw=";
  };
in
{
  beads = buildGo127Module {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-akJBtvchASCHKCmzuD77n6WKD/jLN1n01WyyCXXR2xY=";

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
