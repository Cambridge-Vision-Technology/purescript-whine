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
              "strings"
              "stringutils"
              "transformers"
              "tuples"
              "type-equality"
              "typelevel-prelude"
              "untagged-union"
            ];
            dir = ./.;
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

            # Skip postinstall scripts that try to download purescript binary
            # We provide purescript through Nix instead
            npmFlags = [ "--ignore-scripts" ];

            nativeBuildInputs = with pkgs; [
              purescript
              spago
              esbuild
            ];

            buildPhase = ''
              runHook preBuild

              # Copy PureScript output
              echo "📦 Copying PureScript output..."
              mkdir -p output
              cp -r ${ps.output {}}/* output/

              # Build whine-core bundle (from bootstrap package)
              echo "🔨 Building whine-core bundle..."
              cd bootstrap
              npx spago bundle --bundle-type module --outfile ../dist/whine-core-bundle.mjs

              cd ..
              echo "✅ whine-core bundle created"

              # Build bootstrap main
              cd bootstrap
              npx spago build
              npx spago bundle --bundle-type module --outfile index.mjs
              cd ..

              # Bundle the entrypoint
              npx esbuild dist/npm/entryPoint.js --bundle --outfile=dist/npm/index.js --platform=node --format=cjs

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
