#!/usr/bin/env bash
set -euo pipefail

package_name="pixi-worktree"
recipe_file="recipe/recipe.yaml"

version="$(
  sed -nE 's/^[[:space:]]*version:[[:space:]]*"([^"]+)".*$/\1/p' "$recipe_file" \
    | head -n 1
)"

if [ -z "$version" ]; then
  echo "Could not read context.version from $recipe_file." >&2
  exit 1
fi

shopt -s nullglob
packages=(
  "output/noarch/${package_name}-${version}"-*.conda
  "output/noarch/${package_name}-${version}"-*.tar.bz2
)
shopt -u nullglob

if [ "${#packages[@]}" -eq 0 ]; then
  echo "No ${package_name} ${version} packages found in output/noarch." >&2
  exit 1
fi

rattler-build upload prefix \
  --channel "${PREFIX_CHANNEL}" \
  --url "${PREFIX_SERVER_URL}" \
  --skip-existing \
  "${packages[@]}"
