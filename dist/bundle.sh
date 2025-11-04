#!/bin/bash
set -e

ROOT=$(dirname $(dirname ${BASH_SOURCE[0]}))

echo "🔨 Pre-bundling whine-core for Nix-friendly builds..."

# Pre-compile whine-core bundle
# Use 'app' bundle type so it calls main() instead of just exporting it
cd $ROOT/bootstrap
npx spago bundle --bundle-type app --outfile ../dist/whine-core-bundle.mjs 2>&1

echo "✅ whine-core bundle created at dist/whine-core-bundle.mjs"
cd $ROOT

# Continue with existing build process (only if output directory exists)
if [ -d "$ROOT/output/Whine.Runner.Client.Main" ]; then
  npx esbuild $ROOT/output/Whine.Runner.Client.Main/index.js --bundle --outfile=$ROOT/dist/vscode-extension/extension.js --platform=node --format=cjs --external:vscode
  npx esbuild $ROOT/dist/npm/entryPoint.js --bundle --outfile=$ROOT/dist/npm/index.js --platform=node --format=cjs
else
  echo "⚠️  Skipping VSCode extension bundle (output directory not found)"
  echo "   Run 'npx spago build' at the root before running this script for full build"
fi

version=$($ROOT/dist/npm/index.js --version)
description="PureScript linter, extensible, with configurable rules, and one-off escape hatches"

for file in $ROOT/dist/npm/package.json $ROOT/dist/vscode-extension/package.json; do
  sed -i "s/\"version\": \".*\"/\"version\": \"$version\"/g" $file
  sed -i "s/\n  \"description\": \".*\"/\n  \"description\": \"$description\"/g" $file
done

cp $ROOT/LICENSE.txt $ROOT/dist/vscode-extension
pushd $ROOT/dist/vscode-extension
npx vsce package --out ./purescript-whine-$version.vsix
popd
