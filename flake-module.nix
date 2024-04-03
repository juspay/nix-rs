# TODO: Upstream to separate repo (for reuse in other repos)
{ self, lib, inputs, flake-parts-lib, ... }:

let
  inherit (flake-parts-lib)
    mkPerSystemOption;
in
{
  options = {
    perSystem = mkPerSystemOption
      ({ config, self', inputs', pkgs, system, ... }: {
        options = {
          rust-project.overrideCraneArgs = lib.mkOption {
            type = lib.types.functionTo lib.types.attrs;
            default = _: { };
            description = "Override crane args for the rust-project package";
          };

          rust-project.rustBuildInputs = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            # XXX: Do we need this?
            default = lib.optionals pkgs.stdenv.isDarwin (
              with pkgs.darwin.apple_sdk.frameworks; [
                IOKit
                Carbon
                WebKit
                Security
                Cocoa
              ]
            );
            description = "(Runtime) buildInputs for the cargo package";
          };

          rust-project.rustToolchain = lib.mkOption {
            type = lib.types.package;
            description = "Rust toolchain to use for the rust-project package";
            default = (pkgs.rust-bin.fromRustupToolchainFile (self + /rust-toolchain.toml)).override {
              extensions = [
                "rust-src"
                "rust-analyzer"
                "clippy"
              ];
            };
          };

          rust-project.craneLib = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = (inputs.crane.mkLib pkgs).overrideToolchain config.rust-project.rustToolchain;
          };

          rust-project.src = lib.mkOption {
            type = lib.types.path;
            description = "Source directory for the rust-project package";
            # When filtering sources, we want to allow assets other than .rs files
            # TODO: Don't hardcode these!
            default = lib.cleanSourceWith {
              src = self; # The original, unfiltered source
              filter = path: type:
                # Default filter from crane (allow .rs files)
                (config.rust-project.craneLib.filterCargoSources path type)
              ;
            };
          };
        };
        config =
          let
            cargoToml = builtins.fromTOML (builtins.readFile (self + /Cargo.toml));
            inherit (cargoToml.package) name version;
            inherit (config.rust-project) rustToolchain craneLib src;

            # Crane builder for Dioxus projects projects
            craneBuild = rec {
              args = {
                inherit src;
                pname = name;
                version = version;
                buildInputs = [
                ] ++ config.rust-project.rustBuildInputs;
                nativeBuildInputs = with pkgs;[
                  pkg-config
                  makeWrapper
                ];
                # glib-sys fails to build on linux without this
                # cf. https://github.com/ipetkov/crane/issues/411#issuecomment-1747533532
                strictDeps = true;
              };
              cargoArtifacts = craneLib.buildDepsOnly args;
              buildArgs = args // {
                inherit cargoArtifacts;
              };
              package = craneLib.buildPackage
                (buildArgs // config.rust-project.overrideCraneArgs buildArgs);

              check = craneLib.cargoClippy (args // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets --all-features -- --deny warnings";
              });

              doc = craneLib.cargoDoc (args // {
                inherit cargoArtifacts;
              });
            };

            rustDevShell = pkgs.mkShell {
              shellHook = ''
                # For rust-analyzer 'hover' tooltips to work.
                export RUST_SRC_PATH="${rustToolchain}/lib/rustlib/src/rust/library";
              '';
              buildInputs = [
                pkgs.libiconv
              ] ++ config.rust-project.rustBuildInputs;
              packages = [
                rustToolchain
              ];
            };
          in
          {
            # Rust package
            packages.${name} = craneBuild.package;
            packages."${name}-doc" = craneBuild.doc;

            checks."${name}-clippy" = craneBuild.check;

            # Rust dev environment
            devShells.${name} = pkgs.mkShell {
              inputsFrom = [
                rustDevShell
              ];
            };
          };
      });
  };
}
