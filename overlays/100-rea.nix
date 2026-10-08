# rea overlay – reverse-engineering CLI/MCP server from bgyss/rea (no tagged releases)

final: prev:

let
  inherit (final) buildNpmPackage fetchFromGitHub lib;
  version = "0-unstable-2026-10-08";
  rev = "c3136064c7f8f72b2f6c6799ec41ea6424111bb7";
in
{
  rea = buildNpmPackage {
    pname = "rea";
    inherit version;

    src = fetchFromGitHub {
      owner = "bgyss";
      repo = "rea";
      inherit rev;
      hash = "sha256-hANxVuvdWw7ERYB2FhN0iX8iyUdYY7FQ9BIDa1hbSRQ=";
    };

    npmDepsHash = "sha256-ninOfE/wyfYkdV5cd6zrl5mdzN6WCDzE2giWnaNjWGk=";

    # Skip husky/prepare hooks and downloads; build only the TypeScript CLI
    npmFlags = [ "--ignore-scripts" ];
    npmBuildScript = "build:unlocked";

    meta = with lib; {
      description = "Reverse engineer anything with agents, from app behavior down to native binaries";
      homepage = "https://github.com/bgyss/rea";
      license = licenses.mit;
      mainProgram = "rea";
      platforms = platforms.unix;
    };
  };
}
