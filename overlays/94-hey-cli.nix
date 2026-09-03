# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib;
  version = "0-unstable-2026-09-03";
  rev = "f9a0208d3a59930c764dd21143bd7897a12321aa";
in
{
  hey-cli = buildGoModule {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-o3oJTm/PYndMEoz34PVu3ycDVbUjah6ikO+8CNoWSRY=";
    };

    vendorHash = "sha256-Nupd+16J+aXwNnstS6W86jjx1Usuwsw4FJSU6tdcQ3o=";

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
