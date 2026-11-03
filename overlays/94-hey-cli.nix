# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGo127Module fetchFromGitHub lib;
  version = "0-unstable-2026-11-03";
  rev = "98430d8adeb6570278d511ac1c10ad3f91783f6e";
in
{
  hey-cli = buildGo127Module {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-tbCwodK9LWY2ot08sSsbd/kVBN/ozIarr2wt0V3+fKM=";
    };

    vendorHash = "sha256-aPYvsI5WEE/A8Oh4w1Q7Ajh2SIXDggNlebJ1nBuErEU=";

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
