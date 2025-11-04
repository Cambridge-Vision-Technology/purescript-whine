{
  description = "Whine - Nix-friendly PureScript linter with pre-bundled whine-core";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purs-nix.url = "github:jamesjwood/purs-nix/json-errors";
    purs-nix.inputs.nixpkgs.follows = "nixpkgs";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    inputs@{
      flake-parts,
      purs-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let
          # Re-import nixpkgs for this system
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # Use native system architecture for purs-nix (supports ARM64)
          purs-nix-lib = purs-nix { inherit system; };

          # PureScript project configuration with purs-nix
          ps = purs-nix-lib.purs {
            dependencies = [
              "aff"
              "aff-promise"
              "ansi"
              "arrays"
              "bifunctors"
              "debug"
              "codec"
              "codec-json"
              "console"
              "control"
              "datetime"
              "effect"
              "either"
              "elmish"
              "exceptions"
              "foldable-traversable"
              "foreign"
              "foreign-object"
              "formatters"
              "functions"
              "identity"
              "json"
              "language-cst-parser"
              "lists"
              "maybe"
              "newtype"
              "node-buffer"
              "node-execa"
              "node-fs"
              "node-path"
              "node-process"
              "now"
              "nullable"
              "optparse"
              "ordered-collections"
              "parsing"
              "prelude"
              "profunctor"
              "record"
              "safe-coerce"
              "simple-json"
              "strings"
              "stringutils"
              "transformers"
              "tuples"
              "type-equality"
              "typelevel-prelude"
              "untagged-union"
              "uuid"
            ];
            dir = ./bootstrap;  # PureScript sources are in bootstrap/src/
            compile = {
              compilerOptions = [ "--json-errors" ];
            };
          };

          nodejs = pkgs.nodejs_22;

          # JavaScript build using buildNpmPackage
          whine-build = pkgs.buildNpmPackage {
            pname = "whine";
            version = "0.0.32-nix";

            src = ./.;

            npmDepsHash = "sha256-N++U504rHEppJMvqXf7gWHpL0v5OWo7RX1CwVJcTvb4=";

            nodejs = nodejs;

            # Use pre-built whine-core bundle (already committed to repo)
            # Building it requires specific npm versions of purescript/spago which need network access
            dontNpmBuild = true;

            # Skip postinstall scripts that try to download purescript binary
            npmFlags = [ "--ignore-scripts" ];

            nativeBuildInputs = with pkgs; [
              esbuild
            ];

            buildPhase = ''
              runHook preBuild

              # Copy PureScript output from purs-nix (for the CLI entrypoint)
              echo "📦 Copying PureScript output from purs-nix..."
              mkdir -p output
              cp -r ${ps.output {}}/* output/

              # whine-core-bundle.mjs is already pre-built and committed to dist/
              echo "📦 Using pre-built whine-core bundle from dist/whine-core-bundle.mjs"

              if [ ! -f "dist/whine-core-bundle.mjs" ]; then
                echo "❌ ERROR: Pre-built whine-core bundle not found!"
                echo "Run 'npm run build && bash dist/bundle.sh' locally to generate it"
                exit 1
              fi

              # Bundle the CLI entrypoint with esbuild
              echo "🔨 Bundling whine CLI entrypoint..."
              npx esbuild dist/npm/entryPoint.js \
                --bundle \
                --platform=node \
                --format=cjs \
                --outfile=dist/npm/index.js

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              # Create output directory structure
              mkdir -p $out/lib/whine
              mkdir -p $out/bin

              # Copy dist/npm contents
              cp -r dist/npm/* $out/lib/whine/

              # Copy whine-core bundle
              cp dist/whine-core-bundle.mjs $out/lib/whine/

              # Create wrapper script
              cat > $out/bin/whine << EOF
              #!/usr/bin/env bash
              exec ${nodejs}/bin/node $out/lib/whine/index.js "\$@"
              EOF
              chmod +x $out/bin/whine

              runHook postInstall
            '';
          };

        in
        {
          packages = {
            default = whine-build;
            inherit whine-build;
          };

          apps = {
            default = {
              type = "app";
              program = "${whine-build}/bin/whine";
              meta = {
                description = "Nix-friendly PureScript linter with pre-bundled whine-core";
                mainProgram = "whine";
              };
            };

            whine = {
              type = "app";
              program = "${whine-build}/bin/whine";
              meta = {
                description = "PureScript linter";
                mainProgram = "whine";
              };
            };
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs
              purescript
              spago
              esbuild

              # PureScript tooling via purs-nix
              (ps.command {})
            ];

            shellHook = ''
              echo "======================================="
              echo "🔍 Whine Development Environment"
              echo "======================================="
              echo "Node.js: $(${nodejs}/bin/node --version)"
              echo "npm: $(${nodejs}/bin/npm --version)"
              echo "PureScript: $(${pkgs.purescript}/bin/purs --version)"
              echo "Spago: $(${pkgs.spago}/bin/spago version)"
              echo ""
              echo "📦 Build Commands:"
              echo "  nix build           - Build whine with Nix"
              echo "  nix run             - Run whine"
              echo "  npx spago build     - Build PureScript"
              echo "  bash dist/bundle.sh - Create whine-core bundle"
              echo ""
              echo "💡 Pre-bundled whine-core for Nix compatibility"
              echo "======================================="
            '';
          };
        };
    };
}
