{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    rust-flake.url = "github:juspay/rust-flake";
    rust-flake.inputs.nixpkgs.follows = "nixpkgs";

    # Dev tools
    treefmt-nix.url = "github:numtide/treefmt-nix";
    just-flake.url = "github:juspay/just-flake";
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.just-flake.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
        inputs.rust-flake.flakeModules.default
        inputs.rust-flake.flakeModules.nixpkgs
      ];
      perSystem = { config, self', pkgs, lib, system, ... }: {
        rust-project.crane.args = {
          buildInputs = lib.optionals pkgs.stdenv.isDarwin (
            with pkgs.darwin.apple_sdk.frameworks; [
              IOKit
            ]
          );
          nativeBuildInputs = with pkgs; [
            nix # Tests need nix cli
          ];
        };

        just-flake.features = {
          treefmt.enable = true;
          rust.enable = true;
          convco.enable = true;
        };

        # Add your auto-formatters here.
        # cf. https://numtide.github.io/treefmt/
        treefmt.config = {
          projectRootFile = "flake.nix";
          flakeCheck = false; # pre-commit-hooks.nix checks this
          programs = {
            nixpkgs-fmt.enable = true;
            rustfmt.enable = true;
          };
        };

        pre-commit = {
          check.enable = true;
          settings = {
            hooks = {
              treefmt.enable = true;
              convco.enable = true;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            self'.devShells.nix_rs
            config.treefmt.build.devShell
            config.just-flake.outputs.devShell
            config.pre-commit.devShell
          ];
          packages = [
            pkgs.cargo-watch
            config.pre-commit.settings.tools.convco
          ];
        };
      };
    };
}
