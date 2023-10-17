{
  description = "nix.dev static website";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nix_2-13.url = "github:NixOS/nix/2.13-maintenance";
  inputs.nix_2-18.url = "github:NixOS/nix/2.18-maintenance";

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            # Add sphinx-sitemap from an overlay until
            # it becomes available from nixpkgs-unstable
            (import ./overlay.nix)
          ];
        };

        devmode =
        let
          pythonEnvironment = pkgs.python310.withPackages (ps: with ps; [
            livereload
          ]);
          script = ''
            from livereload import Server, shell

            server = Server()

            build_docs = shell("nix build")

            print("Doing an initial build of the docs...")
            build_docs()

            server.watch("source/*", build_docs)
            server.watch("source/**/*", build_docs)
            server.watch("_templates/*.html", build_docs)
            server.serve(root="result/")
          '';
        in
        pkgs.writeShellApplication {
          name = "devmode";
          runtimeInputs = [ pythonEnvironment ];
          text = ''
            python ${pkgs.writeText "live.py" script}
          '';
        };
      in {
        packages.default = let 
          nix_2-13_doc = inputs.nix_2-13.packages.${system}.nix.doc;
          #nix_2-18_doc = nix_2-18.packages.${system}.nix.doc;

          # Relevant issue: https://github.com/sphinx-doc/sphinx/issues/701
          sourcesCombined = pkgs.stdenv.mkDerivation {
            name = "nixDevSourcesCombined";
            src = ./.;

            buildInputs = [
              nix_2-13_doc
            ];

            dontUnpack = true;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out
              mkdir -p $out/source/reference/manual/nix/{2.13,2.18}
              
              cp -R $src/* $out/
              cp -R ${nix_2-13_doc}/share/doc/nix/manual/* $out/source/reference/manual/nix/2.13
            '';
          };
        in pkgs.stdenv.mkDerivation {
          name = "nix-dev";
          src = sourcesCombined;
          
          nativeBuildInputs = with pkgs.python310.pkgs; [
            linkify-it-py
            myst-parser
            sphinx
            sphinx-book-theme
            sphinx-copybutton
            sphinx-design
            sphinx-notfound-page
            sphinx-sitemap
          ];
          buildPhase = ''
            ls -lah .
            ls -la ./source
            make html
          '';
          installPhase = ''
            mkdir -p $out/build/reference/
            ls -lah build/html/reference
            
            # copy manuals over the build directory
            ls -lah $src/source/reference

            cp -R $src/source/reference/manual $out/build/reference/
            
            cp -R build/html/* $out/
          '';
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
          packages = with pkgs.python310.pkgs; [
            black
            devmode
          ];
        };
      }
    );
}
