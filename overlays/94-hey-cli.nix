# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGo127Module fetchFromGitHub lib;
  version = "0-unstable-2026-10-25";
  rev = "5388a803cd43c8fba1d93dee5fd970e4da823d41";
in
{
  hey-cli = buildGo127Module {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-FtSui8G5S7I/46k9CLxlN2DNURnPi27+9OAknMx6+wE=";
    };

    vendorHash = "sha256-eU2YUbyuOLwZ/owju0HcziWNFM1xG1DqnjpfCqkT85k=";

    subPackages = [ "cmd/hey" ];

    ldflags = [
      "-s"
      "-w"
      "-X github.com/basecamp/hey-cli/internal/version.Version=${version}"
      "-X github.com/basecamp/hey-cli/internal/version.Commit=${builtins.substring 0 7 rev}"
    ];

    # Tests reach the network / require credentials
    doCheck = false;

    meta = with lib; {
      description = "HEY email and calendar client for the terminal";
      homepage = "https://github.com/basecamp/hey-cli";
      license = licenses.mit;
      mainProgram = "hey";
      platforms = platforms.unix;
    };
  };
}
