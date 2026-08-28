# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib;
  version = "0-unstable-2026-08-28";
  rev = "5782053d1814ed0ceac20db333cedc1c75649c32";
in
{
  hey-cli = buildGoModule {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-FN9lOGfA9kTgW+MY26TwmJf8QvYhRxxD5SOwpjT6kJc=";
    };

    vendorHash = "sha256-NcBIegczL+UYiHTTVa/fnhiur2lWvUH/+lOzSmmx1Io=";

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
