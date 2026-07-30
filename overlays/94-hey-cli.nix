# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGoModule fetchFromGitHub lib;
  version = "0-unstable-2026-07-30";
  rev = "3793b8910e41073c2cf4e5440b897cd7667dca7b";
in
{
  hey-cli = buildGoModule {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-lsyHp1nEY06odMXGko4Zwly9bj7WnyZPSIrYQf6MzFI=";
    };

    vendorHash = "sha256-NtcJ8ocYePsC2lP84MNzXdg4cqpXWnEgGasdLMG60K0=";

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
