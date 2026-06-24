# Publishing pixi-worktree to a conda channel

`pixi-worktree` builds with `rattler-build` and publishes to a prefix.dev conda
channel. The recipe lives in `recipe/` and builds from the local working tree
(`source: path: ..`) -- no clone, no Git credentials.

## Configure the channel

Set the destination in `pixi.toml` under `[feature.pkg.activation.env]`:

```toml
PREFIX_CHANNEL = "wv-forge"
PREFIX_SERVER_URL = "https://prefix.dev"
```

You can override the channel per invocation, e.g.
`PREFIX_CHANNEL=my-staging pixi run -e pkg publish`.

## GitHub Actions publishing

The workflow in `.github/workflows/publish.yml` publishes to the `wv-forge`
prefix.dev channel when you push a `v*` tag or run it manually from GitHub
Actions.

Add the API key as a GitHub repository secret:

1. Go to the GitHub repository.
2. Open **Settings** -> **Secrets and variables** -> **Actions**.
3. Click **New repository secret**.
4. Name it `PREFIX_API_KEY`.
5. Paste the prefix.dev API key as the value.

```text
PREFIX_API_KEY
```

The workflow maps that secret to the `PREFIX_API_KEY` environment variable that
`rattler-build upload prefix` understands. No credentials are stored in the repo.

## One-time: authenticate

For local publishing, `rattler-build` reads `PREFIX_API_KEY` or its own auth
store at `~/.rattler/credentials.json`. Register credentials once:

```bash
pixi run -e pkg channel-auth
```

This prompts for a prefix.dev API key and stores it for `prefix.dev` in
`~/.rattler/credentials.json`. Nothing secret is written to the repo.

Equivalent manual form:

```bash
rattler-build auth login prefix.dev --token "$PREFIX_API_KEY"
```

## Build and upload locally

```bash
pixi run build    # build only -> output/noarch/
pixi run upload   # build, then upload the current recipe version to $PREFIX_CHANNEL
```

The upload task uses `rattler-build upload prefix --skip-existing`.

## Releasing a new version

Run the guided release task:

```bash
pixi run publish
```

The script asks for a patch/minor/major/no-change release. For version bumps, it
updates both `PIXI_WORKTREE_VERSION` in the `pixi-worktree` script and
`context.version` in `recipe/recipe.yaml`, resets the recipe build `number` to
0, builds the package, commits the version bump, creates `vX.Y.Z`, and pushes
the branch and tag. The `Publish` GitHub Action then builds the tagged source
and uploads it to the `wv-forge` prefix.dev channel.

A rebuild of the same version+build is a no-op the channel skips. For a local
upload, run `pixi run upload` after authenticating with `pixi run channel-auth`.
