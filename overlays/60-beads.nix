# beads overlay – package bd CLI from steveyegge/beads

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib sqlite;
  version = "0.30.2";
  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-ltzLDSkW1Qtxqy6LwLKPn20o6LzWEJ0Nvp9wP3VKp8Q=";
  };
in {
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-ha3sFcbr3fGrHVtSnbrDut/DAnCEy3uGtrcQAozAFJs=";

    buildInputs = [ sqlite ];
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
