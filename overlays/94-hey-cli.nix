# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib;
  version = "0-unstable-2026-09-01";
  rev = "7f10134a7cd026358adc4bda9a62e55341ac5682";
in
{
  hey-cli = buildGoModule {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-Xr8iRctUGXeZJoQwAR1yKXQkA60mY1I8Lu87ZnAFd2Q=";
    };

    vendorHash = "sha256-hs2gFLO2xk8x1iFVZhBhkAkVQ/AreTvGdhf7nj5N/MU=";

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
