#!/usr/bin/env bash
set -euo pipefail

package_name="pixi-worktree"

mkdir -p output/noarch
rm -f "output/noarch/${package_name}"-*.conda
rm -f "output/noarch/${package_name}"-*.tar.bz2

rattler-build build --recipe recipe/recipe.yaml --output-dir output
