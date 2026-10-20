# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGo127Module fetchFromGitHub lib;
  version = "0-unstable-2026-10-20";
  rev = "eef0bd8b1166a69bf53b383c0d270394c482e301";
in
{
  hey-cli = buildGo127Module {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-pgD6zHbelGSv+6LPx+bPV5EsGPeRkdMPjppmNls0lWM=";
    };

    vendorHash = "sha256-OqGvfQNawKocBuiUS3vy2KIRdtId479lE429E712+WU=";

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
