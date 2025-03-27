# SPDX-FileCopyrightText: 2024 László Vaskó <vlaci@fastmail.com>
#
# SPDX-License-Identifier: EUPL-1.2

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-compat = {
      url = "github:edolstra/flake-compat";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        inputs.pre-commit-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];
      perSystem =
        {
          system,
          config,
          pkgs,
          ...
        }:
        let
          emacs' = (pkgs.emacsPackagesFor pkgs.emacs30).emacsWithPackages (
            epkgs: with epkgs; [
              citeproc
              el-patch
              org-roam
              ox-hugo
            ]
          );
        in
        {
          _module.args.pkgs = import inputs.nixpkgs { inherit system; };

          pre-commit = {
            settings.hooks = {
              treefmt = {
                enable = true;
                always_run = true;
              };
              reuse = {
                enable = true;
                name = "reuse";
                description = "Run REUSE compliance tests";
                entry = "${pkgs.reuse}/bin/reuse lint";
                pass_filenames = false;
                always_run = true;
              };
            };
          };
          treefmt.config = {
            projectRootFile = "dev/flake.nix";
            programs = {
              statix.enable = true;
              deadnix.enable = true;
              shellcheck.enable = true;
              nixfmt = {
                enable = true;
                package = pkgs.nixfmt-rfc-style;
              };
            };
          };

          devShells = {
            default = pkgs.mkShell {
              nativeBuildInputs = with pkgs; [
                emacs'
                git
                jujutsu
                just
                nh
                nodejs
                reuse
                sops
                unzip
              ];
              inputsFrom = [
                config.pre-commit.devShell
                config.treefmt.build.devShell
              ];
              env = {
                SOPS_AGE_KEY_FILE = ".git/sops/age/keys.txt";
              };
            };
          };
        };
    };
}
