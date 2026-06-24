#!/usr/bin/env bash
set -euo pipefail

package_name="pixi-worktree"
recipe_file="recipe/recipe.yaml"
cli_file="pixi-worktree"

die() {
  echo "publish: $*" >&2
  exit 1
}

read_recipe_version() {
  sed -nE 's/^[[:space:]]*version:[[:space:]]*"([^"]+)".*$/\1/p' "$recipe_file" \
    | head -n 1
}

read_cli_version() {
  sed -nE 's/^PIXI_WORKTREE_VERSION="([^"]+)".*$/\1/p' "$cli_file" \
    | head -n 1
}

require_clean_worktree() {
  if [ -n "$(git status --porcelain)" ]; then
    git status --short >&2
    die "working tree is not clean; commit or stash changes before publishing"
  fi
}

require_semver() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "expected X.Y.Z version, got '$version'"
}

bump_version() {
  local version="$1"
  local bump="$2"
  local major minor patch

  IFS=. read -r major minor patch <<<"$version"
  case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    none) ;;
    *) die "unknown version bump: $bump" ;;
  esac

  echo "${major}.${minor}.${patch}"
}

replace_first_match() {
  local file="$1"
  local awk_script="$2"
  local tmp

  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  if ! awk "$awk_script" "$file" > "$tmp"; then
    rm -f "$tmp"
    die "failed to update $file"
  fi
  mv "$tmp" "$file"
}

write_version() {
  local version="$1"
  export NEW_VERSION="$version"

  replace_first_match "$recipe_file" '
    !done && $0 ~ /^[[:space:]]*version:[[:space:]]*"[^"]+"/ {
      sub(/"[^"]+"/, "\"" ENVIRON["NEW_VERSION"] "\"")
      done = 1
    }
    { print }
    END { if (!done) exit 1 }
  '

  replace_first_match "$recipe_file" '
    !done && $0 ~ /^[[:space:]]*number:[[:space:]]*[0-9]+/ {
      sub(/number:[[:space:]]*[0-9]+/, "number: 0")
      done = 1
    }
    { print }
    END { if (!done) exit 1 }
  '

  replace_first_match "$cli_file" '
    !done && $0 ~ /^PIXI_WORKTREE_VERSION="[^"]+"/ {
      sub(/"[^"]+"/, "\"" ENVIRON["NEW_VERSION"] "\"")
      done = 1
    }
    { print }
    END { if (!done) exit 1 }
  '
  chmod +x "$cli_file"
}

ensure_tag_available() {
  local tag="$1"
  local head_commit tag_commit

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    tag_commit="$(git rev-list -n 1 "$tag")"
    head_commit="$(git rev-parse HEAD)"
    [ "$tag_commit" = "$head_commit" ] \
      || die "local tag $tag already exists on a different commit"
  fi
}

push_branch_and_tag() {
  local tag="$1"
  local branch

  branch="$(git symbolic-ref --short HEAD)" \
    || die "cannot publish from detached HEAD"

  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git push
  else
    git push -u origin "$branch"
  fi

  git push origin "$tag"
}

echo "=== ${package_name} publish ==="
echo

require_clean_worktree

current_version="$(read_recipe_version)"
cli_version="$(read_cli_version)"

[ -n "$current_version" ] || die "could not read context.version from $recipe_file"
[ -n "$cli_version" ] || die "could not read PIXI_WORKTREE_VERSION from $cli_file"
[ "$current_version" = "$cli_version" ] \
  || die "version mismatch: $recipe_file has $current_version, $cli_file has $cli_version"
require_semver "$current_version"

echo "Current version: $current_version"
echo
echo "Select version bump:"
echo "  1) patch ($(bump_version "$current_version" patch))"
echo "  2) minor ($(bump_version "$current_version" minor))"
echo "  3) major ($(bump_version "$current_version" major))"
echo "  4) no change (tag current commit as v$current_version)"
echo
read -rp "Choice [1-4]: " choice

case "$choice" in
  1) bump="patch" ;;
  2) bump="minor" ;;
  3) bump="major" ;;
  4) bump="none" ;;
  *) die "invalid choice" ;;
esac

new_version="$(bump_version "$current_version" "$bump")"
tag="v$new_version"

ensure_tag_available "$tag"

echo
if [ "$bump" = "none" ]; then
  echo "Keeping version $new_version."
else
  echo "Version will be bumped: $current_version -> $new_version"
fi
echo "The script will build, commit/tag if needed, and push $tag."
read -rp "Continue? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || die "cancelled"

if [ "$bump" != "none" ]; then
  echo
  echo "Updating version files..."
  NEW_VERSION="$new_version" write_version "$new_version"
  echo "Updated $recipe_file and $cli_file."
fi

echo
echo "Building package..."
pixi run -e pkg build
echo
echo "Build succeeded."

if [ "$bump" != "none" ]; then
  echo
  echo "Committing version bump..."
  git add "$recipe_file" "$cli_file"
  git commit -m "chore: release $tag"
fi

if ! git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  echo
  echo "Creating tag $tag..."
  git tag "$tag"
else
  echo
  echo "Tag $tag already exists locally on HEAD."
fi

echo
echo "Pushing branch and tag..."
push_branch_and_tag "$tag"

echo
echo "Published release trigger for $package_name $new_version."
echo "The GitHub Publish workflow will upload the package from tag $tag."
