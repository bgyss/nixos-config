{
  description = "Starter Configuration for MacOS and NixOS";

  inputs = {
    # Pinned to commit before libxml2 CVE patches that cause OOM in patch utility
    # See: CVE-2026-0989/0990/0992 patches cause patch to run out of memory
    # TODO: Unpin when upstream fixes the patch OOM issue
    nixpkgs.url = "github:NixOS/nixpkgs/af45a5c7362bcf6585aff1ffd1de09663cce80c8";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    # Pinned to last commit before services-modular added lib/services/lib.nix
    # dependency that doesn't exist in the pinned nixpkgs (af45a5c)
    home-manager.url = "github:nix-community/home-manager/9ce9f7f";
    emacs-overlay = {
      url = "github:dustinlyons/emacs-overlay/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned to the release branch matching the pinned nixpkgs (26.05).
    # nix-darwin master rolled over to 26.11 and enforces a branch/nixpkgs
    # release match, so `master` no longer works with the 26.05 nixpkgs pin.
    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    dagger-tap = {
      url = "github:dagger/homebrew-tap";
      flake = false;
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Formatting / linting: drives `nix fmt` and the `treefmt` / `statix` /
    # `deadnix` checks (nixfmt-rfc-style + statix + deadnix). See treefmt.nix.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    secrets = {
      url = "git+ssh://git@github.com/bgyss/nix-secrets.git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      darwin,
      nix-homebrew,
      homebrew-bundle,
      homebrew-core,
      homebrew-cask,
      home-manager,
      nixpkgs,
      nixpkgs-master,
      emacs-overlay,
      disko,
      dagger-tap,
      agenix,
      treefmt-nix,
      secrets,
    }@inputs:
    let
      user = "briangyss";
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      darwinSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs (linuxSystems ++ darwinSystems) f;
      # treefmt (nixfmt-rfc-style + statix + deadnix) evaluated per system.
      # Drives `nix fmt`, the `formatter` output, and the `treefmt` check.
      treefmtEval = forAllSystems (
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix
      );
      devShell =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default =
            with pkgs;
            mkShell {
              nativeBuildInputs = with pkgs; [
                bashInteractive
                git
                agenix.packages.${system}.default
              ];
              shellHook = with pkgs; ''
                export EDITOR=vim
              '';
            };
        };
      mkApp = scriptName: system: {
        type = "app";
        program = "${
          (nixpkgs.legacyPackages.${system}.writeScriptBin scriptName ''
            #!/usr/bin/env bash
            PATH=${nixpkgs.legacyPackages.${system}.git}/bin:$PATH
            echo "Running ${scriptName} for ${system}"
            exec ${self}/apps/${system}/${scriptName}
          '')
        }/bin/${scriptName}";
      };
      mkLinuxApps = system: {
        "apply" = mkApp "apply" system;
        "build-switch" = mkApp "build-switch" system;
        "copy-keys" = mkApp "copy-keys" system;
        "create-keys" = mkApp "create-keys" system;
        "check-keys" = mkApp "check-keys" system;
        "install" = mkApp "install" system;
      };
      mkDarwinApps =
        system:
        let
          script =
            name: contents: (nixpkgs.legacyPackages.${system}.writeScriptBin name contents) + "/bin/" + name;
        in
        {
          "apply" = mkApp "apply" system;
          "build" = mkApp "build" system;
          # Make build-switch independent of current working directory by invoking
          # darwin-rebuild from the nix-darwin input and pointing it at this flake.
          "build-switch" = {
            type = "app";
            program = script "build-switch" ''
              #!/usr/bin/env bash
              set -euo pipefail
              export PATH=${nixpkgs.legacyPackages.${system}.git}/bin:$PATH
              echo "Running build-switch for ${system}"
              exec sudo -H -- /run/current-system/sw/bin/darwin-rebuild switch --flake ${self} "$@"
            '';
          };
          "copy-keys" = mkApp "copy-keys" system;
          "create-keys" = mkApp "create-keys" system;
          "check-keys" = mkApp "check-keys" system;
          "rollback" = mkApp "rollback" system;
          "fix-hashes" = mkApp "fix-hashes" system;
          "update" = mkApp "update" system;
        };
    in
    {
      devShells = forAllSystems devShell;

      # `nix fmt` formats the whole tree with treefmt (nixfmt-rfc-style).
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # `nix flake check` gate. Everything an agent must not break is expressed
      # here: the config evaluates, the live darwin system builds, and the tree
      # is formatted / lint-clean (statix, deadnix) and updates.json ↔ overlays
      # stay consistent. "Green check = safe to attempt switch."
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Formatting + statix + deadnix (all wired through treefmt.nix).
          treefmt = treefmtEval.${system}.config.build.check self;

          # updates.json parses and matches the overlays it references.
          overlays-manifest =
            pkgs.runCommand "check-overlays-manifest"
              {
                nativeBuildInputs = [ pkgs.jq ];
              }
              ''
                ${pkgs.bash}/bin/bash ${./scripts/check-overlay-manifest.sh} ${self}
                touch $out
              '';
        }
        # Build the live darwin system as a check on its native system only.
        // nixpkgs.lib.optionalAttrs (system == "aarch64-darwin") {
          darwin-build = self.darwinConfigurations.garmonbozia.system;
        }
      );

      templates = {
        starter = {
          path = ./templates/starter;
          description = "Starter configuration for macOS and NixOS (agenix secrets pulled from a separate GitHub repo)";
        };
        default = self.templates.starter;
      };
      # Export selected custom packages so users can `nix build .#<name>`
      packages = forAllSystems (
        system:
        let
          basePkgs = nixpkgs.legacyPackages.${system};
          pkgs = basePkgs.extend (
            final: prev:
            (import ./overlays/40-codex-openai.nix final prev)
            // (import ./overlays/50-trailbase.nix final prev)
            // (import ./overlays/60-beads.nix final prev)
            // (import ./overlays/90-svg-term-cli.nix final prev)
          );
          trailbasePkg = nixpkgs.lib.optionalAttrs (pkgs ? trailbase) { inherit (pkgs) trailbase; };
        in
        {
          inherit (pkgs) beads;
          inherit (pkgs) codex-openai;
          inherit (pkgs) svg-term-cli;
        }
        // trailbasePkg
      );
      apps =
        nixpkgs.lib.genAttrs linuxSystems mkLinuxApps // nixpkgs.lib.genAttrs darwinSystems mkDarwinApps;

      darwinConfigurations = {
        # Host-specific configuration for this Mac
        garmonbozia =
          let
            system = "aarch64-darwin";
          in
          darwin.lib.darwinSystem {
            inherit system;
            specialArgs = inputs // {
              inherit user;
            };
            modules = [
              home-manager.darwinModules.home-manager
              agenix.darwinModules.default
              nix-homebrew.darwinModules.nix-homebrew
              {
                nix-homebrew = {
                  inherit user;
                  enable = true;
                  taps = {
                    "homebrew/core" = homebrew-core;
                    "homebrew/cask" = homebrew-cask;
                    "homebrew/bundle" = homebrew-bundle;
                    "dagger/tap" = dagger-tap;
                  };
                  mutableTaps = false;
                  autoMigrate = true;
                };
              }
              # Import your darwin Home Manager module which itself configures HM
              ./modules/darwin/home-manager.nix
              ./hosts/darwin
            ];
          };
      };

      nixosConfigurations = nixpkgs.lib.genAttrs linuxSystems (
        system:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = inputs // {
            inherit user;
          };
          modules = [
            disko.nixosModules.disko
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${user} = import ./modules/nixos/home-manager.nix;
              };
            }
            ./hosts/nixos
          ];
        }
      );
    };
}
