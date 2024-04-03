{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";

    # Dev tools
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # TODO: Move to flake-module.nix?
    rust-overlay.url = "github:oxalica/rust-overlay";
    # https://github.com/ipetkov/crane/issues/527
    crane.url = "github:ipetkov/crane/2c653e4478476a52c6aa3ac0495e4dea7449ea0e"; # Cargo.toml parsing is broken in newer crane (Mar 24)
    crane.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.treefmt-nix.flakeModule
        ./flake-module.nix
      ];
      perSystem = { config, self', pkgs, lib, system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.rust-overlay.overlays.default
          ];
        };

        # Add your auto-formatters here.
        # cf. https://numtide.github.io/treefmt/
        treefmt.config = {
          projectRootFile = "flake.nix";
          programs = {
            nixpkgs-fmt.enable = true;
            rustfmt.enable = true;
          };
        };

        devShells.default = self'.devShells.nix_rs;
      };
    };
}
