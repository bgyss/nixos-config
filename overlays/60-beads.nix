# beads overlay – package bd CLI from steveyegge/beads

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib sqlite;
  version = "0.9.0-unstable-2025-10-13";
  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "00b0292514da82b56eb1e1b580b89f1bbbc629f4";
    hash = "sha256-luVe7fZxXIu/El56R8oiuTP86IeixAx406q17yyEN04=";
  };
in {
  beads = buildGoModule {
    pname = "beads";
    inherit version src;

    subPackages = [ "cmd/bd" ];
    modRoot = ".";
    vendorHash = "sha256-muggwMeVrwzZafDgbwR8B1IzGIDdrIK6xkGSGbFrxhA=";

    buildInputs = [ sqlite ];
    preBuild = ''
      export CGO_ENABLED=1
    '';

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
