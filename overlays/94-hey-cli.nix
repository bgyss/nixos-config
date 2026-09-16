# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib;
  version = "0-unstable-2026-09-16";
  rev = "47475ff0083c6f7e4e3ae05e8e0782bf41881119";
in
{
  hey-cli = buildGoModule {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-Ahz0Dp1dOViGV/46mqi34QbXZvr5B4hqliBJlwLi1kc=";
    };

    vendorHash = "sha256-XyAcTos6b7HGtL7QqKMsOuVjxDnH1laqc+2yGOSkKOg=";

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
