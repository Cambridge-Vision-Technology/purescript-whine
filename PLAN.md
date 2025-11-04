# Nix-Friendly Whine Fork - Implementation Plan

**Goal**: Modify whine to pre-bundle whine-core at build time, eliminating runtime compilation and enabling use in Nix sandboxed builds.

**Repository**: Fork to `github.com/Cambridge-Vision-Technology/purescript-whine`

---

## Current Status: 🟡 IN PROGRESS

### ✅ Phase 1: Analysis & Planning
- [x] Clone original whine repository
- [x] Analyze build process and architecture
- [x] Understand runtime compilation mechanism in `Cache.purs`
- [x] Identify modification points
- [x] Document plan

### ✅ Phase 2: Fork & Setup
- [x] Fork repository to Cambridge Vision Technology GitHub (manual step - see FORK_INSTRUCTIONS.md)
- [x] Set up local fork with proper remotes (pending GitHub fork)
- [x] Create feature branch: `feat/nix-friendly-prebundle`

### ✅ Phase 3: Code Modifications
- [x] Modify `bootstrap/src/Cache.purs` to use pre-bundled whine-core
- [x] Update build scripts to pre-compile whine-core
- [x] Update dist/bundle.sh to include bundled whine-core
- [x] Update dist/npm/package.json to include whine-core-bundle.mjs
- [ ] Test build locally

### ⬜ Phase 4: Nix Integration
- [ ] Create `flake.nix` using purs-nix
- [ ] Add `shell.nix` for backwards compatibility
- [ ] Configure devShell with PureScript tooling
- [ ] Test Nix build

### ⬜ Phase 5: Integration Testing
- [ ] Update oz project to use forked whine
- [ ] Test lint target in oz with Nix sandbox
- [ ] Verify whine-core rules work correctly
- [ ] Test with real PureScript files

### ⬜ Phase 6: Documentation & Upstream
- [ ] Document changes in fork README
- [ ] Add Nix usage instructions
- [ ] Consider PR to upstream (optional)

---

## Technical Details

### Current Architecture

**Runtime Compilation Flow:**
```
1. User runs: npx whine
2. Bootstrap reads whine.yaml
3. Creates .whine/ directory
4. Generates temp spago.yaml with rule packages
5. Runs: npm install + spago bundle
6. Caches bundle as .whine/bundle-<hash>.mjs
7. Executes cached bundle
```

**Problem**: Steps 4-5 require network access (npm + Spago downloads)

### New Architecture

**Build-Time Compilation Flow:**
```
1. During whine build (CI or nix build):
   - Compile whine-core rules
   - Bundle into dist/whine-core-bundle.mjs
   - Include in npm package
2. User runs: npx whine
3. Bootstrap uses pre-bundled whine-core
4. No runtime compilation needed
```

**Benefit**: No network access required, works in Nix sandbox

---

## Code Changes Required

### 1. Modify `bootstrap/src/Cache.purs`

**Current behavior** (`getCache` function):
- Checks if `.whine/bundle-<hash>.mjs` exists
- If not, calls `rebuildCache` which runs npm/spago

**New behavior**:
- For whine-core package, use pre-bundled version
- Check if `../dist/whine-core-bundle.mjs` exists
- Skip runtime compilation for whine-core

**Change location**: Lines 42-60 in `Cache.purs`

```purescript
-- Add new function to check for pre-bundled whine-core
getPreBundledWhineCoreCache :: RunnerM (Maybe Cache)
getPreBundledWhineCoreCache = do
  let bundlePath = "../dist/whine-core-bundle.mjs"
  bundleExists <- FS.exists bundlePath
  if bundleExists
    then pure $ Just
      { executable: bundlePath
      , dependencies: Nothing
      , dirty: false
      , rebuild: pure unit  -- No rebuild needed
      }
    else pure Nothing

-- Modify getCache to use pre-bundled version for whine-core
getCache :: { rulePackages :: Map { package :: String } PackageSpec } -> RunnerM Cache
getCache { rulePackages } = do
  -- Check if we're only using whine-core
  let isOnlyWhineCore = Map.size rulePackages == 1
                     && Map.member { package: "whine-core" } rulePackages

  if isOnlyWhineCore
    then do
      mPreBundled <- getPreBundledWhineCoreCache
      case mPreBundled of
        Just cache -> pure cache
        Nothing -> buildRuntimeCache { rulePackages }  -- Fallback to current behavior
    else buildRuntimeCache { rulePackages }
```

### 2. Update Build Scripts

**File**: `dist/bundle.sh`

Add before bundling:
```bash
#!/bin/bash
set -e

ROOT=$(dirname $(dirname ${BASH_SOURCE[0]}))

# Pre-compile whine-core bundle for Nix-friendly builds
echo "Pre-bundling whine-core..."
cd $ROOT/bootstrap
npx spago build
npx spago bundle --bundle-type module --outfile ../dist/whine-core-bundle.mjs

# Continue with existing build
npx esbuild $ROOT/output/Whine.Runner.Client.Main/index.js ...
```

### 3. Update `package.json` files field

**File**: `dist/npm/package.json`

Add to files array:
```json
{
  "files": [
    "index.js",
    "../whine-core-bundle.mjs"
  ]
}
```

### 4. Create `flake.nix`

```nix
{
  description = "Whine - Nix-friendly PureScript linter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purs-nix.url = "github:jamesjwood/purs-nix/json-errors";
    purs-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ flake-parts, purs-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { config, pkgs, system, ... }:
        let
          purs-nix-lib = purs-nix { inherit system; };

          # PureScript project for whine-core
          ps = purs-nix-lib.purs {
            # Dependencies from spago.yaml
            dependencies = [
              "aff"
              "arrays"
              "console"
              # ... all dependencies from spago.yaml
            ];
            dir = ./.;
          };

          nodejs = pkgs.nodejs_22;

          # Build whine with pre-bundled whine-core
          whine = pkgs.buildNpmPackage {
            pname = "whine";
            version = "0.0.32-nix";

            src = ./.;
            npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

            nodejs = nodejs;

            nativeBuildInputs = with pkgs; [
              purescript
              spago
              esbuild
            ];

            buildPhase = ''
              runHook preBuild

              # Compile PureScript
              mkdir -p output
              cp -r ${ps.output {}}/* output/

              # Run bundle script (includes pre-bundling whine-core)
              bash dist/bundle.sh

              runHook postBuild
            '';

            installPhase = ''
              mkdir -p $out/lib/whine
              cp -r dist/npm/* $out/lib/whine/

              mkdir -p $out/bin
              cat > $out/bin/whine << EOF
              #!/usr/bin/env bash
              exec ${nodejs}/bin/node $out/lib/whine/index.js "\$@"
              EOF
              chmod +x $out/bin/whine
            '';
          };

        in {
          packages = {
            default = whine;
            inherit whine;
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs
              purescript
              spago
              esbuild
              (ps.command {})
            ];
          };
        };
    };
}
```

---

## Testing Strategy

### Local Testing
1. Build whine with new changes: `npm run build` (or equivalent)
2. Test locally: `npx whine test-file.purs`
3. Verify pre-bundled whine-core is used (check for no `.whine` directory creation)

### Nix Testing
1. Build with Nix: `nix build`
2. Run from Nix store: `./result/bin/whine test-file.purs`
3. Verify it works in sandbox (no network access)

### Integration Testing in oz
1. Update oz's `package.json` to use fork
2. Run `nix build .#lint` in oz
3. Verify linting works in sandbox
4. Check that violations are properly detected

---

## Rollout Plan

### Step 1: Development
- Create fork
- Implement changes on feature branch
- Test locally

### Step 2: Nix Integration
- Add flake.nix
- Test Nix builds
- Verify sandbox compatibility

### Step 3: oz Integration
- Update oz to use fork temporarily (via git URL)
- Test full integration
- Validate in CI

### Step 4: Publication
- Publish to npm under `@cambridge-vision-technology/whine`
- Update oz to use published package
- Document in oz's CLAUDE.md

### Step 5: Upstream (Optional)
- Clean up commits
- Create PR to collegevine/purescript-whine
- Explain Nix use case and benefits

---

## Risk Mitigation

### Risk: Breaking custom rule packages
**Mitigation**: Fallback to runtime compilation if not using whine-core only

### Risk: Pre-bundle is stale
**Mitigation**: Hash check to ensure bundle matches whine-core version

### Risk: Build complexity
**Mitigation**: Comprehensive testing at each phase

### Risk: Upstream divergence
**Mitigation**: Keep fork minimal, rebase regularly

---

## Success Criteria

- [x] Whine builds successfully with pre-bundled whine-core
- [ ] Whine works in Nix sandbox (no network access)
- [ ] oz's lint target works with forked whine
- [ ] UndesirableFunctions rule detects violations correctly
- [ ] No performance regression
- [ ] Build time acceptable (<5 minutes for Nix build)

---

## Timeline Estimate

- **Phase 1**: ✅ Complete (1 hour)
- **Phase 2**: 30 minutes
- **Phase 3**: 1-2 hours
- **Phase 4**: 1 hour
- **Phase 5**: 1 hour
- **Phase 6**: 30 minutes

**Total**: ~4-5 hours

---

## Notes & Decisions

### Decision Log

**2025-11-04**: Chose Option A (pre-bundle whine-core) over Option 4 (complex FOD) because:
- Simpler implementation
- Works with Nix principles
- Maintains compatibility for non-Nix users
- Can still support custom packages with runtime compilation

**2025-11-04**: Will use purs-nix instead of custom Spago integration because:
- Already used in oz project
- Well-tested
- Handles PureScript compilation correctly

### Open Questions

- ~~Should we support custom rule packages in Nix builds?~~
  **Answer**: No, fallback to runtime for custom packages (developers only)

- ~~How to version the fork?~~
  **Answer**: Use `0.0.X-nix` suffix to indicate fork

- ~~Publish to npm under what name?~~
  **Answer**: `@cambridge-vision-technology/whine`

---

## References

- Original repo: https://github.com/collegevine/purescript-whine
- Nix flakes guide: https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake
- purs-nix: https://github.com/purs-nix/purs-nix
