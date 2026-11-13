# hey-cli overlay – HEY mail/calendar TUI from basecamp/hey-cli (no tagged releases)

final: prev:

let
  inherit (final) buildGo127Module fetchFromGitHub lib;
  version = "0-unstable-2026-11-12";
  rev = "2de736c1e47bacd704ec30505399823dc4e0e3d7";
in
{
  hey-cli = buildGo127Module {
    pname = "hey-cli";
    inherit version;

    src = fetchFromGitHub {
      owner = "basecamp";
      repo = "hey-cli";
      inherit rev;
      hash = "sha256-bRsoXMo425YC5Vfqqhf0rs9R4BVi/2Gmu7Y/G5OSmC4=";
    };

    vendorHash = "sha256-XKI6b10MwEMGLnrTvct0uR8hzwelKL3/sR/sv3Uhm8Y=";

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
