{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    crane.url = "github:ipetkov/crane";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          pkgs,
          lib,
          system,
          ...
        }:
        let
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rust;
          overlays = [ inputs.rust-overlay.overlays.default ];
          src = lib.cleanSource ./.;
          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src;
          };
          exec-counter = craneLib.buildPackage {
            inherit src cargoArtifacts;
            strictDeps = true;

            doCheck = true;
          };
          cargo-clippy = craneLib.cargoClippy {
            inherit src cargoArtifacts;
            cargoClippyExtraArgs = "--verbose -- --deny warning";
          };
          cargo-doc = craneLib.cargoDoc {
            inherit src cargoArtifacts;
          };
          llvm-cov-text = craneLib.cargoLlvmCov {
            inherit cargoArtifacts src;
            cargoExtraArgs = "--locked";
            cargoLlvmCovCommand = "test";
            cargoLlvmCovExtraArgs = "--text --output-dir $out";
          };
          llvm-cov = craneLib.cargoLlvmCov {
            inherit cargoArtifacts src;
            cargoExtraArgs = "--locked";
            cargoLlvmCovCommand = "test";
            cargoLlvmCovExtraArgs = "--html --output-dir $out";
          };
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system overlays;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            programs.rustfmt.enable = true;
            programs.taplo.enable = true;
            programs.actionlint.enable = true;
          };

          packages = {
            inherit exec-counter llvm-cov llvm-cov-text;
            default = exec-counter;
            doc = cargo-doc;
          };

          checks = {
            inherit
              exec-counter
              cargo-clippy
              cargo-doc
              llvm-cov
              llvm-cov-text
              ;
          };

          devShells.default = pkgs.mkShell rec {
            packages = [
              # Rust
              rust

              # Nix
              pkgs.nil
            ];

            shellHook = ''
              export PS1="\n[nix-shell:\w]$ "
            '';
          };
        };
    };
}
